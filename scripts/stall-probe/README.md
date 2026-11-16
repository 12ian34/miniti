# Stall detector probe

Evidence for the transcript stall detector work in the [3.10.0 plan](../../docs/releases/3.10.0.md) (package TG1). It talks to Deepgram directly with the same listen settings as the app, so it measures the provider, not the app.

It costs real Deepgram minutes (a full run is about 14 minutes of audio). Do not run it without a key you are allowed to spend on.

## Audio

Four files of raw 16 kHz mono signed 16-bit PCM in one directory, none of them committed:

```bash
mkdir -p /tmp/stall-audio && cd /tmp/stall-audio
ffmpeg -y -t 150 -i "https://stream.live.vc.bbcmedia.co.uk/bbc_world_service" -ac 1 -ar 16000 -f s16le speech.raw
ffmpeg -y -f lavfi -i "anullsrc=r=16000:cl=mono" -t 70 -f s16le silence.raw
ffmpeg -y -f lavfi -i "anoisesrc=d=70:c=pink:r=16000:a=0.05" -ac 1 -f s16le noise.raw
ffmpeg -y -f lavfi -i "sine=frequency=262:sample_rate=16000:duration=70" -f lavfi -i "sine=frequency=330:sample_rate=16000:duration=70" -f lavfi -i "sine=frequency=392:sample_rate=16000:duration=70" -filter_complex "[0][1][2]amix=inputs=3,tremolo=f=2:d=0.6,volume=-12dB" -ac 1 -ar 16000 -f s16le tones.raw
```

The noise file averages about -40 dBFS, just above the app's microphone loudness threshold (0.008, about -42 dBFS).

## Run

```bash
DEEPGRAM_API_KEY=... node dg-probe.mjs /tmp/stall-audio cadence
DEEPGRAM_API_KEY=... node dg-probe.mjs /tmp/stall-audio onset
DEEPGRAM_API_KEY=... node dg-probe.mjs /tmp/stall-audio reconnect
```

- `cadence`: 60 seconds each of silence, noise, tones and speech. Reports message counts by kind and the longest gap between messages.
- `onset`: 10 seconds of silence or noise, then speech. Reports how long the first speech event and the first words take.
- `reconnect`: a reference transcript of 70 seconds of speech, twice, then five runs that replay the app's forced reconnect (keep sending for 1 second, drop the socket without finishing, reconnect) at different points, and count the reference words that never arrive.

## Result, 2026-11-14

| Check | Result |
|---|---|
| Longest gap between messages on a healthy socket | 1.05 s on silence, 1.10 s on noise, 1.04 s on tones, 1.13 s on speech |
| Speech events on 3 minutes of non-speech | 0 |
| Speech events on 60 seconds of speech | 15 |
| First speech event after speech starts | 0.08 to 0.09 s |
| First words after speech starts | 0.5 to 1.2 s |
| Reference transcript repeatability | 168 of 168 words |
| Words lost by one forced reconnect during speech | 7, 4, 12, 13, 12 (finished lines only); 3, 1, 3, 2, 3 if the unfinished line were kept |
| Reconnect handshake, audio unsent | 0.16 s, 0.2 s |

One speech source (BBC World Service, English), one network, one day. The numbers are a measurement of that, not a guarantee.
