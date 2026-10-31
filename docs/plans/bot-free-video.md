# Bot-free video recording on Mac

Status: scoped proposal, not implemented. Updated 2026-10-31. Selected product direction: optional Mac video that continues while other apps are foreground. Outside 3.6.0. [Roadmap](../roadmap.md#planned-later-bot-free-video-recording) owns priority; this document does not authorize implementation or deployment.

## First deliverable

Record a user-selected meeting window with mic and system audio, save it on the Mac, play it in History, seek from transcript timestamps, and export an MP4. Video is off by default and selected before a meeting starts. Audio-only sessions retain their existing capture and permission behavior. Recording miniti itself is not required; minimising miniti must not interrupt capture.

The selected window must keep recording when covered by other windows or when another app/Space is foreground. Minimising the meeting window may pause video while audio/transcription continue, with clear status and a preserved timeline. Closing the source must not silently capture another window. A browser meeting needs its own window: changing tabs changes the captured content. Pop-outs and screen-share window changes need explicit handling or documented limitations. No separate participant camera feeds or automatic layout composition.

Hosting is not required for this deliverable. Existing cloud sync can continue to carry meeting text under its existing policy; a video remains on the recording Mac and is clearly labelled as local. No new uploads are implied by an existing Cloud setting. Local video consumes disk space and is lost with that disk unless the user exports or backs it up.

Excluded: mobile/Linux video capture, unattended meeting bots, hosted playback/sharing, clip editing, video understanding/OCR, independent participant tracks and live video broadcast. Local recording must remain independent of optional cloud sync and of managed/BYOK transcription.

## Existing architecture and proposed integration

- `AudioCaptureService.swift` currently uses Core Audio process taps plus AVAudioEngine, with 16 kHz transcription buffers. This is not an existing video/media library. Reuse the proven transcription path; add a separate media recorder with bounded off-main work and independent failure handling.
- Use ScreenCaptureKit's independent-window capture. Apple documents capture behind other windows, off-screen and across displays, and pausing when minimised. Behaviour across Spaces remains an explicit V0 check. These platform capabilities still require testing with actual meeting apps on supported OS versions. [Apple capture behaviour](https://developer.apple.com/videos/play/wwdc2022/10155/).
- Prototype the media/audio clock boundary before choosing between writing timestamped samples with AVAssetWriter and newer ScreenCaptureKit recording outputs. The app supports macOS 14.2, so do not assume newer recording/microphone convenience APIs exist everywhere. Resolve availability/fallback in V0; changing the app minimum OS is a separate decision. [Apple recording overview](https://developer.apple.com/videos/play/wwdc2024/10088/).
- Start with a proposed 1080p maximum, 15 fps, H.264/AAC preset. Measure slide legibility, motion, encoding load and file sizes; this is a test preset, not a quality guarantee. Preserve microphone/system identity in transcription and prevent duplicate audio or echo in playback. Decide whether capture needs higher-quality audio than the transcription buffers during V0.
- Own media files in a separate local store keyed by stable meeting identity. Keep file bytes out of SwiftData, cloud documents, Redis and Postgres. Any shared metadata must be optional and compatible with existing records; do not sync local absolute paths.
- Map media timestamps to meeting time through starts, pauses, ending grace, resume, audio route changes and transcription reconnects. Missing video frames must not shorten the audio timeline. Provider reconnects must not duplicate media or move transcript seeking.
- Prefer independently recoverable segments or another measured crash-safe format, then produce an ordinary seekable MP4 for export. Finalisation must not block taking notes in the next meeting. Bound disk buffers, expose disk-full failures, and preserve completed segments after interruption.
- Show recording, video-paused, finalising, ready and failed states truthfully. Provide file-size visibility, explicit video removal and export. Transcript trimming does not redact the media: say so beside video export until media trimming is implemented. Deleting a meeting must clean up its owned media without deleting unrelated files.

## Work estimate

Planning ranges for one experienced engineer familiar with this app, using coding assistance. Active engineering days including focused QA, not measured throughput or promised calendar dates. Access to supported macOS versions and physical meeting/audio setups is assumed. Re-estimate after V0; cross-app rendering or clock problems could exceed these ranges.

| Work | Estimate | Completion evidence |
|---|---|---|
| V0: capture/clock feasibility | 2–4 days | Zoom, Teams and Meet background capture; both audio sources; 60-minute synchronisation; OS compatibility decision |
| V1: recording lifecycle and durable files | 4–6 days | Start/stop/grace/resume, route changes, recoverable interruptions, disk failure and next-meeting isolation |
| V2: History and controls | 3–5 days | Window picker, permissions, playback, timestamp seeking, local-file state, MP4 export/removal |
| V3: compatibility and release QA | 4–7 days | Long sessions, resource measurements, app/OS matrix, migration, accessibility and release evidence |
| Local version total, including V0 | 13–22 days | Roughly 3–5 focused working weeks |

A capture demo is only V0. A dependable local feature includes V1–V3. Hosted playback and sharing would add an estimated 10–20 engineering days after this foundation, roughly 5–9 weeks total for both scopes. Team workspaces, clip editing and broad platform parity would require their own estimates.

## Acceptance and release gates

1. V0 must demonstrate native Zoom and Teams plus Google Meet in supported browsers, while switching apps, covering the meeting, moving Spaces, resizing and switching call layouts. Record minimisation, closed-window and browser-tab limitations explicitly. Test miniti minimised separately from the meeting window.
2. Measure audio/video alignment at the start and end of at least a 60-minute call and after interruptions; proposed target is within 200 ms for media sync. Transcript seeking should reach the spoken phrase within 1 second using existing timestamps. These targets are not achieved evidence.
3. Verify permission refusal/revocation, failed video start, mic-only/system-only capture, Bluetooth changes, ending grace, resume, sleep/wake, quit/relaunch, forced termination, disk exhaustion and deletion during finalisation. Screen lock/sleep need truthful pause/gap states, not a promise of continued capture.
4. Verify independent audio/transcription survives a video failure, with no regression in diarization, provider reconnect or local transcription. Respect the existing private-mode and configured-export contracts; new video never uploads automatically.
5. Use disk-backed recovery tests and real two-hour calls to measure lost trailing media, peak memory, CPU/energy and storage. Set release budgets from V0 measurements before V1. Synthetic stream tests alone do not establish cross-app compatibility.
6. Verify a legacy meeting, a meeting with a missing file, a meeting synced to another device, a transcript edited/trimmed after capture, and an account switch. Never silently transfer hosted media ownership if a later phase is selected.
7. Run both Apple bundles for shared model/view changes, affected integration tests, and physical Mac QA. Add Linux parity tracking before introducing a user-visible implementation or shared contract. Update public docs and privacy copy for actual shipped behavior.

Rollout: opt-in, local-only, no automatic conversion of past meetings. Disable new video starts if regressions occur while preserving existing audio recording and access/export of saved media. File/schema changes must remain readable or have a documented recovery path. Closing this plan requires measured compatibility, resource/recovery results and a release record.

## Optional hosted phase, not selected

Hosting is useful for opening video on another device and sending a link that works while the recording Mac is offline. Upload after recording is sufficient; recording does not need a live video server.

Two candidates: an encoded MP4 in private object storage with range-based playback, or a managed video service that supplies transcoding and adaptive playback. Object storage leaves us responsible for encoding compatibility, players and access controls. A managed service reduces that media work but does not implement miniti account permissions, retention or sharing policy.

Proposed flow: app records locally, obtains scoped upload authority from miniti-api, uploads directly to media storage with resumable transfers, then confirms durable completion. Backend stores metadata/ownership/quota only and authorises playback. Never route video bytes through ordinary sync JSON or use permanent public object URLs. [Example temporary object access](https://developers.cloudflare.com/r2/api/s3/presigned-urls/).

Before selecting this phase, settle provider/region, retained hours/bytes, retention expiry, downgrade behavior, local/cloud deletion semantics, account ownership and sharing audience. Implement upload retries, quota reservations, incomplete-upload cleanup, expiry/deletion jobs, revocable shares and bounded playback authority. Check permissions again after account changes or a meeting becomes Local; queued uploads must not undo a privacy choice. Existing account/meeting ownership gaps must be resolved for media rather than copied into a new storage service.

Proposed hosted breakdown: uploads and quota 3–5 days; playback/share authorisation 3–6 days; retention/deletion/account fences and operations 4–9 days. Provider selection and product decisions remain open. Cloud storage is a separate entitlement decision; current transcription minutes do not promise unlimited retained video.

## Evidence status

2026-10-31: repository/API-document review and planning only. No video prototype, device measurement, provider selection or purchase has occurred. Private provider-cost scenarios are kept in an ignored local financial note, not in the public repository or website. No dates or scope changes to 3.6.0 follow from this plan.
