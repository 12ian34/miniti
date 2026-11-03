#!/usr/bin/env python3
"""Exercise coverage.sh with fake tools; never starts a test host or edits live data."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parent / "coverage.sh"
for status in (65, 0):
    with tempfile.TemporaryDirectory(prefix="miniti-runner-check-") as directory:
        root = Path(directory)
        (root / "scripts").mkdir()
        (root / "bin").mkdir()
        shutil.copy2(source, root / "scripts/coverage.sh")
        for name, body in {
            "xcodebuild": f"#!/bin/sh\nexit {status}\n",
            "xcrun": '#!/bin/sh\nprintf \'{"targets":[]}\\n\'\n',
        }.items():
            tool = root / "bin" / name
            tool.write_text(body)
            tool.chmod(0o755)
        env = dict(os.environ, PATH=f"{root / 'bin'}:{os.environ['PATH']}")
        result = subprocess.run(["bash", str(root / "scripts/coverage.sh"), "mac"],
                                env=env, capture_output=True, text=True)
        assert result.returncode == status, (status, result.returncode, result.stderr)
        assert (root / "DerivedDataCoverage/results/mac.json").exists() == (status == 0)
print("Coverage runner propagates build/test failure and accepts a quiet successful run.")
