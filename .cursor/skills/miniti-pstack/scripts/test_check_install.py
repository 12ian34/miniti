"""Exercise installer drift detection using disposable copies of the actual skill."""

import json
from pathlib import Path
import shutil
import tempfile
import unittest

from check_install import validate


class InstallValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="miniti-pstack-check-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.skill = self.repo / ".cursor/skills/miniti-pstack"
        shutil.copytree(Path(__file__).resolve().parents[1], self.skill,
                        ignore=shutil.ignore_patterns("__pycache__"))
        for directory in (".agents/skills", ".claude/skills"):
            parent = self.repo / directory
            parent.mkdir(parents=True)
            (parent / "miniti-pstack").symlink_to("../../.cursor/skills/miniti-pstack")

    def test_complete_install_passes(self):
        self.assertEqual(validate(self.skill, self.repo), [])

    def test_changed_reference_is_detected(self):
        path = self.skill / "references/upstream/interrogate.txt"
        path.write_bytes(path.read_bytes() + b"\nchanged\n")
        self.assertTrue(any("Hash mismatch" in e for e in validate(self.skill, self.repo)))

    def test_broken_alias_is_detected(self):
        alias = self.repo / ".claude/skills/miniti-pstack"
        alias.unlink()
        alias.symlink_to("../../missing")
        self.assertTrue(any("discovery alias" in e for e in validate(self.skill, self.repo)))

    def test_missing_license_is_detected(self):
        (self.skill / "LICENSE").unlink()
        self.assertTrue(any("LICENSE" in e for e in validate(self.skill, self.repo)))

    def test_unpinned_reference_is_detected(self):
        (self.skill / "references/upstream/extra.txt").write_text("unreviewed")
        self.assertTrue(any("Pinned file list" in e for e in validate(self.skill, self.repo)))

    def test_escaping_manifest_path_is_rejected(self):
        path = self.skill / "upstream-lock.json"
        manifest = json.loads(path.read_text())
        manifest["files"][0]["local"] = "../../outside.txt"
        path.write_text(json.dumps(manifest))
        self.assertTrue(any("Unsafe pinned path" in e for e in validate(self.skill, self.repo)))


if __name__ == "__main__":
    unittest.main()
