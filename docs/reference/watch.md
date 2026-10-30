# Apple Watch capture and iPhone processing

Shipped in 3.1.0; voice-print/phone diarization support shipped in 3.2.0; permission waiting added in 3.4.0. Watch records offline, paired iPhone handles transcription, insights, account and History. No standalone Watch backend identity.

## Durable boundaries

- AAC mono 16 kHz, 32 kbps, five-minute segments. Prepare the next recorder before rotating. Persist manifest/segments; interruption finalizes partial capture. On relaunch, unfinished capture becomes interrupted rather than discarded.
- Use `UIBackgroundModes: audio`; App Store Connect rejects audio under `WKBackgroundModes`. Watch is embedded in the iPhone archive. Simulator transfer uses messages because it does not deliver `transferFile`; this is not physical-device evidence.
- Move received temporary files into the durable phone inbox inside the delivery callback. Receipts acknowledge durable ownership; ready removes the Watch copy only after the phone has saved the meeting. Preserve duplicate/tombstone behavior on resend/relaunch.
- Stitch AAC without re-encoding and transcribe once where possible so speaker IDs remain coherent. Import using `externalSource=watch` and recording ID as the stable duplicate key. Account usage uses prerecorded duration, not upload wall time; provider calls still require admission.
- Retain audio until a durable result or an explicit user discard. Failed/blocked jobs must not silently lose it. On-device diarization/voice prints on the phone are optional and do not make Deepgram transcription local.

## Permission and retries

History Update and Watch processing enforce third-party permission. A Watch job without permission waits with its audio; no grant, upload or insights. Recheck before each part upload and before insights. Permission grant resumes once; withdrawal returns to waiting. Private-mode refusal remains separate from permission and minute limits.

The immediate retry/spin and blocked-first-job starvation are still open R4 work in [reliability](../plans/reliability.md). Preserve one worker and durable eligibility/backoff when fixing it. T10’s end-to-end receipts, retries, relaunch and billing tests belong to that plan.

## QA and history

Physical 5/30/60-minute capture, wrist down, phone absent/reconnect, interruptions, low storage, locked phone and battery measurements lack complete recorded evidence. Simulator success does not close these checks. See [validation register](../runbooks/validation.md), [original Watch record](../archive/apple-watch-plan.md) and [voice-print record](../archive/voice-prints-plan.md). No Linux Watch app is implied; shared billing/document changes still require Linux contract tracking.
