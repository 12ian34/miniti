# Recording lifecycle, calendar starts and speaker identity

Current shipped contracts, consolidated 2026-10-27. [Audio](audio.md) owns capture/recovery; [patterns](patterns.md) owns save/async boundaries. Historical plans retain detailed transition matrices and rationale.

## Automation and presence

Smart meetings is distinct from auto-start/stop. Call-app evidence and conservative policy drive macOS call lifecycle; silence and calendar evidence are supporting signals, not proof a call ended. Ending grace is reversible until actual stop. User-visible start/end/quiet/calendar choices remain reachable from the floating surface/menu bar, with notifications as fallback. Reopening the app must not create an extra meeting or lose the current one.

Every start path goes through the same guarded meeting transition, including calendar Join, countdown, automation and handoff. Seed prepared notes once. Open a join URL only after recording start was accepted; a failed browser open must remain retryable. Notification actions foreground the app; cold-launch actions wait for calendar resolution. Backend event keys are camelCase; the decoder’s fallback is compatibility, not permission to silently drop links/attendees.

Calendar-linked macOS auto-start waits for a live call in the T−5 to T+10 window, then offers Record/Skip rather than recording a no-show. No-link/in-room and iOS follow their separately defined clock behavior. iOS cannot wake itself to auto-start. Calendar visibility filters are not cloud privacy filters.

## Speaker and source invariants

Mic and system channels keep distinct source identities; multiple in-room mic speakers must not collide with remote IDs. Environment inference is diagnostic evidence, not authority to change capture, usage, persistence or transcript content. Do not infer “in room” merely from missing remote transcript. Echo removal remains conservative; preserving genuine speech takes priority over aggressive deduplication.

Use finalized evidence for speaker promotion, not replayed cumulative interims. Stable identities survive reconnects and user edits. Do not lower speaker thresholds globally to fix short interjections; evaluate fixtures for existing known speakers, simultaneous speech and echo first. Keep local diarization’s clock/maturity rules in [local models](local-models.md).

## Regression sources

- [Call lifecycle and recording presence](../archive/call-lifecycle-and-recording-presence-plan.md): shipped transition, grace, reopen, notification and recording-surface matrices. Old implementation estimates are historical.
- [Smart meetings](../archive/smart-meetings-plan.md): safe handoff/save transaction and notification routes. Later call-lifecycle behavior takes precedence over earlier quiet-end proposals.
- [Calendar wait-for-call](../archive/calendar-auto-start-waits-for-call-plan.md): late join/no-show policy and QA evidence gap.
- [Join links and corrections](../archive/join-links-speaker-clones-inline-corrections-plan.md): camelCase decoding incident, start/browser ordering and inline dictionary edits.
- [In-room diarization](../archive/automatic-in-room-diarization-plan.md): source/identity rules. Its deferred on-device/voice-print items subsequently shipped; those are not current backlog.

Physical route changes, Bluetooth callbacks, denied permissions and 60-minute behavior retain real-device checks. Do not promote historical tests to passes without evidence.

## Local 3.7.0 stop/reconnect follow-through

Not released. Stop always enters a bounded final drain before deciding whether an empty recording can be discarded. It settles pending/visible transcript before diagnostics, voice learning and persistence. The socket receive bound stays 800 ms; local transcription may finish for up to 30 seconds, then receives for 800 ms (30.8-second maximum). The [transcription POC](../../scripts/transcription-poc/RESULTS.md) measured 17.5 minutes decoded in 16 seconds and 47 ms p95 per 1.12-second chunk on M5 Pro. The cap adds headroom over that measured decode workload, not a guarantee on other Macs. Controlled delayed-finish and hang fixtures cover the bounds; physical devices retain separate checks. The first final does not truncate another source's tail; an old connection generation cannot tear down a replacement. Reconnect waits for connection completion/failure within its timeout and preserves generation ownership through credential awaits and cleanup. iOS readiness only expects microphone PCM. See the [recording plan](../plans/recording-reliability-followup.md#initial-local-implementation-2026-11-03) for implementation and validation boundaries.

Local 3.7.0 speaker settlement precedes transcription drain and allows two seconds plus accepted queued audio duration, including the in-flight packet and audio buffered inside the processor (fed-minus-processed timeline gap), up to 18 seconds for two sources. Session lag invalidates its labels/voice evidence but preserves prepared models; real inference/load errors still require retry. Discard retires its worker and invalidates its timeline/voice evidence; a stale finalizer checks meeting ownership again before disconnecting transcription. A failed local speaker timeline remains latched through ordinary transport reconnect, so no speaker-only recovery is implied. See [speaker failure handling](../plans/local-speakers-default.md#local-failure-handling-implementation-2026-11-03).

### Local 3.7.0 diagnostic outcome follow-through

Each recording attempt latches valid capture sources and its starting accumulated duration. Successful capture start is distinct from PCM readiness; lifecycle stopped/cancelled/failed is independent of transcription evidence. New words, including final-drain receipt, mark the current attempt, while saved text from an earlier recording does not. Final duration subtracts earlier active intervals. New outcome events remain informational and follow managed/Share diagnostics/private gates. iOS recovery checks only its microphone source. See the [bounded reliability plan](../plans/recording-reliability-followup.md#local-activity-and-outcome-follow-through-2026-11-03) for implemented recovery-generation and AI evidence.


Recovery milestones now distinguish planned restart, connection restoration and fresh words. A queued connected notification from the socket being replaced cannot cancel its retry owner; generation-bound progress and recent requested-source capture gate recovery. Live speaker ingestion, failure handling and Stop/discard retain their speaker-session ID and cannot mutate an independent prerecorded Watch worker. See the [reporting contract](recording-reporting-contract.md#recovery-and-ai-context-additive-v1) and [Watch compatibility](watch.md#local-370-speaker-work-compatibility).
