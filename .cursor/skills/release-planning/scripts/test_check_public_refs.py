#!/usr/bin/env python3
"""Behavioral checks for the public-reference scanner; uses temporary files only."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCANNER = Path(__file__).with_name('check_public_refs.py')


class PublicReferenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def scan(self, path):
        return subprocess.run([sys.executable, str(SCANNER), str(path)],
                              capture_output=True, text=True)

    def test_public_and_local_links_pass(self):
        path = self.root / 'plan.md'
        path.write_text('[docs](https://example.com/docs) and [plan](../plan.md#scope)')
        self.assertEqual(self.scan(path).returncode, 0)

    def test_private_references_fail_without_echoing_values(self):
        for prefix in ('t3-thread://v2/', 'https://claude.ai/chat/',
                       'https://chatgpt.com/c/', 'plugin://'):
            with self.subTest(prefix=prefix):
                path = self.root / 'plan.md'
                path.write_text('review: <' + prefix + 'secret-fixture-id>')
                result = self.scan(path)
                self.assertEqual(result.returncode, 1)
                self.assertIn('plan.md:1:', result.stdout)
                self.assertNotIn('secret-fixture-id', result.stdout + result.stderr)

    def test_missing_path_is_an_error(self):
        self.assertEqual(self.scan(self.root / 'missing.md').returncode, 2)

    def test_oversized_text_is_not_silently_skipped(self):
        path = self.root / 'large.md'
        path.write_text('a' * 2_000_001)
        self.assertEqual(self.scan(path).returncode, 1)

    def test_symlink_requires_review(self):
        target = self.root / 'target.md'
        target.write_text('public text')
        link = self.root / 'link.md'
        link.symlink_to(target)
        self.assertEqual(self.scan(link).returncode, 1)

    def test_directory_checks_nested_public_text_but_not_git_metadata(self):
        git = self.root / '.git'
        git.mkdir()
        (git / 'internal.txt').write_text('t3-thread://v2/internal-fixture')
        nested = self.root / 'docs'
        nested.mkdir()
        page = nested / 'page.mdx'
        page.write_text('safe text')
        self.assertEqual(self.scan(self.root).returncode, 0)
        page.write_text('t3-thread://v2/private-fixture')
        self.assertEqual(self.scan(self.root).returncode, 1)


if __name__ == '__main__':
    unittest.main()
