#!/bin/zsh
set -u
S="$(cd "$(dirname "$0")" && pwd)"
H=$S/harness/.build/release/harness
D="$S/../diarization-poc/data"
AMI=($D/ES2004a.Mix-Headset.16k.wav $D/ES2004a.Array1-01.16k.wav $D/IS1009a.Mix-Headset.16k.wav $D/IS1009a.Array1-01.16k.wav)
cd $S
echo "== $(date) nemotron AMI en-US 1120"; $H nemotron en-US 1120 out/nemotron-ami-1120.json $AMI 2>&1 | grep -v "^\[" | tail -3
echo "== $(date) apple AMI en-US";          $H apple en-US out/apple-ami.json $AMI 2>&1 | tail -3
echo "== $(date) parakeet AMI";             $H parakeet out/parakeet-ami.json $AMI 2>&1 | grep -v "^\[" | tail -3
echo "== $(date) nemotron AMI en-US 560";   $H nemotron en-US 560 out/nemotron-ami-560.json $AMI 2>&1 | grep -v "^\[" | tail -3
typeset -A NEM=(en_us en-US es_419 es-US fr_fr fr-FR de_de de-DE sv_se sv-SE el_gr el-GR pl_pl pl-PL nl_nl nl-NL ru_ru ru-RU)
typeset -A APL=(en_us en-US es_419 es-MX fr_fr fr-FR de_de de-DE)
for L in en_us es_419 fr_fr de_de sv_se el_gr pl_pl nl_nl ru_ru; do
  F=($S/fleurs/$L/*.wav)
  echo "== $(date) nemotron fleurs $L ${NEM[$L]}"; $H nemotron ${NEM[$L]} 1120 out/nemotron-fleurs-$L.json $F 2>&1 | grep -v "^\[" | grep -v "^done" | tail -2
  if [[ -n "${APL[$L]:-}" ]]; then echo "== $(date) apple fleurs $L"; $H apple ${APL[$L]} out/apple-fleurs-$L.json $F 2>&1 | tail -2; fi
  echo "== $(date) parakeet fleurs $L"; $H parakeet out/parakeet-fleurs-$L.json $F 2>&1 | grep -v "^\[" | tail -2
done
echo "== $(date) ALL DONE"
