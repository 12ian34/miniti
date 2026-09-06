#!/bin/bash
# build.sh [ios|mac|all]  — one Debug build per platform into DerivedDataLocal.
source "$(dirname "$0")/env.sh"
WHAT="${1:-all}"
cd "$REPO_ROOT"
if [[ "$WHAT" == "ios" || "$WHAT" == "all" ]]; then
  log "building MinitiMobile for the simulator"
  xcodebuild -project Miniti.xcodeproj -scheme MinitiMobile -configuration Debug \
    -destination "platform=iOS Simulator,name=$IPHONE_SIM" \
    -derivedDataPath "$DERIVED_DATA" -quiet build CODE_SIGNING_ALLOWED=NO
fi
if [[ "$WHAT" == "mac" || "$WHAT" == "all" ]]; then
  log "building Miniti for macOS"
  xcodebuild -project Miniti.xcodeproj -scheme Miniti -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" -quiet build
fi
log "built into $DERIVED_DATA/Build/Products"
