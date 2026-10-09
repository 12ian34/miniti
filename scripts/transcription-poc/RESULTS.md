# Local transcription POC results (2026-10-09)

> Offline evaluation on Ian's M5 Pro (24 GB), macOS 27.0.1, Xcode 27.0, FluidAudio 0.17.4. Nothing in the app changed. Deepgram rows reuse the transcripts captured for the diarization POC on 2026-09-25.

## Decision

Use **Nemotron 3.5 ASR Streaming Multilingual (latin family, 1120 ms chunks) as the live engine**, with an optional **Parakeet TDT v3 batch pass at meeting end** for the saved transcript. Keep Apple SpeechTranscriber as the zero-download candidate for iOS 26+ on its six languages. Keep Greek, Swedish, and Polish on Deepgram.

Why, in one line each:

- Nemotron is the only engine that updates the live transcript every chunk (about 1.1 s) with word timings for the diarizer, covers all 11 languages, and lands within 2 to 3 points of Deepgram live on headset meeting audio and ahead of it on the far-field mic.
- Parakeet v3 is the most accurate on meeting audio (better than Deepgram batch on all four files) and keeps far more fillers, but its live mode emits text in 11-second blocks, so it is a finaliser, not a live engine.
- Apple ties Nemotron on meetings and beats it on read speech, costs nothing to distribute, but needs macOS 26 / iOS 26 and covers only en, es, fr, de, pt, it.

## AMI meetings (English, four speakers; reference includes fillers and overlap, so compare columns, not absolutes)

| file | Deepgram batch | Deepgram live (app path) | Nemotron 1120 | Nemotron 560 | Apple | Parakeet v3 live | Parakeet v3 batch |
|---|---:|---:|---:|---:|---:|---:|---:|
| ES2004a headset mix | 21.3% | 22.3% | 24.5% | 24.8% | 24.3% | 19.9% | 18.2% |
| ES2004a far-field mic | 43.2% | 45.2% | 37.4% | 38.1% | 36.5% | 28.3% | 27.3% |
| IS1009a headset mix | 24.2% | 25.1% | 28.2% | 28.0% | 27.6% | 24.6% | 21.9% |
| IS1009a far-field mic | 26.1% | 29.1% | 32.8% | 33.4% | 31.5% | 24.0% | 24.9% |

Reading it:

- On the headset mix (a good call recording) Nemotron is 2 to 3 points behind Deepgram live. On the far-field room mic it is 8 points ahead on one meeting and 4 behind on the other. Apple is within a point of Nemotron everywhere.
- Parakeet v3 batch beats Deepgram batch on every file by 1 to 16 points. Its sliding-window live mode is nearly as good on text, but see cadence below.
- The 560 ms Nemotron tier gains nothing on accuracy and the package warns it loses punctuation on long sessions; 1120 ms is the tier to use.

## Live cadence and compute (real-time paced feed of a 60 s clip, 100 ms packets)

| engine | how the live transcript advances | compute per 1.12 s chunk (M5 Pro) |
|---|---|---|
| Nemotron 1120 | new tokens after every chunk, so words appear within about one chunk plus 15 ms (p95 47 ms) | 15 ms mean |
| Nemotron 560 | every 0.56 s | 12 ms mean |
| Parakeet v3 sliding window (`.streaming` preset) | confirmed text every 11 s, no usable hypothesis updates in between (6 updates in 60 s) | n/a |
| Deepgram live today | interims every few hundred ms, finals per utterance | n/a |

Whole-file throughput: Nemotron 0.014 real-time factor (17.5 min in 16 s), Apple 0.007, Parakeet batch 0.006. In-process memory of the harness stayed under 170 MB for every engine because Core ML keeps the int8 weights outside the process; system-wide cost was not measured here.

## Fillers (count of um / uh / hmm in output; reference has 123 to 131 per file)

| file | Deepgram live | Nemotron 1120 | Apple | Parakeet v3 |
|---|---:|---:|---:|---:|
| ES2004a headset | 0 | 16 | 5 | 55 |
| ES2004a far-field | 0 | 10 | 8 | 45 |
| IS1009a headset | 8 | 32 | 19 | 93 |
| IS1009a far-field | 3 | 22 | 19 | 81 |

Deepgram live, as the app queries it, dropped almost every filler on these files, so the coaching filler metric is already weak on the cloud path. Nemotron keeps more than Deepgram live, Parakeet keeps most. No engine needs a "filler metric unavailable" state that the cloud path does not also need.

## FLEURS read speech (25 clips per language, about 10 s each; Nemotron and Parakeet use language conditioning)

| language | Nemotron 1120 | Apple | Parakeet v3 batch |
|---|---:|---:|---:|
| English | 7.6% | 6.0% | 3.6% |
| Spanish (LatAm) | 5.0% | 4.1% | 11.2% |
| French | 9.9% | 5.9% | 4.3% |
| German | 9.7% | 5.3% | 8.5% |
| Dutch | 14.2% | not supported | 8.7% |
| Russian | 13.2% | not supported | 7.7% |
| Polish | 19.1% | not supported | 6.1% |
| Swedish | 23.0% | not supported | 16.3% |
| Greek | 42.4% | not supported | 34.1% |

Stripping diacritics changes these by under 2 points, so the Greek and Swedish numbers are real errors (the Greek output drops word boundaries and final letters). Polish is the odd one: Nemotron streaming is poor, Parakeet batch is good, so a Polish user would want the finaliser pass even if live stays on cloud.

Language gate from this data: ship en, es, fr, de, pt, it (the latin bundle) as tested; nl and ru as experimental; pl, sv, el stay on Deepgram.

## Caveats

- Two meetings and nine 25-clip sets. Enough to pick an engine, not enough to quote WER to users.
- The AMI reference merges overlapping speakers in time order, which penalises every engine equally but inflates absolute numbers.
- No iPhone measurements. The FluidAudio floor is iOS 17, but memory and thermal behaviour on a phone with the diarizer also loaded are unknown.
- Deepgram transcripts were captured two weeks earlier on the same files; the model is `nova-3` with the app's query parameters.
- Portuguese and Italian were not in the FLEURS sample; they are in the latin bundle and have published WER of 5.5% and 4.3%.
