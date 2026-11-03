#!/usr/bin/env python3
"""Check local file links in current docs without requiring sibling checkouts.

Historical archive/research/release records retain dated links. Web URLs,
anchors and links outside this checkout are not network-checked here.
"""
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote

root = Path(__file__).resolve().parent.parent
files = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', '*.md'], cwd=root).decode().split('\0')
failures = []
checked = 0
for name in sorted(set(filter(None, files))):
    if name.startswith(('docs/archive/', 'docs/research/', 'docs/releases/')) and name != 'docs/releases/3.7.0.md':
        continue
    path = root / name
    if not path.exists():
        continue
    source = re.sub(r'^```.*?^```[^\n]*', '', path.read_text(), flags=re.M | re.S)
    for match in re.finditer(r'!?\[[^\]\n]*\]\(([^)\n]+)\)', source):
        target = match.group(1).split(' "', 1)[0].strip('<>')
        if target.startswith(('#', '/')) or re.match(r'[a-zA-Z][\w+.-]*:', target):
            continue
        target = unquote(target.split('#', 1)[0])
        resolved = (path.parent / target).resolve()
        if not resolved.is_relative_to(root):
            continue
        checked += 1
        if not resolved.exists():
            failures.append(f'{name}: {target}')
if failures:
    raise SystemExit('Broken local documentation links:\n' + '\n'.join(failures))
print(f'{checked} current local documentation links resolve')
