# Feature reference

### macOS — native AI meeting assistant

- mic + system audio recording, with a microphone picker (Home mic pill and Settings → Recording) so earphones connecting do not silently move recording off a desk mic
- live transcription with deepgram, including distinct in-room speakers sharing the Mac microphone alongside remote/system speakers
- live speaker identification + automatic speaker naming (infers real names from the transcript; uses calendar attendees as hints when connected)
- optional on-device speaker separation (Settings → Transcription, Speakers: This Mac): Nemotron-3 diarization on Apple silicon replaces Deepgram's diarizer for new recordings; falls back to Deepgram whenever the model is unavailable
- voice prints (3.2.0, Settings → Transcription, Voices, both off by default, need Speakers: This Mac): "Your voice" learns you from speakers marked as me and labels you from the first 10 s of own speech; "Remember voices" keeps a print per attendee email and names them next time, confirm band in the rename sheet; CAM++ embeddings (FluidAudio, 17 MB download), stored only on the device, never synced or exported; [local-model contracts](local-models.md)
- private mode (Settings → Privacy, 2.12.0, Apple silicon): one switch that turns on both on-device engines and turns off every cloud AI feature (summaries, questions, Sales, templates, catch-up, speaker names, Jev, Playbook, investigations), restoring the previous choices when switched off; cloud-only languages cannot record while it is on; managed limit does not gate a private meeting
- optional on-device transcription (Settings → Transcription, Transcription: This Mac, 2.12.0): Nemotron 3.5 streaming recognition on Apple silicon replaces the Deepgram socket for new recordings in 8 of the 11 languages; a 590 or 640 MB model downloads on first enable; no minutes metered; a start with the model missing is refused unless Deepgram fallback for that meeting is allowed
- optional Jev classifier (managed only, Settings → AI, Speaker names: Jev): attendee speaker naming and the sales-conversation suggestion answered by TypeSafe Jev through `/api/classify` in under a second; GPT and the phrase list take over on any failure
- live AI-generated summaries and action items
- optional live Sales analysis using MEDDPICC (enabled from the specialist insights menu, with a local default-on suggestion when a conversation sounds commercial)
- optional Templates view — structured notes filled live from a built-in template (BANT, SPIN, interview scorecard, customer check-in, stand-up, 1:1) or your own; chosen per meeting from the insights More menu (one flat list with Sales, then Playbook; the tab remembers the pick for the meeting), refilled on a Sales-like cadence and at finalization, persisted on the meeting, and included in markdown exports and webhooks. Settings → Templates drafts a template from a one-line description (2.12.0, managed `template_draft` or BYOK OpenAI)
- questions mode — AI-generated incisive questions to ask during or after a meeting (deeper, challenge, reframe, clarify, explore, follow-up)
- optional Playbook view — docs-MCP cards with citations (configure MCP URL in Settings; automatic topic lookup for Pro/BYOK, manual metered lookup for managed-free)
- coaching mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- google calendar integration — upcoming meetings across coming days, event prep notes carried into live notes, auto-fill title and attendees, auto Attio or Twenty CRM sync; adjustable meeting filters (out of office, focus time, all-day, declined, no guests or meeting link, title prefixes) with a next-7-days preview in Settings → Calendar
- local conversation-moment detection with explicit in-app OpenAI web or codebase investigation; it never runs an investigation automatically
- saved-meeting CRM export to Attio or Twenty with a task preview, deadlines/assignment details, and per-task inclusion controls
- Granola CSV import with duplicate protection and source labels
- grouped, pinnable meeting history browser
- saved transcript trimming with insight regeneration
- native menu bar controls with an elapsed recording timer, plus a floating call/recording surface that raises for every start, recording, ending, quiet, and calendar-handoff decision and carries foreground question/coaching nudges
- keyboard shortcuts for common recording and navigation actions
- default-on Smart meetings prompts for likely-ended recordings and safe calendar handoffs (join next / end & start next / end meeting / keep recording / remind), independently switchable from existing auto-start/stop
- managed account: anonymous recovery key, up to 5 devices, Pro follows the account (a sponsored device shows "Pro comes from another device"), move this device to another account
- outbound webhooks over https only (loopback excepted), hook URLs never logged; Share Diagnostics on by default in managed mode
- cloud (3.0.0, Pro only, default off, Settings → Cloud): finished meetings synced across every device on the account through miniti's servers (Neon Postgres); optional email for web sign-in and new-device sign-in by approval link; personal access tokens for the read-only REST API and the MCP server (Claude Code, Cursor) and OAuth for Claude.ai and ChatGPT connectors; per-meeting "Keep off the cloud"; meetings recorded under private mode never sync; delete cloud copy; since 3.3.0 the switch belongs to the account: on or off on one device is on or off on every device at its next usage check (`/api/account/cloud`, mirrored on `/api/usage`), private mode still pauses this device only
- in-app auto-update via Sparkle (Miniti menu → Check for Updates…)

### iOS — mobile AI meeting assistant

- mic recording with background support
- live transcription with deepgram, including multiple speakers sharing the device microphone
- automatic speaker naming (infers real names from the transcript; uses calendar attendees as hints when connected)
- optional on-device speaker separation (Settings → Transcription, Speakers: This device): Nemotron-3 diarization on the phone replaces Deepgram's diarizer for new recordings; falls back to Deepgram whenever the model is unavailable
- live AI-generated summaries and action items
- optional live Sales analysis using MEDDPICC (enabled from the specialist insights menu, with a local default-on suggestion when a conversation sounds commercial)
- optional Templates view — structured notes filled live from a built-in template (BANT, SPIN, interview scorecard, customer check-in, stand-up, 1:1) or your own; chosen per meeting from the insights More menu (flat list, remembers the pick), refilled on a Sales-like cadence and at finalization, persisted on the meeting, and included in markdown exports and webhooks. Settings → Templates drafts a template from a one-line description (2.12.0)
- questions mode — AI-generated incisive questions to ask during or after a meeting
- optional Playbook view — docs-MCP cards with citations (configure MCP URL in Settings; automatic topic lookup for Pro/BYOK, manual metered lookup for managed-free)
- coaching mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- google calendar integration — upcoming meetings across coming days, event prep notes carried into live notes, auto-start countdown, attendee context in insights; adjustable meeting filters with a next-7-days preview in Settings → Calendar
- local conversation-moment detection with explicit in-app OpenAI web research; it never runs an investigation automatically
- Granola CSV import with duplicate protection and source labels
- grouped, pinnable meeting history browser
- saved transcript trimming with insight regeneration
- Live Activity on Dynamic Island and Lock Screen (timer + optional live transcript, with tap-through to the active meeting)
- Apple Watch app (3.1.0, watchOS 10+, embedded in the iOS app): records on the wrist to AAC in 5-minute pieces and moves them to the iPhone over Watch Connectivity while recording. The phone normally joins and transcribes them as one file through Deepgram prerecorded (managed grant via `/api/session/prerecorded` or BYOK key); since 3.2.0, joining re-encodes multiple pieces and a failed join falls back to separate transcription. It saves one meeting with `externalSource "watch"` and runs the usual final insights. Optional on-phone speaker separation and voice matching joined in 3.2.0. History shows "From your watch" rows with Try again and Remove; minutes use audio duration; private mode refuses processing, and missing third-party permission waits with the audio since 3.4.0. The simulator uses message-based transfer because it never delivers `transferFile`. See [Watch](watch.md) for receipt/cleanup rules and remaining reliability work.
- default-on Smart meetings prompts for likely-ended recordings and safe calendar handoffs (join next / end & start next / end meeting / keep recording / remind), independently switchable from existing auto-start/stop
- managed account: anonymous recovery key, up to 5 devices, Pro follows the account, move this device to another account
- outbound webhooks over https only; Share Diagnostics on by default in managed mode
- cloud (3.0.0, Pro only, default off, Settings → Cloud): the same sync, web sign-in, tokens and connected apps as macOS; since 3.3.0 the switch belongs to the account: on or off on one device is on or off on every device at its next usage check (`/api/account/cloud`, mirrored on `/api/usage`), private mode still pauses this device only
- dark mode terminal-style UI

Current account/email, consent and Sending behavior is in [Settings](settings.md). Scope and platform delivery evidence are in [the roadmap](../roadmap.md) and [release record](../releases/3.4.0.md).
