# Apple Watch capture and iPhone processing

3.8.0 local candidate: the importer persists attempt count, next eligibility, Retry-After, captured owner/session and per-response usage checkpoints. One foreground worker chooses the oldest eligible recording; permission/quota waits do not spin or starve eligible work. Transient delays are 5/15/60/300 seconds, stopping after eight failures, with a five-second manual retry floor. One foreground wake timer and network-recovery notification respect persisted eligibility. Transcription is cached before meeting save so later retries resume without retranscribing. A failed ledger write stops progress and retains audio before any success receipt or cleanup. Summary failure finishes with a warning and can be retried explicitly in History; owner changes cannot charge the replacement account. See the [current 3.8.0 checklist](../releases/3.8.0.md) and paid-checkpoint contract below.

Shipped in 3.1.0, requiring watchOS 10 or later; voice-print/phone diarization support shipped in 3.2.0; permission waiting added in 3.4.0. Watch records offline, paired iPhone handles transcription, insights, account and History. No standalone Watch backend identity.

## Durable boundaries

- AAC mono 16 kHz, 32 kbps, five-minute segments. Prepare the next recorder before rotating. Persist manifest/segments; interruption finalizes partial capture. On relaunch, unfinished capture becomes interrupted rather than discarded.
- Use `UIBackgroundModes: audio`; App Store Connect rejects audio under `WKBackgroundModes`. Watch is embedded in the iPhone archive. Simulator transfer uses messages because it does not deliver `transferFile`; this is not physical-device evidence.
- Move received temporary files into the durable phone inbox inside the delivery callback. A receipt lets the watch delete the segment files whose indexes the phone has acknowledged, including while capture continues. The recording manifest/queue row remains until `ready`; that receipt follows completed phone processing or an explicit discard. Preserve duplicate/tombstone behavior on resend/relaunch.
- A single readable AAC segment is copied; multiple readable segments are joined by re-encoding with the Apple M4A preset. Passthrough composition export failed for recordings longer than five minutes in 3.1.0 and was replaced in 3.2.0. Normally transcribe the joined file once so speaker IDs remain coherent. If joining fails, transcribe the parts separately and offset their timestamps; speaker numbers can change between parts. Import using `externalSource=watch` and recording ID as the stable duplicate key. Account usage uses prerecorded duration, not upload wall time; provider calls still require admission.
- Retain audio until a durable result or an explicit user discard. Failed/blocked jobs must not silently lose it. On-device diarization/voice prints on the phone are optional and do not make Deepgram transcription local.

## Permission and retries

History Update and Watch processing enforce third-party permission. A Watch job without permission waits with its audio; no grant, upload or insights. Recheck before each part upload and before insights. Permission grant resumes once; withdrawal returns to waiting. Private-mode refusal remains separate from permission and minute limits.

R4 retry/spin and blocked-first-job starvation are fixed in the local 3.8.0 candidate, with one worker and durable eligibility/backoff. [Reliability](../plans/reliability.md) owns scope; the [current checklist](../releases/3.8.0.md) separates automated receipt/retry/billing coverage from remaining physical Watch evidence.

## QA and history

Physical 5/30/60-minute capture, wrist down, phone absent/reconnect, interruptions, low storage, locked phone and battery measurements lack complete recorded evidence. Simulator success does not close these checks. See [validation register](../runbooks/validation.md), [original Watch record](../archive/apple-watch-plan.md) and [voice-print record](../archive/voice-prints-plan.md). No Linux Watch app is implied; shared billing/document changes still require Linux contract tracking.


## Local 3.7.0 speaker-work compatibility

Prerecorded Watch diarization awaits completion of each one-second chunk instead of queueing a whole file into the live worker's eight-second/128-packet limit. Each wait is bounded to two seconds; failure/cancellation keeps the existing Deepgram labels and prevents voice learning from incomplete local work. There is no flush between chunks. File ingestion, live audio callbacks, failure reporting and finalization carry their owning speaker-session ID, so a live recording that falls back to provider labels cannot feed, stop or report the Watch worker as its own. Controlled backpressure, timeout and stale-owner tests cover this boundary. Physical Watch transfer/long-file performance remains separate validation.

3.8.0 second review: once a transcript is saved, a real summary failure completes import with a summary warning rather than retrying import/webhook eight times. Settled failed/skipped processing is not automatically regenerated on job recovery. History can explicitly generate missing insights. Pre-transcript transport/retry rules and audio-retention-until-save remain unchanged.


Review follow-up (2026-11-06, supersedes the earlier background-arrival allowance): background Watch transfers save and acknowledge audio, but new provider jobs wait for the iPhone scene to become active. WCSession activation alone does not activate the worker. If the scene backgrounds during a running import, lease expiry cancels its task; suspension requeues without spending a retry attempt. Throttled and 5xx upload failures close unused managed grants before retrying. An account change waits for a running Watch import; dormant jobs retain audio and the original owner and do not prevent credential repair. Real suspension and lost provider-response behavior still need physical QA.


3.8.0 seventh-review audio boundary: joining requires all expected source parts and checks cancellation at asynchronous boundaries. It writes a temporary sibling, validates the full duration, then atomically replaces the joined file. Cached joins must match the sum of readable source durations before reuse. Joining or cancellation cannot publish a first-part-only success, and separate-part transcription cannot silently skip an unreadable duration. Cancellation leaves the job and audio for activation; summary cancellation does not send a ready receipt in that cancelled run. Physical background expiration remains a separate gate from the real AAC fixture tests.

## Paid transcription checkpoints (3.8.0 local, 2026-11-06)

Each successfully received provider result is atomically cached before observing cancellation. Separate-part checkpoints retain session and account ownership, including silent results with a valid duration; full-file results follow the same rule. Retries reuse completed parts and, once part checkpoints exist, continue that path instead of uploading a newly joined whole recording. Audio remains until the complete meeting is saved.

The importer durably queues settlement for prior managed sessions before replacing a grant or switching the remaining work to BYOK. Only the original managed parts contribute to that session's duration; BYOK parts are excluded. Settled-session IDs survive retries. Legacy jobs without checkpoints retain their prior duration/cache fallback. The running job cannot be dismissed and resurrected mid-attempt; background expiration is scoped to its worker generation. Every part must have a finite positive duration, and an owner mismatch asks for the original account.

This cannot recover a paid response that never reached the phone or guarantee a checkpoint through disk failure. Unreadable-part salvage UI remains deferred with original audio retained. Physical suspension, permission and provider checks remain release gates.

A complete paid-response checkpoint is reused before obtaining credentials or rebuilding audio, even if the final transcript cache write failed. Silent provider responses retain the provider's duration directly, avoiding a cancellation-sensitive file read after the paid request. No retry switches a complete checkpoint into a per-part upload.

Ninth-review settlement contract: a complete set of part checkpoints is assembled before requesting a new grant, including all-silent results. New receipt-based sessions, including pre-155 private jobs identified by their saved checkpoints, settle only their own received parts; an unused retry grant settles zero. Older ledgers retain their legacy fallback. Dismiss removes audio immediately but retains receipt JSON until usage is durably queued under its original account; this survives relaunch. Dismissed checkpoints expire after 30 days, including unreadable ones, matching the usage delivery window. An unreadable dismissed checkpoint is attempted at most once per service lifetime before expiry; it never invents billable minutes. Corrupt undismissed checkpoints are reported with audio retained rather than automatically uploaded and charged again. Full-worker cancellation/resume and a switch of remaining work to BYOK have regression coverage.
