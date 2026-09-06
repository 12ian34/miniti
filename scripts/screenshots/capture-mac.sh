#!/bin/bash
# capture-mac.sh [scene ...]
# For each scene, launches the Debug macOS build in screenshot mode. The app sizes its
# own window (1440×900 pt), renders the scene, writes the window image into its own
# sandbox container (a terminal without Screen Recording permission cannot capture
# another app's window), restores the user's defaults, and quits. The PNG is then
# moved to $SHOTS_DIR/mac/<NN>-<scene>.png. Defaults to every scene in MAC_SCENES.
# Build first with build.sh mac.
source "$(dirname "$0")/env.sh"
SCENES=("$@"); [[ ${#SCENES[@]} -eq 0 ]] && SCENES=("${MAC_SCENES[@]}")

APP="$DERIVED_DATA/Build/Products/Debug/Miniti.app"
[[ -d "$APP" ]] || { echo "no macOS build at $APP — run build.sh mac" >&2; exit 1; }
: "${MAC_BUNDLE_ID:=com.miniti.app}"
CONTAINER_TMP="$HOME/Library/Containers/$MAC_BUNDLE_ID/Data/tmp"

if pgrep -xq Miniti; then
  echo "Miniti is running; quit it first so the capture build can own the window and defaults." >&2
  exit 1
fi

OUT_DIR="$SHOTS_DIR/mac"
mkdir -p "$OUT_DIR"
for SCENE in "${SCENES[@]}"; do
  KEY="$(scene_key "$SCENE")"
  OUT="$OUT_DIR/$SCENE.png"
  APP_OUT="$CONTAINER_TMP/miniti-screenshot-$KEY.png"
  rm -f "$OUT" "$APP_OUT"
  # -W waits for the app to exit; the app exits itself once the PNG is written.
  open -n -W -a "$APP" --args -MinitiScreenshotScene "$KEY" -MinitiScreenshotSettleSeconds "${SETTLE_SECONDS:-4}" ${SCREENSHOT_EXTRA_ARGS:-}
  if [[ ! -s "$APP_OUT" ]]; then
    echo "scene $SCENE produced no file at $APP_OUT" >&2; exit 1
  fi
  mv "$APP_OUT" "$OUT"
  python3 - "$OUT" <<'PY'
import struct, sys
p = sys.argv[1]
h = open(p, "rb").read(24)
assert h[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG: " + p
w, hh = struct.unpack(">II", h[16:24])
print("  %-28s %dx%d" % (p.split("/out/")[-1], w, hh))
PY
done
log "captured ${#SCENES[@]} scene(s) into $OUT_DIR"
