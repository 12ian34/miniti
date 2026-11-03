# Apple Watch capture and iPhone processing

Shipped in 3.1.0, requiring watchOS 10 or later; voice-print/phone diarization support shipped in 3.2.0; permission waiting added in 3.4.0. Watch records offline, paired iPhone handles transcription, insights, account and History. No standalone Watch backend identity.

## Durable boundaries

- AAC mono 16 kHz, 32 kbps, five-minute segments. Prepare the next recorder before rotating. Persist manifest/segments; interruption finalizes partial capture. On relaunch, unfinished capture becomes interrupted rather than discarded.
- Use `UIBackgroundModes: audio`; App Store Connect rejects audio under `WKBackgroundModes`. Watch is embedded in the iPhone archive. Simulator transfer uses messages because it does not deliver `transferFile`; this is not physical-device evidence.
- Move received temporary files into the durable phone inbox inside the delivery callback. A receipt lets the watch delete the segment files whose indexes the phone has acknowledged, including while capture continues. The recording manifest/queue row remains until `ready`; that receipt follows completed phone processing or an explicit discard. Preserve duplicate/tombstone behavior on resend/relaunch.
- A single readable AAC segment is copied; multiple readable segments are joined by re-encoding with the Apple M4A preset. Passthrough composition export failed for recordings longer than five minutes in 3.1.0 and was replaced in 3.2.0. Normally transcribe the joined file once so speaker IDs remain coherent. If joining fails, transcribe the parts separately and offset their timestamps; speaker numbers can change between parts. Import using `externalSource=watch` and recording ID as the stable duplicate key. Account usage uses prerecorded duration, not upload wall time; provider calls still require admission.
- Retain audio until a durable result or an explicit user discard. Failed/blocked jobs must not silently lose it. On-device diarization/voice prints on the phone are optional and do not make Deepgram transcription local.

## Permission and retries

History Update and Watch processing enforce third-party permission. A Watch job without permission waits with its audio; no grant, upload or insights. Recheck before each part upload and before insights. Permission grant resumes once; withdrawal returns to waiting. Private-mode refusal remains separate from permission and minute limits.

The immediate retry/spin and blocked-first-job starvation are still open R4 work in [reliability](../plans/reliability.md). Preserve one worker and durable eligibility/backoff when fixing it. T10’s end-to-end receipts, retries, relaunch and billing tests belong to that plan.

## QA and history

Physical 5/30/60-minute capture, wrist down, phone absent/reconnect, interruptions, low storage, locked phone and battery measurements lack complete recorded evidence. Simulator success does not close these checks. See [validation register](../runbooks/validation.md), [original Watch record](../archive/apple-watch-plan.md) and [voice-print record](../archive/voice-prints-plan.md). No Linux Watch app is implied; shared billing/document changes still require Linux contract tracking.


## Local 3.7.0 speaker-work compatibility

Prerecorded Watch diarization awaits completion of each one-second chunk instead of queueing a whole file into the live worker's eight-second/128-packet limit. Each wait is bounded to two seconds; failure/cancellation keeps the existing Deepgram labels and prevents voice learning from incomplete local work. There is no flush between chunks. File ingestion, live audio callbacks, failure reporting and finalization carry their owning speaker-session ID, so a live recording that falls back to provider labels cannot feed, stop or report the Watch worker as its own. Controlled backpressure, timeout and stale-owner tests cover this boundary. Physical Watch transfer/long-file performance remains separate validation.
