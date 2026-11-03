# On-device transcription usage tracking

Selected by Ian on 2026-11-02 for 3.7.0; implemented locally on Apple/backend, with validation and release checks below; not deployed. The [roadmap](../roadmap.md#selected-next-release-370) owns priority. Follow the selected test foundation before running hosted app tests.

## Problem and current behavior

Local transcription opens no managed session and sends no session-end usage report (`AppState.startManagedRecording` and `stopRecording`). Backend `incrementUsage` feeds device cycle/lifetime usage, daily admin charts and Deepgram cost estimates. Consequently, those minute totals omit local recordings even when managed AI requests generate separately tracked costs.

## Selected scope

- Record on-device recording duration and the transcription engine actually used. Selecting This Mac with a permitted Deepgram fallback must report the actual session route, not the saved preference. Local speaker separation alongside Deepgram transcription remains Deepgram usage.
- Keep local minutes separate from the existing managed allowance counters and Deepgram cost inputs. This work does not change pricing, allowances or AI gating.
- Show total, managed Deepgram and on-device minutes in admin daily charts, aggregate/lifetime totals and individual device rows, with matching API/CSV fields and explicit reporting coverage.
- Add authenticated, validated reporting with durable offline retry and idempotent counting. Recording must not depend on a successful analytics request. Handle pause/resume, restart recovery and account changes without duplicate minutes or attribution to a different account.
- Send only the bounded duration/engine metadata needed for usage reporting, never audio, transcript or meeting content. Ian confirmed on 2026-11-03: count all managed recording minutes, including local/private duration, independently of Share diagnostics. BYOK reporting stays off. The contract below owns coverage; update Privacy descriptions before shipping the producer.
- Establish a collection start boundary. Existing local minutes cannot be reconstructed reliably from the current counters; older clients remain incomplete coverage, not evidence of zero local activity. Do not invent historical totals or infer exact usage from optional diagnostics.

## Coverage and counting contract, confirmed 2026-11-03

| Situation | Report usage | Consume managed allowance |
|---|---|---|
| Managed Deepgram transcription, local or cloud speaker separation | Existing managed session reporting | Existing rules, unchanged |
| Managed on-device transcription, including private recordings | New local-duration reporting | No |
| Managed with Share diagnostics off | Same usage reporting as above; no automatic hardware/error diagnostics | Only existing Deepgram rules |
| BYOK, any engine/private setting | No new usage reporting | No |

"All managed minutes" is the collection target for updated clients, not a claim of complete historical or offline coverage. Admin totals must label the collection start, older-client/undelivered gaps and excluded BYOK usage. Keep existing managed Watch/prerecorded Deepgram accounting; do not add a second report for imported History, retranscription or the same audio already counted by the managed route. This plan does not introduce new local Watch/iOS transcription support.

Count active recording duration, excluding pauses and pre-start/failed-start time; it is not successfully transcribed speech duration. A local engine failure while capture continues remains local recording time with an independent outcome, not Deepgram time. Use the session-latched actual transcription engine, not the preference or diarization engine. Stop/resume creates non-overlapping reporting epochs, while socket retries within an epoch do not create additional minutes. Preserve existing Deepgram counters/cost inputs byte-for-byte for equivalent requests; local counters are additive and never enter billing or allowance checks.

Use a durable random usage-report ID scoped to the originating enrolled installation/account, not a meeting/content identifier. Keep payloads to engine, duration, coarse reporting day, schema/version and idempotency metadata; do not report private-mode flags, meeting titles, precise meeting schedules, speaker identities or content. Split contributions at reporting-day boundaries consistently with existing daily usage; round only for display. Persist the report and stable ID before send, use authenticated writes/proofs, and atomically deduplicate with counter updates. Concurrent delivery and lost-response retries must count once.

Persist bounded active-duration checkpoints without customer content. After a crash, report only durably observed active time, never infer capture from time spent closed or from transcript timestamps; label possible undercount. Choose bounded checkpoint/queue limits in the implementation and test them. Reject reports older than the supported delivery window; deduplication retention must exceed that window so expiry cannot make a valid retry count again. Define overflow/expiry behavior explicitly in current contracts, with incomplete reporting rather than fabricated totals.

Queued reports keep their original owner. Account switch/sign-out must never reattribute them or authenticate them using the new account; retain bounded owner-fenced pending work only where the original identity can send it, otherwise expire it with honest coverage. New BYOK recordings never enqueue reports. An eligible report created under managed mode may be retried only under the original managed identity; no new BYOK enrollment/telemetry is introduced.

Before the client ships, update Settings Privacy/data-flow summaries and the website privacy/model documentation: managed duration accounting also covers local/private recordings, while hardware/error diagnostics follow Share diagnostics. Private mode still keeps audio/transcript processing local and cloud AI off; configured exports remain allowed. No new content upload, paid allowance consumption or hardware collection follows from usage reporting. Public wording must say recording usage, not generic product analytics, and must not promise an exact census while delivery gaps exist.

## Delivery and acceptance

1. Define an additive client/backend contract, storage fields, deduplication/retention rules and privacy/coverage behavior. Keep existing client routes and quota responses compatible. Record the same-day Linux contract handoff in its own tracker when the contract changes; local transcription currently ships on macOS, so do not imply new iOS/Linux engine support.
2. Implement backend ingestion and separate admin reporting. Existing Deepgram minute totals, allowance checks and provider cost estimates must remain unchanged for identical Deepgram inputs.
3. Implement the app producer and durable retry against the counting contract above. Cover successful local recording, permitted pre-start cloud fallback, local-engine failure, pauses/resumes, failed starts, interrupted recordings, offline delivery and account changes. Verify managed/private and diagnostics-off recordings count, BYOK does not, and no private-mode flag/content enters the payload.
4. Verify duplicate and concurrent reports count once, retries survive restart, and total minutes reconcile to the displayed engine breakdown for the same period/device filters. Test legacy requests, older-client coverage and exclusion from Deepgram costs/allowance consumption.
5. Deploy the additive backend before releasing the reporting app. Verify one local and one managed Deepgram recording end to end, including dashboard/CSV totals, unchanged allowance behavior and an offline retry. Update current backend/client contracts and release evidence with actual results.

## Boundaries

This is a bounded reporting correction, separate from the later [usage costs and prompt caching](usage-cost-and-cache.md) analysis. No billing migration, account-ownership redesign, historical backfill from customer content, new transcription engine or public feature promise is included. The [local-model reference](../reference/local-models.md) remains the current behavior until implementation ships.

## Local implementation, 2026-11-03

The [versioned reporting contract](../reference/recording-reporting-contract.md) defines the distinct usage/diagnostic boundaries. Backend `/api/recording-usage` requires enrolled-device proof and exact originating account ownership. Reports are immutable integer milliseconds, UTC-day split and bounded to four hours. One Lua operation validates storage types and numeric destinations before changing counters, atomically deduplicates and retains 35-day receipts for a 30-day delivery window. Existing allowance/cost keys remain unchanged. Both device casing aliases are checked for disablement without creating or repairing legacy device rows.

Apple begins a local epoch only after capture starts, for an enrolled managed owner and actual on-device transcription. It checkpoints to an atomically replaced content-free file every 15 observed seconds, seals at Stop, splits at midnight/four hours, caps pending and active work together at 2,048 reports and expires after 30 days. Crash recovery seals only the persisted checkpoint; an unobserved timer gap contributes at most five seconds, with incomplete coverage recorded. Reports survive offline failures and cannot be sent or acknowledged by another owner. API authorization checks the captured credential generation after awaiting signing. Idle retry runs at bounded intervals; recording does not await delivery. Pre-start failure, BYOK and Deepgram do not create local reports. Unenrolled/offline owners remain a coverage gap rather than triggering enrollment for analytics.

Admin API/chart adds Deepgram/on-device/total daily duration, local installation/lifetime totals, canonical-device sums and explicit coverage. Existing Deepgram fields retain their meaning. CSV distinguishes total rows from installation rows so historical global totals without device breakdowns are retained. Privacy/data-flow wording is prepared in the app and website, not published.

Validation: backend full suite passed 776 tests with five optional cases skipped. Required disposable Postgres/Redis lane passed 14 tests, including 16 concurrent deliveries, lost-response replay, payload conflict, daily cap and malformed-storage atomicity. Apple controlled tests cover midnight/pause, checkpoint recovery, ownership changes during delivery, no sends on storage failure, retry/expiry, actual signed request fields and shared sanitizer fixtures. Full macOS suite passed at `Test-Miniti-2026.11.03_12-40-09-+0000.xcresult`; iOS build-for-testing passed. The final nine-test queue suite also passed, including combined active/pending capacity, repeated wall-clock corrections and four-hour chunks. Loaded day strings are validated once; periodic expiry avoids repeated date parsing on the main actor. Final tooling reconciliation is recorded in the release checklist.

Still required before release: physical local/cloud/private recordings, offline retry through deployed backend and dashboard/CSV reconciliation, any required App Store metadata correction. The current iPhone 16 automated suite and internal disclosure check are complete; see the release record. No backend, website or client release occurred. Recording reliability now also implements analytics writes/digest/latest-metadata normalization locally. Billing/device registry repair remains separate; no authoritative financial snapshots are merged.


## Removal and support validation, 2026-11-03

Local-counter removal is implemented. Revocation first fences the installation, removes local per-installation breakdowns over the bounded retention window, then detaches membership. Account deletion also removes its local aggregate. Global duration totals remain; receipts expire after 35 days and legacy billing/audit records retain their existing policy. Ingestion checks current account ownership, active account state and revocation atomically with both counters and replay acknowledgement. Controlled and real-Redis cases reject moved/revoked in-flight reports and verify that other owners and financial counters are unchanged. Apple removes the deleted account’s pending and active reports without reviving them on a late acknowledgement; other owners survive a restart. See the [reporting contract](../reference/recording-reporting-contract.md) for disk-failure and coverage limits and the [support runbook](../runbooks/operations.md#local-recording-usage-support-370) for reconciliation.
