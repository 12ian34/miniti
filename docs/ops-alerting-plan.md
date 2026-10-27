# Operator alerting plan: what emails Ian, when, and why

> Started 2026-10-23 after the Deepgram credit outage (2026-10-20 19:18 to 2026-10-22 20:50 UTC): the backend looked healthy the whole time, the apps sat on "recovering audio", and the first alert was a customer threatening to cancel. The Deepgram check went in on 2026-10-22 ([admin-stats-access-plan.md](admin-stats-access-plan.md) status table). This doc covers the rest: what else should page, what is only worth a weekly line, and what is deliberately not built. Everything lives in `miniti-api`; nothing here touches the apps.

## Status

| Step | Status | Notes |
|---|---|---|
| Deepgram balance and handshake, hourly, email | **Deployed 2026-10-22** | `GET /api/cron/deepgram-health` at :15, `lib/deepgramHealth.ts`. `low` under `DEEPGRAM_BALANCE_ALERT_USD` (25) daily, `critical` on a refused handshake every 6 h, one recovery mail. Details in the admin-stats plan |
| Hourly ops check: client error spikes, server errors, OpenAI, Resend, Neon, KV, cron heartbeats, spend | **Deployed 2026-10-22 23:25 UTC** (commit ced379d on `miniti-api` main, auto deploy) | `GET /api/cron/ops-health` at :45, `lib/opsHealth.ts`, state per check in KV `ops:alert:{name}`, same email policy as Deepgram (`warn` daily, `critical` every 6 h, one recovery; spend weekly / every 3 days). 20 tests |
| Server error recording | **Deployed 2026-10-22 23:25 UTC** | `lib/opsStore.ts`: every 5xx built with `errorResponse` and every uncaught route error (`instrumentation.ts`, Next's `onRequestError`) lands in KV `ops:server_errors:recent` (code, fixed message, path without query, method; nothing from the body). Before this, a 500 was a Vercel log line nobody read |
| Weekly digest, Monday 07:00 UTC | **Deployed 2026-10-22 23:25 UTC**, first digest sent 23:29 UTC | `GET /api/cron/weekly-digest`, `lib/opsDigest.ts`: money (ledger, MRR, spend against budgets with a month-end projection), usage this week against last, health (Deepgram, providers, client and server errors, cron ages), every alert mail of the week, and any source that could not be read. 4 tests. No digest on a Monday is itself the signal that the crons are dead |
| Admin route and terminal | **Deployed 2026-10-22 23:25 UTC** | `GET /api/admin/ops-health` (`?refresh=1`, `?check=name`, `?digest=1`), `scripts/admin-stats.mjs ops` and `digest`, an `alerts` block in `summary`, the curl cookbook section for Grok Bot |
| Budgets in Vercel Production | **Set 2026-10-23** | `OPS_BUDGET_OPENAI_USD=150`, `OPS_BUDGET_DEEPGRAM_USD=120`, `OPS_BUDGET_ALL_IN_USD=350`, from October's pace (OpenAI about $105 a month, Deepgram about $80, all in about $280). Raise them as usage grows; the digest shows the percentage every week |
| First run of every cron after deploy | **Done 2026-10-22 23:28 UTC** | All four answered 200; every check `ok`, Deepgram `ok` ($99.96, handshake 101), all four crons registered. Order matters: the ops check ran before the digest, so its `cron` check warned "weekly-digest has never run" and emailed, and a second run emailed the recovery. Next time run `weekly-digest` first |
| Vercel console notifications | owed, Ian's hands | Deployment failed and domain expiry notifications in the Vercel team settings. Not reachable from the API |
| Deepgram auto-recharge or overage | not now, Ian's decision 2026-10-23 | The only thing that stops a refused handshake rather than reporting it. Console setting, revisit when the balance alert has proven itself |
| Polar license-key path: `polarConfigId` trims whitespace, handles the known trailing literal backslash-n, then UUID-validates organisation/product IDs. Hourly `polar_config` uses an authenticated subscriptions-list read filtered by organisation, plus a narrow unknown-key validate probe; it never activates. Product ID is shape-checked only, not read or ownership-verified. A 403 on the subscriptions read warns about scope; 401/404/422 are configuration refusals. After a successful read, any `provider_config` restore outcome in the last 7 days is critical; three or more `provider_unavailable` outcomes warn. Earlier probe failures have their own returns. The digest includes Polar and 7-day restore outcomes by code | **built through `3512172`, deployment reported by Ian 2026-10-26**; no live verification performed by this docs update | Discovered after the migration incident: a malformed organisation value caused activations to fail. A green check does not prove activation works or that the product belongs to the token. The current success summary overstates product validation; correct that wording in the next backend maintenance update |
| App: a refused Deepgram handshake shows an error and sends a diagnostic | open, not started | `DeepgramService` stays on `.connecting` forever after a 4xx at the upgrade (no `didCompleteWithError`, the receive failure returns early when never connected), so the app shows "recovering audio" and sends nothing. Until this ships, the client error check cannot see this exact failure; the Deepgram probe can. The Linux client likely shares the hang |

## Why nothing alerted

Three gaps, each closed differently:

1. **The failure happened off our infrastructure.** The app asks `/api/session` for a token (200), then opens the socket straight to Deepgram (402). Vercel saw nothing. Only a probe that makes the same handshake can see this, hence `deepgram-health`.
2. **The app did not report it.** A refused handshake never reaches the reconnect path, so no `deepgram_reconnect_exhausted` diagnostic. The client error check is blind to this case until the app fix ships; it is still the right check for everything the apps do report (insights failures, auth enrollment, audio recovery).
3. **Nothing read what was recorded.** Client diagnostics have been stored since 2.9.0 and only ever read by hand with `admin-stats.mjs events`. The hourly check reads them now.

## Design

### One policy for every check

A check produces a level: `ok`, `warn`, `critical` or `unknown`, plus a one-line summary and a few detail lines. The runner keeps the previous state in KV and emails on the same rule as the Deepgram check: a new `warn` or `critical` at once, `critical` again every 6 hours, `warn` every 24 hours, one recovery mail on the first `ok` after an alert. `unknown` is logged, shown by the admin route and never emailed. Spend repeats slower (3 and 7 days) because it only ever goes up during a month.

`unknown` matters: the false critical of 2026-10-22 came from treating any non-101 as a refusal. Now only the provider's own refusal pages (a 401/403 on the key, a 429 `insufficient_quota`, a 400/404 on the pinned model, a failed Neon query, a KV write that does not read back). A network failure, a timeout or a 5xx is `unknown`: it may be Vercel, the probe or a blip, and an hourly probe that pages on blips trains Ian to ignore it.

### Thresholds

| Check | Warns when | Why that line |
|---|---|---|
| `client_errors` | at least 5 error-level diagnostics in the hour from at least 2 devices | Existing fleet-spike policy; a single blocked user can be missed. Proposed O1 below adds a separate incident check |
| `server_errors` | at least 5 recorded 5xx or uncaught errors in the hour | Baseline is zero most hours; 5 avoids paging on a single retried request |
| `openai`, `resend`, `neon`, `kv` | `critical` on the provider's refusal, `warn` on rate limiting | See above |
| `cron` | `deepgram-health` older than 3 h, `cloud-maintenance` 26 h, `weekly-digest` 8 days, or never ran | Schedule plus one missed run. The ops cron does not judge itself; the Monday digest does |
| `spend` | 80 percent of a budget (`warn`), 100 percent (`critical`) | Budgets in env, read once a day because the ledger fans out to every provider |

All five numbers are env overrides (`OPS_CLIENT_ERROR_COUNT`, `OPS_CLIENT_ERROR_DEVICES`, `OPS_SERVER_ERROR_COUNT`, `OPS_BUDGET_*`), documented in `miniti-api/docs/agents/02-environment.md`.

### What the probes cost

OpenAI: one 16-token completion on `gpt-5-mini-2025-08-07` per hour, well under a cent a month. Resend: a domain list, free. Neon: `select 1` over the HTTP driver. KV: one write with a 10 minute TTL and one read. Deepgram: one handshake closed on 101, not billed. The ledger read behind the spend check is the expensive one (five providers), so it runs once a day and is reused by the other 23 runs.

### What is deliberately not built

- **An error tracker (Sentry and the like) in the apps.** The diagnostics pipeline already carries name, category, level, version, platform and a details map; what was missing was a reader, not a collector.
- **Log drains and Vercel's paid observability alerting.** Backend 5xx are rare, the in-process record catches them, and the hourly check reads it. Revisit if the count stops being near zero.
- **Alerts on Polar or Apple webhooks.** They have retries and dashboards of their own, and a missed one shows up in the devices report; the digest's MRR line is the weekly check.
- **Slack or push.** Email is what Ian reads and what Resend already sends; one channel, one address.

## Manual checks owed

- [x] After the deploy: each cron once with `CRON_SECRET`; `admin-stats.mjs summary` prints `8 checks … all ok` and `weekly digest: last sent 2026-10-22 23:29 UTC` (2026-10-22).
- [x] Server evidence checked 2026-10-27: the scheduled 2026-10-26 digest records sent_at 07:00:47 UTC, no reported problems. Inbox receipt/read was not independently checked.
- [ ] Vercel team settings: deployment failed notifications on (Ian).
- [ ] When the app fix ships: break a handshake on purpose (wrong key in a test build) and confirm both the diagnostic and, with a second device, the client error mail.


## Post-3.4.0 observability follow-up (O1–O4)

**Status: proposed 2026-10-27 after the release, not implemented or scheduled.** Keep this work in the existing diagnostics/ops pipeline. The roadmap owns priority; P1.4 owns the shared event schema/retention contract and P0.12 supplies tests. No new monitoring vendor is required for this slice.

### Evidence and current limits

- Production read-only snapshot: the nine ops checks at **2026-10-27 21:45 UTC** were `ok`; no error-level client events or server errors in the last hour. The Deepgram check at **21:15 UTC** returned handshake 101 and $83.35 balance. Email recipient/transport are configured. The Monday digest records `sent_at` 2026-10-26 07:00:47 UTC with no reported problems; that is server send evidence, not proof someone read it. No refresh/probe/email was triggered for this review.
- A retained 3.3.0 device trace on 2026-10-27 contained 18 `transcript_starvation_detected` **warnings**, including the failed-microphone incident window, and repeated reconnect/recovery events. This is a bounded retained sample, not a complete incident count. `scanClientErrors` reads only `level === 'error'`; `evaluateClientErrors` requires at least 5 errors from at least 2 devices in an hour. That user can remain blocked without an alert, even if all the warnings arrive. The 3.3.0 `audio_recovery_healthy` events are not reliable proof of delivered PCM, which 3.4.0 specifically fixes.
- Diagnostics are opt-in/out via Share Diagnostics (default on in managed mode); BYOK sends none. `/api/client-events` itself requires working device auth/proof. A broken key or offline device can be unable to report its own failure. A green aggregate check cannot prove all users are healthy.
- Client queue: max 200, 8-second debounce, batches of 25. `AppState.flushClientEvents` copies `pendingClientEvents`, awaits sends, then assigns the old remainder back. An event appended during the await can be overwritten; launch/stop and debounce can also enter separate flushes. This race is identified from code, not a completed failing-test reproduction. Backend assigns a new UUID per receipt, so a lost-response retry is counted again. Recent retention is count-only: 2,000 global / 300 per device; the weekly scanner reads the same rolling list, so it cannot promise a complete week.
- `microphone_capture_failed` has no error-domain/code details and emits only while `isRecording`; audit initial-start failures against that gate. `audio_recovery_degraded`, unknown-key failures, restore/email failures and many insight failures are warnings that the error-only scanner excludes.

### O1: alert on one blocked device using existing events first

Backend-first, compatible with installed clients. Retain the fleet-spike check; add a separate incident check keyed by canonical device id, platform/version and failure family. Do not simply lower every error threshold to one.

- Initial proposed warning threshold: three high-signal failures in ten minutes on one device, seen within the scan window. Include `transcript_starvation_detected`, persistent capture/reconnect failure, and repeated `client_auth_key_unavailable` / enrollment / restore failures by an explicit allowlist. One terminal `deepgram_reconnect_exhausted` or persistent-store failure can open an incident immediately when received. Tune against retained traces and false-positive tests before deployment.
- Evaluate on the existing hourly cron initially, so notification latency can be about an hour. A shorter cadence is an explicit follow-up operational decision, not implied by this plan. Offline uploads must be labelled delayed and not represented as a live outage; retain both occurred and received times, validate clock skew, and report scan truncation/insufficient history instead of “no failures”.
- Email one incident summary, repeat at most daily while unresolved, and send one recovery when evidence supports it. Include version/platform, safe error code, first/last occurrence, affected-device count and authenticated admin drill-down. No meeting titles/content, account emails or device names in telemetry or mail. Do not contact a customer automatically.
- Count bounded legacy warning clusters even when old clients emit misleading healthy transitions. Only close an incident with trustworthy, version-aware evidence or mark it “no recent evidence”, not “recovered”. Repeated failures across devices still use the fleet alert. Add affected-device/version breakdown to the digest, including warning-only incidents.
- Tests: anonymized shape of the 3.3.0 starvation trace opens one incident; one transient warning does not; supported recovery closes it once; old healthy events do not erase the incident; dedupe/cooldown, delayed delivery, mixed case device IDs, clock skew, scan truncation, warning-only auth failures and diagnostics-off/no-data states.

### O2: make diagnostics delivery and retention trustworthy

A small client/backend integrity slice before relying on new outcome rates. One flush in flight; acknowledge only event IDs actually accepted, preserving events appended during awaits. Respect consent withdrawal, account/credential changes and queue clear without restoring discarded events. Bound retries with backoff and report dropped/expired counts locally. Keep queueing independent of successful auth so failures can be sent after recovery; do not weaken proof requirements to upload them immediately.

Add a stable event ID generated once by the client, persisted with the event, and idempotent server ingestion for that ID under its device. Old clients without IDs remain accepted; mark their counts approximate. Enforce event-name/detail-key allowlists server-side, not just string lengths. Follow P1.4's time-based retention (14–30 days detailed events, up to 90 days aggregates); capacity limits must expose incompleteness. Aggregate incident/version counts at ingestion so info-event floods do not erase the evidence before the hourly scan. Do not print raw errors, tokens, recovery/license keys, meeting IDs/titles, email addresses, device names or audio/transcripts as new details.

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

**Acceptance:** replay a synthetic Charlie-shaped failure through ingestion → incident evaluation → the test mail sink and prove one actionable alert without needing a second device. Then demonstrate a recovery and a delayed/offline case. Verify in a controlled production smoke test only after explicit authorization to send that test alert. Monitor state must distinguish healthy, incident, stale and no-data. These are proposed follow-ups; none was built by this documentation reconciliation.
