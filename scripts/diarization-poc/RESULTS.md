# Nemotron-3-Diarization vs Deepgram: POC results (2026-09-25)

> Offline evaluation only. Nothing in the app changed. Run on Ian's M5 Pro (24 GB) with NeMo from GitHub main.

## Setup

- **Data:** two AMI meeting-corpus test meetings, four real speakers each, about 17 and 14 minutes. Two recordings of each: the headset mix (close-talk, what a good call recording sounds like) and a single far-field array microphone (what a laptop mic hears in a room). References are the `only_words` RTTMs from pyannote's AMI setup, which are tight word-level labels with 14 to 16% of speech overlapped.
- **Metric:** DER with the standard 0.25 s collar and overlap included, plus a no-collar and an overlap-excluded figure. Absolute numbers are higher than the model card's 9.25% AMI figure because the card uses forced-alignment references; compare systems against each other, not against the card.
- **Systems:** Deepgram nova-3 prerecorded (`diarize=true`, the batch diarizer, an upper bound for Deepgram), Deepgram nova-3 live WebSocket with the app's exact query parameters (`diarize_model=latest`, the path miniti actually runs), and Nemotron-3-Diarization in offline mode (30.4 s window) and the 1.04 s low-latency streaming mode.

## Accuracy

The rows that matter are the two live paths: what miniti runs today versus what it would run.

| meeting | recording | Deepgram live (app path) | Nemotron 1.04 s streaming | Deepgram batch (upper bound) | Nemotron offline |
|---|---|---|---|---|---|
| ES2004a | far-field room mic | 51.2% (5 spk) | **30.8%** (4 spk) | 45.0% (4 spk) | 32.2% (4 spk) |
| ES2004a | headset mix | 34.8% (4 spk) | **25.6%** (5 spk) | 28.3% (5 spk) | 25.2% (4 spk) |
| IS1009a | far-field room mic | 36.5% (5 spk) | **20.2%** (4 spk) | 25.5% (4 spk) | 19.3% (4 spk) |
| IS1009a | headset mix | 32.3% (5 spk) | **26.0%** (4 spk) | 24.9% (5 spk) | 26.0% (4 spk) |

DER with 0.25 s collar, overlap included; speaker count in brackets against 4 real speakers. The full table with no-collar and overlap-excluded variants and the missed / false-alarm / confusion split is in `out/scores.json` (run `score.py`).

Reading it:

- Against the path the app actually uses, Nemotron streaming is better on every recording, by 6 to 20 DER points, and the gap is widest on the far-field room mic, which is the in-room case miniti's diarization plan cares about.
- Deepgram's live diarizer is 6 to 11 points worse than its own batch diarizer and over-counts speakers on three of four recordings; its confusion (words given to the wrong speaker) is 5 to 7% on three files versus 0.3 to 2% for Nemotron on the same files. Confusion is the error users notice as "wrong name on the line".
- Nemotron's 1.04 s streaming mode is within 1 point of its offline mode. It over-counted once (5 speakers on the ES2004a headset mix); the offline mode never did.
- Nemotron streaming even beats Deepgram's batch diarizer on three of four recordings.
- Most of both systems' error is "missed", which the tight references drive. A binarisation threshold sweep on Nemotron's raw probabilities (0.3 to 0.7) moves DER by at most 2 points, so the default 0.5 stands; see `out/threshold-sweep.md`.

## Speed on the M5 Pro

| mode | device | real-time factor | meaning |
|---|---|---|---|
| offline | CPU | 0.013 | 17.5 min of audio in 13.7 s |
| offline | MPS | 0.008 | 8.3 s |
| low latency (1.04 s) | CPU | 0.25 | a 0.72 s chunk costs about 0.18 s; live is fine at roughly a quarter of one core |
| low latency (1.04 s) | MPS | 0.21 | the streaming loop is Python-overhead bound, so the GPU barely helps here |

Model load is 0.3 s from the local cache; weights are 190 MB in fp32 (95 MB quantised).

## Can it work with everything?

**Yes, and the hard part is already done by someone else.** The model is a 100M-parameter Transformer with an arrival-order speaker cache and FIFO for streaming. Running PyTorch inside the sandboxed Swift app is not an option, but three on-device ports exist:

- [FluidAudio](https://github.com/FluidInference/FluidAudio) (Swift, Apache 2.0, macOS and iOS, Core ML): [PR #883](https://github.com/FluidInference/FluidAudio/pull/883) ports this exact model with the streaming cache logic in Swift (`Nemotron3Diarizer`, `appendAudio` / `processBufferedAudio` / `finishStream`), presets from 0.32 s to offline, and models auto-downloaded from HuggingFace. Their own M5 Pro numbers on AMI: 9.75% DER at 31x realtime for the 1.04 s preset, 9.47% at 904x offline. Parity with NeMo is 1.9e-4 per chunk.
- [onnx-community/Nemotron-3-Diarization-ONNX](https://huggingface.co/onnx-community/Nemotron-3-Diarization-ONNX) for ONNX Runtime, which is what the Linux client would use.
- [NeMo-Speech.cpp](https://github.com/zajca/zwhisper/issues/18) and the shipped `.q8_0.gguf` for a whisper.cpp-style C++ runtime with Metal.

How it would slot into miniti:

1. **Audio is already right.** The app streams 16 kHz mono linear16 per channel to Deepgram; Nemotron wants exactly that. Run one diarizer instance on the mic channel (in-room speakers) and optionally one on the system channel (remote speakers).
2. **Keep Deepgram for words, drop its speaker labels.** Nemotron gives per-10 ms speaker activity with a stable arrival-order index (0 to 7). Assign each Deepgram word to the speaker with the most activity over the word's timestamps, and map index n on the mic channel to miniti's 1000 + n IDs. Deepgram's `diarize_model` query parameter goes away, which also removes the diarizer churn `DeepgramService` currently defends against.
3. **Latency fits the current pipeline.** The 1.04 s preset is inside Deepgram's own finalisation delay (`utterance_end_ms=1000`), so speaker labels land before or with the final transcript, not after it.
4. **Overlap becomes representable.** Nemotron emits simultaneous speakers; the transcript model assumes one speaker per word, which is fine for word assignment but means interruptions still attach to whoever dominates the word.
5. **Cost.** Deepgram diarization is bundled into the streaming price today, so there is no direct saving; the win is quality, a fixed speaker count per session, and independence from Deepgram's diarizer updates.

Open items before an implementation plan:

- Evaluate FluidAudio's Core ML build directly (ANE, fp16) on the same four files rather than trusting the PR's numbers; check memory and energy on an iPhone.
- Decide whether the system channel also moves to Nemotron or stays on Deepgram (remote speakers are usually already clean).
- The Linux client needs the ONNX route; same-day tracking issue in `../miniti-linux` if this is funded.
- Word-to-speaker assignment needs a small labelled set with word timestamps to tune the "most activity over the word" rule against short words and overlap.

## Cost (measured on miniti's Deepgram account, 2026-09-25)

Three 60 s streams of the same clip, single channel, read back from the Deepgram requests API:

| streaming request | billed per audio minute |
|---|---|
| nova-3, smart_format, filler_words | $0.00483 |
| same plus `diarize_model=latest` | $0.00683 |
| same plus one `keyterm` | $0.00567 |

So streaming diarization costs **$0.0020 per channel-minute** on this account (Deepgram's published add-on price), keyterm prompting $0.00084, and prerecorded diarization is free ($0.00434/min). Production single-channel requests bill $0.0077/min (diarize + keyterm), two-channel macOS requests $0.00625 per channel-minute.

Last 30 days: 165 billed channel-hours (9,900 channel-minutes), 1,201 requests, every one with diarize on. Removing the add-on saves about **$20 a month at today's volume, roughly 29% of the Deepgram bill** (about $69) and a quarter of total API cost, since Deepgram is about 90% of it. The saving scales linearly with minutes; BYOK users get the same reduction on their own Deepgram bill.

## Considerations before shipping to everyone

1. **Validate on miniti audio, not AMI.** Mac mic plus system channel in a real room, iPhone mic, non-English meetings. A small labelled set from Ian's own recordings, scored with `score.py`, before any rollout.
2. **Hardware floor and fallback.** Core ML on Apple silicon is the target; Intel Macs and older iPhones need a measured decision, and Deepgram diarization stays as the fallback behind a flag. Nothing is removed from the Deepgram path until the flag has been on for a release.
3. **Battery and thermal on iOS.** Measure a 45-minute background recording on a mid-range iPhone before enabling there.
4. **Model delivery.** Weights are 95 to 190 MB. Either bundle them (App Store and DMG size, Sparkle delta size) or host them on miniti's own CDN like the DMG, never a third-party download at runtime from a sandboxed app. First run without the model falls back to Deepgram.
5. **Speaker identity plumbing.** Arrival-order IDs are stable within a session; map mic-channel index n to 1000 + n and keep the existing speaker-naming, clone, and inline-correction contracts. Saved meetings keep their old labels; no migration.
6. **Word assignment rule.** Words go to the speaker with the most activity over the word's timestamps; short back-channels and overlaps need explicit handling and unit tests.
7. **Licensing and notices.** Weights under OpenMDW 1.1, FluidAudio under Apache 2.0; add both to third-party notices and check attribution wording.
8. **Linux parity.** Diarization is client-side so the backend contract does not change, but `../miniti-linux` needs the ONNX route or stays on Deepgram; same-day tracking issue when this is funded.
9. **Privacy copy improves.** Speaker separation moves on-device and no new vendor is involved; update the privacy wording to say so.
10. **Rollout signal.** Ship behind a feature flag, Pro and BYOK first, and watch speaker count per meeting and the inline-correction rate in Share Diagnostics as the quality signal.
