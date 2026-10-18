#!/bin/zsh
# Apple Watch screenshots for App Store Connect (416 x 496, the Series 10 / 46mm size).
# Builds nothing: run `xcodebuild -scheme MinitiMobile -destination 'generic/platform=iOS Simulator' build`
# first (the watch app is embedded in the iOS product). Two states, driven by the
# `-MinitiScreenshotScene record|queue` launch argument the watch app understands.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${OUT:-fastlane/screenshots/en-US}"
SIM_NAME="${WATCH_SIM:-Apple Watch Series 12 (46mm)}"
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Miniti-*/Build/Products/Debug-iphonesimulator/MinitiMobile.app/Watch/MinitiWatch.app | head -1)
UDID=$(xcrun simctl list devices available | grep "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -n "$UDID" ]] || { echo "no simulator named $SIM_NAME"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"
i=1
for scene in record queue; do
  xcrun simctl terminate "$UDID" com.miniti.mobile.watchkitapp 2>/dev/null || true
  xcrun simctl launch "$UDID" com.miniti.mobile.watchkitapp -MinitiScreenshotScene "$scene" >/dev/null
  sleep 4
  xcrun simctl io "$UDID" screenshot "$OUT/Apple Watch Series 10-0$i.png" >/dev/null
  echo "wrote $OUT/Apple Watch Series 10-0$i.png ($scene)"
  i=$((i+1))
done
xcrun simctl terminate "$UDID" com.miniti.mobile.watchkitapp 2>/dev/null || true
