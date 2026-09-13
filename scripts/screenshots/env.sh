#!/bin/bash
# Shared configuration for the capture scripts. Sourced by the others; override
# any value in the environment.
#
#   export IPHONE_SIM="iPhone 17 Pro Max" IPAD_SIM="iPad Pro 13-inch (M5)" SHOTS_DIR=...
set -euo pipefail

SCREENSHOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCREENSHOTS_DIR/../.." && pwd)"

: "${SHOTS_DIR:=$SCREENSHOTS_DIR/out}"
: "${DERIVED_DATA:=$REPO_ROOT/DerivedDataLocal}"
: "${IPHONE_SIM:=iPhone 17 Pro Max}"
: "${IPAD_SIM:=iPad Pro 13-inch (M5)}"
: "${IOS_BUNDLE_ID:=com.miniti.mobile}"

# The scenes the app knows how to render. Keep in sync with ScreenshotMode.swift.
IOS_SCENES=(
  "01-home"
  "02-recording-transcript"
  "03-recording-insights"
  "04-recording-sales"
  "05-recording-questions"
  "06-recording-coaching"
  "07-coaching"
  "08-coaching-stats"
  "09-history"
  "10-meeting"
  "11-settings"
  "12-recording-template"
  "13-meeting-coaching"
  "14-store-recovery"
  "15-persistence-issue"
  "16-settings-templates"
)
MAC_SCENES=(
  "01-home"
  "02-recording"
  "03-recording-sales"
  "04-recording-questions"
  "05-meeting"
  "06-coaching"
  "07-coaching-stats"
  "08-settings"
  "09-recording-template"
  "10-meeting-coaching"
  "11-settings-account"
  "12-store-recovery"
  "13-persistence-issue"
  "14-settings-templates"
)

# scene_key "03-recording-insights" -> "recording-insights"
scene_key() { echo "${1#*-}"; }

# resolve_sim <iphone|ipad> -> sets DEV (folder name) and UDID
resolve_sim() {
  case "$1" in
    iphone) DEV="iphone"; SIM_NAME="$IPHONE_SIM";;
    ipad)   DEV="ipad";   SIM_NAME="$IPAD_SIM";;
    *) echo "unknown device key '$1' (want iphone or ipad)" >&2; return 1;;
  esac
  UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
matches = [d for devs in data["devices"].values() for d in devs if d["name"] == name]
if not matches:
    sys.exit("no available simulator named %r; see: xcrun simctl list devices available" % name)
# Prefer a booted one, then the newest runtime (last listed).
matches.sort(key=lambda d: d["state"] == "Booted")
print(matches[-1]["udid"])
' "$SIM_NAME")"
}

log() { printf '\033[1;32m»\033[0m %s\n' "$*" >&2; }
