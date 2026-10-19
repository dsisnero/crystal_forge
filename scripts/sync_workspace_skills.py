#!/usr/bin/env python3
"""Refresh workspace skills while preserving installed origin metadata.

Run with --check to detect drift. Resource directories link to canonical source;
existing copies are backed up before replacement. Local binaries are untouched.
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import tempfile


REPO = Path(__file__).resolve().parents[1]
METADATA = re.compile(r"^metadata:[^\n]*\n(?:(?:[ \t]+[^\n]*|)[\n])*", re.MULTILINE)


def installed_text(source: str, current: str) -> str:
    frontmatter = current.split("---", 2)
    origin = METADATA.search(frontmatter[1]) if len(frontmatter) == 3 else None
    if not origin:
        return source
    parts = source.split("---", 2)
    parts[1] = METADATA.sub("", parts[1]).rstrip() + "\n" + origin.group().rstrip() + "\n"
    return "---".join(parts)


def sync(repo: Path, check: bool) -> int:
    destination = repo / ".agents" / "skills"
    differences = []
    backup = None

    def preserve(path: Path) -> None:
        nonlocal backup
        if not path.exists() and not path.is_symlink():
            return
        if backup is None:
            backup = Path(tempfile.mkdtemp(prefix="crystal-forge-skills-backup-"))
        saved = backup / path.relative_to(destination)
        saved.parent.mkdir(parents=True, exist_ok=True)
        if path.is_dir() and not path.is_symlink():
            shutil.copytree(path, saved, symlinks=True)
            shutil.rmtree(path)
        else:
            shutil.copy2(path, saved, follow_symlinks=False)
            path.unlink()

    for skill in sorted((repo / "skills").glob("*/SKILL.md")):
        target = destination / skill.parent.name
        entries = [source for source in skill.parent.iterdir()
                   if not source.name.startswith(".") and source.name != "bin"]
        entries += [source for source in (skill.parent / "bin" / "README.md",
                                         skill.parent / "bin" / ".gitignore") if source.is_file()]
        for source in sorted(entries):
            path = target / source.relative_to(skill.parent)
            if source.is_dir():
                if path.is_symlink() and path.resolve() == source.resolve():
                    continue
                differences.append(str(path.relative_to(repo)))
                if not check:
                    preserve(path)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.symlink_to(os.path.relpath(source, path.parent), target_is_directory=True)
            else:
                expected = source.read_text()
                if source.name == "SKILL.md":
                    expected = installed_text(expected, path.read_text() if path.exists() else "")
                if path.is_file() and path.read_text() == expected:
                    continue
                differences.append(str(path.relative_to(repo)))
                if not check:
                    preserve(path)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(expected)
                    shutil.copymode(source, path)
    for path in differences:
        print(("STALE " if check else "UPDATED ") + path)
    if backup:
        print(f"Previous files preserved at {backup}")
    if not differences:
        print("Workspace skills match canonical sources.")
    return int(check and bool(differences))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    raise SystemExit(sync(REPO, args.check))
