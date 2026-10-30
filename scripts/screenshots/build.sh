#!/bin/bash
# build.sh [ios|mac|all]  — one Debug build per platform into DerivedDataLocal.
source "$(dirname "$0")/env.sh"
WHAT="${1:-all}"
cd "$REPO_ROOT"
if [[ "$WHAT" == "ios" || "$WHAT" == "all" ]]; then
  # By id, not name: the same model exists on every installed runtime (26.5 and 27.2 on
  # 2026-10-30), and a name-only destination then matches nothing. resolve_sim prefers a
  # booted device, then the newest runtime, the same choice the capture scripts make.
  resolve_sim iphone
  log "building MinitiMobile for the simulator ($SIM_NAME, $UDID)"
  xcodebuild -project Miniti.xcodeproj -scheme MinitiMobile -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" -quiet build CODE_SIGNING_ALLOWED=NO
fi
if [[ "$WHAT" == "mac" || "$WHAT" == "all" ]]; then
  log "building Miniti for macOS"
  xcodebuild -project Miniti.xcodeproj -scheme Miniti -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" -quiet build
fi
log "built into $DERIVED_DATA/Build/Products"
