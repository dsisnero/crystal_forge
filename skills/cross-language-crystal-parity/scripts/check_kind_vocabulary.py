#!/usr/bin/env python3
"""Gate each language's curated kind set against what discovery actually emits.

`chiasmus-discover` writes declaration rows and auxiliary rows (params, fields,
package, references, definition.*) into the same TSV. A curated kind set can only
drop declarations, so the check is only meaningful once auxiliary rows are
excluded -- that split is the vocabulary documented under "Curated kind
vocabulary" in SKILL.md, and this script makes it executable.

For every language it reports the declaration kinds discovery emits that the
curated set does not contain, with row counts, because a missing kind named
`function` is 4,796 lost rows and a missing kind named `interface` is 15.

Exit status: 0 when every emitted declaration kind is curated, 1 on drops,
2 on usage or toolchain failure.

Usage:
  scripts/check_kind_vocabulary.py --scan go=vendor/upstream/go \\
                                   --scan rust=vendor/upstream/crates/core/src

  # prove the gate catches a regression before trusting it
  scripts/check_kind_vocabulary.py --scan rust=vendor/upstream \\
      --curated-override rust=const,struct,enum,trait,type,func,method,test
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from toolchain_lib import ToolchainError, binary  # noqa: E402

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SKILL_LIB = SCRIPT_DIR / "parity_inventory_lib.rb"

# Rows about a declaration rather than declarations. Dotted kinds are namespaced
# auxiliaries by construction, so they are classified structurally instead of
# being enumerated forever.
AUXILIARY_KINDS = {"params", "return_type", "field", "package"}


def is_auxiliary(kind: str, extra: set[str]) -> bool:
    return "." in kind or kind in AUXILIARY_KINDS or kind in extra


def run_discover(discover_bin: str, language: str, directory: str) -> dict[str, int]:
    result = subprocess.run(
        [discover_bin, "--language", language, "--dir", directory],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"chiasmus-discover failed for {language} in {directory} "
            f"({result.returncode}): {result.stderr.strip()[:400]}"
        )

    counts: dict[str, int] = {}
    for line in result.stdout.splitlines():
        if not line or line.startswith("#"):
            continue  # the header is row-shaped; counting it invents a kind
        columns = line.split("\t")
        if len(columns) < 2:
            continue
        kind = columns[1].strip()
        if kind:
            counts[kind] = counts.get(kind, 0) + 1
    return counts


def curated_from_ruby(skill_lib: Path) -> dict[str, set[str]]:
    """Ask the library itself, so the kind sets have one source of truth."""
    script = (
        'require_relative "parity_inventory_lib"; '
        'require "json"; '
        "print JSON.generate(ParityInventory::CURATED_KINDS.transform_values { |kinds| kinds.to_a })"
    )
    result = subprocess.run(
        ["ruby", "-e", script],
        cwd=str(skill_lib.parent),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError(result.stderr.strip() or "ruby produced no curated kinds")
    return {language: set(kinds) for language, kinds in json.loads(result.stdout).items()}


def curated_from_source(skill_lib: Path) -> dict[str, set[str]]:
    """Fallback when ruby is unavailable: read the literal sets out of the file."""
    text = skill_lib.read_text(encoding="utf-8")
    curated: dict[str, set[str]] = {}
    for language, kinds in re.findall(r"'(\w+)'\s*=>\s*Set\.new\(%w\[([^\]]*)\]\)", text):
        curated[language] = set(kinds.split())
    if not curated:
        raise SystemExit(f"no curated kind sets found in {skill_lib}")
    return curated


def render_prolog(emitted: dict[str, dict[str, int]], curated: dict[str, set[str]],
                  extra_auxiliary: set[str]) -> str:
    """The same question as an SMT/Prolog-style template for chiasmus_verify."""
    def atom(value: str) -> str:
        if re.fullmatch(r"[a-z][A-Za-z0-9_]*", value):
            return value
        return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

    lines = [":- dynamic(auxiliary/1).", ""]
    for language, counts in emitted.items():
        for kind, count in sorted(counts.items()):
            lines.append(f"emits({atom(language)}, {atom(kind)}, {count}).")
    lines.append("")
    for kind in sorted({kind for counts in emitted.values() for kind in counts}):
        if is_auxiliary(kind, extra_auxiliary):
            lines.append(f"auxiliary({atom(kind)}).")
    lines.append("")
    for language in sorted(emitted):
        for kind in sorted(curated.get(language, set())):
            lines.append(f"curated({atom(language)}, {atom(kind)}).")
    lines.append("")
    lines.append("declaration(Kind) :- emits(_, Kind, _), \\+ auxiliary(Kind).")
    lines.append("dropped(Lang, Kind, N) :- emits(Lang, Kind, N), declaration(Kind), \\+ curated(Lang, Kind).")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--scan", action="append", default=[], metavar="LANG=DIR",
                        help="language and source directory to discover (repeatable)")
    parser.add_argument("--discover-bin", help="discover binary (default: resolved toolchain)")
    parser.add_argument("--skill-lib", default=str(DEFAULT_SKILL_LIB),
                        help="parity_inventory_lib.rb providing CURATED_KINDS")
    parser.add_argument("--curated-override", action="append", default=[],
                        metavar="LANG=KIND[,KIND...]",
                        help="replace the curated set for LANG (used to prove the gate catches a regression)")
    parser.add_argument("--extra-auxiliary", action="append", default=[],
                        help="additional non-declaration kind (repeatable)")
    parser.add_argument("--emit-prolog", action="store_true",
                        help="print the equivalent Prolog program for chiasmus_verify")
    args = parser.parse_args(argv)

    if not args.scan:
        parser.error("at least one --scan LANG=DIR is required")

    try:
        discover_bin = binary("chiasmus-discover", ["discover.tree-sitter"], args.discover_bin)
    except ToolchainError as error:
        print(str(error), file=sys.stderr)
        return 2

    emitted: dict[str, dict[str, int]] = {}
    for entry in args.scan:
        language, _, directory = entry.partition("=")
        if not language or not directory:
            parser.error(f"--scan expects LANG=DIR, got {entry!r}")
        emitted[language] = run_discover(discover_bin, language, directory)

    skill_lib = Path(args.skill_lib).expanduser()
    try:
        curated = curated_from_ruby(skill_lib)
    except (RuntimeError, FileNotFoundError, json.JSONDecodeError):
        curated = curated_from_source(skill_lib)
    for override in args.curated_override:
        language, _, kinds = override.partition("=")
        curated[language] = {part.strip() for part in kinds.split(",") if part.strip()}

    extra = set(args.extra_auxiliary)
    if args.emit_prolog:
        print(render_prolog(emitted, curated, extra))

    total_drops = 0
    for language in sorted(emitted):
        counts = emitted[language]
        declarations = {k: v for k, v in counts.items() if not is_auxiliary(k, extra)}
        auxiliaries = sum(v for k, v in counts.items() if is_auxiliary(k, extra))
        print(f"{language}: {sum(declarations.values())} declarations in "
              f"{len(declarations)} kinds ({auxiliaries} auxiliary rows ignored); "
              f"curated set has {len(curated.get(language, set()))} kinds")
        for kind in sorted(declarations):
            if kind not in curated.get(language, set()):
                print(f"  dropped\t{kind}\t{declarations[kind]}")
                total_drops += declarations[kind]

    if total_drops:
        print(f"\ntotal dropped: {total_drops} rows in uncurated declaration kinds")
        return 1
    print("\nno drops: every emitted declaration kind is curated")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
