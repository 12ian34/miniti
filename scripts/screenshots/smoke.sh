#!/bin/bash
# smoke.sh [ios|mac|all]
# Launch-and-render gate (roadmap P0.6). Builds the Debug apps and runs every screenshot
# scene: on macOS the app must open its window, render, write a PNG, and exit 0; on iOS
# the app must reach first layout (it writes a ready marker after the settle delay) and the
# simulator must produce a PNG. Any scene that never gets there fails the run. Captures go
# to out-smoke/ so they never overwrite the marketing set.
# Set before env.sh so its default (out/, the marketing set) does not win.
export SHOTS_DIR="${SHOTS_DIR:-$(cd "$(dirname "$0")" && pwd)/out-smoke}"
source "$(dirname "$0")/env.sh"
WHAT="${1:-all}"
rm -rf "$SHOTS_DIR"
mkdir -p "$SHOTS_DIR"

"$SCREENSHOTS_DIR/build.sh" "$WHAT"
if [[ "$WHAT" == "mac" || "$WHAT" == "all" ]]; then
  "$SCREENSHOTS_DIR/capture-mac.sh"
fi
if [[ "$WHAT" == "ios" || "$WHAT" == "all" ]]; then
  "$SCREENSHOTS_DIR/capture-ios.sh" iphone
fi
log "smoke passed: every scene launched, reached ready, and rendered under $SHOTS_DIR"
