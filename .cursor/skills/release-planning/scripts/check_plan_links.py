#!/usr/bin/env python3
"""Check inline local Markdown links/heading anchors, including changed release plans.

No network access. Explicit files/directories and repeatable --changed REPO inputs.
Reference-style links and Markdown extensions are outside this bounded checker.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote


def without_fences(text):
    return re.sub(r'^```.*?^```[^\n]*', '', text, flags=re.M | re.S)


def anchor_ids(path):
    text = without_fences(path.read_text())
    ids = set(re.findall(r'\b(?:id|name)=["\x27]([^"\x27]+)', text))
    seen = {}
    for title in re.findall(r'^#{1,6}\s+(.+?)\s*#*\s*$', text, re.M):
        title = re.sub(r'<[^>]+>', '', title).lower()
        slug = re.sub(r'[^\w\- ]', '', title).replace(' ', '-')
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        ids.add(slug if not count else f'{slug}-{count}')
    return ids


def collect(paths, repos):
    files = set()
    for value in paths:
        path = Path(value).resolve()
        if not path.exists():
            raise ValueError(f'Missing input: {path}')
        if path.is_dir():
            files.update(p.resolve() for p in path.rglob('*')
                         if p.is_file() and p.suffix in ('.md', '.mdx') and '.git' not in p.parts)
        else:
            files.add(path)
    for value in repos:
        root = Path(value).resolve()
        for args in [('diff', '--name-only', '-z', 'HEAD'),
                     ('ls-files', '--others', '--exclude-standard', '-z')]:
            names = subprocess.check_output(['git', *args], cwd=root).decode().split('\0')
            files.update((root / name).resolve() for name in names
                         if name.endswith(('.md', '.mdx')) and (root / name).is_file())
    return sorted(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='*')
    parser.add_argument('--changed', action='append', default=[], metavar='REPO')
    args = parser.parse_args()
    if not args.paths and not args.changed:
        parser.error('Supply files/directories or --changed REPO')
    failures, cache = [], {}
    links = anchors = 0
    try:
        files = collect(args.paths, args.changed)
        for path in files:
            source = without_fences(path.read_text())
            for match in re.finditer(r'!?\[[^\]\n]*\]\(([^)\n]+)\)', source):
                target = match.group(1).split(' "', 1)[0].strip('<>')
                if re.match(r'[a-zA-Z][\w+.-]*:', target) or target.startswith('/'):
                    continue
                name, sep, anchor = unquote(target).partition('#')
                dest = (path.parent / name).resolve() if name else path
                links += 1
                if not dest.exists():
                    failures.append(f'{path}: missing {target}')
                    continue
                if sep and anchor and dest.suffix in ('.md', '.mdx'):
                    anchors += 1
                    if dest not in cache:
                        cache[dest] = anchor_ids(dest)
                    if anchor not in cache[dest]:
                        failures.append(f'{path}: missing anchor {target}')
    except (OSError, ValueError, UnicodeError, subprocess.CalledProcessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 2
    print(f'{len(files)} Markdown files, {links} local links, {anchors} anchors')
    if failures:
        print('\n'.join(failures))
        return 1
    print('PASS')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
