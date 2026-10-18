# On-device speaker diarization (Nemotron-3) plan

> Started 2026-09-25 after the offline POC in [scripts/diarization-poc/RESULTS.md](../scripts/diarization-poc/RESULTS.md). Built behind a default-off setting; not released until Ian says so.

## Status

| Step | Status | Notes |
|---|---|---|
| POC: Nemotron vs Deepgram on AMI | done 2026-09-25 | Nemotron 1.04 s streaming beat Deepgram live diarization on all four recordings by 6 to 20 DER points; Deepgram diarization is $0.0020 per channel-minute on our account (about 29% of the Deepgram bill). |
| FluidAudio package (Core ML port) | done 2026-09-25 | v0.17.4, `upToNextMinor`, linked into Miniti and MinitiMobile. Apache 2.0; weights OpenMDW 1.1. |
| `OnDeviceDiarizationService` + speaker timeline | built 2026-09-25 | Per-source Nemotron streaming (`low` preset, 1.04 s) fed from the same 16 kHz PCM the app already sends to Deepgram. |
| Deepgram word reassignment | built 2026-09-25 | When a session has an on-device timeline, `diarize_model` is left out of the Deepgram query and each word's provider speaker comes from the timeline. |
| Setting + status UI (macOS, iOS) | built 2026-09-25; moved 2026-10-09 | Now Settings → Transcription, Speakers: Deepgram or This Mac (a segmented picker), beta label dropped at Ian's request; private mode forces This Mac. Default off. The model ships inside the app. |
| Tests | macOS suite green 2026-09-25 (743 tests, 1 opt-in skipped); opt-in end-to-end run with the real model passes; iOS suite green later the same day on an iPhone 17 Pro simulator (708 tests, 1 opt-in skipped) | Timeline lookup, de-interleave, stable identities across reconnects, query building, fallback paths. |
| Docs, changelog, Linux note | done 2026-09-25; combined 2.10.0 tree (with the calendar, call-lifecycle, panel-drag, calendar-status and VAD changes) builds on both platforms and passes 754 macOS tests | `### Unreleased - v2.10.0` entry; AGENTS/architecture/audio/testing updates; note in `../miniti-linux/PLAN.md`. |
| Manual validation | not started | BBC World Service stream on macOS (mic + system), a real in-room meeting, an iPhone meeting; compare speaker labels and corrections against the Deepgram path. |
| Model delivery | decided 2026-09-25: bundled in the app | `scripts/fetch-nemotron-model.sh` pulls the `low` preset bundle and `learnable_sil_emb.bin` from one pinned HuggingFace revision (`1b0b133f`, weights `ga-2026-09-23`) into the gitignored `Miniti/Resources/NemotronDiarizer/`, verifies every file by SHA-256, and runs as the first build phase of both app targets (needs network once per machine). The folder is a resource in both apps; the service loads from the bundle and only falls back to a HuggingFace download if the folder is missing. About 190 MB on the App Store download, the DMG, and each Sparkle update. No miniti-hosted files. |
| Third-party notices | done 2026-09-25 (Settings → About → Acknowledgements) | What the licences actually require (checked 2026-09-25): FluidAudio is Apache 2.0, and its code is compiled into the app, so the app must carry the Apache licence text and FluidAudio's copyright notice (a bundled text file or an acknowledgements screen; a link in Settings is the usual shape). The Nemotron weights are OpenMDW 1.1, which obliges you when you *distribute* the Model Materials, and bundling them in the app is distribution: the app must carry a copy of the OpenMDW 1.1 agreement and the model's copyright and origin notices (NVIDIA's model card attribution and FluidInference's conversion notice). Outputs carry no obligation. Sparkle (macOS) already had the same Apache-style gap; fix all three in one acknowledgements list before release. |
| Default on | not started | Only after manual validation (including one real iPhone meeting), third-party notices, and privacy copy on miniti.app/docs. Bundling removed the download dependency from this gate. |

## Build notes (2026-09-25)

- macOS app and iOS app both compile with FluidAudio 0.17.4 linked; the built macOS app launches and stays up with the setting off.
- Two `xcodebuild test` runs on this Mac failed before any test ran ("The test runner hung before establishing connection"). An untouched checkout ran 52 DeepgramParsingTests cleanly right after, so the machine can host tests; the likely cause was another miniti instance with the same bundle ID running at the time (the test host launch gets redirected to it). Rerun with no other instance running: `MinitiTests` executed 743 tests, 0 failures, 1 skipped (the opt-in end-to-end test).
- Opt-in end-to-end test (`TEST_RUNNER_MINITI_NEMOTRON_E2E=<wav> xcodebuild test … -only-testing:MinitiTests/OnDeviceDiarizationEndToEndTests`) on the AMI ES2004a far-field recording: 1,049 s of audio through `ingest → Session → OnDeviceSpeakerTimeline` in 28.4 s wall (RTF 0.027 on the Neural Engine), 5 speaker slots for 4 real speakers, 459 of 524 probe lookups covered.
- Launching the built app with the setting on: the 193 MB `low` bundle downloaded into the sandbox container in 5 s and both per-source models loaded (1.4 s, then 0.03 s from cache). Setting reset to off afterwards.
- iOS suite: first attempt could not run (CoreSimulator older than Xcode 27.0); after the simulator runtime was fixed, `MinitiMobileTests` on an iPhone 17 Pro simulator executed 708 tests, 0 failures, 1 skipped, on the combined 2.10.0 tree.
- Nothing is committed. Uncommitted: the package pin, the service, DeepgramService and AppState changes, both Settings views, tests, docs, changelog.

## First live test (2026-09-26)

Ian's first real run on an M5 Pro (mic + system audio, radio on the system channel, two people in the room): the diarizer separated the two in-room voices at first, then every mic word landed on "You" in one growing paragraph, which also read as lag. Two causes, both in how the on-device labels met the existing segmentation guards, not in the model:

1. Per-word confidence was agreement × horizon coverage, so words near the diarizer's ~1.3 s horizon carried confidences the promotion gates rejected. Now confidence is the agreement share when at least half the word is diarized, and a less-covered word borrows a neighbour at 0.3.
2. With system audio active the meeting is "remote-likely", so an additional mic speaker had to pass the v2.7.0 strict clone guard (12 words, 4 s, average confidence 0.85). That guard exists for Deepgram's per-socket churn; Nemotron's slots are stable, so on-device sources now promote under the standard policy (6 words, 1.5 s, 0.65). Regression test in `OnDeviceDiarizationTests`.

Each final now logs a content-free `On-device speakers` line (slot histogram, borrowed words, horizon, fed, last word time) so the next run shows what the diarizer saw. Latency is to be re-checked after this fix: the merged paragraph updated only when finals arrived, which looks like lag; per-chunk inference costs about 3% of realtime on this Mac.

Second run the same day, after that fix: too many speaker switches and an interim line that flickered. Two more glue defects, both fixed with regression tests:

3. **Socket clock off by one packet.** The diarizer clock was advanced by the packet that opened the Deepgram socket *before* socket time 0 was pinned, so every lookup read frames 85 to 250 ms late and the last words of each turn took the next speaker. `markSocketStart()` now places time 0 at the start of that packet.
4. **Borrowed words followed the timeline, not the utterance.** Words past the diarizer horizon took the timeline's last-heard speaker, which could differ from the speaker of the already-diarized words in the same response and changed between interim updates. They now continue the last diarized word of the same response (`continueBorrowedSpeakers`).

Third run, BBC World Service on the system channel: seven remote speakers in four minutes, with the correspondent getting a fresh slot after the anchor cut in and three-word fragments on their own slots. That is the model: Nemotron's arrival-order cache mints a new slot when one voice's acoustics change (phone line, jingle, crowd noise), and broadcast audio does that constantly. Mitigation, not a cure: a **slot maturity gate** in the timeline (`slotMaturitySeconds` = 3). No word switches to a slot until it has 3 s of dominant speech; until then words stay with the current speaker, and a slot that never gets there was churn. A real new speaker's first couple of seconds stay on the previous label, which is how Deepgram's own lag reads today. The log line now lists mature slots. Judge speaker counts on a real call (clean per-participant audio), not on radio; radio remains the stress test for glue bugs.

## Design

**Where diarization runs.** `OnDeviceDiarizationService` owns one `Nemotron3Diarizer` per capture source (microphone, system). The audio callback that already feeds `DeepgramService.sendAudio` also feeds `ingest(_:multichannel:monoSource:)`, which de-interleaves the stereo PCM16 miniti sends in dual capture (channel 0 mic, channel 1 system), converts to Float, and queues it on a serial diarization queue. Each chunk result (10 ms speaker-activity frames, 8 speaker slots in arrival order) is appended to an `OnDeviceSpeakerTimeline`, a lock-protected per-source array of dominant speaker per frame.

**How Deepgram words get their speaker.** Deepgram timestamps are per socket. The timeline records, per source, the diarizer clock (samples fed / 16000) at the first audio packet of each socket, so socket time maps to timeline time. In the off-main parse, when the session has a timeline covering the word's source, the provider speaker for each word is the majority dominant speaker over the word's frames, with `speakerConfidence` = agreement × coverage. Words past the diarizer's horizon (up to about 1.3 s behind live audio) inherit the last active speaker at low confidence, which the existing switch gate treats as weak evidence. The rest of the pipeline (identity allocation, promotion, segmentation) is unchanged.

**Identities across reconnects.** Nemotron's slots are stable for the whole meeting, so `SpeakerIdentityState` keys those sources at generation 0 regardless of socket reconnects; Deepgram-diarized sources keep the generation-aware behaviour.

**Fallbacks.** The Deepgram path is untouched when: the setting is off, the hardware is not Apple silicon, the model is not downloaded yet, model load failed, or a session's diarizer throws. Every one of those keeps `diarize_model=latest` on the socket. A diarizer failure mid-session logs once and stops feeding; the session's remaining words fall back to the last active speaker, and the next session uses Deepgram again until the model is re-prepared.

**Cost.** When on-device diarization is active the socket carries no diarization add-on, which is $0.0020 per channel-minute less. Managed users see nothing; BYOK users pay Deepgram less.

**Privacy.** Speaker separation happens on the device. Audio still goes to Deepgram for words. Setting copy says so.

## How this composes with the Jev plan

[jev-system-one-plan.md](jev-system-one-plan.md) picked speaker naming and the sales nudge as the first Jev slice. Neither is built yet. On-device diarization changes the inputs Jev would see, all for the better:

- **Stable speaker IDs are the prerequisite Jev needs.** Jev's speaker-naming shape is one `Choice` per speaker ID over the attendee list. Its weakest case in the eval was Deepgram's diarizer inventing and splitting speakers mid-meeting (5 speakers found for 4). With arrival-ordered Nemotron slots there are fewer, more stable IDs to name, and a name attached to slot n stays right for the whole meeting. Build Jev naming on top of this, not before it.
- **The evidence prefilter gets a real signal.** The plan sends Jev only turns that mention an attendee name or an introduction pattern. The timeline adds "who was speaking when someone said a name": a turn like "thanks Priya" is evidence about the *previous* speaker, and the timeline gives that neighbour precisely.
- **Speaker count as a gate.** The Jev plan's "is there transcript evidence" question underperformed. A cheaper gate is structural: only ask Jev to name slot n after it has more than a few seconds of speech and at least one addressed or introduced name exists in the transcript. No model call needed for the gate.
- **The sales nudge does not touch diarization.** Its state is a bounded recent-transcript window; speaker labels are cosmetic there. No coupling.
- **Coaching metrics stay deterministic** and only benefit: talk ratio and monologue detection read the same segments, now with better speaker boundaries.
- **Ordering.** Ship diarization first (this plan), validate it on real meetings, then start the Jev slice with the evaluation harness pointed at transcripts produced by this path, so the naming eval measures the real input distribution.

## Non-negotiables carried over

- Suggest-only surfaces stay suggest-only; nothing here auto-enables anything.
- No transcript or audio leaves the device for diarization. The model download is the only new network call, and it is weights only.
- Keep the phrase heuristics and the Deepgram diarizer as fallbacks. Never delete the Deepgram path in this batch.
- `../miniti-linux` needs the ONNX build of the same model or stays on Deepgram diarization; tracked in its PLAN.md.
