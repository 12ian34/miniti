#!/bin/bash
# all.sh — build, capture every scene on iPhone, iPad, and Mac, and render the frames.
source "$(dirname "$0")/env.sh"
cd "$REPO_ROOT"
scripts/screenshots/build.sh all
scripts/screenshots/capture-ios.sh iphone
scripts/screenshots/capture-ios.sh ipad
scripts/screenshots/capture-mac.sh
python3 scripts/screenshots/render_frames.py --captures "$SHOTS_DIR" \
  --ios-out fastlane/screenshots/en-US --mac-out "$SHOTS_DIR/framed"
# App Store Connect carries en-US and en-GB; deliver only replaces locales it has files for.
mkdir -p fastlane/screenshots/en-GB && cp fastlane/screenshots/en-US/*.png fastlane/screenshots/en-GB/
if [[ -d "$REPO_ROOT/../minitidotapp/images" ]]; then
  scripts/screenshots/export-website.sh
fi
log "done — review fastlane/screenshots/en-US, $SHOTS_DIR/framed, and ../minitidotapp/images/screens before shipping"
