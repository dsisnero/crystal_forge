"""Behavioral tests for migrate_crystal_refs.py (offline facts, no Chiasmus binary)."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "migrate_crystal_refs.py"

FACTS = """\
defines('{root}/src/tea.cr', run, function, 10, 20).
qualified_name('{root}/src/tea.cr', run, 'Tea.Program.run').
defines('{root}/src/tea.cr', send, function, 30, 40).
qualified_name('{root}/src/tea.cr', send, 'Tea.Program.send').
defines('{root}/src/clipboard.cr', read_clipboard, function, 5, 8).
qualified_name('{root}/src/clipboard.cr', read_clipboard, 'Bubbletea.read_clipboard').
defines('{root}/src/other.cr', moved_symbol, function, 1, 2).
qualified_name('{root}/src/other.cr', moved_symbol, 'Other.moved_symbol').
defines('{root}/src/exec.cr', run, function, 60, 70).
qualified_name('{root}/src/exec.cr', run, 'Tea.Exec.run').
"""

LEDGER = """\
# source_id\tkind\tstatus\tcrystal_refs\tnotes
tea.go::func::Run\tfunc\tported\tsrc/tea.cr\tloop
clipboard.go::func::ReadClipboard\tfunc\tported\tsrc/clipboard.cr\tclipboard
other.go::func::MovedSymbol\tfunc\tported\tsrc/tea.cr\tstale file ref
missing.go::func::Gone\tfunc\tported\tsrc/tea.cr\tno counterpart
tea.go::method::Program.Run\tmethod\tported\tsrc/tea.cr\tqualified source name
"""


class MigrateCrystalRefsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="refs-migration-")
        self.root = Path(self.temp.name)
        (self.root / "src").mkdir()
        for name in ("tea.cr", "clipboard.cr", "other.cr", "exec.cr"):
            (self.root / "src" / name).write_text("", encoding="utf-8")
        self.facts = self.root / "facts.pl"
        self.facts.write_text(FACTS.format(root=self.root), encoding="utf-8")
        self.ledger = self.root / "ledger.tsv"
        self.ledger.write_text(LEDGER, encoding="utf-8")
        self.out = self.root / "migrated.tsv"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def migrate(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT),
             "--ledger", str(self.ledger),
             "--port-facts", str(self.facts),
             "--port-root", str(self.root),
             "--out", str(self.out)],
            capture_output=True, text=True,
        )

    def test_stages_bare_name_qualified_name_and_stale_file(self) -> None:
        result = self.migrate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("stage 1:    1", result.stdout)  # Program.Run -> Tea.Program.run
        self.assertIn("stage 2:    2", result.stdout)  # Run, ReadClipboard
        self.assertIn("stage 3:    1", result.stdout)  # MovedSymbol, file ref stale
        self.assertIn("stage 4:    1", result.stdout)  # Gone
        self.assertIn("resolved: 4/5 = 80%", result.stdout)

        rows = self.out.read_text(encoding="utf-8").splitlines()
        self.assertTrue(rows[0].startswith("# source_id"))
        by_id = {row.split("\t")[0]: row.split("\t") for row in rows[1:]}
        self.assertEqual(by_id["tea.go::func::Run"][3], "src/tea.cr::function::Tea.Program.run")
        self.assertEqual(
            by_id["clipboard.go::func::ReadClipboard"][3],
            "src/clipboard.cr::function::Bubbletea.read_clipboard",
        )
        # stage 3: the symbol lives elsewhere, so the ref is repaired and noted
        self.assertEqual(by_id["other.go::func::MovedSymbol"][3], "src/other.cr::function::Other.moved_symbol")
        self.assertIn("symbol lives in src/other.cr", by_id["other.go::func::MovedSymbol"][4])
        # stage 1: the receiver-qualified name beats a same-file bare `run`
        self.assertEqual(by_id["tea.go::method::Program.Run"][3], "src/tea.cr::function::Tea.Program.run")
        # stage 4: untouched, still a file ref
        self.assertEqual(by_id["missing.go::func::Gone"][3], "src/tea.cr")

    def test_never_edits_the_input_ledger(self) -> None:
        before = self.ledger.read_text(encoding="utf-8")
        self.assertEqual(self.migrate().returncode, 0)
        self.assertEqual(self.ledger.read_text(encoding="utf-8"), before)


if __name__ == "__main__":
    unittest.main()
