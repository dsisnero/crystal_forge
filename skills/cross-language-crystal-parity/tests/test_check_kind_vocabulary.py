"""Behavioral tests for check_kind_vocabulary.py (offline, no Chiasmus binary)."""

from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "check_kind_vocabulary.py"

FAKE_DISCOVER = """#!/usr/bin/env python3
import pathlib, sys
lang = sys.argv[sys.argv.index("--language") + 1]
directory = pathlib.Path(sys.argv[sys.argv.index("--dir") + 1])
spec = directory / "kinds.txt"
if spec.is_file():
    rows = []
    for line in spec.read_text().splitlines():
        kind, count = line.split()
        rows.append((kind, int(count)))
else:
    rows = {
        "rust": [("class", 2), ("function", 5), ("const", 1), ("reference.call", 7)],
        "go": [("method", 3), ("params", 4)],
    }.get(lang, [])
print("# source_id\\tkind\\tstatus\\tcrystal_refs\\tnotes")
for kind, count in rows:
    for index in range(count):
        print(f"f{index}.rs::{kind}::{kind}_{index}\\t{kind}\\tported\\t-\\tparser=fake")
"""

SKILL_LIB = """module ParityInventory
  CURATED_KINDS = {
    'rust' => Set.new(%w[const struct enum trait type func function method test class interface]),
    'go' => Set.new(%w[class const func function interface method struct test type])
  }.freeze
end
"""


class CheckKindVocabularyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="kind-vocab-")
        self.root = Path(self.temp.name)
        self.discover = self.root / "fake-discover"
        self.discover.write_text(FAKE_DISCOVER, encoding="utf-8")
        self.discover.chmod(self.discover.stat().st_mode | stat.S_IEXEC)
        self.skill_lib = self.root / "parity_inventory_lib.rb"
        self.skill_lib.write_text(SKILL_LIB, encoding="utf-8")
        self.scan_dir = self.root / "src"
        self.scan_dir.mkdir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_check(self, *extra: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--discover-bin", str(self.discover),
             "--skill-lib", str(self.skill_lib), "--scan", f"rust={self.scan_dir}", *extra],
            capture_output=True, text=True,
        )

    def test_passes_when_every_declaration_kind_is_curated(self) -> None:
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no drops", result.stdout)
        # reference.call is auxiliary, so it is reported as ignored, not dropped
        self.assertIn("7 auxiliary rows ignored", result.stdout)

    def test_fails_with_row_counts_for_a_missing_kind(self) -> None:
        result = self.run_check(
            "--curated-override", "rust=const,struct,enum,trait,type,func,method,test"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("dropped\tclass\t2", result.stdout)
        self.assertIn("dropped\tfunction\t5", result.stdout)
        self.assertIn("total dropped: 7 rows", result.stdout)

    def test_header_row_is_not_counted_as_a_kind(self) -> None:
        result = self.run_check("--emit-prolog")
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("emits(rust, 'source_id'", result.stdout)

    def test_multiple_roots_for_one_language_are_summed(self) -> None:
        other = self.root / "src2"
        other.mkdir()
        (self.scan_dir / "kinds.txt").write_text("class 2\nfunction 5\n", encoding="utf-8")
        (other / "kinds.txt").write_text("const 3\nreference.call 4\n", encoding="utf-8")

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--discover-bin", str(self.discover),
             "--skill-lib", str(self.skill_lib),
             "--scan", f"rust={self.scan_dir}", "--scan", f"rust={other}"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("10 declarations in 3 kinds", result.stdout)
        self.assertIn("from 2 roots", result.stdout)
        self.assertIn("4 auxiliary rows ignored", result.stdout)

    def test_typescript_field_props_are_auxiliary(self) -> None:
        (self.scan_dir / "kinds.txt").write_text(
            "class 1\nfield_prop 3\nfield 2\n", encoding="utf-8"
        )
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--discover-bin", str(self.discover),
             "--skill-lib", str(self.skill_lib), "--scan", f"rust={self.scan_dir}"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("5 auxiliary rows ignored", result.stdout)
        self.assertIn("1 declarations in 1 kinds", result.stdout)

    def test_emit_prolog_quotes_dotted_atoms(self) -> None:
        result = self.run_check("--emit-prolog")
        self.assertIn("auxiliary('reference.call').", result.stdout)
        self.assertIn("\\+ auxiliary(Kind)", result.stdout)


if __name__ == "__main__":
    unittest.main()
