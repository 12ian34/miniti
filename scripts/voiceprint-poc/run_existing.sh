#!/bin/zsh
# Embed and score whatever audio is present, without fetching.
set -e
cd "$(dirname "$0")"
(cd harness && swift build -c release 2>&1 | tail -2)
for r in data/*.rttm; do
  m=$(basename "$r" .rttm)
  for ch in Mix-Headset Array1-01; do
    w="data/$m.$ch.16k.wav"; o="out/$m.$ch.json"
    [ -f "$w" ] || continue
    [ -s "$o" ] || ./harness/.build/release/harness "$r" "$w" "$o"
  done
done
PY=python3; [ -x ../diarization-poc/.venv/bin/python3 ] && PY=../diarization-poc/.venv/bin/python3
$PY score.py > RESULTS.md
echo "wrote RESULTS.md"
