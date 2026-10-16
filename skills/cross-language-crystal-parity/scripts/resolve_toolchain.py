#!/usr/bin/env python3
"""Resolve one verified Chiasmus toolchain for the current platform."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile


RELEASES_URL = "https://api.github.com/repos/dsisnero/chiasmus.cr/releases?per_page=100"
TOOLS = ("discover", "facts", "parity", "plan", "complete")
GRAMMARS = ("java", "go", "crystal")
PLATFORMS = {
    "darwin": ("macOS", "dylib", ""),
    "linux": ("Linux", "so", ""),
    "windows": ("Windows", "dll", ".exe"),
}


class ResolutionError(Exception):
    pass


def platform_details(platform: str) -> tuple[str, str, str]:
    match = re.fullmatch(r"(darwin|linux|windows)-(aarch64|x86_64)", platform)
    if not match:
        raise ResolutionError(f"unsupported platform: {platform}")
    return PLATFORMS[match.group(1)]


def host_platform() -> str:
    import platform as host

    system = {"Darwin": "darwin", "Linux": "linux", "Windows": "windows"}.get(host.system())
    machine = {"arm64": "aarch64", "aarch64": "aarch64", "amd64": "x86_64", "x86_64": "x86_64"}.get(host.machine().lower())
    if not system or not machine:
        raise ResolutionError(f"unsupported host: {host.system()} {host.machine()}")
    return f"{system}-{machine}"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def archive_files(root: Path) -> dict[str, Path]:
    if root.is_symlink() or not root.is_dir():
        raise ResolutionError(f"toolchain directory missing or symlinked: {root}")
    files = {}
    for parent, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            path = Path(parent) / name
            if path.is_symlink():
                raise ResolutionError(f"symlink in toolchain: {path}")
        for name in names:
            path = Path(parent) / name
            relative = path.relative_to(root).as_posix()
            if relative != "toolchain-manifest.json":
                files[relative] = path
    return files


def verify_toolchain(root: Path, platform: str, capabilities: list[str]) -> dict:
    _label, grammar_extension, executable = platform_details(platform)
    manifest_path = root / "toolchain-manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ResolutionError("toolchain manifest missing or symlinked")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ResolutionError(f"invalid toolchain manifest: {error}") from error
    if not isinstance(manifest, dict) or manifest.get("manifest_version") != 1:
        raise ResolutionError("unsupported toolchain manifest version")
    if manifest.get("platform") != platform:
        raise ResolutionError(f"toolchain platform mismatch: {manifest.get('platform')} != {platform}")
    if not isinstance(manifest.get("build_id"), str) or not manifest["build_id"]:
        raise ResolutionError("toolchain build ID missing")
    records = manifest.get("files")
    if not isinstance(records, dict):
        raise ResolutionError("toolchain file hashes missing")
    actual = archive_files(root)
    required = {f"chiasmus-{tool}{executable}" for tool in TOOLS} | {
        f"grammars/libtree-sitter-{language}.{grammar_extension}" for language in GRAMMARS
    }
    missing = required - actual.keys()
    if missing:
        raise ResolutionError("missing toolchain files: " + ", ".join(sorted(missing)))
    if platform.split("-", 1)[0] != "windows":
        for tool in TOOLS:
            executable_path = actual[f"chiasmus-{tool}"]
            if not os.access(executable_path, os.X_OK):
                raise ResolutionError(f"toolchain CLI is not executable: {executable_path}")
    for name in records:
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or name != path.as_posix():
            raise ResolutionError(f"invalid manifest file path: {name}")
    if actual.keys() != records.keys():
        missing = records.keys() - actual.keys()
        extra = actual.keys() - records.keys()
        raise ResolutionError(f"toolchain file set mismatch; missing={sorted(missing)}, unmanifested={sorted(extra)}")
    for name, path in actual.items():
        record = records[name]
        if not isinstance(record, dict) or record.get("sha256") != sha256(path):
            raise ResolutionError(f"toolchain checksum mismatch: {name}")
        if record.get("size") != path.stat().st_size:
            raise ResolutionError(f"toolchain size mismatch: {name}")
    offered = manifest.get("capabilities")
    if not isinstance(offered, dict):
        raise ResolutionError("toolchain capabilities missing")
    for required_capability in capabilities:
        tool, separator, name = required_capability.partition(".")
        if not separator or name not in offered.get(tool, []):
            raise ResolutionError(f"missing capability: {required_capability}")
    return manifest


def release_index(location: str | None) -> list[dict]:
    if location and Path(location).is_file():
        content = Path(location).read_text(encoding="utf-8")
    else:
        request = urllib.request.Request(
            location or RELEASES_URL,
            headers={"Accept": "application/vnd.github+json", "User-Agent": "chiasmus-parity-skill"},
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            content = response.read(8 * 1024 * 1024).decode("utf-8")
    releases = json.loads(content)
    if not isinstance(releases, list):
        raise ResolutionError("release index must be a JSON array")
    return releases


def release_sort_key(release: dict) -> tuple:
    tag = str(release.get("tag_name", ""))
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)(?:[.-].*)?", tag)
    version = tuple(int(part) for part in match.groups()) if match else (0, 0, 0)
    return version, str(release.get("published_at") or "")


def release_asset(release: dict, platform: str) -> dict | None:
    label, _grammar, _executable = platform_details(platform)
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not re.fullmatch(r"[A-Za-z0-9._+-]+", tag):
        return None
    suffix = ".zip" if label == "Windows" else ".tar.gz"
    name = f"chiasmus-{label}-{platform.split('-', 1)[1]}-{tag}{suffix}"
    return next((asset for asset in release.get("assets", []) if asset.get("name") == name), None)


def archive_member(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "chiasmus":
        raise ResolutionError(f"unsafe archive path: {name}")
    return path


def extract_archive(archive: Path, destination: Path) -> None:
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                relative = archive_member(member.filename)
                mode = (member.external_attr >> 16) & 0o170000
                if mode == 0o120000:
                    raise ResolutionError(f"symlink in archive: {member.filename}")
                target = destination.joinpath(*relative.parts)
                if member.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with bundle.open(member) as source, target.open("wb") as output:
                        shutil.copyfileobj(source, output)
    else:
        with tarfile.open(archive, "r:gz") as bundle:
            for member in bundle:
                relative = archive_member(member.name)
                target = destination.joinpath(*relative.parts)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    source = bundle.extractfile(member)
                    if source is None:
                        raise ResolutionError(f"cannot read archive file: {member.name}")
                    with source, target.open("wb") as output:
                        shutil.copyfileobj(source, output)
                    target.chmod(member.mode & 0o777)
                else:
                    raise ResolutionError(f"unsupported archive member: {member.name}")


def active_toolchain(cache: Path, platform: str, capabilities: list[str]) -> Path:
    pointer = cache / platform / "active.json"
    data = json.loads(pointer.read_text(encoding="utf-8"))
    tag = data["tag"]
    if not isinstance(tag, str) or not re.fullmatch(r"[A-Za-z0-9._+-]+", tag):
        raise ResolutionError("invalid active toolchain tag")
    root = cache / platform / tag
    verify_toolchain(root, platform, capabilities)
    return root


def activate(cache: Path, platform: str, tag: str, root: Path) -> None:
    pointer = cache / platform / "active.json"
    temporary = pointer.with_name(f"active-{os.getpid()}.tmp")
    temporary.write_text(json.dumps({"tag": tag, "build_id": verify_toolchain(root, platform, [])["build_id"]}), encoding="utf-8")
    os.replace(temporary, pointer)


def install_release(cache: Path, platform: str, release: dict, asset: dict, capabilities: list[str]) -> Path:
    tag = release["tag_name"]
    platform_cache = cache / platform
    platform_cache.mkdir(parents=True, exist_ok=True)
    final = platform_cache / tag
    if final.is_dir():
        verify_toolchain(final, platform, capabilities)
        activate(cache, platform, tag, final)
        return final
    digest = asset.get("digest", "")
    if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
        raise ResolutionError(f"release {tag} has no SHA-256 asset digest")
    with tempfile.TemporaryDirectory(prefix=".toolchain-", dir=platform_cache) as scratch:
        temporary = Path(scratch)
        archive = temporary / "toolchain.archive"
        url = asset.get("browser_download_url")
        if not isinstance(url, str):
            raise ResolutionError(f"release {tag} has no archive URL")
        with urllib.request.urlopen(url, timeout=60) as source, archive.open("wb") as output:
            shutil.copyfileobj(source, output)
        if sha256(archive) != digest.split(":", 1)[1].lower():
            raise ResolutionError(f"archive checksum mismatch for {tag}")
        unpacked = temporary / "unpacked"
        unpacked.mkdir()
        extract_archive(archive, unpacked)
        root = unpacked / "chiasmus"
        verify_toolchain(root, platform, capabilities)
        try:
            os.rename(root, final)
        except FileExistsError:
            verify_toolchain(final, platform, capabilities)
        activate(cache, platform, tag, final)
    return final


def resolve(args: argparse.Namespace) -> Path:
    for name in ("CHIASMUS_DISCOVER_BIN", "CHIASMUS_FACTS_BIN", "CHIASMUS_PARITY_BIN", "CHIASMUS_PLAN_BIN", "CHIASMUS_COMPLETE_BIN"):
        if os.environ.get(name):
            raise ResolutionError(f"individual binary override {name} is not allowed; use a whole toolchain")
    platform = args.platform or host_platform()
    platform_details(platform)
    override = args.toolchain_dir or os.environ.get("CHIASMUS_TOOLCHAIN_DIR")
    if override:
        root = Path(override).expanduser().resolve()
        verify_toolchain(root, platform, args.require_capability)
        return root
    cache = Path(args.cache_dir).expanduser().resolve()
    if args.offline:
        return active_toolchain(cache, platform, args.require_capability)
    try:
        releases = release_index(args.release_index)
    except (OSError, ValueError, urllib.error.URLError) as error:
        try:
            fallback = active_toolchain(cache, platform, args.require_capability)
        except (OSError, ValueError, KeyError, ResolutionError):
            raise ResolutionError(f"release check failed and no verified cached toolchain exists: {error}") from error
        print(f"release check failed; using verified cached toolchain: {error}", file=sys.stderr)
        return fallback
    for release in sorted(releases, key=release_sort_key, reverse=True):
        if release.get("draft") or release.get("prerelease"):
            continue
        asset = release_asset(release, platform)
        if asset is None:
            continue
        try:
            return install_release(cache, platform, release, asset, args.require_capability)
        except ResolutionError as error:
            if str(error).startswith("missing capability:"):
                continue
            raise
    raise ResolutionError(f"no compatible stable Chiasmus release for {platform}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform")
    parser.add_argument("--release-index", default=os.environ.get("CHIASMUS_RELEASE_INDEX"), help="Local JSON index or URL (for tests/offline mirrors)")
    parser.add_argument("--cache-dir", default=os.environ.get("CHIASMUS_TOOLCHAIN_CACHE_DIR", str(Path.home() / ".cache" / "chiasmus" / "toolchains")))
    parser.add_argument("--require-capability", action="append", default=[])
    parser.add_argument("--offline", action="store_true", default=os.environ.get("CHIASMUS_TOOLCHAIN_OFFLINE") == "1")
    parser.add_argument("--toolchain-dir", help="Validate and use a complete preinstalled toolchain")
    args = parser.parse_args()
    try:
        print(resolve(args))
    except (ResolutionError, OSError, ValueError, KeyError, tarfile.TarError, zipfile.BadZipFile) as error:
        print(f"Chiasmus toolchain: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
