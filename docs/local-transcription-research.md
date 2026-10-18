# Local transcription research

> Research note captured 2026-10-09, product shape agreed the same day (opt-in private mode, see below), engines measured the same day (see [scripts/transcription-poc/RESULTS.md](../scripts/transcription-poc/RESULTS.md) and the "Measured results" section). Not an implementation plan yet. Revalidate model, package, OS, and pricing details before starting work. The earlier [local-ai-research.md](local-ai-research.md) covers local insights (LLM) and only sketched transcription; this note replaces its "Local transcription: separate investigation" section.

## Short answer

Yes, local live transcription is feasible for miniti on Apple silicon, and the best candidate is already a dependency. FluidAudio 0.17.4, the package miniti ships for Nemotron-3 diarization, also contains `StreamingNemotronMultilingualAsrManager`: NVIDIA's Nemotron 3.5 ASR Streaming 0.6B converted to Core ML, running on the Neural Engine, with per-token timings, punctuation, language conditioning, and vocabulary biasing. It covers all 11 miniti languages, the FluidAudio package floor is macOS 14 / iOS 17 (the same as miniti), and the model licence allows commercial redistribution.

The main costs are a 565 to 612 MB per-language-family model download that cannot be bundled in the app, roughly 1.2 GB peak memory per loaded model on a Mac, a live transcript that lags about 1.2 s instead of Deepgram's ~0.3 s, and measured accuracy that is behind Deepgram on English and well behind on Swedish, Polish, and Greek.

Apple's own SpeechTranscriber is the second real option, but it covers only 6 of the 11 languages, needs macOS 26 / iOS 26 on Apple silicon, and has no diarization. Google's new audio models (Gemma 4) are not streaming speech recognisers and are the wrong tool for live meetings. Whisper (WhisperKit) remains the breadth fallback but is a batch architecture with a paid tier for real-time speakers.

Decision after measuring (2026-10-09): Nemotron 3.5 streaming (latin bundle, 1120 ms) is the live engine; Parakeet TDT v3 batch is an optional finaliser pass for the saved transcript; Apple SpeechTranscriber stays the zero-download candidate for iOS 26+ on its six languages; Greek, Swedish, and Polish stay on Deepgram. Numbers in "Measured results" below.

## Why it matters

Deepgram is miniti's dominant direct cost and the free and Pro tiers are priced on it.

| | Rate today (promotional) | Non-promotional |
|---|---:|---:|
| Nova-3 multilingual streaming, pay as you go | $0.0058 / channel-minute | $0.0092 |
| Streaming diarization add-on | $0.0020 / channel-minute | $0.0020 |
| Total per channel-minute | $0.0078 | $0.0112 |

Source: [Deepgram pricing](https://deepgram.com/pricing), checked 2026-10-09. The strikethrough prices on the page are the non-promotional ones.

A macOS meeting bills two channels (mic and system). At the promotional rate:

| Usage | Channel-minutes | Deepgram cost |
|---|---:|---:|
| One 30-minute macOS meeting | 60 | $0.47 |
| One 30-minute iOS meeting | 30 | $0.23 |
| Free tier fully used on macOS (500 min) | 1,000 | $7.80 / month |
| Pro tier fully used on macOS (5,000 min) | 10,000 | $78 / month against $5 revenue |

Local transcription on capable hardware is the only lever that makes the managed tiers robust at full usage. Local insights (the earlier note) remove cents per meeting; local transcription removes tens of cents.

## What "Google released something new" is

Two things, neither of which fits live meeting transcription on Apple platforms:

- **Gemma 4** (April 2026 for E2B and E4B, June 2026 for 12B) adds native audio input to an open-weight LLM under Apache 2.0. Audio input is capped at 30 seconds per clip, the models are 4.5 to 12 B parameters, and the audio path is a USM-style encoder feeding the language model. It is a batch "listen to a clip, answer" model, not a streaming recogniser, so a live transcript would need manual 30-second chunking, the LLM decoding every chunk, and no token timings for the diarizer. It is a candidate for a later local insights model, not for transcription. Sources: [Gemma 4 E4B model card](https://huggingface.co/google/gemma-4-E4B-it), [Gemma 4 audio encoder write-up](https://www.mindstudio.ai/blog/gemma-4-audio-encoder-e2b-e4b-speech-recognition), [Gemma 4 on MLX Swift](https://github.com/VincentGourbin/gemma-4-swift-mlx).
- **ML Kit GenAI speech recognition** (Gemini Nano through Android AICore) is Android-only and the advanced mode is limited to Pixel 10. Relevant for the Android plan only. Source: [Android speech recognition guide](https://picovoice.ai/blog/android-speech-recognition/).

## Candidates

### 1. Nemotron 3.5 ASR Streaming Multilingual 0.6B via FluidAudio (recommended for the spike)

What it is: NVIDIA's cache-aware FastConformer encoder plus RNN-T decoder, 600 M parameters, 40 locales, built-in punctuation and capitalisation, language conditioning through a prompt id. Licence OpenMDW-1.1 (commercial use and redistribution allowed). FluidInference publishes Core ML int8 bundles in two families: `latin` (vocabulary pruned to en, es, fr, it, pt, de, smaller and faster joint) and `multilingual` (full 13,087-token vocabulary). Sources: [NVIDIA model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b), [FluidInference Core ML bundle](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML).

What is already in miniti's dependency (verified in the FluidAudio 0.17.4 checkout under DerivedData, 2026-10-09):

- `StreamingNemotronMultilingualAsrManager` (actor) with `appendAudio`, `process(samples:)`, `finish()`, `setLanguage`, `setPartialCallback` for live partial text, `detectedLanguage()` in auto mode, and `finishWithTokenTimings()` / `getTokenTimings()` returning `TokenTiming { token, startTime, endTime, confidence }`.
- `downloadAndPreloadShared(languageCode:chunkMs:)` fetching a `<latin|multilingual>/<chunkMs>ms` variant from Hugging Face into Application Support, and `SharedNemotronMultilingualModels` so several sessions share one loaded model (macOS mic and system streams need two sessions, not two copies of the weights).
- Chunk tiers 560, 1120, 2240 (package default), and 4480 ms. The package warns that the 560 ms tier emits increasingly sparse punctuation on long sessions and recommends 1120 ms or more when punctuation matters.
- `NemotronVocabularyBias` for word boosting, the local analogue of Deepgram keyterms, added in FluidAudio 0.15.8.
- A native Swift mel front end, so the Core ML preprocessor is not needed.
- `StreamingNemotronAsrManager` (English-only sibling, 160 ms chunks) and `StreamingEouAsrManager` (Parakeet EOU 120 M, English, end-of-utterance detection) also exist.

Measured numbers from the sources, not from miniti:

| Metric | Value | Source |
|---|---|---|
| Disk, Core ML int8 | 565 to 612 MB per family | soniqo guide, speech-swift docs |
| Peak memory, M5 Pro, streaming | ~1.24 GB | [soniqo Nemotron guide](https://soniqo.audio/guides/nemotron) |
| Throughput, M5 Pro, latin, 1120 to 2240 ms tiers | 103 to 150× real time | FluidInference model card |
| Throughput, iPhone (model unspecified), community Core ML port | ~50× real time | [community ANE port](https://huggingface.co/beshkenadze/nemotron-3.5-asr-streaming-0.6b-coreml-ane) |
| WER, latin family on FLEURS-style sets, M5 Pro | 4.8 to 10.8 % by tier and language | FluidInference model card |

NVIDIA's own WER at the 1.12 s chunk with language conditioning, for miniti's languages:

| Language | WER | Tier |
|---|---:|---|
| Spanish | 4.1 % | transcription-ready |
| Italian | 4.3 % | transcription-ready |
| Portuguese | 5.5 % | transcription-ready |
| English | 7.9 % | transcription-ready |
| German | 8.3 % | transcription-ready |
| French | 9.0 % | transcription-ready |
| Russian | 9.2 % | transcription-ready |
| Dutch | 11.5 % | transcription-ready |
| Polish | 15.2 % | broad coverage |
| Swedish | 22.2 % | broad coverage |
| Greek | no published baseline | adaptation-ready |

For comparison Deepgram claims 6.8 % median streaming WER for Nova-3 on English and independent tests put it at 7 to 10 % on real recordings ([summary](https://vexascribe.com/how-accurate-is-deepgram)). So English is roughly comparable in the published numbers and must be measured on miniti audio, while Polish, Swedish, and Greek should stay on Deepgram until measured.

Fit with miniti's pipeline:

- Audio is already 16 kHz linear16 mono per source. Each `TranscriptSource` (mic, system) gets its own manager sharing the loaded weights.
- Token timings map onto the existing `OnDeviceSpeakerTimeline` the same way Deepgram word times do today (`DeepgramService` already converts word start and end on the socket clock into a diarizer lookup). The diarizer and the recogniser both run on the Neural Engine, so contention must be measured with both on.
- Partial text replaces Deepgram interims. Finals arrive per chunk instead of per Deepgram utterance, so the segmentation and speaker-promotion logic that keys off `is_final` and `utterance_end_ms` needs a local equivalent (silence from FluidAudio's Silero VAD, or punctuation boundaries, because the model has no end-of-utterance token).
- Keyterms become `NemotronVocabularyBias` entries; replace pairs are already applied client-side by `TranscriptCorrector`.
- Deepgram `filler_words=true` keeps "um" and "uh" for the coaching filler-word metric. Whether Nemotron emits fillers is not documented and must be checked; if it drops them, coaching loses one metric in local mode and the UI must say so.
- `smart_format` number and date formatting has no local equivalent beyond the model's own output.

Hardware floor: Apple silicon only in practice (the int8 Core ML encoder needs the Neural Engine; the existing diarization service already gates on `hw.optional.arm64`). Package floor macOS 14 / iOS 17 matches miniti. Minimum iPhone must be measured; the 190 MB diarizer plus a 600 MB recogniser and a 1 GB-class working set is the risk on 4 to 6 GB phones.

Distribution: the model is 3× the diarizer and cannot ride in the app bundle. It needs the on-demand download path the diarization plan already called for before default-on (CDN hosting, pinned revision, checksums, resumable download, disk check, delete and upgrade), plus a user-facing notice that a 600 MB download is about to happen. Downloading straight from Hugging Face inside the consumer app is acceptable for the spike only.

### 2. Apple SpeechAnalyzer / SpeechTranscriber (macOS 26+, iOS 26+)

What it is: Apple's on-device long-form speech model behind the new Speech framework. Models are downloaded and managed by the OS (`AssetInventory`), shared between apps, auto-updated, and cost nothing to distribute. Live audio uses volatile results plus finals, and attributed-string runs carry `audioTimeRange`. Apple silicon and a 16-core Neural Engine are required: iPhone 11 and the second-generation SE report no supported locales, Intel Macs report unavailable. Sources: [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/), [developer forum on supported devices](https://developer.apple.com/forums/thread/806765), [field notes on the API](https://github.com/yrocaz/mac-transcriber/blob/main/docs/research/2026-07-27-apple-speechanalyzer-docs.md).

Languages, verified on the development Mac (macOS 27.0.1, Xcode 27.0) by calling `SpeechTranscriber.supportedLocales` on 2026-10-09: 45 locales, which for miniti means English, Spanish, French, German, Portuguese, and Italian are supported and Swedish, Greek, Dutch, Polish, and Russian are not. The rest of the list is Chinese variants, Japanese, Korean, and a block of Indian languages. Only the English locales were installed.

Accuracy from third parties: Argmax measured 14.0 % WER on long-form conversational English, between Whisper base and small, at about 70× real time ([Argmax comparison](https://www.argmaxinc.com/blog/apple-and-argmax)). A 13,000-recording comparison found it best on clean French, German, and Italian, worse than Parakeet on disfluent speech, and weak on proper nouns without custom vocabulary ([dicta.to benchmark](https://dicta.to/blog/speech-to-text-engine-comparison-mac-2026/)). No custom vocabulary, no diarization, no language detection. Nothing from WWDC 2026 adds speaker identification; the macOS 27 changes are input-plumbing (`AssetInputSequenceProvider`, `AnalyzerInputConverter`).

Fit: zero distribution cost and OS-managed models make it the cheapest route for iOS, but it raises miniti's floor for the feature to macOS 26 / iOS 26, loses five languages, has no vocabulary biasing, and would be a second provider to evaluate and maintain. Worth running in the same harness as Nemotron for the six shared languages; not the first choice.

### 3. WhisperKit (Argmax open-source SDK)

MIT licensed as of v1.0.0 (May 2026, repo renamed to `argmax-oss-swift`), macOS 14 / iOS 17, Whisper large-v3-turbo at 626 MB compressed, 99 languages, word timestamps, file-based diarization through SpeakerKit (pyannote 4). Real-time transcription is in the open-source tier but "~9× faster", custom vocabulary, real-time diarization, and real-time transcription with speakers are Pro-only at $0.42 per device per month ([open-source vs Pro](https://app.argmaxinc.com/docs/wiki/open-source-vs-pro-sdk), [pricing](https://www.argmaxinc.com/pricing)). Whisper is an encoder-decoder over 30-second windows, so live use is sliding-window re-decoding with higher latency and compute than a cache-aware streaming model. It stays the breadth fallback (Greek, Swedish, Polish) if Nemotron fails those languages, and the proper-noun biasing in the benchmark above is its strongest point.

### 4. Parakeet TDT 0.6B v3 via FluidAudio (batch and sliding window)

Same package, CC-BY-4.0, 25 European languages covering all 11 of miniti's, word timestamps, strong published FLEURS WER (English 4.9 %, Spanish 3.5 %, Italian 3.0 %, German 5.0 %, French 5.2 %, Portuguese 4.8 %, Dutch 7.5 %, Polish 7.3 %, Russian 5.5 %, Swedish 15.1 %, Greek 20.7 %) ([model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)). It is a batch model; FluidAudio drives it live through `SlidingWindowAsrManager`, which re-decodes a window and reconciles seams. Good candidate for the post-meeting "re-transcribe locally for a better final transcript" pass and for languages where it beats Nemotron streaming, less good as the live engine.

### 5. Mistral Voxtral Realtime 4B

Open weights, Apache 2.0, sub-500 ms streaming, but 4 B parameters, 13 languages that exclude Swedish, Greek, and Polish, and only MLX and C runtimes on Apple silicon with no Core ML or Swift package. Too heavy for phones and would add a second inference runtime. Not pursued. Sources: [Voxtral Realtime paper](https://arxiv.org/html/2602.11298v1), [launch coverage](https://www.marktechpost.com/2026/02/04/mistral-ai-launches-voxtral-transcribe-2-pairing-batch-diarization-and-open-realtime-asr-for-multilingual-production-workloads-at-scale/).

### 6. Others seen and set aside

Moonshine (27 to 331 M, English-centric, tiny), Qwen3-ASR 1.7B (52 languages, MLX only), Canary 1B v2 and Cohere Transcribe (batch, both already in FluidAudio for a later offline pass), Kyutai STT (no Swift path). None beats the two front-runners on the combination of languages, streaming, Swift runtime, and licence.

## Comparison for miniti

| | Nemotron 3.5 streaming (FluidAudio) | Apple SpeechTranscriber | WhisperKit (open) | Deepgram Nova-3 today |
|---|---|---|---|---|
| miniti languages covered | 11 / 11 | 6 / 11 | 11 / 11 | 11 / 11 |
| Streaming design | native, cache-aware | native | sliding window | native |
| Live lag | ~1.2 s at the 1120 ms tier | sub-second | seconds | ~0.3 to 0.5 s |
| Token or word timings | yes | per-run time ranges | yes | yes |
| Vocabulary biasing | yes | no | Pro only | keyterms |
| Fillers kept for coaching | unknown, test | unknown, test | yes with prompt | yes |
| Diarization | compose with existing Nemotron-3 diarizer | none, compose the same way | file only in open tier | per channel |
| OS floor | macOS 14 / iOS 17, Apple silicon | macOS 26 / iOS 26, Apple silicon, 16-core ANE | macOS 14 / iOS 17 | any |
| Download | 565 to 612 MB per family, app-managed | OS-managed, free | 626 MB, app-managed | none |
| Licence | OpenMDW-1.1 | Apple SDK | MIT | commercial |
| Per-minute cost | 0 | 0 | 0 | $0.0078 per channel |

## Risks and open questions

1. **Accuracy on miniti audio is unmeasured.** Published WER is on read or clean sets; meeting audio with bleed, overlap, and system-channel compression is harder. Measure against Deepgram on the same recordings.
2. **Coaching metrics.** Filler-word counts and pace depend on fillers and timings. If the local model drops fillers, local mode needs a visible "filler metric unavailable" state rather than silently reporting zero.
3. **Segmentation.** Speaker-turn segmentation, the mic speaker promotion policy, and clone guards in `DeepgramService` assume Deepgram finals and utterance ends. A local engine needs its own utterance boundaries (VAD or punctuation) and the segmentation code needs to be provider-neutral.
4. **Memory on iPhone.** ~1.2 GB working set measured on a Mac; the phone floor is unknown and the diarizer is already resident. Measure on the oldest iPhone miniti wants to support before promising iOS.
5. **Neural Engine contention.** Diarizer and recogniser share the ANE on both sources. The 2240 ms tier is faster but lags more; the 1120 ms tier is the likely compromise.
6. **Distribution and trust.** 600 MB on-demand download with a notice, pinned revision, checksums, and a delete control. The diarizer's "CDN hosting + notices before default-on" prerequisite applies here first.
7. **Package maturity.** FluidAudio moves fast (0.15.8 on 2026-09-20 to 0.17.7 on 2026-10-08) and the multilingual manager's own comments still disagree about whether the Hugging Face repo exists. Pin, vendor the model, and keep a Deepgram fallback for every failure.
8. **Metering and tiers.** Local minutes should not count against managed allowances and BYOK users would no longer need a Deepgram key, which touches onboarding, `/api/usage`, and the Linux client's contract. Decide this before shipping, not in the spike.
9. **Privacy copy.** Keep the two behaviours from the local insights note: local only (never upload, even on failure) versus prefer local with cloud fallback. Never silently fall back after a user chose local only.

## Measured results (2026-10-09)

Offline harness in `scripts/transcription-poc` on the M5 Pro: two AMI meetings (headset mix and far-field mic, four speakers, reference includes fillers and overlap) plus 25 FLEURS clips in each of nine languages. Deepgram columns reuse the diarization POC transcripts captured with the app's exact query parameters. Full tables and caveats in [scripts/transcription-poc/RESULTS.md](../scripts/transcription-poc/RESULTS.md).

| AMI file | Deepgram live | Nemotron 1120 | Apple | Parakeet v3 live | Parakeet v3 batch |
|---|---:|---:|---:|---:|---:|
| ES2004a headset mix | 22.3% | 24.5% | 24.3% | 19.9% | 18.2% |
| ES2004a far-field mic | 45.2% | 37.4% | 36.5% | 28.3% | 27.3% |
| IS1009a headset mix | 25.1% | 28.2% | 27.6% | 24.6% | 21.9% |
| IS1009a far-field mic | 29.1% | 32.8% | 31.5% | 24.0% | 24.9% |

| FLEURS | Nemotron 1120 | Apple | Parakeet v3 |
|---|---:|---:|---:|
| en / es / fr / de | 7.6 / 5.0 / 9.9 / 9.7% | 6.0 / 4.1 / 5.9 / 5.3% | 3.6 / 11.2 / 4.3 / 8.5% |
| nl / ru | 14.2 / 13.2% | no | 8.7 / 7.7% |
| pl / sv / el | 19.1 / 23.0 / 42.4% | no | 6.1 / 16.3 / 34.1% |

What it settled:

- **Nemotron is the live engine.** It is the only candidate that advances the transcript every chunk (about 1.1 s, 15 ms of compute per chunk) with token timings for the diarizer, covers every language, and sits 2 to 3 points behind Deepgram live on headset audio while beating it on the far-field mic.
- **Parakeet v3 is a finaliser, not a live engine.** Best accuracy on meetings, better than Deepgram batch on all four files, keeps most fillers, but its sliding-window live mode emits confirmed text every 11 s with no usable interim updates. Worth a "re-transcribe locally at meeting end" pass; adds an 850 MB download.
- **Apple ties Nemotron on meetings and beats it on read speech**, with no download, but only on macOS 26 / iOS 26 and six languages. Right candidate for iOS first.
- **Fillers are not a local-mode regression.** Deepgram live as the app queries it kept 0 to 8 fillers per file against 123 to 131 in the reference; Nemotron kept 10 to 32, Parakeet 45 to 93.
- **Language gate:** en, es, fr, de, pt, it tested; nl, ru experimental; pl, sv, el stay on cloud (Greek is unusable at 42% and Swedish at 23%).
- **Memory in-process is small** (under 170 MB for the harness) because Core ML keeps the int8 weights outside the process; system-wide cost and iPhone behaviour are still unmeasured.

## Product shape: an opt-in private mode, not a Deepgram replacement

Decision direction from Ian, 2026-10-09: offer this as an option for people who want strong privacy and accept the download, the model size, and the language limits. That lowers the bar from "match Deepgram everywhere" to "be honest about the trade-offs", and it matches how on-device speaker separation already ships (beta, default off, Settings → Recording, Apple silicon only).

What that implies:

- **Setting, not mode.** Settings → Recording gains a transcription choice: miniti cloud, or on this device (beta). Independent of managed/BYOK, as the roadmap requires. Managed users keep their account and insights; BYOK users stop needing a Deepgram key.
- **Honest privacy copy in two stages.** With local transcription and local diarization on, the true claim is "audio never leaves this Mac". The transcript still goes to OpenAI (or the managed proxy) for insights, speaker naming, Jev, and Playbook until local insights ship. Say exactly that in the setting, and keep "nothing leaves this device" for a later bundle that also turns on local insights, turns off Share Diagnostics, and leaves calendar, CRM, webhooks, and Playbook as explicit user-initiated choices.
- **Local only means no silent fallback.** If the model is missing, fails to load, or stalls, recording continues, the transcript shows a visible local error, and the app never uploads audio. Offer "allow cloud fallback" as a separate explicit toggle, off by default, for people who want privacy most of the time but never want to lose a meeting.
- **Download with consent.** Show the size per language family (about 600 MB), require a click, show progress, allow delete, and warn before downloading on a metered connection. Pinned revision and checksums as with the diarizer. CDN hosting is the shared prerequisite for this and for diarization default-on.
- **Languages labelled by evidence.** Ship the latin family first (English, Spanish, French, German, Portuguese, Italian) as "tested", keep Dutch and Russian as "experimental" once measured, and leave Polish, Swedish, and Greek on cloud until they measure acceptably. The language picker should say which engine will handle the chosen language.
- **Visible degradations.** Live transcript lags about a second more; coaching filler-word counts may be unavailable; smart number formatting is gone; Deepgram keyterms become local vocabulary biasing. Each should be stated once in the setting's description, not discovered in the meeting.
- **Hardware gate.** Apple silicon only, with the same `hw.optional.arm64` check the diarizer uses; iOS only after a measured floor on the oldest supported iPhone.
- **Tiers and metering.** Local minutes do not touch `/api/usage`. Do not gate the feature behind Pro: it costs miniti nothing per minute and reduces Deepgram spend, and the privacy-minded users are mostly the BYOK crowd. Pro and free stay about cloud minutes and insights. The Linux client needs a matching contract note if `/api/usage` semantics change.

## Recommended sequence

1. **Offline engine comparison: done 2026-10-09** (`scripts/transcription-poc`). Nemotron live, Parakeet finaliser, Apple for iOS later, pl/sv/el stay on cloud.
2. **In-app spike on macOS.** Feed the mic and system sources into `StreamingNemotronMultilingualAsrManager` (latin, 1120 ms) behind a debug flag with Deepgram still running, on the BBC World Service stream and three real meetings. What the offline harness could not measure: the diarizer and recogniser sharing the Neural Engine on two sources, system-wide memory, segmentation and speaker promotion driven by chunk finals instead of Deepgram utterances, and the live-view feel at a 1.1 s cadence.
3. **Design the provider boundary.** A `TranscriptionProvider` protocol behind which Deepgram and the local engine both produce the same `TranscriptUpdate` with words, timings, source, and final flags, so segmentation, diarizer mapping, speaker naming, and insights stay untouched. Independent of `AppMode`, as the roadmap already requires.
4. **Distribution.** Reuse the pinned, checksummed fetch pattern from `scripts/fetch-nemotron-model.sh` for the server side, and build the in-app download, notice, and delete flow once for both the diarizer and the recogniser.
5. **Run Apple SpeechTranscriber through the same harness** for the six shared languages. If it matches Nemotron on those, it becomes the zero-download option for iOS 26 devices.
6. **iOS after Mac data**, with the oldest supported iPhone measured first.
7. **Offline re-transcription** with Parakeet TDT v3 or Canary as a later, separate feature for better final transcripts.

## Sources

- [FluidAudio repository](https://github.com/FluidInference/FluidAudio) and [releases](https://github.com/FluidInference/FluidAudio/releases)
- [FluidInference Nemotron 3.5 multilingual Core ML bundle](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML)
- [NVIDIA Nemotron 3.5 ASR Streaming 0.6B model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)
- [soniqo Nemotron on Apple guide](https://soniqo.audio/guides/nemotron) and [speech-swift model notes](https://github.com/soniqo/speech-swift/blob/main/docs/models/nemotron-asr-streaming.md)
- [NVIDIA Parakeet TDT 0.6B v3 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) and [FluidInference Core ML port](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- [Apple SpeechTranscriber documentation](https://developer.apple.com/documentation/speech/speechtranscriber), [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/), [supported devices thread](https://developer.apple.com/forums/thread/806765)
- [Argmax: Apple SpeechAnalyzer and WhisperKit](https://www.argmaxinc.com/blog/apple-and-argmax), [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift), [open-source vs Pro](https://app.argmaxinc.com/docs/wiki/open-source-vs-pro-sdk), [pricing](https://www.argmaxinc.com/pricing)
- [dicta.to four-engine benchmark on 13,000 recordings](https://dicta.to/blog/speech-to-text-engine-comparison-mac-2026/)
- [Gemma 4 E4B model card](https://huggingface.co/google/gemma-4-E4B-it), [Gemma 4 audio encoder](https://www.mindstudio.ai/blog/gemma-4-audio-encoder-e2b-e4b-speech-recognition)
- [Voxtral Realtime](https://arxiv.org/html/2602.11298v1)
- [Deepgram pricing](https://deepgram.com/pricing), [Deepgram accuracy summary](https://vexascribe.com/how-accurate-is-deepgram)
