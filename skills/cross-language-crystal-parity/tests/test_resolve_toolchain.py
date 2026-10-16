"""Offline behavioral tests for the whole-toolchain resolver."""

from __future__ import annotations

import hashlib
import json
import os
import platform
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "resolve_toolchain.py"


class ResolveToolchainTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="toolchain-resolver-")
        self.root = Path(self.temp.name)
        self.cache = self.root / "cache"
        self.archive_dir = self.root / "archives"
        self.archive_dir.mkdir()
        self.index = self.root / "releases.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_selects_newest_stable_release_with_platform_and_required_capabilities(self) -> None:
        old = self.make_release("v1.8.0", "darwin-aarch64", {"discover.tree-sitter", "facts.typed-declarations"})
        newer_incompatible = self.make_release("v1.10.0", "darwin-aarch64", {"discover.regex"})
        prerelease = self.make_release(
            "v2.0.0-rc.1", "darwin-aarch64", {"discover.tree-sitter", "facts.typed-declarations"}, prerelease=True
        )
        wrong_platform = self.make_release("v3.0.0", "linux-x86_64", {"discover.tree-sitter", "facts.typed-declarations"})
        self.write_index([old, newer_incompatible, prerelease, wrong_platform])

        resolved = self.resolve("darwin-aarch64", "discover.tree-sitter", "facts.typed-declarations")

        self.assertEqual(resolved.name, "v1.8.0")
        self.assertTrue((resolved / "chiasmus-discover").is_file())
        self.assertTrue((resolved / "chiasmus-facts").is_file())
        self.assertTrue((resolved / "grammars" / "libtree-sitter-java.dylib").is_file())

    def test_offline_warm_cache_resolves_without_archive_or_network(self) -> None:
        release = self.make_release("v1.2.0", "linux-x86_64", {"discover.tree-sitter", "facts.typed-declarations"})
        self.write_index([release])
        first = self.resolve("linux-x86_64", "discover.tree-sitter", "facts.typed-declarations")
        Path(release["archive"]).unlink()

        second = self.resolve("linux-x86_64", "discover.tree-sitter", "facts.typed-declarations", offline=True)

        self.assertEqual(first, second)
        self.assertTrue((second / "chiasmus-discover").is_file())

    def test_corrupt_archive_is_rejected_and_last_good_version_is_preserved(self) -> None:
        good = self.make_release("v1.0.0", "linux-x86_64", {"discover.tree-sitter", "facts.typed-declarations"})
        self.write_index([good])
        prior = self.resolve("linux-x86_64", "discover.tree-sitter", "facts.typed-declarations")
        old_binary = (prior / "chiasmus-discover").read_bytes()
        corrupt = self.make_release(
            "v1.1.0", "linux-x86_64", {"discover.tree-sitter", "facts.typed-declarations"}, corrupt=True
        )
        self.write_index([good, corrupt])

        result = self.run_resolver("linux-x86_64", "discover.tree-sitter", "facts.typed-declarations")

        self.assert_resolver_started(result)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((prior / "chiasmus-discover").read_bytes(), old_binary)
        self.assertTrue(prior.is_dir())

    def test_rejects_wrong_platform_in_archive_manifest(self) -> None:
        release = self.make_release(
            "v1.0.0", "linux-x86_64", {"discover.tree-sitter", "facts.typed-declarations"},
            manifest_platform="darwin-aarch64",
        )
        self.write_index([release])

        result = self.run_resolver("linux-x86_64", "discover.tree-sitter", "facts.typed-declarations")

        self.assert_resolver_started(result)
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_rejects_nonexecutable_tool_in_local_toolchain(self) -> None:
        self.make_release("v1.0.0", self.host_platform(), {"discover.tree-sitter"})
        stage = self.root / "stage-v1.0.0" / "chiasmus"
        (stage / "chiasmus-discover").chmod(0o644)
        result = self.run_resolver(self.host_platform(), "discover.tree-sitter",
                                   env={"CHIASMUS_TOOLCHAIN_DIR": str(stage)})
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_rejects_mixed_individual_binary_overrides(self) -> None:
        release = self.make_release("v1.0.0", "linux-x86_64", {"discover.tree-sitter", "facts.typed-declarations"})
        self.write_index([release])

        result = self.run_resolver(
            "linux-x86_64", "discover.tree-sitter", "facts.typed-declarations",
            env={"CHIASMUS_DISCOVER_BIN": "/custom/discover",
                 "CHIASMUS_FACTS_BIN": "/custom/facts"},
        )

        self.assert_resolver_started(result)
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_does_not_use_stale_bundled_binary_when_no_compatible_release_exists(self) -> None:
        bundled = self.root / "bundled"
        (bundled / "bin").mkdir(parents=True)
        (bundled / "bin" / "chiasmus-discover").write_text("stale", encoding="utf-8")
        self.write_index([])

        result = self.run_resolver(
            "linux-x86_64", "discover.tree-sitter", "facts.typed-declarations",
            env={"CHIASMUS_TOOLCHAIN_DIR": str(bundled)},
        )

        self.assert_resolver_started(result)
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def assert_resolver_started(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotIn("can't open file", result.stderr)
        self.assertNotIn("No such file or directory", result.stderr)

    def test_accepts_zip_toolchain_archive(self) -> None:
        release = self.make_release(
            "v1.0.0", "windows-x86_64", {"discover.tree-sitter", "facts.typed-declarations"}, archive_format="zip"
        )
        self.write_index([release])

        resolved = self.resolve("windows-x86_64", "discover.tree-sitter", "facts.typed-declarations")

        self.assertTrue((resolved / "chiasmus-discover.exe").is_file())

    def test_verify_wrapper_uses_only_verified_whole_toolchain(self) -> None:
        host = self.host_platform()
        release = self.make_release("v1.0.0", host, {"discover.tree-sitter"})
        stage = self.root / "stage-v1.0.0" / "chiasmus"
        probe = b"#!/bin/sh\necho 'parser=tree-sitter'\n"
        (stage / "chiasmus-discover").write_bytes(probe)
        manifest_path = stage / "toolchain-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["files"]["chiasmus-discover"] = {"sha256": hashlib.sha256(probe).hexdigest(), "size": len(probe)}
        manifest_path.write_text(json.dumps(manifest))
        repo = self.root / "repo"
        repo.mkdir()
        env = os.environ.copy()
        env.update({"CHIASMUS_TOOLCHAIN_DIR": str(stage), "CHIASMUS_DISCOVER_BIN": str(self.root / "stale")})
        result = subprocess.run(["bash", str(SCRIPT.with_name("verify_skill_install.sh")), str(repo), "java", "tree-sitter"],
                                env=env, capture_output=True, text=True, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("individual binary override", result.stderr)
        env.pop("CHIASMUS_DISCOVER_BIN")
        result = subprocess.run(["bash", str(SCRIPT.with_name("verify_skill_install.sh")), str(repo), "java", "tree-sitter"],
                                env=env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(stage / "chiasmus-discover"), result.stdout)

    def test_inventory_library_does_not_select_unverified_repo_binary(self) -> None:
        repo = self.root / "repo"
        (repo / "bin").mkdir(parents=True)
        stale = repo / "bin" / "chiasmus-discover"
        stale.write_text("#!/bin/sh\nexit 0\n")
        stale.chmod(0o755)
        self.write_index([])
        library = SCRIPT.with_name("parity_inventory_lib.rb")
        result = subprocess.run(["ruby", "-r", str(library), "-e",
                                 "puts ParityInventory.discover_crystal_binary(ARGV[0]).inspect", str(repo)],
                                capture_output=True, text=True, check=False,
                                env={**os.environ, "CHIASMUS_RELEASE_INDEX": str(self.index)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "nil")

    def test_completion_gate_uses_one_verified_toolchain(self) -> None:
        self.make_release("v1.0.0", self.host_platform(), {"facts.typed-declarations"})
        stage = self.root / "stage-v1.0.0" / "chiasmus"
        for name, body in (("facts", b"#!/bin/sh\necho 'defines(source).'\n"),
                           ("complete", b"#!/bin/sh\necho 'verified-completion'\n")):
            (stage / f"chiasmus-{name}").write_bytes(body)
        manifest_path = stage / "toolchain-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        for name in ("facts", "complete"):
            body = (stage / f"chiasmus-{name}").read_bytes()
            manifest["files"][f"chiasmus-{name}"] = {"sha256": hashlib.sha256(body).hexdigest(), "size": len(body)}
        manifest_path.write_text(json.dumps(manifest))
        repo = self.root / "repo"
        for directory in ("upstream", "src"):
            (repo / directory).mkdir(parents=True)
        (repo / "upstream" / "Probe.java").write_text("class Probe {}")
        (repo / "src" / "probe.cr").write_text("class Probe; end")
        inventory = repo / "inventory.tsv"
        inventory.write_text("id\tkind\tstatus\n")
        env = {**os.environ, "CHIASMUS_TOOLCHAIN_DIR": str(stage)}
        result = subprocess.run(["bash", str(SCRIPT.with_name("check_completion_gate.sh")),
                                 str(repo), str(inventory), "upstream", "java", "src"],
                                env=env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("verified-completion", result.stdout)

    def write_index(self, releases: list[dict[str, object]]) -> None:
        self.index.write_text(json.dumps(releases), encoding="utf-8")

    def host_platform(self) -> str:
        system = "darwin" if platform.system() == "Darwin" else "linux"
        cpu = "aarch64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"
        return f"{system}-{cpu}"

    def resolve(self, platform: str, *capabilities: str, offline: bool = False) -> Path:
        result = self.run_resolver(platform, *capabilities, offline=offline)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.strip().splitlines()
        self.assertEqual(len(lines), 1, result.stdout)
        path = Path(lines[0])
        self.assertTrue(path.is_absolute(), lines[0])
        return path

    def run_resolver(
        self,
        platform: str,
        *capabilities: str,
        offline: bool = False,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            "python3", str(SCRIPT), "--platform", platform,
            "--release-index", str(self.index), "--cache-dir", str(self.cache),
        ]
        for capability in capabilities:
            command.extend(["--require-capability", capability])
        if offline:
            command.append("--offline")
        process_env = os.environ.copy()
        for name in ("CHIASMUS_TOOLCHAIN_DIR", "CHIASMUS_DISCOVER_BIN", "CHIASMUS_FACTS_BIN", "CHIASMUS_PARITY_BIN"):
            process_env.pop(name, None)
        process_env.update(env or {})
        return subprocess.run(command, text=True, capture_output=True, env=process_env, check=False)

    def make_release(
        self,
        version: str,
        platform: str,
        capabilities: set[str],
        *,
        manifest_platform: str | None = None,
        corrupt: bool = False,
        prerelease: bool = False,
        archive_format: str = "tar",
    ) -> dict[str, object]:
        stage = self.root / f"stage-{version}" / "chiasmus"
        (stage / "grammars").mkdir(parents=True)
        executable = ".exe" if platform.startswith("windows-") else ""
        extension = "dll" if platform.startswith("windows-") else "dylib" if platform.startswith("darwin-") else "so"
        payload = {
            **{f"chiasmus-{tool}{executable}": f"tool:{tool}".encode()
               for tool in ("discover", "facts", "parity", "plan", "complete")},
            **{f"grammars/libtree-sitter-{language}.{extension}": f"grammar:{language}".encode()
               for language in ("java", "go", "crystal")},
        }
        for relative, contents in payload.items():
            target = stage / relative
            target.write_bytes(contents)
            if relative.startswith("chiasmus-"):
                target.chmod(0o755)
        capability_groups: dict[str, list[str]] = {}
        for capability in capabilities:
            tool, name = capability.split(".", 1)
            capability_groups.setdefault(tool, []).append(name)
        manifest = {
            "manifest_version": 1,
            "platform": manifest_platform or platform,
            "source_commit": "a" * 40,
            "build_id": version,
            "capabilities": capability_groups,
            "schema_versions": {"extraction_cache": "5", "declaration_id": "v1", "port_concept": 1, "report": 1},
            "files": {name: {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
                      for name, data in payload.items()},
        }
        (stage / "toolchain-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        suffix = "zip" if archive_format == "zip" else "tar.gz"
        archive = self.archive_dir / f"{version}.{suffix}"
        if archive_format == "zip":
            with zipfile.ZipFile(archive, "w") as bundle:
                for path in stage.rglob("*"):
                    if path.is_file():
                        bundle.write(path, path.relative_to(stage.parent).as_posix())
        else:
            with tarfile.open(archive, "w:gz") as bundle:
                bundle.add(stage, arcname="chiasmus")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if corrupt:
            archive.write_bytes(archive.read_bytes() + b"tampered")
        return {
            "archive": str(archive),
            "tag_name": version,
            "draft": False,
            "prerelease": prerelease,
            "published_at": "2026-01-01T00:00:00Z",
            "assets": [{
                "name": f"chiasmus-{'macOS' if platform.startswith('darwin-') else 'Linux' if platform.startswith('linux-') else 'Windows'}-{platform.split('-', 1)[1]}-{version}.{suffix}",
                "browser_download_url": archive.as_uri(),
                "digest": f"sha256:{digest}",
            }],
        }


if __name__ == "__main__":
    unittest.main()
