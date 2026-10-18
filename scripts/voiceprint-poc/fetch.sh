#!/bin/zsh
# AMI sessions with recurring participants: ES2004a/b/c and IS1009a/b/c, headset mix and one
# far-field array mic, converted to 16 kHz mono, plus the pyannote only_words reference RTTMs.
# Reuses files the diarization spike already fetched into ../diarization-poc/data.
set -e
cd "$(dirname "$0")/data"
OLD=../../diarization-poc/data
for m in ES2004a ES2004b ES2004c IS1009a IS1009b IS1009c; do
  for ch in Mix-Headset Array1-01; do
    f="$m.$ch.wav"
    k="$m.$ch.16k.wav"
    if [ ! -f "$k" ]; then
      if [ -f "$OLD/$k" ]; then ln -sf "$OLD/$k" "$k"; else
        [ -f "$f" ] || curl -sSL -o "$f" "https://groups.inf.ed.ac.uk/ami/AMICorpusMirror/amicorpus/$m/audio/$f"
        ffmpeg -v error -y -i "$f" -ac 1 -ar 16000 -sample_fmt s16 "$k"
        rm -f "$f"
      fi
    fi
  done
  if [ ! -f "$m.rttm" ]; then
    if [ -f "$OLD/$m.rttm" ]; then ln -sf "$OLD/$m.rttm" "$m.rttm"; else
      for split in test dev train; do
        curl -sSfL -o "$m.rttm" "https://raw.githubusercontent.com/pyannote/AMI-diarization-setup/main/only_words/rttms/$split/$m.rttm" && break || true
      done
    fi
  fi
done
ls -la
