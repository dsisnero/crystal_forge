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
import sys
LANG = sys.argv[sys.argv.index("--language") + 1]
ROWS = {
    "rust": [("class", 2), ("function", 5), ("const", 1), ("reference.call", 7)],
    "go": [("method", 3), ("params", 4)],
}
print("# source_id\\tkind\\tstatus\\tcrystal_refs\\tnotes")
for kind, count in ROWS.get(LANG, []):
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

    def test_emit_prolog_quotes_dotted_atoms(self) -> None:
        result = self.run_check("--emit-prolog")
        self.assertIn("auxiliary('reference.call').", result.stdout)
        self.assertIn("\\+ auxiliary(Kind)", result.stdout)


if __name__ == "__main__":
    unittest.main()
