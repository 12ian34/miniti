#!/usr/bin/env python3
"""Read-only check for private conversation/app URIs in candidate public text.

No network access. Not a general secrets scanner. Prints locations, never values.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys

SUFFIXES = {'.md', '.mdx', '.txt', '.html', '.json', '.yaml', '.yml'}
PATTERNS = {
    'private conversation URI': re.compile(r'\b(?:t3-thread|codex|chatgpt)://[^\s<>"\x27)]+', re.I),
    'private chat page': re.compile(r'https://(?:chatgpt\.com/c/|claude\.ai/chat/)[^\s<>"\x27)]+', re.I),
    'session-specific app reference': re.compile(r'\b(?:plugin|app)://[^\s<>"\x27)]+', re.I),
}


def candidates(paths, repos):
    result = set()
    for value in paths:
        path = Path(value).absolute()
        if not path.exists():
            raise ValueError(f'Path does not exist: {path}')
        if path.is_dir():
            result.update(p for p in path.rglob('*') if p.is_file() and p.suffix in SUFFIXES and '.git' not in p.parts)
        else:
            result.add(path)
    for value in repos:
        root = Path(value).resolve()
        for args in [('diff', '--name-only', '-z', 'HEAD', '--'), ('ls-files', '--others', '--exclude-standard', '-z')]:
            output = subprocess.check_output(['git', *args], cwd=root)
            result.update(root / name.decode() for name in output.split(b'\0') if name and Path(name.decode()).suffix in SUFFIXES)
    return sorted(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='*')
    parser.add_argument('--changed', action='append', default=[], metavar='REPO')
    args = parser.parse_args()
    if not args.paths and not args.changed:
        parser.error('Supply public text paths or --changed REPO')
    checked = 0
    problems = []
    try:
        for path in candidates(args.paths, args.changed):
            if not path.exists():  # Deleted tracked file.
                continue
            if path.is_symlink():
                problems.append(f'{path}: symbolic link requires explicit review')
                continue
            if path.stat().st_size > 2_000_000:
                problems.append(f'{path}: text exceeds 2 MB scan limit; review explicitly')
                continue
            body = path.read_text(encoding='utf-8')
            checked += 1
            for number, line in enumerate(body.splitlines(), 1):
                for label, pattern in PATTERNS.items():
                    if pattern.search(line):
                        problems.append(f'{path}:{number}: {label}')
    except (OSError, ValueError, UnicodeError, subprocess.CalledProcessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 2
    if problems:
        print('\n'.join(problems))
        print(f'FAIL: {len(problems)} finding(s), {checked} text files inspected')
        return 1
    print(f'PASS: {checked} text files inspected; no private conversation/app references')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
