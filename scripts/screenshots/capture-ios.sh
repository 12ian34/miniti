#!/bin/bash
# capture-ios.sh <iphone|ipad> [scene ...]
# Boots the simulator, installs the Debug build, and for each scene launches the app
# in screenshot mode and captures the screen to $SHOTS_DIR/<device>/<NN>-<scene>.png.
# Defaults to every scene in IOS_SCENES. Build first with build.sh ios.
source "$(dirname "$0")/env.sh"
resolve_sim "${1:?usage: capture-ios.sh <iphone|ipad> [scene ...]}"; shift
SCENES=("$@"); [[ ${#SCENES[@]} -eq 0 ]] && SCENES=("${IOS_SCENES[@]}")

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/MinitiMobile.app"
[[ -d "$APP" ]] || { echo "no simulator build at $APP — run build.sh ios" >&2; exit 1; }

log "device $SIM_NAME ($UDID)"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$APP"
# The app writes <container>/tmp/miniti-screenshot-ready-<scene> after its settle delay.
# `simctl launch` returns as soon as the process starts, so this marker is the only proof
# the scene actually reached first layout rather than crashing behind a blank capture.
CONTAINER_TMP="$(xcrun simctl get_app_container "$UDID" "$IOS_BUNDLE_ID" data)/tmp"

OUT_DIR="$SHOTS_DIR/$DEV"
mkdir -p "$OUT_DIR"
for SCENE in "${SCENES[@]}"; do
  KEY="$(scene_key "$SCENE")"
  READY="$CONTAINER_TMP/miniti-screenshot-ready-$KEY"
  rm -f "$READY"
  xcrun simctl terminate "$UDID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$IOS_BUNDLE_ID" -MinitiScreenshotScene "$KEY" >/dev/null
  # Let SwiftUI settle: seeded store, tab selection, first layout pass, no in-flight animation.
  # The app writes its ready marker after the same settle delay (default 3 s in the app).
  sleep "${SETTLE_SECONDS:-4}"
  if [[ ! -f "$READY" ]]; then
    echo "scene $SCENE never reached first layout (no $READY); the app probably crashed" >&2; exit 1
  fi
  OUT="$OUT_DIR/$SCENE.png"
  xcrun simctl io "$UDID" screenshot "$OUT" >/dev/null 2>&1
  python3 - "$OUT" <<'PY'
import struct, sys
p = sys.argv[1]
h = open(p, "rb").read(24)
assert h[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG: " + p
w, hh = struct.unpack(">II", h[16:24])
print("  %-28s %dx%d" % (p.split("/out/")[-1], w, hh))
PY
done
xcrun simctl terminate "$UDID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
log "captured ${#SCENES[@]} scene(s) into $OUT_DIR"
