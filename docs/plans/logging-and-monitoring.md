# Logging, diagnostics and actionable incident monitoring

Status: delivered in macOS 3.5.0 build 142 on 2026-10-30; shared backend/site deployed. iOS build 142 confirmed available on 2026-10-31. This is the implementation record, not future build scope. [Release evidence](../releases/3.5.0.md) owns delivery and remaining evidence; [roadmap](../roadmap.md) owns subsequent work.

## Deliverable and boundary

O1–O6: detect one blocked user, deliver diagnostics reliably, report bounded recording/auth outcomes and detect sustained probe/mail/cron blind spots. Includes the initial Deepgram handshake refusal/timeout UI failure. Includes explicit Help reports and a bounded local timeline for auth/Keychain, recording, cloud and purchases. Current operations remain in the runbook.

## Prerequisites and decisions

Existing admin authentication, diagnostics choice, hourly probes and weekly digest remain. Ian confirmed on 2026-10-28: retain the hourly cadence and the proposed thresholds below. Use Ian's existing UptimeRobot account for independent coverage. The release record reports UptimeRobot setup and mail QA through Ian's grouped confirmation; independent monitor configuration/inbox evidence is not attached. The public health bit returned 200 after the 11:45 job on 2026-10-30. Do not infer external monitoring coverage from that response alone. Automatic diagnostics remain authenticated and exclude transcript/audio content. No analytics SDK is added. O5 is a separate explicit, rate-limited support form that must work when sign-in is broken.

## Implementation evidence and remaining gates

See the [QA handoff](../releases/monitoring-cloud-purchase-qa.md) for tested behavior, exact remaining checks and deployment order, and the [local code contract](../reference/monitoring-cloud-purchase.md) for file ownership and compatibility. Implementation is delivered; the release record supersedes earlier local-only status. Ian reported device QA good as a group, not an itemised independently observed run. Preserve those evidence limits and iOS availability separately.

## Implementation contract

## Post-3.4.0 observability follow-up (O1–O4)

**Implementation authorized after 3.4.0; built on 2026-10-29 and deployed on 2026-10-30.** Keep this work in the existing diagnostics/ops pipeline. The roadmap owns priority; this plan owns event schema, retention and feature regressions, using the test-foundation infrastructure where needed. No new monitoring vendor is required for this slice.

### Pre-implementation evidence and limits (2026-10-27)

- Production read-only snapshot: the nine ops checks at **2026-10-27 21:45 UTC** were `ok`; no error-level client events or server errors in the last hour. The Deepgram check at **21:15 UTC** returned handshake 101 and $83.35 balance. Email recipient/transport are configured. The Monday digest records `sent_at` 2026-10-26 07:00:47 UTC with no reported problems; that is server send evidence, not proof someone read it. No refresh/probe/email was triggered for this review.
- A retained 3.3.0 device trace on 2026-10-27 contained 18 `transcript_starvation_detected` **warnings**, including the failed-microphone incident window, and repeated reconnect/recovery events. This is a bounded retained sample, not a complete incident count. `scanClientErrors` reads only `level === 'error'`; `evaluateClientErrors` requires at least 5 errors from at least 2 devices in an hour. That user can remain blocked without an alert, even if all the warnings arrive. Legacy `audio_recovery_healthy` events are not reliable proof of delivered PCM. Correction from shipped-code inspection on 2026-10-30: the strong `recording_recovered` event arrives in 3.5.0, not shipped 3.4.0; the next alert-quality plan owns capability handling.
- Diagnostics are opt-in/out via Share Diagnostics (default on in managed mode); BYOK sends none. `/api/client-events` itself requires working device auth/proof. A broken key or offline device can be unable to report its own failure. A green aggregate check cannot prove all users are healthy.
- Client queue: max 200, 8-second debounce, batches of 25. `AppState.flushClientEvents` copies `pendingClientEvents`, awaits sends, then assigns the old remainder back. An event appended during the await can be overwritten; launch/stop and debounce can also enter separate flushes. This race is identified from code, not a completed failing-test reproduction. Backend assigns a new UUID per receipt, so a lost-response retry is counted again. Recent retention is count-only: 2,000 global / 300 per device; the weekly scanner reads the same rolling list, so it cannot promise a complete week.
- `microphone_capture_failed` has no error-domain/code details and emits only while `isRecording`; audit initial-start failures against that gate. `audio_recovery_degraded`, unknown-key failures, restore/email failures and many insight failures are warnings that the error-only scanner excludes.

### O1: alert on one blocked device using existing events first

Backend-first, compatible with installed clients. Retain the fleet-spike check; add a separate incident check keyed by canonical device id, platform/version and failure family. Do not simply lower every error threshold to one.

- Initial proposed warning threshold: three high-signal failures in distinct ten-second occurrence windows within ten minutes on one device, seen within the scan window. Include `transcript_starvation_detected`, persistent capture/reconnect failure, and repeated `client_auth_key_unavailable` / enrollment / restore failures by an explicit allowlist. One terminal `deepgram_reconnect_exhausted` or persistent-store failure can open an incident immediately when received. Tune against retained traces and false-positive tests before deployment.
- Evaluate on the existing hourly cron initially, so notification latency can be about an hour. A shorter cadence is an explicit follow-up operational decision, not implied by this plan. Offline uploads must be labelled delayed and not represented as a live outage; retain both occurred and received times, validate clock skew, and report scan truncation/insufficient history instead of “no failures”.
- Email one incident summary, repeat at most daily while unresolved, and send one recovery when evidence supports it. Include version/platform, safe error code, first/last occurrence, affected-device count and authenticated admin drill-down. No meeting titles/content, account emails or device names in telemetry or mail. Do not contact a customer automatically.
- Count bounded legacy warning clusters even when old clients emit misleading healthy transitions. Only close an incident with trustworthy, version-aware evidence or mark it “no recent evidence”, not “recovered”. Repeated failures across devices still use the fleet alert. Add affected-device/version breakdown to the digest, including warning-only incidents.
- Tests: anonymized shape of the 3.3.0 starvation trace opens one incident; one transient warning does not; supported recovery closes it once; old healthy events do not erase the incident; dedupe/cooldown, delayed delivery, mixed case device IDs, clock skew, scan truncation, warning-only auth failures and diagnostics-off/no-data states.

### O2: make diagnostics delivery and retention trustworthy

A small client/backend integrity slice before relying on new outcome rates. One flush in flight; acknowledge only event IDs actually accepted, preserving events appended during awaits. Respect consent withdrawal, account/credential changes and queue clear without restoring discarded events. Bound retries with backoff and report dropped/expired counts locally. Keep queueing independent of successful auth so failures can be sent after recovery; do not weaken proof requirements to upload them immediately.

Add a stable event ID generated once by the client, persisted with the event, and idempotent server ingestion for that ID under its device. Old clients without IDs remain accepted; mark their counts approximate. Enforce event-name/detail-key allowlists server-side, not just string lengths. Use time-based retention: 14–30 days for detailed events and up to 90 days for aggregates; capacity limits must expose incompleteness. Aggregate incident/version counts at ingestion so info-event floods do not erase the evidence before the hourly scan. Do not print raw errors, tokens, recovery/license keys, meeting IDs/titles, email addresses, device names or audio/transcripts as new details.

Tests: suspend a real flush, enqueue another event, complete the send and verify the new event persists; simultaneous launch/stop/debounce; lost response/retry counted once; consent withdrawn or account switched mid-flush; offline/relaunch; unknown payload redaction; retention/cap truncation. Coordinate the additive event-ID contract with Linux.

### O3: record outcomes, and make stalled starts end visibly

Use one bounded recording-attempt/incident ID and coarse, content-free counters. Report attempt, ready or failed, degraded/recovered and final outcome, rather than periodic heartbeats. Include app **build** and OS version, route (local/managed/BYOK as locally applicable), requested sources, converted-buffer presence per source, whether PCM was sent, whether speech activity was detected, whether a transcript arrived, sanitized error domain/code and recovery action. Raw Bluetooth/device names are not needed. BYOK/diagnostics-off reporting stays off; local error UI still works.

- Distinguish “socket connected but no PCM” from “speech/PCM sent but no transcript”, ordinary silence, user cancel and an intentional stop. Never alert just because a silent meeting has no words. Timeouts must be tied to observed capture/connection progress, not words alone.
- Close the already-open Deepgram pre-handshake refusal gap: handle the initial task completion/HTTP refusal and a bounded connection timeout, transition out of connecting, give useful retry/configuration/network copy and emit one classified failure. A stale connection callback must not affect a new recording. Add fixtures for pre-connect 401/402/429/5xx, timeout, cancel, reconnect and healthy silence.
- Auth: pair repair attempts with succeeded/failed/stale outcomes and a safe reason/code; unknown macOS key codes should be diagnosable without assuming every failure is a migrated key. Count unsuccessful repairs and restore/email outcomes by stage, plus rates only when the matching attempted-operation denominator exists. Do not add codes to the destructive-repair allowlist based on a single telemetry sample.
- Health reporting: show attempts, success/failure/degraded counts by platform/version/build and diagnostic coverage. “No reports” is not “100% success”. Long sessions or crashes without a final event remain incomplete, not automatically successful or billed by telemetry. Minutes accounting stays in B2.

### O4: narrow probe and alert-delivery blind spots

- Repeated `unknown` provider checks need an alert after a sustained window (proposed three consecutive hourly unknowns), while a one-off network blip stays quiet. Use an independent dead-man check for missing ops/digest heartbeats and a mail-path test; a cron cannot reliably alert that it never ran, and a failed mail provider cannot deliver its own warning. Record configuration/owner before claiming this exists.
- The current OpenAI probe tests `gpt-5-mini-2025-08-07` only; add bounded coverage for the other shipped managed model or correlate real request failures by model. Keep costs tiny and use synthetic input.
- Correct the live `polar_config` success wording: product ID shape validation and an organisation-filtered read do not prove the product's ownership or successful activation. Keep the probe read-only; existing restore outcomes remain the evidence for actual restores.
- Test alert delivery failure, sustained unknown, missing heartbeat, unsupported model and recovery without weakening current provider-refusal alerts. Preserve no-activation probes and the existing diagnostic privacy/opt-out rules.

**Acceptance:** replay a synthetic Charlie-shaped failure through ingestion → incident evaluation → the test mail sink and prove one actionable alert without needing a second device. Then demonstrate a recovery and a delayed/offline case. Verify in a controlled production smoke test only after explicit authorization to send that test alert. Monitor state must distinguish healthy, incident, stale and no-data. The local implementation and synthetic acceptance evidence are recorded below. Production delivery remains unverified.

## Acceptance and delivery

Synthetic Charlie-shaped event ingestion → incident detection → test mail sink must alert for one device, deduplicate and recover. Cover offline/delayed delivery, opt-out, account changes, queue arrivals during awaits, lost-response replay, sustained unknown, missing heartbeat and provider-model failures. O1 can deploy first using existing events; O2 must precede reliance on O3 denominators. Deliver all four within the chosen release scope, or explicitly split before implementation.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

Rollback: independently disable new alert policies/counters while retaining existing probes and bounded diagnostics. Queue schema changes must preserve unsent events safely. A production test email requires explicit authorization; unit sinks do not. [Current operations](../runbooks/operations.md).

Implementation choice: ten-second windows prevent several diagnostic layers for one fault from meeting the three-failure threshold. Legacy reports remain approximate. Signal events have their own bounded list, so informational events cannot evict all incident evidence. Daily aggregates count version/build/outcome groups; they are not a complete fleet or billing denominator. `OPS_CLIENT_INCIDENTS=off` disables the new incident evaluator independently; the existing fleet/provider checks continue. Counter rollback requires reverting ingestion while preserving the additive event receipts and unsent client queue.

## O5: explicit Help reports (Ian, 2026-10-29)

Delivered in 3.5.0. Help replaces the Account support-details disclosure, shows the details expanded and provides Copy all, Preview, an optional reply address and an explicit Send report. Include diagnostic log defaults on but exports the fixed sanitized fields described in O6; raw debug messages are excluded. The user-written description is included as entered. No automatic telemetry preference is changed.

`POST /api/support/report` sends through the existing Resend helper to server-only `SUPPORT_EMAIL`, falling back to `ALERT_EMAIL`. The app contains no recipient address. The public route supports broken credentials and BYOK: reported IDs/reply address are unverified, grant no account authority and never choose the recipient. Body limit 64 KiB; description 4,000 UTF-16 units, whitelisted detail keys, 100 strictly shaped diagnostic events. Three reports per network/hour and 100 total/day; storage/configuration failure fails closed. Resend idempotency uses report UUID plus content hash (provider's 24-hour dedupe window); retries keep the same report until edited/refreshed. No support content is stored in KV or server logs; delivery failures enter normal 5xx monitoring with static copy. Email is the report store.

Acceptance: verify local copy/preview with diagnostics checked/unchecked, no raw strings in the log, signed-out/BYOK path, bad/oversize input, rate limits, lost-response retry, provider failure and matching receipts. Deploy the endpoint with the existing Resend configuration and verify one approved synthetic report reaches the configured inbox before claiming delivery. No real test mail or deployment has been performed. iPhone/iPad/accessibility review remains in the QA handoff.

## O6: useful bounded local diagnostics (2026-10-29)

Delivered in the 3.5.0 client. `DiagnosticTimeline` in `DebugLogger.swift` observes existing operations: Keychain read/write/fallback outcomes; credential load, key load/sign failure and repair, refresh and server refusal; recording attempt, first PCM/transcript and connection/recovery milestones; cloud choices, queued/uploaded/removed outcomes and pauses; purchase return, pending/confirmed/refused outcomes. No new auth checks, network requests, Keychain reads, signing probes, repairs or recording decisions are introduced. Error domains/codes and operation metadata use fixed vocabularies. Never store keys, tokens, content, titles, paths, addresses, checkout/meeting identifiers or arbitrary server bodies. Operation UUIDs are freshly generated diagnostic IDs.

The utility queue owns a 300-event, 96 KiB, 48-hour local file with owner-only permissions and backup exclusion. Writes batch at two seconds. At most 64 records can await processing; admission loss and storage failure are visible in snapshots. Equal events within 60 seconds of the previous occurrence fold into first/last/count, even across interleaved events. No audio-buffer/word logging; audio milestones use the existing main-actor sampler. Background cloud polling/autosaves do not add empty-pass events. A simulated hour with 3,600 repeated network failures retains one counted failure and the successful milestones. A crash may lose the last two seconds; this is diagnostic evidence, not an audit or billing ledger.

Help includes up to 100 events and a 32,000-byte encoded event budget, retaining successful milestones and full fixed fields. It retains the legacy safe category/code fallback for uninstrumented errors in the last 15 minutes. Preview/Copy/Send share this snapshot, and opening Help sends nothing. Debug Copy/Save includes the retained timeline; Clear removes it. Automatic telemetry consent and its existing delivery queue remain unchanged. The new optional `fields`, `count` and `last_time` support-event fields require the additive backend parser before this client ships; old report shapes remain accepted. Linux parity is tracked, not implemented.

Validation: tests cover redaction/unknown metadata, status=-34018 extraction, the hour-long retry case, count/byte/age limits, persistence/relaunch/clear, corrupt/oversized files, unavailable storage, successful milestones in reports, backend strict validation and mail formatting. Final combined-tree results: macOS 1,067 executed / 4 skipped, iOS 1,005 executed / 3 skipped, zero failures; backend 655 passed / 5 skipped with typecheck/lint clean. See the QA handoff for log locations. Real inbox, device and monitoring QA gates from O1–O5 remain open; no deployment or test mail is implied.

### O5 Home feedback and submission limits (2026-10-29)

Home has a bottom-right Feedback control on Mac and iPhone/iPad. Its small sheet accepts any message (4,000 UTF-16 units) and optional reply email; it sends only these plus app version/platform. No account IDs or diagnostic log are attached. It shares the Help endpoint and server-only recipient, with `kind: feedback` selecting a fixed email subject. No request occurs until Send; failure retains the text and ID for an idempotent retry. Help retains its optional diagnostics and full support details.

Both forms share a single in-flight client gate, a 30-second cooldown after confirmed success, and the server's Retry-After on 429. Server admission adds one request per 30-second fixed network window before the existing three/hour network and 100/day global limits; fixed windows can allow two requests around a boundary. Limits are shared across Help and Feedback, fail closed, and are not authenticated device identity. Server configuration/inbox delivery remains a deployment QA gate.

## Post-release follow-up

The first deployed scan alerted on retained 3.4.0 events. [Incident alert clarity](incident-alert-clarity.md) owns the next-release correction, including legacy recovery capability and event-count wording. Backend `2458ddb` already fixed alert links through dashboard login. Do not reopen O1–O6 or classify that deployed fix as outstanding.
