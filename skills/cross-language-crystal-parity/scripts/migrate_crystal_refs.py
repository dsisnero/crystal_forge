#!/usr/bin/env python3
"""Migrate a port ledger's crystal_refs from file paths to symbol ids.

Two problems this solves, in one pass:

1. The ledger names files (`src/tea/clipboard.cr`) while the call graph speaks in
   symbols (`calls(run, init)`), so every symbol mapping had to be guessed from
   names. A symbol ref (`path::kind::qualified_name`) is a lookup.
2. A file ref cannot notice a method being renamed inside an intact file. A
   symbol ref can.

It never edits the input. It writes a migrated copy plus a staged report:

  stage 0  already a symbol ref                        left untouched
  stage 1  qualified-name suffix match in the ref'd file  Program.Run -> Tea.Program.run
  stage 2  bare name match in the ref'd file
  stage 3  qualified-name suffix match elsewhere         (file moved; the ref was stale)
  stage 4  unresolved                                    (valid file ref, no match: renamed/collapsed)
  stage 5  coarse ref: names a directory, not a file     (cannot be mapped; fix the ledger)
  stage 6  the ref's file does not exist                 (stale path)

`::` is deliberate: check_port_inventory.rb validates `ref.split(":").first` as a
path, so `path::kind::name` keeps passing while `path#name` would not.

Usage:
  scripts/parity/migrate_crystal_refs.py \\
      --ledger ../bubbletea.cr/plans/inventory/go_port_inventory.tsv \\
      --port-facts /tmp/cr-facts.pl \\
      --port-root ../bubbletea.cr \\
      --out temp/go_port_inventory.migrated.tsv
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from toolchain_lib import ToolchainError, binary  # noqa: E402

DEFINE_RE = re.compile(r"^defines\((.+?),\s*(.+?),\s*([a-z_]+),\s*(\d+),\s*(\d+)\)\.$")
QNAME_RE = re.compile(r"^qualified_name\((.+?),\s*(.+?),\s*(.+?)\)\.$")


def atom_value(text: str) -> str:
    text = text.strip()
    if text.startswith("'") and text.endswith("'"):
        text = text[1:-1].replace("\\'", "'").replace("\\\\", "\\")
    return text


def snake(segment: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", segment).lower()


def segments(name: str) -> tuple[str, ...]:
    """`Tea::Program#run` and `Program.Run` both become ('tea','program','run')."""
    pieces = re.split(r"::|[.#]", name)
    return tuple(snake(piece.rstrip("?!")) for piece in pieces if piece)


@dataclass
class Symbol:
    file: str            # repo-relative
    bare: str
    kind: str
    qname: str
    qsegments: tuple[str, ...]

    @property
    def ref(self) -> str:
        return f"{self.file}::{self.kind}::{self.qname}"


@dataclass
class Row:
    columns: list[str]
    stage: int = 0
    candidates: int = 0
    out_refs: list[str] = field(default_factory=list)
    moved: list[tuple[str, str]] = field(default_factory=list)  # (old file, new file)
    original: str = ""


def load_port(facts_paths: list[Path], port_root: Path) -> dict[str, list[Symbol]]:
    qnames: dict[tuple[str, str], str] = {}
    defines: list[tuple[str, str, str]] = []

    for facts in facts_paths:
        with facts.open(encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line.startswith("defines(") and (match := DEFINE_RE.match(line)):
                    defines.append((atom_value(match.group(1)), atom_value(match.group(2)), match.group(3)))
                elif line.startswith("qualified_name(") and (match := QNAME_RE.match(line)):
                    qnames[(atom_value(match.group(1)), atom_value(match.group(2)))] = atom_value(match.group(3))

    by_file: dict[str, list[Symbol]] = {}
    for file_name, bare, kind in defines:
        try:
            relative = str(Path(file_name).resolve().relative_to(port_root.resolve()))
        except ValueError:
            relative = file_name
        qname = qnames.get((file_name, bare), bare)
        by_file.setdefault(relative, []).append(
            Symbol(file=relative, bare=bare, kind=kind, qname=qname, qsegments=segments(qname))
        )
    return by_file


def read_ledger(path: Path) -> list[Row]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        rows.append(Row(columns=line.split("\t")))
    return rows


def source_symbol(row: Row) -> str | None:
    source_id = row.columns[0]
    parts = source_id.split("::")
    return parts[-1] if parts else None


# Canonical output is comma-separated with no spaces: the column is already
# tab-delimited, commas need no quoting, and `split(",")` works everywhere.
# Input is parsed liberally because older ledgers also used `;` and ` + `.
REF_SEPARATOR = ","
REF_SPLIT = re.compile(r"\s*[,;]\s*|\s+\+\s+")


def split_refs(column: str) -> list[str]:
    return [ref.strip() for ref in REF_SPLIT.split(column) if ref.strip() and ref.strip() != "-"]


def join_refs(refs: list[str]) -> str:
    return REF_SEPARATOR.join(refs)


def is_symbol_ref(ref: str) -> bool:
    return "::" in ref


def dedupe(candidates: list[Symbol]) -> list[Symbol]:
    seen: dict[str, Symbol] = {}
    for symbol in candidates:
        seen.setdefault(f"{symbol.file}::{symbol.qname}", symbol)
    return list(seen.values())


def pick(candidates: list[Symbol]) -> Symbol | None:
    unique = dedupe(candidates)
    return unique[0] if len(unique) == 1 else None


def classify(row: Row, port_by_file: dict[str, list[Symbol]], port_root: Path) -> Row:
    refs = split_refs(row.columns[3]) if len(row.columns) > 3 else []
    if not refs:
        return row
    row.original = row.columns[3]

    if all(is_symbol_ref(ref) for ref in refs):
        row.stage = 0
        row.out_refs = list(refs)
        return row

    source = source_symbol(row)
    if not source:
        row.stage = 4
        row.out_refs = list(refs)
        return row
    source_segments = segments(source)
    bare = source_segments[-1]

    first_ref = next((ref for ref in refs if not is_symbol_ref(ref)), None)
    first_dir = Path(first_ref.split(":")[0]).parent if first_ref else None

    entries = []
    for ref in refs:
        if is_symbol_ref(ref):
            entries.append({"ref": ref, "kind": "symbol"})
            continue
        file_ref = ref.split(":")[0]
        target = port_root / file_ref
        if not target.exists() and first_dir and first_dir != Path("."):
            sibling = port_root / first_dir / file_ref
            if sibling.exists():
                target = sibling
                file_ref = (first_dir / file_ref).as_posix()
        if target.is_dir():
            entries.append({"ref": ref, "kind": "coarse"})
        elif not target.exists():
            entries.append({"ref": ref, "kind": "missing"})
        else:
            entries.append({"ref": ref, "kind": "valid", "file": file_ref})

    def in_file_match(file_ref: str):
        in_file = port_by_file.get(file_ref, [])
        if len(source_segments) > 1:
            candidates = [symbol for symbol in in_file
                          if len(symbol.qsegments) >= len(source_segments)
                          and symbol.qsegments[-len(source_segments):] == source_segments]
            if (picked := pick(candidates)) is not None:
                return picked, 1, len(candidates)
        candidates = [symbol for symbol in in_file if snake(symbol.bare.rstrip("?!")) == bare]
        if (picked := pick(candidates)) is not None:
            return picked, 2, len(candidates)
        if len(source_segments) == 1:
            candidates = [symbol for symbol in in_file
                          if len(symbol.qsegments) >= 1 and symbol.qsegments[-1] == bare]
            if (picked := pick(candidates)) is not None:
                return picked, 1, len(candidates)
        return None, 0, 0

    def global_match():
        candidates = [symbol for symbols in port_by_file.values() for symbol in symbols
                      if len(symbol.qsegments) >= len(source_segments)
                      and symbol.qsegments[-len(source_segments):] == source_segments]
        return pick(candidates), len(candidates)

    # Pass 1: in-file matches for every ref. Pass 2: only then fall back to the
    # whole port, so a multi-target row never prefers a guess over its own file.
    stages = {}
    for index, entry in enumerate(entries):
        if entry["kind"] != "valid":
            continue
        picked, stage, count = in_file_match(entry["file"])
        if picked is not None:
            entry["symbol"] = picked
            stages[index] = stage
            row.candidates = count

    # Only search the whole port when no ref in this row matched its own file:
    # otherwise a resolved row would sprout extra guesses from unrelated files.
    in_file_hits = bool(stages)
    for index, entry in enumerate(entries):
        if entry["kind"] != "valid" or "symbol" in entry or in_file_hits:
            continue
        picked, count = global_match()
        if picked is not None:
            entry["symbol"] = picked
            stages[index] = 3
            row.candidates = count
            if picked.file != entry["file"]:
                row.moved.append((entry["file"], picked.file))

    seen: list[str] = []
    for entry in entries:
        ref = entry["symbol"].ref if "symbol" in entry else entry["ref"]
        if ref not in seen:
            seen.append(ref)
    row.out_refs = seen
    if stages:
        row.stage = min(stages.values())
    elif any(entry["kind"] == "coarse" for entry in entries):
        row.stage = 5
    elif any(entry["kind"] == "missing" for entry in entries):
        row.stage = 6
    else:
        row.stage = 4
    return row


def render(row: Row) -> str:
    columns = list(row.columns)
    if row.out_refs:
        columns[3] = join_refs(row.out_refs)
    if row.moved and len(columns) > 4:
        markers = "; ".join(f"symbol lives in {new}" for _old, new in row.moved)
        note = columns[4]
        columns[4] = f"{note}; {markers}" if note and note != "-" else markers
    return "\t".join(columns)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--port-facts", action="append", default=[],
                        help="existing chiasmus-facts output (repeatable)")
    parser.add_argument("--port-dir", action="append", default=[],
                        help="port source directory to scan when --port-facts is omitted (repeatable)")
    parser.add_argument("--port-language", default="crystal")
    parser.add_argument("--facts-bin", help="chiasmus-facts binary (default: resolved toolchain)")
    parser.add_argument("--port-root", default=".")
    parser.add_argument("--out", required=True)
    parser.add_argument("--samples", type=int, default=8, help="stage-4 samples to print")
    parser.add_argument("--strict-refs", action="store_true",
                        help="reject legacy separators (';', ' + '); output is always comma-separated")
    args = parser.parse_args(argv)

    port_root = Path(args.port_root).expanduser().resolve()

    facts_paths = [Path(path).expanduser() for path in args.port_facts]
    temporary = None
    if not facts_paths:
        if not args.port_dir:
            parser.error("provide --port-facts or at least one --port-dir")
        try:
            facts_bin = binary("chiasmus-facts", override=args.facts_bin)
        except ToolchainError as error:
            print(str(error), file=sys.stderr)
            return 2
        temporary = tempfile.TemporaryDirectory(prefix="crystal-refs-")
        for index, directory in enumerate(args.port_dir):
            target = Path(temporary.name) / f"facts-{index}.pl"
            result = subprocess.run(
                [facts_bin, "--language", args.port_language, "--dir", directory],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                print(f"chiasmus-facts failed for {directory}: {result.stderr[:400]}", file=sys.stderr)
                return 2
            target.write_text(result.stdout, encoding="utf-8")
            facts_paths.append(target)

    port_by_file = load_port(facts_paths, port_root)
    ledger_path = Path(args.ledger).expanduser()

    raw_rows = read_ledger(ledger_path)
    if args.strict_refs:
        legacy = [row.columns[0] for row in raw_rows
                  if len(row.columns) > 3 and re.search(r"[;]|\s\+\s", row.columns[3])]
        if legacy:
            print(f"{len(legacy)} rows use legacy ref separators (';' or ' + '); "
                  f"rewrite them with ',' first:\n  " + "\n  ".join(legacy[:10]), file=sys.stderr)
            return 2
    rows = [classify(row, port_by_file, port_root) for row in raw_rows]

    counts = {stage: 0 for stage in range(7)}
    for row in rows:
        if len(row.columns) > 3 and split_refs(row.columns[3]):
            counts[row.stage] += 1

    total = sum(counts.values())
    print(f"rows with a file ref: {total}")
    labels = {
        0: "already a symbol ref",
        1: "qualified name in the ref'd file",
        2: "bare name in the ref'd file",
        3: "qualified name elsewhere (stale file ref)",
        4: "unresolved (valid file ref, no match)",
        5: "coarse ref: a directory, not a file",
        6: "ref file does not exist",
    }
    for stage in range(7):
        print(f"  stage {stage}: {counts[stage]:4d}  {labels[stage]}")
    resolved = counts[0] + counts[1] + counts[2] + counts[3]
    print(f"resolved: {resolved}/{total} = {100 * resolved / max(1, total):.0f}%")

    unresolved = [row for row in rows if row.stage == 4]
    coarse_rows = [row for row in rows if row.stage == 5]
    if coarse_rows:
        print(f"\ncoarse refs (fix the ledger, then migrate again): {len(coarse_rows)}")
    if unresolved:
        print(f"\nstage 4 samples ({min(args.samples, len(unresolved))} of {len(unresolved)}):")
        for row in unresolved[: args.samples]:
            refs = split_refs(row.columns[3]) if len(row.columns) > 3 else []
            print(f"  {row.columns[0]:48s} refs={refs}")

    # Preserve comment lines verbatim, then the rewritten rows.
    header = [line for line in ledger_path.read_text(encoding="utf-8").splitlines() if line.startswith("#")]
    out_path = Path(args.out).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    body = "\n".join(render(row) for row in rows)
    out_path.write_text("\n".join(header) + ("\n" + body if body else "") + "\n", encoding="utf-8")
    print(f"\nwrote {out_path} ({len(rows)} rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
