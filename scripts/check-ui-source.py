#!/usr/bin/env python3
"""Bounded lexical UI guard. See docs/reference/ui-source-check.md for limits."""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
BASELINE = Path('scripts/ui-source-baseline.json')
SOURCE_ROOTS = ('Miniti', 'MinitiMobile')
# Palette definitions are the sole raw-colour authority in the main apps.
EXCLUDED = {'Miniti/Models/ColorPalette.swift'}
RULES = {'raw-color', 'focus-opt-out', 'small-fixed-font', 'local-chrome'}
COLOR_TYPES = {'Color', 'NSColor', 'UIColor', 'CGColor'}
RAW_LABELS = {'hex', 'red', 'green', 'blue', 'white', 'gray', 'hue', 'saturation',
              'brightness', 'cyan', 'magenta', 'yellow', 'black', 'components',
              'displayP3Red', 'calibratedRed', 'calibratedWhite', 'deviceRed', 'deviceWhite'}


@dataclass(frozen=True)
class Token:
    value: str
    offset: int
    kind: str = 'code'


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str
    signature: str

    @property
    def key(self):
        return self.path, self.rule, self.signature


def tokenize(source: str) -> list[Token]:
    """Ignore nested comments/string prose, retaining code in interpolations.

    This is not a Swift parser: no type/alias/macro or conditional-build resolution.
    String tokens retain exact spelling; whitespace/comments in code do not matter.
    """
    n = len(source)

    def region(i, closing=None):
        out = []
        while i < n:
            if closing and source[i] == closing:
                return out, i
            if source[i].isspace():
                i += 1
                continue
            if source.startswith('//', i):
                end = source.find('\n', i)
                i = n if end < 0 else end
                continue
            if source.startswith('/*', i):
                depth, i = 1, i + 2
                while i < n and depth:
                    if source.startswith('/*', i):
                        depth, i = depth + 1, i + 2
                    elif source.startswith('*/', i):
                        depth, i = depth - 1, i + 2
                    else:
                        i += 1
                if depth:
                    raise ValueError('unterminated block comment')
                continue
            string = re.match(r'(#+)?("""|")', source[i:])
            if string:
                start = i
                hashes, quote = string.group(1) or '', string.group(2)
                end_mark, escape = quote + hashes, '\\' + hashes
                i += len(string.group())
                interpolations = []
                while i < n and not source.startswith(end_mark, i):
                    if source.startswith(escape + '(', i):
                        opening = i + len(escape)
                        inner, end = region(opening + 1, ')')
                        interpolations += [Token('(', opening), *inner, Token(')', end)]
                        i = end + 1
                    elif source.startswith(escape, i):
                        i += len(escape) + 1
                    else:
                        i += 1
                if i >= n:
                    raise ValueError('unterminated string')
                i += len(end_mark)
                # The additional balanced tokens expose executable interpolation
                # expressions without mistaking ordinary string prose for code.
                out += [Token(source[start:i], start, 'string'), *interpolations]
                continue
            char = source[i]
            if char in '([{':
                end_char = {'(': ')', '[': ']', '{': '}'}[char]
                inner, end = region(i + 1, end_char)
                out += [Token(char, i), *inner, Token(end_char, end)]
                i = end + 1
                continue
            if char in ')]}':
                raise ValueError(f'unmatched delimiter at line {source.count(chr(10), 0, i) + 1}')
            word = re.match(r'`[^`\n]+`|[A-Za-z_$][A-Za-z_0-9$]*|(?:\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)', source[i:])
            value = word.group() if word else char
            out.append(Token(value, i))
            i += len(value)
        if closing:
            raise ValueError(f'unclosed {closing} delimiter')
        return out, i

    return region(0)[0]


def calls(tokens):
    """Yield named calls and their balanced argument tokens, including nested calls."""
    ends, stack = {}, []
    for i, token in enumerate(tokens):
        if token.kind == 'code' and token.value == '(':
            stack.append(i)
        elif token.kind == 'code' and token.value == ')':
            ends[stack.pop()] = i
    for i, token in enumerate(tokens[:-1]):
        if token.kind != 'code' or tokens[i + 1].value != '(' or i + 1 not in ends:
            continue
        if not re.fullmatch(r'`?\w+`?', token.value):
            continue
        end = ends[i + 1]
        # Normalize qualified Color.init(...) to the same constructor identity.
        start, name = i, token.value.strip('`')
        if name == 'init' and i >= 2 and tokens[i - 1].value == '.':
            start, name = i - 2, tokens[i - 2].value.strip('`')
        yield start, end, name, tokens[i + 2:end]


def arguments(tokens):
    """Top-level labels, so Color(nsColor: make(red: ...)) is not raw RGB."""
    depth, result = 0, {}
    for i, token in enumerate(tokens[:-1]):
        if token.kind == 'code':
            if token.value in '([{':
                depth += 1
            elif token.value in ')]}':
                depth -= 1
            elif depth == 0 and (i == 0 or tokens[i - 1].value == ',') and tokens[i + 1].value == ':':
                result[token.value.strip('`')] = tokens[i + 2:]
    return result


def scan(path: str, source: str) -> list[Finding]:
    tokens = tokenize(source)
    found = []
    for start, end, name, args in calls(tokens):
        labels = arguments(args)
        rule = None
        if (name in COLOR_TYPES and RAW_LABELS.intersection(labels)) or (name == 'colorLiteral' and start > 0 and tokens[start - 1].value == '#'):
            rule = 'raw-color'
        elif name == 'focusable' and args and args[0].value == 'false':
            rule = 'focus-opt-out'
        elif name in {'system', 'systemFont', 'monospacedSystemFont', 'boldSystemFont', 'italicSystemFont'}:
            size = labels.get('size', labels.get('ofSize', []))
            # Only a direct numeric argument. Expressions and resolved metrics
            # are not evaluated; a small fixed font is a review cue, not a defect.
            if size and re.fullmatch(r'\d+(?:\.\d+)?', size[0].value) and (len(size) == 1 or size[1].value == ',') and float(size[0].value) < 13:
                rule = 'small-fixed-font'
        elif name in {'cornerRadius', 'RoundedRectangle'}:
            radius = args if name == 'cornerRadius' else labels.get('cornerRadius', [])
            if radius and re.fullmatch(r'\d+(?:\.\d+)?', radius[0].value):
                rule = 'local-chrome'
        if rule:
            # A signature/count allowance is local to one file. It does not
            # freeze line numbers or silently expand for new files/values.
            signature = ' '.join(t.value for t in tokens[start:end + 1])
            found.append(Finding(path, source.count('\n', 0, tokens[start].offset) + 1, rule, signature))
    return found


def inventory(root: Path):
    findings, files = [], []
    for directory in SOURCE_ROOTS:
        location = root / directory
        if not location.is_dir():
            raise ValueError(f'missing source directory: {directory}')
        for path in sorted(location.rglob('*.swift')):
            relative = path.relative_to(root).as_posix()
            if relative in EXCLUDED:
                continue
            if path.is_symlink():
                raise ValueError(f'symlinked source is not supported: {relative}')
            files.append(relative)
            try:
                findings += scan(relative, path.read_text())
            except ValueError as error:
                raise ValueError(f'{relative}: {error}') from error
    if not files:
        raise ValueError('no main-app Swift sources found')
    return files, findings


def load_baseline(path: Path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or data.get('version') != 1 or not isinstance(data.get('entries'), list):
        raise ValueError('unsupported baseline format')
    counts = Counter()
    for entry in data['entries']:
        if not isinstance(entry, dict):
            raise ValueError('baseline entries must be objects')
        name, rule, signature, count = (entry.get(k) for k in ('path', 'rule', 'signature', 'count'))
        if (not isinstance(name, str) or not name.endswith('.swift') or '..' in Path(name).parts
                or not any(name.startswith(d + '/') for d in SOURCE_ROOTS) or name in EXCLUDED
                or rule not in RULES or not isinstance(signature, str) or not signature
                or type(count) is not int or count < 1):
            raise ValueError(f'invalid baseline entry: {entry}')
        key = name, rule, signature
        if key in counts:
            raise ValueError(f'duplicate baseline entry: {key}')
        counts[key] = count
    return data, counts


def compare(findings, baseline):
    current = Counter(f.key for f in findings)
    return current - baseline, baseline - current


def prune(data, current):
    """Only remove/decrease existing allowances. Never accept a new finding."""
    result = dict(data)
    result['entries'] = []
    for entry in data['entries']:
        count = min(entry['count'], current[entry['path'], entry['rule'], entry['signature']])
        if count:
            result['entries'].append({**entry, 'count': count})
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--baseline', type=Path, default=BASELINE, help='Relative to root, or absolute')
    parser.add_argument('--inventory', action='store_true', help='Print every occurrence with current line numbers')
    parser.add_argument('--prune-baseline', action='store_true', help='Remove stale allowances only; refuses new raw colours')
    args = parser.parse_args(argv)
    try:
        files, findings = inventory(args.root)
        baseline_path = args.root / args.baseline
        data, baseline = load_baseline(baseline_path)
        added, stale = compare(findings, baseline)
        hard = {key: count for key, count in added.items() if key[1] == 'raw-color'}
        if args.prune_baseline and not hard:
            data = prune(data, Counter(f.key for f in findings))
            baseline_path.write_text(json.dumps(data, indent=2) + '\n')
            stale = Counter()
        locations = {}
        for finding in findings:
            locations.setdefault(finding.key, []).append(finding.line)
            if args.inventory:
                print(f'{finding.path}:{finding.line}: {finding.rule}: {finding.signature}')
        for key, count in sorted(added.items()):
            path, rule, signature = key
            level = 'ERROR' if rule == 'raw-color' else 'REVIEW'
            lines = ','.join(str(line) for line in locations[key])
            print(f'{level}: {path}:{lines}: {rule}: +{count} (all matching lines): {signature}')
        for (path, rule, signature), count in sorted(stale.items()):
            print(f'STALE: {path}: {rule}: -{count}: {signature}')
        print(f'{len(files)} Swift files; {len(findings)} occurrences; {sum(hard.values())} new raw colours; '
              f'{sum(added.values()) - sum(hard.values())} review cues; {sum(stale.values())} stale allowances')
        if hard or stale:
            print('FAIL: use palette roles for new colours; prune removed debt with --prune-baseline.')
            return 1
        print('PASS' + (' (review new cues before accepting the change)' if added else ''))
        return 0
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
