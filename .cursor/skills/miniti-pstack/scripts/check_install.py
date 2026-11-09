#!/usr/bin/env python3
"""Validate pinned pstack references and project skill aliases without networking."""

import hashlib
import json
from pathlib import Path
import re
import sys


def validate(skill, repo):
    skill, repo = Path(skill).resolve(), Path(repo).resolve()
    errors = []
    for name in ("SKILL.md", "UPSTREAM.md", "LICENSE", "agents/openai.yaml",
                 "references/review-brief.md"):
        if not (skill / name).is_file():
            errors.append(f"Missing skill file: {name}")
    try:
        manifest = json.loads((skill / "upstream-lock.json").read_text())
        if manifest["repository"] != "https://github.com/cursor/plugins":
            errors.append("Unexpected upstream repository")
        if not re.fullmatch(r"[0-9a-f]{40}", manifest["commit"]):
            errors.append("Upstream commit must be a full SHA")
        entries = manifest["files"]
        if not entries:
            errors.append("No pinned upstream files")
        seen = set()
        for entry in entries:
            local = entry["local"]
            path = (skill / local).resolve()
            if Path(local).is_absolute() or not path.is_relative_to(skill):
                errors.append(f"Unsafe pinned path: {local}")
                continue
            if local in seen:
                errors.append(f"Duplicate pinned path: {local}")
            seen.add(local)
            if not entry["upstream"].startswith("pstack/") or ".." in Path(entry["upstream"]).parts:
                errors.append(f"Invalid upstream path: {local}")
            if not path.is_file():
                errors.append(f"Missing pinned file: {local}")
            elif hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
                errors.append(f"Hash mismatch: {local}")
        if "LICENSE" not in seen:
            errors.append("Upstream license is not pinned")
        actual = {str(p.relative_to(skill)) for p in (skill / "references/upstream").rglob("*") if p.is_file()}
        if actual != seen - {"LICENSE"}:
            errors.append("Pinned file list differs from vendored references")
    except (OSError, ValueError, KeyError, TypeError) as exc:
        errors.append(f"Invalid pin manifest: {exc}")
    for directory in (".agents/skills", ".claude/skills"):
        alias = repo / directory / "miniti-pstack"
        if not alias.is_symlink() or alias.resolve() != skill:
            errors.append(f"Missing or incorrect discovery alias: {directory}/miniti-pstack")
    return errors


if __name__ == "__main__":
    script = Path(__file__).resolve()
    failures = validate(script.parents[1], script.parents[4])
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit(1)
    print("PASS: upstream pin/hashes, required files and both discovery aliases")
