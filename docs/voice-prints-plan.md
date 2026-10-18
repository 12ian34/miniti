# Voice prints: recognising people by voice across meetings

Started 2026-10-18 after the Apple Watch release. Owner: Ian. Related: `docs/on-device-diarization-plan.md` (the separation half this builds on), `docs/jev-system-one-plan.md` (speaker naming), `docs/apple-watch-plan.md` (watch recordings diarised on the phone).

## Status

| Step | Status | Notes |
|---|---|---|
| Plan | written 2026-10-18 | This document. Decisions below are Ian's from the 2026-10-18 conversation: build it, voice prints first, the attendee email link alongside. |
| Spike: does CAM++ separate people across meetings and microphones | done 2026-10-19, go | `scripts/voiceprint-poc/RESULTS.md`, six AMI sessions. With the product's unit (30 s print, 30 s average, threshold 0.60): headset to headset across days 100% correct and no false accepts; room mic across days 76 to 100% correct with up to 24% false accepts on the worst pair; across microphones the misses are unassigned (0 to 4% false accepts), which the confirm band turns into suggestions. Thresholds 0.60 and 0.45 kept. Follow-up: per-microphone prints. |
| Slice 0: attendee email link | built 2026-10-18, unreleased | `speaker_emails` on the meeting, matched at naming time and when a speaker is renamed from the attendee list; in the webhook, markdown, cloud document, REST and MCP; shown under the name in the speaker rename popover on both platforms. Caro's ask; independent of the spike. |
| Slice 1: your voice | built 2026-10-19, unreleased | Settings, Transcription, Voices, "Your voice" (off by default). Learnt from every speaker marked as me at the end of a meeting with the on-device diarizer (20 s of own speech minimum), merged across meetings with a history cap. Matched live every 15 s once a speaker has 10 s of own speech; a confident match marks the speaker as you, a close one shows "sounds like You" in the rename sheet with a confirm button. No reading-passage enrolment yet; mark yourself once in a meeting instead. |
| Slice 2: remembered voices | built 2026-10-19, unreleased | "Remember voices" (off by default). A print per attendee email, learnt at the end of a meeting from speakers that resolve to an email (name match or pick), named next meeting from the first 10 s of own speech, with a confirm band in the rename sheet. The Voices section lists everyone with a Forget button; switching off deletes all. Prints are JSON files in Application Support/VoicePrints, never in SwiftData, the sync document, exports or diagnostics (test). |
| Slice 3: watch recordings diarised on the phone | built 2026-10-19, unreleased | When Speakers is "This device" and the model is loaded, the phone runs the Nemotron diarizer over the joined file, relabels Deepgram's words by the local timeline (splitting utterances where the speaker changes), and names speakers from the prints; confident matches also reinforce the print. Skipped when a live meeting is using the diarizer. |
| Privacy policy and docs | app copy done 2026-10-19; website at release | Settings, Privacy on both platforms states what is kept and where. The website privacy policy paragraph and the docs page are written at release. |

## Why

Diarization separates voices inside one meeting and numbers them from zero every time. Nothing today says that speaker 2 in Tuesday's call is the same person as speaker 1 on Thursday, and on the phone nobody is "You". A voice embedding fixes both: a 192-number fingerprint of a voice, compared by cosine similarity. The FluidAudio package miniti already ships (0.17.4) contains the extractor (`CampPlusEmbedder`, CAM++ on Core ML, about 7 M parameters, two stages, downloaded on demand from `FluidInference/campplus-coreml`), and the AMI evaluation data from the diarization spike has the same people across sessions, so the question can be answered with a day of measurement before any UI exists.

## Decisions (2026-10-18)

1. **Build voice prints, with the attendee email link alongside.** The email link (slice 0) ships regardless of the spike because the webhook consumers want it now; the prints key off the same email.
2. **Measure before building.** The spike has a go or no-go number (status table). No slice 1 or 2 code until it passes.
3. **On-device only.** Prints are computed by the on-device models, stored in the app's container, never written into the cloud document, never sent to Deepgram, OpenAI or miniti's servers. BYOK and managed behave the same. Cloud sync carries the resulting speaker names and emails, not the prints.
4. **Opt-in, explicit.** Your own voice: one setting, off by default, enrolled by reading a short passage or by a one-tap "learn from this meeting" on the Mac where the mic channel is already you. Other people's voices: a second setting, off by default, with the sentence "miniti keeps a voice fingerprint for people it has named, on this device only, so it can recognise them next time". Delete per person from the speaker list; turning the setting off deletes all of them.
5. **Needs the on-device diarizer.** Deepgram's diarizer gives no embeddings. When the diarizer runs on Deepgram, prints do nothing and the settings say so. This is the reason to make the Nemotron diarizer the default on Apple silicon and iPhone, which is a separate decision once the spike and slice 1 are in.
6. **Never guess.** Below the threshold the speaker stays a number. Between the threshold and a margin above it, the speaker gets the name with a "?" and a one-tap confirm; confirming updates the print. The rules from `docs/jev-system-one-plan.md` apply: pin the model, keep thresholds in code with the measurement that set them, no raw-score gating in the UI.
7. **Out of scope now:** prints for people without an attendee email (a name typed by hand can still get a print, keyed by name, in slice 2 if the spike is strong), sharing prints between devices, Linux.

## Design

### Extraction

The on-device diarizer already produces a speaker timeline (10 ms resolution, up to four speakers) over the 16 kHz mono PCM the audio pipeline feeds it. For each speaker, accumulate that speaker's own speech (no overlap) into windows of about 6 s; every window goes through `CampPlusEmbedder.embed(audio:)` (preprocessor on CPU, model on GPU, a few milliseconds per window on Apple silicon; measured in the spike). A speaker's **meeting embedding** is the L2-normalised mean of its windows. Extraction runs on the diarizer's queue, after the timeline update, never on the audio thread.

### Matching

At meeting time, every 30 s and when a new speaker appears: compare each speaker's meeting embedding (once it has at least 10 s of speech) against the stored prints by cosine similarity.

- similarity above `matchThreshold`: label the speaker with the print's name and email;
- between `confirmThreshold` and `matchThreshold`: label with "?" and offer confirm;
- below: leave the number.

One print per speaker, one speaker per print (Hungarian assignment on the similarity matrix when several speakers compete for one print). Both thresholds come from the spike. "You" is matched first and is exempt from the attendee requirement.

### Storage

`VoicePrintStore`, one JSON file per print in Application Support, `VoicePrints/<key>.json`: key (`self` or an attendee email, lowercased), display name, 192 floats, number of meetings merged, created and updated dates, device. Never part of the SwiftData store, never in the sync document, excluded from exports and diagnostics. On macOS the file is written with the same protection the outbox uses. Updating a print after a confirmed match: running mean with a cap on the weight of history (so a voice that changes, or a bad early match, does not stick forever).

### Where it shows

- Speaker pills while recording and the speaker list in the saved meeting: the name, the email under it (slice 0), a small "recognised" mark when the label came from a print, "?" and confirm when uncertain.
- Settings, Transcription: "Your voice" (enrol, re-enrol, remove) and "Remember voices" (switch, list of people with a remove button, count).
- Privacy: the policy's on-device paragraph gains the voice print sentences; the in-app Privacy tab links to the same.

### Watch recordings (slice 3)

The phone has the joined AAC file. Run the Nemotron diarizer over it offline (the FluidAudio offline mode measured in the diarization spike), extract windows per speaker, match against prints, and map Deepgram's words to the local speaker timeline the way the live path already does. Deepgram's `diarize` parameter then stays on only as the fallback when the local model is unavailable.

## Spike protocol

Data: AMI ES2004a, ES2004b, ES2004c (the same four people, three sessions) and IS1009a, IS1009b, IS1009c (another four), each as the headset mix and the far-field array mic, 16 kHz mono; references are the pyannote AMI `only_words` RTTMs. `scripts/voiceprint-poc/fetch.sh` downloads what the diarization spike did not already fetch.

Harness (`scripts/voiceprint-poc/harness`, Swift, FluidAudio 0.17.4 like the transcription harness): for each session and mic, for each reference speaker, concatenate that speaker's non-overlapping speech, cut 6 s windows (minimum 3 s), embed each window, and write `out/<session>.<mic>.json` with the windows' embeddings and timings. `score.py` then reports:

1. **Within a session**: same-speaker versus different-speaker window similarities, and the equal error rate.
2. **Across sessions, same mic**: enrol from the first 20 s of speech of each speaker in session a, identify every window in sessions b and c. EER and the accuracy at the chosen threshold.
3. **Across mics**: enrol on the headset mix, identify on the array mic, and the reverse. The hard case: the phone on a table.
4. **Speed**: milliseconds per window on this Mac, to size the live budget.

Go: EER under 5% within and across sessions on the headset mix, under 10% across mics, with one threshold that keeps false accepts under 2% in every condition. No go: write it up and stop at slice 0.

## As built (2026-10-19)

- `Miniti/Services/VoicePrints.swift`: `VoicePrint`, `VoicePrintStore` (JSON per print, merge with `historyCap` 10), `VoicePrintMatcher` (thresholds 0.60 and 0.45, 10 s minimum, 20 s to learn, self first, one to one), `VoicePrintEmbedderService` (CAM++ via FluidAudio, 17 MB download on first enable), `VoicePrintCollector` (per-slot own-speech windows of 6 s, embedded off the audio thread, running mean per slot).
- `OnDeviceSpeakerTimeline.append` now reports exclusivity per frame and calls `onFrames`; the diarization `Session` takes an optional collector and can ingest decoded samples (watch files); `endSessionAndWait()` for offline runs.
- `SpeakerIdentityState.stableProviderMap()` and `DeepgramService.onDeviceSpeakerMap` translate diarizer slots to app speaker ids.
- `AppState+VoicePrints.swift`: settings (`voicePrintSelfEnabled`, `voicePrintOthersEnabled`), `voicePrintMatchTick` from the transcript-finalize hook, `learnVoicePrintsAtMeetingEnd` from `stopRecording`, suggestions and confirm. Confident print names are protected from the GPT and Jev naming merge (`livePrintMatchedIDs`).
- `Miniti/Views/VoicePrintSettingsView.swift` (both platforms), suggestion row in `RenameSpeakerView`, `MinitiMobile/WatchVoiceDiarization.swift`.
- Tests: `MinitiTests/VoicePrintTests.swift`.

## Rules

- Prints never leave the device. Grep for `VoicePrint` in `MeetingSyncDocument`, `WebhookService`, the markdown export and the diagnostics payload must stay empty; a test asserts it.
- Thresholds live in one place with the spike numbers next to them.
- No em dashes in any copy; the setting names are "Your voice" and "Remember voices"; no "beta" label.
- A print is deleted when the person is removed, when the switch is turned off, and with the account's local data.

## Tests

- Store: round trip, update with history cap, delete per person and all, exclusion from sync and exports.
- Matching: assignment with competing speakers, thresholds, the confirm band, "You" first.
- Extraction: windows from a synthetic timeline, overlap excluded, minimum length.
- Settings and privacy copy present on both platforms.
