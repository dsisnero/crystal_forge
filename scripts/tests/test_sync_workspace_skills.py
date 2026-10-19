import importlib.util
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("workspace_sync", Path(__file__).parents[1] / "sync_workspace_skills.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class WorkspaceSyncTest(unittest.TestCase):
    def test_preserves_metadata_and_binaries_and_keeps_resources_live(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            source = repo / "skills/demo"
            target = repo / ".agents/skills/demo"
            for directory in (source / "scripts", target / "scripts", target / "bin"):
                directory.mkdir(parents=True, exist_ok=True)
            (source / "SKILL.md").write_text("---\nname: demo\ndescription: New\n---\nNew body\n")
            (target / "SKILL.md").write_text("---\nmetadata:\n  github-pinned: v1\nname: demo\ndescription: Old\n---\nOld body\n")
            (source / "scripts/run.sh").write_text("new")
            (target / "scripts/stale.sh").write_text("old")
            (target / "bin/local").write_bytes(b"binary")
            self.assertEqual(MODULE.sync(repo, check=True), 1)
            self.assertTrue((target / "scripts/stale.sh").exists())
            self.assertEqual(MODULE.sync(repo, check=False), 0)
            self.assertIn("github-pinned: v1", (target / "SKILL.md").read_text())
            self.assertIn("New body", (target / "SKILL.md").read_text())
            self.assertFalse((target / "scripts/stale.sh").exists())
            self.assertEqual((target / "bin/local").read_bytes(), b"binary")
            self.assertEqual(MODULE.sync(repo, check=True), 0)
            (source / "scripts/run.sh").write_text("updated")
            self.assertEqual((target / "scripts/run.sh").read_text(), "updated")


if __name__ == "__main__":
    unittest.main()
