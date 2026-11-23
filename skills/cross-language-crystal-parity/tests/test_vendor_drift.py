"""Behavioral tests for vendor_drift.py (offline: temporary git repo + fake discover)."""

from __future__ import annotations

import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "vendor_drift.py"

FAKE_DISCOVER = """#!/usr/bin/env python3
import pathlib, re, sys
directory = pathlib.Path(sys.argv[sys.argv.index("--dir") + 1])
for path in sorted(directory.rglob("*.rs")):
    relative = path.relative_to(directory).as_posix()
    text = path.read_text()
    for name in re.findall(r"fn\\s+([A-Za-z_][A-Za-z0-9_]*)", text):
        print(f"{relative}::func::{name}\\tfunc\\tported\\t-\\tparser=fake")
"""


def git(*args: str, cwd: Path) -> None:
    subprocess.run(["git", "-c", "user.email=t@example.com", "-c", "user.name=t", *args],
                   cwd=str(cwd), check=True, capture_output=True)


class VendorDriftTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="vendor-drift-")
        self.root = Path(self.temp.name)
        self.vendor = self.root / "vendor"
        (self.vendor / "demo").mkdir(parents=True)
        (self.vendor / "demo" / "keep.rs").write_text("pub fn keep() {}\n", encoding="utf-8")
        (self.vendor / "demo" / "drop.rs").write_text("fn drop_it() {}\n", encoding="utf-8")

        git("init", "-q", cwd=self.vendor)
        git("add", ".", cwd=self.vendor)
        git("commit", "-qm", "fixture: old baseline", cwd=self.vendor)
        git("tag", "v1", cwd=self.vendor)

        (self.vendor / "demo" / "drop.rs").unlink()
        (self.vendor / "demo" / "fresh.rs").write_text("pub fn fresh() {}\n", encoding="utf-8")
        (self.vendor / "demo" / "keep.rs").write_text("pub fn keep() {}\npub fn added() {}\n", encoding="utf-8")
        git("add", "-A", cwd=self.vendor)
        git("commit", "-qm", "fixture: new baseline", cwd=self.vendor)
        git("tag", "v2", cwd=self.vendor)

        self.discover = self.root / "fake-discover"
        self.discover.write_text(FAKE_DISCOVER, encoding="utf-8")
        self.discover.chmod(self.discover.stat().st_mode | stat.S_IEXEC)

        self.triage = self.root / "triage.tsv"
        self.triage.write_text(
            "upstream_path\tchange\tassigned_phase\tnote\n"
            "demo/fresh.rs\tA\tphase_03\ttriage stub\n"
            "demo/keep.rs\tM\tphase_03\ttriage stub\n"
            "demo/drop.rs\tD\tphase_03\ttriage stub\n",
            encoding="utf-8",
        )
        self.ledger = self.root / "ledger.tsv"
        self.ledger.write_text(
            "# source_id\tkind\tstatus\tcrystal_refs\tnotes\n"
            "demo/drop.rs::func::drop_it\tfunc\tported\tsrc/x.cr\tstale claim\n",
            encoding="utf-8",
        )
        self.out = self.root / "out.tsv"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def drift(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT),
             "--vendor", str(self.vendor), "--old", "v1", "--new", "v2",
             "--scan-subdirs", "demo",
             "--discover-bin", str(self.discover),
             "--ledger", str(self.ledger), "--triage", str(self.triage),
             "--out", str(self.out)],
            capture_output=True, text=True,
        )

    def test_classifies_added_removed_and_reports_stale_ledger_rows(self) -> None:
        result = self.drift()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("changed declarations: 3", result.stdout)
        self.assertIn("added=2", result.stdout)

        rows = self.out.read_text(encoding="utf-8").splitlines()
        header = rows[0].split("\t")
        self.assertEqual(header[0], "source_id")
        self.assertIn("visibility", header)

        by_id = {row.split("\t")[0]: row.split("\t") for row in rows[1:]}
        self.assertEqual(by_id["demo/fresh.rs::func::fresh"][2], "added")
        self.assertEqual(by_id["demo/fresh.rs::func::fresh"][3], "pub")
        self.assertEqual(by_id["demo/fresh.rs::func::fresh"][4], "phase_03")
        self.assertEqual(by_id["demo/fresh.rs::func::fresh"][5], "missing")

        added_in_existing_file = by_id["demo/keep.rs::func::added"]
        self.assertEqual(added_in_existing_file[2], "added")
        self.assertEqual(added_in_existing_file[3], "pub")

        removed = by_id["demo/drop.rs::func::drop_it"]
        self.assertEqual(removed[2], "removed")
        self.assertEqual(removed[5], "ported")  # the ledger still claims it

    def test_ledger_status_and_phase_join(self) -> None:
        result = self.drift()
        self.assertIn("already in ledger: 0", result.stdout)
        self.assertIn("phase_03", result.stdout)


if __name__ == "__main__":
    unittest.main()
