#!/usr/bin/env python3
"""Per-declaration drift report for a vendored upstream bump.

`git diff --name-status old..new` answers "which paths changed" and the parity
triages assign those *paths* to phases. A path can hold dozens of declarations,
so the work item a phase actually owns is invisible until someone reads the diff.

This produces the missing granularity: run `chiasmus-discover` on the old tag and
on the working tree, diff the declaration ids, and emit one row per declaration
with change kind, visibility, phase (inherited from the path triage) and ledger
status.

Change kinds:
  added    present in new, absent in old, name not seen elsewhere in old
  moved    present in new with the same kind+qualified name, different file
  removed  present in old, absent in new, name not seen elsewhere in new
  gone     present in old, absent in new, and the name is not anywhere in new

Usage:
  scripts/parity/vendor_drift.py \\
      --vendor ../crig/vendor/rig \\
      --old v0.43.0 --new v0.44.0 \\
      --scan-subdirs crates/rig-core/src crates/rig-core/tests \\
      --ledger ../crig/plans/inventory/rust_port_inventory.tsv \\
      --triage ../crig/plans/inventory/v44_delta_triage.tsv \\
      --out ../crig/plans/inventory/v44_delta_symbols.tsv

Read-only with respect to the vendor and the ledger. It writes only --out plus
temporary extraction under $TMPDIR.
"""

from __future__ import annotations

import argparse
import collections
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from toolchain_lib import ToolchainError, binary  # noqa: E402

DECL_RE = re.compile(
    r"pub(?:\((?P<restricted>[^)]*)\))?\s+(?:async\s+)?"
    r"(?:unsafe\s+)?(?:fn|struct|enum|trait|const|static|type|mod)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
PRIVATE_HINT_RE = re.compile(r"^\s*(?:async\s+)?(?:fn|struct|enum|trait|const|static|type|mod)\s+")


@dataclass(frozen=True)
class Decl:
    source_id: str
    path: str          # repo-relative, e.g. src/catalog/mod.rs
    kind: str
    name: str          # qualified within the file, e.g. Catalog.new


def run(cmd: list[str], cwd: Path | None = None) -> str:
    result = subprocess.run(cmd, cwd=str(cwd) if cwd else None, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"{' '.join(cmd)} failed ({result.returncode}): {result.stderr[:400]}")
    return result.stdout


def extract(vendor: Path, ref: str, subdir: str, destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    archive = subprocess.run(
        ["git", "-C", str(vendor), "archive", ref, subdir],
        capture_output=True,
    )
    if archive.returncode != 0:
        raise SystemExit(f"git archive {ref} {subdir} failed: {archive.stderr.decode()[:400]}")
    with tempfile.NamedTemporaryFile(suffix=".tar", delete=False) as handle:
        handle.write(archive.stdout)
        tar_path = handle.name
    try:
        with tarfile.open(tar_path) as tar:
            tar.extractall(destination)
    finally:
        os.unlink(tar_path)
    return destination / subdir


def discover(discover_bin: str, language: str, directory: Path, prefix: str) -> dict[str, Decl]:
    output = run([discover_bin, "--language", language, "--dir", str(directory)])
    declarations: dict[str, Decl] = {}
    for line in output.splitlines():
        if not line or line.startswith("#"):
            continue  # header is row-shaped; counting it invents a kind
        columns = line.split("\t")
        if len(columns) < 2:
            continue
        raw_id, kind = columns[0], columns[1]
        path, _, name = raw_id.partition("::")
        source_id = f"{prefix}{raw_id}"
        declarations[source_id] = Decl(source_id=source_id, path=f"{prefix}{path}", kind=kind, name=name)
    return declarations


def visibility_index(root: Path) -> dict[str, str]:
    """path -> 'pub' | 'restricted' | 'private' for every path we scanned."""
    index: dict[str, str] = {}
    for file_path in root.rglob("*.rs"):
        relative = file_path.relative_to(root.parent).as_posix()
        try:
            text = file_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if DECL_RE.search(text):
            index[relative] = "pub"
        else:
            index[relative] = "private"
    return index


def declaration_visibility(path: str, name: str, cache: dict[str, str], roots: list[Path]) -> str:
    short = name.split(".")[-1].split("::")[-1]
    relative = path.split("/", 1)[1] if "/" in path else path
    for root in roots:
        candidate = root / relative
        if not candidate.exists():
            continue
        key = str(candidate)
        if key not in cache:
            cache[key] = candidate.read_text(encoding="utf-8", errors="ignore")
        text = cache[key]
        for match in DECL_RE.finditer(text):
            if match.group("name") != short:
                continue
            return "pub(crate)" if match.group("restricted") else "pub"
        if re.search(r"(?:^|\n)\s*(?:async\s+)?(?:fn|struct|enum|trait|const|static|type|mod)\s+"
                     + re.escape(short) + r"\b", text):
            return "private"
        return "unknown"
    return "unknown"


def read_ledger(path: Path) -> dict[str, str]:
    statuses: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        columns = line.split("\t")
        if len(columns) >= 3:
            statuses[columns[0]] = columns[2]
    return statuses


def read_triage(path: Path) -> dict[str, str]:
    phases: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("upstream_path") or line.startswith("#"):
            continue
        columns = line.split("\t")
        if len(columns) >= 3:
            phases[columns[0]] = columns[2]
    return phases


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--vendor", required=True, help="git checkout of the upstream (e.g. vendor/rig)")
    parser.add_argument("--old", required=True, help="tag or commit of the previous baseline")
    parser.add_argument("--new", default="HEAD", help="tag, commit or HEAD of the new baseline")
    parser.add_argument("--scan-subdirs", nargs="+", default=["crates/rig-core/src"],
                        help="subdirectories to discover")
    parser.add_argument("--prefix-mode", choices=["name", "path"], default="name",
                        help="id prefix per scan dir: 'name' uses its last component (src/, tests/); "
                             "'path' uses the dir relative to --prefix-root (Java modules)")
    parser.add_argument("--prefix-root",
                        help="root that --prefix-mode path is relative to (default: the vendor root)")
    parser.add_argument("--language", default="rust")
    parser.add_argument("--discover-bin", help="discover binary (default: resolved toolchain)")
    parser.add_argument("--ledger", help="port inventory TSV (source_id/kind/status/...)")
    parser.add_argument("--triage", help="path-level delta triage TSV (upstream_path/change/assigned_phase/note)")
    parser.add_argument("--out", required=True)
    parser.add_argument("--samples", type=int, default=6)
    args = parser.parse_args(argv)

    vendor = Path(args.vendor).expanduser().resolve()
    scan_subdirs = args.scan_subdirs
    try:
        args.discover_bin = binary("chiasmus-discover", ["discover.tree-sitter"], args.discover_bin)
    except ToolchainError as error:
        print(str(error), file=sys.stderr)
        return 2

    prefix_root = Path(args.prefix_root).expanduser().resolve() if args.prefix_root else vendor

    def prefix_for(subdir: str) -> str:
        if args.prefix_mode == "path":
            absolute = (vendor / subdir).resolve()
            try:
                return absolute.relative_to(prefix_root).as_posix().rstrip("/") + "/"
            except ValueError:
                raise SystemExit(f"--scan-subdirs {subdir} is outside --prefix-root {prefix_root}")
        return Path(subdir.rstrip("/")).name + "/"

    def merge(target: dict[str, Decl], found: dict[str, Decl], tree: str) -> None:
        for source_id, decl in found.items():
            if source_id in target:
                raise SystemExit(
                    f"duplicate declaration id across scan dirs ({tree}): {source_id}. "
                    f"Use --prefix-mode path (with --prefix-root) so each root keeps its own prefix."
                )
            target[source_id] = decl

    with tempfile.TemporaryDirectory(prefix="vendor-drift-") as work:
        old_root = Path(work) / "old"
        new_root = Path(work) / "new"

        old_decls: dict[str, Decl] = {}
        new_decls: dict[str, Decl] = {}
        for subdir in scan_subdirs:
            prefix = prefix_for(subdir)
            old_tree = extract(vendor, args.old, subdir, old_root)
            new_tree = extract(vendor, args.new, subdir, new_root)
            merge(old_decls, discover(args.discover_bin, args.language, old_tree, prefix), "old")
            merge(new_decls, discover(args.discover_bin, args.language, new_tree, prefix), "new")

        visibility_roots = [new_root / subdir for subdir in scan_subdirs]

        def signature(decl: Decl) -> str:
            return f"{decl.kind}::{decl.name}"

        old_signatures = collections.Counter(signature(d) for d in old_decls.values())
        new_signatures = collections.Counter(signature(d) for d in new_decls.values())

        added, removed = [], []
        for source_id, decl in new_decls.items():
            if source_id in old_decls:
                continue
            change = "moved" if old_signatures[signature(decl)] else "added"
            added.append((decl, change))
        for source_id, decl in old_decls.items():
            if source_id in new_decls:
                continue
            change = "moved-away" if new_signatures[signature(decl)] else "removed"
            removed.append((decl, change))

        ledger = read_ledger(Path(args.ledger).expanduser()) if args.ledger else {}
        triage = read_triage(Path(args.triage).expanduser()) if args.triage else {}
        text_cache: dict[str, str] = {}

        rows = []
        for decl, change in added:
            visibility = declaration_visibility(decl.path, decl.name, text_cache, visibility_roots)
            rows.append({
                "source_id": decl.source_id,
                "kind": decl.kind,
                "change": change,
                "visibility": visibility,
                "phase": triage.get(decl.path, "unassigned"),
                "ledger_status": ledger.get(decl.source_id, "missing"),
                "upstream_path": decl.path,
            })
        for decl, change in removed:
            rows.append({
                "source_id": decl.source_id,
                "kind": decl.kind,
                "change": change,
                "visibility": "n/a",
                "phase": triage.get(decl.path, "unassigned"),
                "ledger_status": ledger.get(decl.source_id, "absent"),
                "upstream_path": decl.path,
            })
        rows.sort(key=lambda row: (row["phase"], row["upstream_path"], row["source_id"]))

        out_path = Path(args.out).expanduser()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        header = "\t".join(["source_id", "kind", "change", "visibility", "phase", "ledger_status", "upstream_path"])
        body = "\n".join("\t".join(row[key] for key in
                                  ("source_id", "kind", "change", "visibility", "phase", "ledger_status", "upstream_path"))
                         for row in rows)
        out_path.write_text(header + "\n" + body + ("\n" if body else ""), encoding="utf-8")

        # ---- report -------------------------------------------------------
        print(f"{args.old} -> {args.new}  ({args.language}, {', '.join(scan_subdirs)})")
        print(f"declarations: old={len(old_decls)} new={len(new_decls)}")
        changes = collections.Counter(row["change"] for row in rows)
        print(f"changed declarations: {len(rows)}  " +
              "  ".join(f"{change}={count}" for change, count in sorted(changes.items())))

        added_non_test = [r for r in rows
                          if r["change"] in ("added", "moved") and r["kind"] != "test"]
        visibility = collections.Counter(r["visibility"] for r in added_non_test)
        print(f"new non-test declarations: {len(added_non_test)}  " +
              "  ".join(f"{name}={count}" for name, count in visibility.most_common()))
        print(f"  already in ledger: {sum(1 for r in added_non_test if r['ledger_status'] != 'missing')}")

        per_phase = collections.Counter(
            r["phase"] for r in added_non_test if r["visibility"] in ("pub", "pub(crate)")
        )
        print("\nportable (pub) new declarations per phase:")
        for phase, count in sorted(per_phase.items()):
            print(f"  {phase:12s} {count:4d}")

        unassigned = [r for r in rows if r["phase"] == "unassigned"]
        if unassigned:
            print(f"\n{len(unassigned)} declarations are in files the triage does not list "
                  f"(sample): {[r['upstream_path'] for r in unassigned[:3]]}")

        print(f"\nwrote {out_path} ({len(rows)} rows)")
        if rows:
            print("sample:")
            for row in rows[: args.samples]:
                print(f"  {row['change']:7s} {row['visibility']:9s} {row['phase']:10s} "
                      f"{row['ledger_status']:7s} {row['source_id']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
