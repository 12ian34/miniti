# Monitoring, cloud privacy and purchase return: implementation contract

Built 2026-10-29 and delivered 2026-10-30: macOS 3.5.0 live, backend/site deployed, iOS confirmed available on 2026-10-31. [Release evidence](../releases/3.5.0.md) owns platform availability and QA limits. [QA and delivery gates](../releases/monitoring-cloud-purchase-qa.md). Existing 3.4.0 contracts and account ownership remain unchanged.

## Diagnostics and incidents

`DiagnosticsQueue.swift` is a bounded durable outbox owned by AppState: 200 events, 14-day client expiry, stable UUID IDs, one flush, 25-event batches, 15-second to one-hour retry backoff. Receipts remove only acknowledged IDs from the current queue. Account changes, opt-out and BYOK clear queued events and invalidate completions. Old array storage is retained for rollback; additive metadata holds ownership/backoff/drop counts. Local debug logging reports retention loss without content. XCTest never flushes production diagnostics.

`/api/client-events` accepts additive `event_id`; returns `accepted`, `accepted_ids` and `rejected_ids`. Invalid/unknown events with valid IDs receive a rejection receipt so they cannot jam the queue. Old clients remain accepted with approximate counts. New clients accept a legacy receipt only if the entire batch was accepted. Proof/auth is unchanged. Details and event names are allowlisted server-side; meeting IDs, raw errors, titles, names, addresses and content are stripped.

`clientDiagnostics.ts` uses one Lua ingestion script for ID deduplication, details and daily aggregates. Detailed events and dedupe keys expire after 30 days; aggregates after 90. Caps: 2,000 global, 300/device, 10,000 separate signal events, 2,000 daily aggregate fields plus overflow. Counts expose capacity loss and legacy approximation. Redis integration executes the actual script, not just the JS fixture.

`clientIncidents.ts` adds an hourly single-device check beside the fleet check. Three high-signal failures in distinct ten-second windows within ten minutes, or one terminal event, opens an incident. One mail, at most daily repeat, one evidence-backed recovery. Legacy healthy transitions cannot close it. Missing evidence becomes no-recent-evidence; delayed reports/clock skew/capacity are labelled. Mail has platform/version, safe error codes, timestamps and authenticated drill-down only. Maximum 20 sends/pass, 1,000 retained incidents; exhausted limits are visible. The hourly claim has no unsafe lease unlock. `OPS_CLIENT_INCIDENTS=off` disables this new evaluator without disabling existing probes.

`RecordingDiagnosticAttempt` and AppState emit attempt, ready, degradation/recovery and final outcomes with coarse per-source PCM/speech/transcript flags and build/OS. Recording readiness is not inferred from words, and final events are not guaranteed after a crash. ClientAuth pairs repair attempts/outcomes without changing credential authority. `DeepgramService` now handles pre-handshake completion/refusal and a 12-second initial timeout, fenced to the task and generation; stale callbacks cannot fail a newer socket.

The original 3.5.0 ops check covered two OpenAI models. The deployed 3.6.0 configuration probes three with Luna enabled; local 3.7.0 retires GPT-5 mini and probes Luna plus GPT-5.4 mini only. See the [operations runbook](../runbooks/operations.md#active-model-probes-2026-11-01). Three consecutive hourly unknown provider checks warn; forced checks in one hour do not advance the streak. Polar success copy describes only the actual read/shape checks. Digest includes incident/version and aggregate outcomes; unavailable aggregates do not suppress the rest of the digest.

`GET /api/health/monitoring` returns only 200 `{status:"ok"}` or 503 `{status:"unavailable"}`, no-store. It reads stored job/check ages, incident mail failures, Resend state and last digest provider acceptance. It does not run probes, send mail or disclose diagnostics. It detects a stopped job or unavailable alert path; it cannot prove inbox receipt, or that every user is healthy.

## Cloud privacy

`CloudExclusionPolicy` and the common `startNewMeeting` path apply local title rules/private mode before any save. There is no manual Home/pre-recording checkbox after Ian's 2026-10-29 UX review. Live and saved meeting toolbars share `MeetingCloudStorageButton`: blue Cloud or crossed-out-cloud Local, with a brief confirmation overlay. Choosing Local during a new recording precedes first upload eligibility. A running private recording stays Local; existing uploaded copies require acknowledged deletion.

The per-meeting explicit choice wins over late calendar association. Without an override, late association can only add a sticky exclusion. Rules do not filter the calendar or change transcription, AI or exports. Watch/imports are outside the rule scope. Add rule opens a focused editor with explicit empty/duplicate/length/cap validation. The seven-day preview is fenced to the current account. History and saved detail show pending/error removal, not a claim of completed cloud deletion. A delayed first upload queues removal at the acknowledged revision while retaining the original locally.

`Meeting.cloudRestoreRequested` is a local defaulted SwiftData property, never part of the sync document. Only explicit Put on the cloud sets it. The upload envelope adds signed `restore_deleted: true`; backend restores only under the same account, exact base revision and existing transcript guard. Ordinary uploads cannot resurrect tombstones. Pull/reconcile preserve a pending restore; a fresh exclusion cancels it. No SQL migration is required. Deploy backend before the client. The production SQL has passed in local PostgreSQL (PGlite); Neon transport tests remain separate.

## Purchase return

`/api/subscribe` captures authenticated installation/account when checkout starts, puts the account into Polar metadata and stores a seven-day `checkout:return:{id}` attribution. Polar uses a fixed HTTPS success URL with `{CHECKOUT_ID}`. `PURCHASE_RETURN_ENABLED=off` removes the new return URL for new checkouts; existing receipts and license restore continue.

`GET /api/subscribe/status?checkout_id=UUID` requires the purchasing installation and captured account before reading Polar, is rate limited, no-store, and returns only pending/ready/failed/expired. Ready requires Polar succeeded and the exact subscription granting this device Pro. Confirmed is not paid. No license activation or account transfer occurs. B1 still owns subscription ownership migration.

`minitidotapp/purchase/complete/` strips the query before analytics and keeps the ID in a JS closure, not an autocaptured link. An explicit button opens `miniti-billing://return?checkout_id=UUID` on macOS. Linux/unknown/old-app visitors retain receipt/license instructions. No automatic launch and no payment claim on the page.

`PurchaseReturnController` validates the callback, coalesces duplicates, opens Account, checks for at most 30 seconds and respects retry throttling. Account plus credential generation fence each response and the usage refresh. A callback never grants Pro itself. AppDelegate queues a cold-launch callback until AppState exists. iOS StoreKit is unchanged.

## Explicit support reports (O5, shipped in 3.5.0)

`HelpSettingsView.swift` is shared by both app targets: expanded support metadata, optional reply/description, Preview and Copy all, with default-on sanitized diagnostic inclusion (O6 below). It combines the structured local timeline with a bounded legacy code-only fallback, discards raw messages, limits recent events, and uses an unauthenticated explicit-send transport so broken sign-in can still be reported. No request runs on merely viewing/copying. Failures retain the form; a matching server receipt is required for success.

The additive backend route `/api/support/report` uses `lib/supportReports.ts` and existing Resend mail. Server-only `SUPPORT_EMAIL` falls back to `ALERT_EMAIL`; reported IDs are unverified. Strict body/schema limits, network/global limits and provider idempotency bound abuse/retries. No report content in server logs/KV; failures use static 5xx reporting. See the logging plan O5 and backend `docs/agents/09-followups.md` for deployment and delivery gates.

## Local support timeline (O6, delivered in 3.5.0)

`DiagnosticTimeline` lives beside the raw in-memory logger in `DebugLogger.swift`. Its fixed `Code` enum and `sanitize` vocabulary are mirrored by `miniti-api/lib/supportReports.ts`; change both together. Only fixed fields are persisted/exported. Raw logger redaction is not a privacy boundary for Help. Structured events are observed locally even when automatic telemetry is off; explicit Help sending is still a separate user action. Auth hooks run after observed results; storage and formatting run on a utility queue with bounded admission, never on audio callbacks. Keychain hooks enqueue metadata only and never call back into auth or acquire credential locks.

Retention is 300 events / 96 KiB / 48 hours, 64 pending records, two-second batched atomic writes, mode 0600 and excluded from backup. Repeated equal code/fields fold into a count while occurrences remain less than 60 seconds apart. Milestones are emitted once through the existing recording sampler; background cloud passes only report real work/failures. Diagnostic write failure leaves functionality intact and is visible in Help. Help retains up to 100 entries within its encoded budget, including first/last/count and safe operation fields; Debug Copy/Save appends the timeline and Clear removes it. XCTest uses an in-memory singleton, never the user's persisted timeline. No new network requests or changes to automatic-diagnostics consent.

Released 3.6.0 sync/delivery changes are described in [patterns](patterns.md#saved-ai-and-webhook-delivery-local-360-not-released) and [cloud sync](cloud-sync.md#local-360-implementation-not-released). The webhook outbox is distinct from the diagnostic outbox above: its held completion marker, immutable delivery identities and current-data resend do not change diagnostics consent, retention or the support schema. They shipped on Mac on 2026-10-31 and iOS on 2026-11-01.

Delivered 3.6.0 follow-through is recorded in separate plans: [sync/delivery](../plans/sync-and-delivery-reliability.md) and [incident alert clarity](../plans/incident-alert-clarity.md). Backend `2458ddb` already routes alert links through dashboard login with the device filter retained.
