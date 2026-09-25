#!/bin/zsh
# Fetches the Nemotron-3-Diarization Core ML bundle (FluidAudio's conversion of
# nvidia/Nemotron-3-Diarization, "low" preset, 1.04 s latency) into
# Miniti/Resources/NemotronDiarizer so it ships inside the app. Pinned to one
# HuggingFace revision and verified by SHA-256, so a build never picks up silently
# changed weights. Idempotent: exits fast once every file verifies. Runs as a build
# phase of both app targets; needs network the first time on a machine.
#
#   scripts/fetch-nemotron-model.sh            # fetch or verify
#   scripts/fetch-nemotron-model.sh --verify   # verify only, fail if missing
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Miniti/Resources/NemotronDiarizer"
REPO="FluidInference/nemotron-3-diarization-coreml"
REVISION="1b0b133f6f8820292010afd776d8f9fbc9fca17e"   # 2026-09-24, weights ga-2026-09-23
SUBDIR="monolithic/v2"
BUNDLE="Nemotron3Diarizer_low.mlmodelc"

# remote path relative to the repo | local path relative to DEST | sha256
FILES=(
  "learnable_sil_emb.bin|learnable_sil_emb.bin|d4417b3c0eabdf7c47032fac2b5b5a7ee83d819a6ddda8fd8eaf74e2b5cc4ac7"
  "$SUBDIR/$BUNDLE/coremldata.bin|$BUNDLE/coremldata.bin|2c2c82efc948433cb47b60aceb4917182e2e00d1d79097b8898adfd615b0c5f8"
  "$SUBDIR/$BUNDLE/analytics/coremldata.bin|$BUNDLE/analytics/coremldata.bin|1ec46d7392b470ebfaac473123de9e5bc62630972b01349b929bf6e48e067c6c"
  "$SUBDIR/$BUNDLE/model.mil|$BUNDLE/model.mil|8e2ffc4ce5edf86b8a1845e5229a219ca9e8cc0e03aa4a6e7317e81cb7da2da5"
  "$SUBDIR/$BUNDLE/weights/weight.bin|$BUNDLE/weights/weight.bin|88307e2c51d1877de59803299354f689e70cad7f8892a197764d5f3626089495"
)

verify() { [ -f "$1" ] && [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$2" ]; }

missing=0
for entry in "${FILES[@]}"; do
  local_path="$DEST/${entry#*|}"; local_path="${local_path%|*}"
  sha="${entry##*|}"
  verify "$local_path" "$sha" || missing=$((missing + 1))
done
if [ "$missing" -eq 0 ]; then echo "Nemotron model present and verified in $DEST"; exit 0; fi
if [ "${1:-}" = "--verify" ]; then echo "error: $missing Nemotron model file(s) missing or corrupt in $DEST; run scripts/fetch-nemotron-model.sh" >&2; exit 1; fi

echo "Fetching Nemotron model ($missing file(s)) from $REPO@${REVISION:0:8}"
for entry in "${FILES[@]}"; do
  remote="${entry%%|*}"
  rest="${entry#*|}"; local_rel="${rest%|*}"; sha="${rest#*|}"
  local_path="$DEST/$local_rel"
  verify "$local_path" "$sha" && continue
  mkdir -p "$(dirname "$local_path")"
  # Xcode's user-script sandbox only lets a build phase write its declared outputs, so
  # the partial download lives in the build's temp dir (or a mktemp dir when run by hand).
  tmp="${TEMP_DIR:-$(mktemp -d)}/$(basename "$local_path").part"
  curl -fSL --retry 5 --retry-delay 3 -o "$tmp" "https://huggingface.co/$REPO/resolve/$REVISION/$remote"
  if ! verify "$tmp" "$sha"; then echo "error: checksum mismatch for $remote" >&2; rm -f "$tmp"; exit 1; fi
  mv "$tmp" "$local_path"
  echo "  fetched $local_rel"
done
echo "Nemotron model ready in $DEST"
