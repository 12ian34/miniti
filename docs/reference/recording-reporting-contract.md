# Recording reporting contract, version 1

Local 3.7.0 implementation contract, 2026-11-03. Not deployed. Usage and diagnostics have distinct endpoints, consent and storage; neither is inferred from the other. The release checklist owns rollout.

## Recording usage

`POST /api/recording-usage` requires device-bound authentication and a write proof. Body fields are exactly `schema_version: 1`, `report_id` (random UUID), `account_id` (originating opaque case-sensitive `acct_…` ID), `engine: "on_device"`, `day` (UTC YYYY-MM-DD) and `duration_ms` (integer 1–14,400,000). Reject unknown fields, non-finite values, future days, days older than 30 days and account mismatch. The client latches managed mode, actual local transcription and owner at successful capture start; private mode and Share diagnostics do not suppress usage. BYOK never creates reports or enrolls for reporting. Deepgram continues through existing session-end/prerecorded reporting; no second Deepgram report is accepted here.

Each report is immutable, persisted before sending, and scoped to the installation plus original account. Atomic Redis ingestion compares the existing receipt payload before incrementing separate local daily/global/device/account counters. An identical retry is acknowledged; changed reuse of an ID conflicts. Receipts last 35 days from acceptance, exceeding the delivery window. A device's local duration cannot exceed 24 hours for one UTC day. Existing allowance, Deepgram, session and cost keys are untouched. Accepted local reports add the canonical installation ID to the corresponding daily active set. Empty or failed starts contribute nothing. Duration means active capture, not successfully transcribed speech.

Client bounds: sample active capture every second, checkpoint every 15 observed active seconds, stop/resume closes an epoch, split at UTC midnight and four-hour chunks, keep at most 2,048 pending and active reports combined for 30 days. Recover only checkpointed duration after a crash. Never count elapsed time while the app is closed. Overflow/expiry drops the oldest pending work, then active chunks if necessary and marks local coverage incomplete; no backfill is inferred. Ownership is checked before each send and after responses; a different account/mode cannot send or acknowledge old work. New usage reports require the original managed identity. An unobserved sampling gap contributes at most five seconds and marks local coverage incomplete, rather than inferring that capture continued through suspension. Queue limits and producer behavior have controlled tests; physical capture/clock behavior remains a release check.

Admin usage is additive: preserve legacy `usage_daily` as Deepgram usage, add `recording_daily` with Deepgram/local/total minutes and normalized per-device contributions. Collection start is first accepted local report, with incomplete historical/offline coverage and BYOK exclusion stated. Daily local counters expire 400 days after their last accepted report. Installation revocation removes its local lifetime and retained daily breakdowns; account deletion also removes its local account aggregate. Global daily/lifetime totals remain without those identity breakdowns. The 35-day deduplication receipts retain their original bounded payload until expiry to prevent replay. Atomic ingestion rechecks active account ownership and installation revocation before both writes and replay acknowledgements. A delayed request cannot recreate removed breakdowns. The client removes the deleted account’s pending/active queue entries after confirmed deletion; if the local file is unwritable, removal is logged and the revoked owner still cannot deliver those records. Other owners’ pending work survives. Existing billing/audit and activity retention is unchanged; admin coverage explicitly includes removed breakdowns. Do not present zero local reports as proof that no local recording occurred.

## Optional diagnostics

Existing `/api/client-events` consent and managed-mode gates remain. Add bounded fields using one validator shared by event ingest and explicit Help sanitization. Older missing fields remain unknown. No prompts, content, raw exception messages, credentials, private-mode flags, precise meeting schedules or hardware-unique identifiers.

| Fields | Values/bounds |
|---|---|
| `schema_version` | `1` |
| `transcription_engine`, `speaker_engine` | `deepgram`, `on_device`, `unavailable`, `unknown` |
| `lifecycle_outcome` | `stopped`, `cancelled`, `failed` |
| `transcription_outcome` | `words_seen`, `speech_without_words`, `no_speech_evidence`, `unknown` |
| `failure_category` | `transport`, `timeout`, `auth`, `admission`, `decode`, `provider`, `persistence`, `model_access`, `cancelled`, `superseded`, `unknown` |
| `task_mode` | supported insights task names; `ai_stage`: `live`, `final`, `saved`, `helper` |
| `request_id` | opaque UUID only, optional |
| `gap_seconds`, `max_attempts`, `lag_ms`, `preparation_ms` | nonnegative bounded integers, max 86,400 seconds / 10 attempts / 3,600,000 ms |
| `model_family`, `chip_family`, `ram_band`, `hardware_support`, `preparation_state`, `thermal_state`, `speaker_failure` | fixed coarse vocabularies defined in backend `reportingContract.ts`; no arbitrary model strings |

Legacy numeric fields such as `attempt` retain their existing compatibility bounds; the new producer contract must still cap recovery attempts.

Hardware snapshots are installation-level, consent-gated and content-free; no meeting/attempt ID or private flag. New per-recording speaker/lag fields are suppressed for private recordings. Keep only the latest accepted hardware snapshot, expire it 30 days after observation (not delayed receipt), remove it on installation revocation/account deletion, and label coverage as consenting managed installations. Speaker failure does not trigger a separate reconnect owner or cloud fallback. Shared diagnostic fields do not change incident-email eligibility by themselves; richer outcome classification requires controlled producer evidence first.

## Handoff

Backend acceptance, sanitization and admin representation precede Apple producers. Swift timeline/queue allowlists mirror this vocabulary through the pinned `test-contracts/v1/reporting-v1.json` fixture. The schema, speaker-state/failure producer and Mac hardware producer/latest-snapshot storage/admin view are implemented locally. Separated lifecycle/transcription outcomes are also local; generation-scoped recovery and AI failure context are implemented locally. Linux keeps its existing Deepgram usage and has no new local engine or hardware producer implied by this contract. The [Linux handoff](../../../miniti-linux/docs/recording-reporting-v1.md) tracks this additive contract without adding a producer. Privacy copy and internal App Store disclosure accuracy review precede app distribution; no reviewer outreach is selected.

## Activity projection

Analytics IDs are lowercase installation IDs. Daily numeric aliases are summed, active sets are deduplicated, and digest period unions normalize across dates. `installation_activity` is an additive read-only admin projection with record count, latest-seen platform/version and explicit unknown/conflicting metadata. Raw device/billing rows and global registration/usage/financial counters keep their meaning; they are not migrated or inferred from the projection.


## Recovery and AI context, additive v1

`test-contracts/v1/recovery-v1.json` extends the manifest without changing earlier fixture bytes. `recording_restart_planned`, `recording_connection_restored` and `recording_transcription_resumed` are informational milestones with no automatic incident family. Fixed `recovery_reason` values are connection_error, unexpected_close, transcript_stall, retry_exhausted, manual, capture_gap and unknown. Connection/recovery generations, send attempts/completions, local-ingest attempts and dropped packets are nonnegative integers capped at 99,999,999. `audio_gap_seconds` is capped at 86,400. Attempt UUID and actual transcription engine accompany these milestones. The same contract feeds ingest and Help sanitization.

A planned retry owns its intentional disconnect; an old queued connection state cannot schedule a new failure. Send completions belong to their socket generation and mean only that the local socket send completed, not provider receipt or complete transcription. Local ingest and disconnected drops remain separate. After recovery, a connected socket reports connection restoration; recent requested-source capture plus new nonempty transcript evidence from an eligible generation reports transcription resumed. Quiet capture remains waiting for transcript. Neither milestone proves that earlier audio was recovered. Existing legacy PCM counters remain attempts. No audio buffering/replay or new recovery loop is introduced.

`insights_request_failed` carries task mode, live/final/saved/helper stage, fixed category, HTTP status when observed and an optional random UUID. Each observed managed insights request adds `X-Client-Request-ID`; the backend accepts a UUID only and includes it in existing completion/error telemetry. API response shapes, routing and bounded retry counts are unchanged. A task-local observer keeps concurrent operations separate and rechecks originating account/credential generation before reporting. Managed mode, Share diagnostics and non-private recording are required; cancellation/supersession are informational, other failures warning-level. A successful HTTP status can accompany a decode failure. Missing backend correlation is unknown. Prompts, responses, credentials and raw errors never enter these new fields.

Review corrections (2026-11-03): `409 report_owner_mismatch` and `403 device_disabled` terminate that queued usage report and increment the persisted dropped count. Empty flushes do not rewrite storage; the recording timer requests a flush only for on-device capture or pending reports. `model_access` is an additive fixed AI failure category in `review-370-v1.json`, with prior fixture hashes unchanged. BYOK failures remain excluded from automatic reporting.
