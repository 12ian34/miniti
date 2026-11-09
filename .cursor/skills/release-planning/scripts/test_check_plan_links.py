#!/usr/bin/env python3
"""Exercise actual checker outcomes against temporary Markdown files."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('check_plan_links.py')


class PlanLinksTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.plan = self.root / 'plan.md'

    def scan(self):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.plan)],
                              capture_output=True, text=True)

    def test_sibling_duplicate_heading_and_explicit_anchor(self):
        (self.root / 'other.md').write_text('# Scope\n# Scope\n<a id="chosen"></a>\n')
        self.plan.write_text('[one](other.md#scope-1) [two](other.md#chosen)')
        self.assertEqual(self.scan().returncode, 0)

    def test_missing_file(self):
        self.plan.write_text('[bad](missing.md)')
        self.assertEqual(self.scan().returncode, 1)

    def test_missing_anchor_and_fenced_fake_heading(self):
        (self.root / 'other.md').write_text('```md\n# Fake\n```\n# Real\n')
        self.plan.write_text('[bad](other.md#fake)')
        self.assertEqual(self.scan().returncode, 1)

    def test_external_links_and_fenced_examples_are_not_local_targets(self):
        self.plan.write_text('[web](https://example.com/a)\n```md\n[example](absent.md)\n```\n')
        self.assertEqual(self.scan().returncode, 0)

    def test_missing_input_is_error(self):
        self.assertEqual(self.scan().returncode, 2)


if __name__ == '__main__':
    unittest.main()
