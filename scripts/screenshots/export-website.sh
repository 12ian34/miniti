#!/bin/bash
# export-website.sh [website-dir]
# Converts the raw captures into web-sized WebP files for the /screens/ page of
# miniti.app: ../minitidotapp/images/screens/<device>-<NN>-<scene>.webp
# Runs after capture; all.sh calls it when the website checkout is present.
source "$(dirname "$0")/env.sh"
SITE="${1:-$REPO_ROOT/../minitidotapp}"
[[ -d "$SITE/images" ]] || { echo "website checkout not found at $SITE" >&2; exit 1; }
command -v cwebp >/dev/null || { echo "cwebp is required (brew install webp)" >&2; exit 1; }

OUT="$SITE/images/screens"
mkdir -p "$OUT"
# device folder → target width in px. Retina pages scale them down; these sizes keep
# text legible at 2x on the page's 1040px column without shipping the raw PNGs.
export_device() {
  local DEV="$1" WIDTH="$2" COUNT=0
  for PNG in "$SHOTS_DIR/$DEV"/*.png; do
    [[ -f "$PNG" ]] || continue
    local NAME; NAME="$(basename "${PNG%.png}")"
    cwebp -quiet -q 84 -resize "$WIDTH" 0 -metadata none "$PNG" -o "$OUT/$DEV-$NAME.webp"
    COUNT=$((COUNT + 1))
  done
  log "$DEV: $COUNT file(s) at ${WIDTH}px wide"
}
export_device mac 1920
export_device iphone 780
export_device ipad 1032
log "wrote $(ls "$OUT" | wc -l | tr -d ' ') files into $OUT"
du -sh "$OUT" | awk '{print "  total " $1}'
