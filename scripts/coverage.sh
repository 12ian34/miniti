#!/bin/bash
# coverage.sh [mac|ios|all]
# Runs the unit tests with code coverage and prints line coverage per target, per top-level
# source folder, and per file, so docs/testing.md can carry dated numbers instead of a guess.
# Result bundles and JSON land in DerivedDataCoverage/results/.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/DerivedDataCoverage/results"
WHAT="${1:-mac}"
: "${IPHONE_SIM:=iPhone 17}"
rm -rf "$OUT"
mkdir -p "$OUT"
cd "$REPO_ROOT"

run() {
  local name=$1 scheme=$2 dest=$3 only=$4
  echo "» $name: running $only with coverage"
  xcodebuild test -project Miniti.xcodeproj -scheme "$scheme" -destination "$dest" \
    -derivedDataPath "$REPO_ROOT/DerivedDataLocal" -enableCodeCoverage YES \
    -resultBundlePath "$OUT/$name.xcresult" -only-testing:"$only" -quiet 2>&1 \
    | grep -E "error:|TEST (SUCCEEDED|FAILED)" || true
  xcrun xccov view --report --json "$OUT/$name.xcresult" > "$OUT/$name.json"
  python3 - "$OUT/$name.json" "$name" <<'PY'
import json, sys, collections
report = json.load(open(sys.argv[1])); name = sys.argv[2]
print(f"\n== {name} ({sys.argv[1].split('/')[-1]}) ==")
for target in report["targets"]:
    if target["name"].endswith(".xctest"):
        continue
    print(f"target {target['name']}: {target['lineCoverage']*100:.1f}% of {target['executableLines']} lines")
    folders = collections.defaultdict(lambda: [0, 0])
    files = []
    for f in target["files"]:
        path = f["path"]
        if "/MinitiTests/" in path or "/DerivedData" in path or "/SourcePackages/" in path:
            continue
        rel = path.split("/dev/miniti/")[-1]
        folder = "/".join(rel.split("/")[:2]) if rel.count("/") >= 2 else rel.split("/")[0]
        folders[folder][0] += f["coveredLines"]; folders[folder][1] += f["executableLines"]
        files.append((f["lineCoverage"], f["executableLines"], rel))
    for folder, (cov, total) in sorted(folders.items()):
        if total:
            print(f"  {folder:<28} {cov/total*100:5.1f}%  ({cov}/{total})")
    print("  files:")
    for cov, lines, rel in sorted(files, key=lambda x: -x[1]):
        print(f"    {cov*100:5.1f}%  {lines:6d}  {rel}")
PY
}

if [[ "$WHAT" == "mac" || "$WHAT" == "all" ]]; then
  run mac Miniti "platform=macOS" MinitiTests
fi
if [[ "$WHAT" == "ios" || "$WHAT" == "all" ]]; then
  run ios MinitiMobile "platform=iOS Simulator,name=$IPHONE_SIM" MinitiMobileTests
fi
