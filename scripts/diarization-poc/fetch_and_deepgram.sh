#!/bin/zsh
# Downloads two AMI test meetings (headset mix + single distant array mic), converts to 16 kHz mono,
# and runs Deepgram nova-3 prerecorded diarization on each. Reference RTTMs come from
# github.com/pyannote/AMI-diarization-setup (only_words). Key: DEEPGRAM_API_KEY from ../../../miniti-api/.env.
set -e
cd "$(dirname "$0")/data"
for m in ES2004a IS1009a; do
  for ch in Mix-Headset Array1-01; do
    f="$m.$ch.wav"
    [ -f "$f" ] || curl -sSL -o "$f" "https://groups.inf.ed.ac.uk/ami/AMICorpusMirror/amicorpus/$m/audio/$f"
    [ -f "$m.$ch.16k.wav" ] || ffmpeg -v error -y -i "$f" -ac 1 -ar 16000 -sample_fmt s16 "$m.$ch.16k.wav"
  done
done
ls -la *.16k.wav
KEY=$(grep '^DEEPGRAM_API_KEY=' ../../../../miniti-api/.env | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//')
echo "dg key len ${#KEY}"
for f in *.16k.wav; do
  o="../out/deepgram-prerecorded-${f%.16k.wav}.json"
  [ -s "$o" ] || curl -sS -X POST "https://api.deepgram.com/v1/listen?model=nova-3&diarize=true&smart_format=true&filler_words=true&language=en" \
    -H "Authorization: Token $KEY" -H "Content-Type: audio/wav" --data-binary @"$f" -o "$o" -w "$f http=%{http_code} t=%{time_total}s\n"
done
