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
