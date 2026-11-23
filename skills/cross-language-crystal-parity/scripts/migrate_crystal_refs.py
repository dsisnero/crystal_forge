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
from dataclasses import dataclass
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
    symbol: Symbol | None = None
    candidates: int = 0


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


REF_SPLIT = re.compile(r"\s*[,;]\s*|\s+\+\s+")


def split_refs(column: str) -> list[str]:
    """Multiple refs are separated by ',', ';' or ' + ' in real ledgers."""
    return [ref.strip() for ref in REF_SPLIT.split(column) if ref.strip() and ref.strip() != "-"]


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
    if all(is_symbol_ref(ref) for ref in refs):
        row.stage = 0
        return row

    source = source_symbol(row)
    if not source:
        row.stage = 4
        return row
    source_segments = segments(source)

    # A ref that names a directory (or a path that no longer exists) cannot be
    # turned into a symbol, and must not fall back to a global name search:
    # "somewhere in src" is not a mapping. Report it as its own defect.
    usable = []
    coarse = False
    missing = False
    first_ref = next((candidate for candidate in refs if not is_symbol_ref(candidate)), None)
    first_dir = Path(first_ref.split(":")[0]).parent if first_ref else None
    for ref in refs:
        if is_symbol_ref(ref):
            continue
        file_ref = ref.split(":")[0]
        target = port_root / file_ref
        if not target.exists() and first_dir and first_dir != Path("."):
            # `a/b.cr + sibling.cr` means a/sibling.cr
            sibling = port_root / first_dir / file_ref
            if sibling.exists():
                target = sibling
                file_ref = (first_dir / file_ref).as_posix()
        if target.is_dir():
            coarse = True
            continue
        if not target.exists():
            missing = True
            continue
        usable.append(file_ref)

    if not usable:
        row.stage = 5 if coarse else 6
        return row

    for file_ref in usable:
        in_file = port_by_file.get(file_ref, [])

        def qualified_candidates(symbols):
            return [
                symbol for symbol in symbols
                if len(symbol.qsegments) >= len(source_segments)
                and symbol.qsegments[-len(source_segments):] == source_segments
            ]

        bare = source_segments[-1]
        bare_candidates = [symbol for symbol in in_file if snake(symbol.bare.rstrip("?!")) == bare]

        # A receiver-qualified source (`Program.Run`) must prefer the qualified
        # match: bare `run` in the same file may belong to another class.
        if len(source_segments) > 1:
            candidates = qualified_candidates(in_file)
            if (chosen := pick(candidates)) is not None:
                row.stage, row.symbol, row.candidates = 1, chosen, len(candidates)
                return row

        if (chosen := pick(bare_candidates)) is not None:
            row.stage, row.symbol, row.candidates = 2, chosen, len(bare_candidates)
            return row

        if len(source_segments) == 1:
            candidates = qualified_candidates(in_file)
            if (chosen := pick(candidates)) is not None:
                row.stage, row.symbol, row.candidates = 1, chosen, len(candidates)
                return row

    # stage 3: suffix match anywhere (the ledger's file ref was stale)
    everywhere = [symbol for symbols in port_by_file.values() for symbol in symbols]
    candidates = [
        symbol for symbol in everywhere
        if len(symbol.qsegments) >= len(source_segments)
        and symbol.qsegments[-len(source_segments):] == source_segments
    ]
    if (chosen := pick(candidates)) is not None:
        row.stage, row.symbol, row.candidates = 3, chosen, len(candidates)
        return row

    row.stage, row.candidates = 4, len(candidates)
    return row


def render(row: Row) -> str:
    if row.stage in (1, 2, 3) and row.symbol is not None:
        first_ref = split_refs(row.columns[3])[0]
        old_file = first_ref.split(":")[0]
        columns = list(row.columns)
        columns[3] = row.symbol.ref
        if row.stage == 3 and row.symbol.file != old_file:
            note = columns[4] if len(columns) > 4 else ""
            marker = f"symbol lives in {row.symbol.file}"
            columns[4] = f"{note}; {marker}" if note and note != "-" else marker
        return "\t".join(columns)
    return "\t".join(row.columns)


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

    rows = [classify(row, port_by_file, port_root) for row in read_ledger(ledger_path)]

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
