# Operations, diagnostics and support

Current deployed behavior reconciled 2026-10-30 after 3.5.0. [Logging and monitoring](../plans/logging-and-monitoring.md) is the delivered implementation record; [incident alert clarity](../plans/incident-alert-clarity.md) owns the next correction. Backend [runbook](../../../miniti-api/docs/agents/05-runbook.md) and [environment contract](../../../miniti-api/docs/agents/02-environment.md) own command/config details.

## Read health without triggering checks or mail

From `miniti-api`, use `node scripts/admin-stats.mjs summary`, `ops`, `deepgram`, `digest`, or `events` with the documented filters. The [admin-stats cookbook](../../../miniti-api/scripts/admin-stats-curl.md) is the read-only HTTP equivalent. Prefer stored state for inspection; refresh options run probes and can send alert/recovery mail. Do not print .env, cookies or tokens.

Auth: ADMIN_READ_TOKEN is read-only for GET admin routes. The script can instead use a session cookie obtained with the server-only admin secret. Mutations require a session and appropriate Origin; never give the bot the mutation secret. Token rotation takes effect on deployment. There is no requirement to build an admin MCP.

## What currently alerts

| Check | Schedule / rule |
|---|---|
| Deepgram | Hourly at :15. Read balance and make a real listen handshake with a granted token; close on 101 without audio. Low below configured balance threshold (default $25); provider refusal critical. Grant 200 alone does not prove listening works. |
| Ops | Hourly at :45. Client/server error counts, OpenAI, Resend, Neon, KV, Polar config, cron ages and spend. |
| Fleet client errors | At least 5 error-level events from at least 2 devices in an hour; supplemented by the single-device evaluator below. |
| Single-device incidents | Hourly: three qualifying events in distinct ten-second windows within ten minutes, or a terminal event. Legacy recovery can remain unconfirmed; retained historical incidents can alert on rollout. Counts are events, not failed meetings. |
| Server errors | At least 5 recorded 5xx/uncaught route errors in an hour. Content-free fixed details. |
| Providers | Explicit provider refusal is critical; rate limiting warns. Network/5xx is unknown; three consecutive hourly unknown checks warn. Repeated manual checks in one hour do not advance that streak. |
| Spend | Warn at 80%, critical at 100% of configured budgets; values are operational settings, not permanent product costs. |
| Digest | Monday 07:00 UTC. Money, usage, provider/cron health, alerts and restore outcomes. A missing digest requires investigation; it is not an independent dead-man monitor. |

New warn/critical emails immediately on a check run; repeat critical every 6 hours, warning daily, one recovery. Spend repeats slower. There can be almost an hour before an incident is evaluated. Resend failure can prevent its own alert. The deployed public `/api/health/monitoring` exposes stale job/probe/mail evidence for external monitoring. UptimeRobot setup is user-reported in the release record; independently verify the monitor/contact before relying on coverage. HTTP 200 is not inbox proof.

Polar config trims/validates known malformed UUID-shaped env input, reads subscriptions with an organization filter and uses a narrow unknown-key validation probe; never activates a license. Product ID shape is checked, not ownership or successful activation. The success wording now distinguishes organization-filter acceptance from product-ID format validation. Restore outcomes supply actual restore evidence: any provider_config in 7 days makes the check critical after successful probe reads; three provider_unavailable outcomes warn. A green check is not an end-to-end purchase/restore test.

## Investigating a user who says “listening, nothing happens”

1. Identify app version/build, OS, device and time range from support details or existing diagnostics. Do not infer account ownership from a name/IP.
2. Inspect stored provider health and client events together. Separate mic/source failure, no converted PCM, pre-connect refusal, connected-but-no-transcript and auth/grant failure. A successful `/api/session` does not prove the client reached Deepgram.
3. Read warnings as well as errors and retain the event timestamp/version. Repeated recoveries are evidence of degradation, not necessarily successful recording. Ordinary silence is not transcript failure.
4. If no events exist, inspect diagnostic choice, queue/auth connectivity and retention coverage. The client may be unable to report because the credential or network is the failure. Ask for the local diagnostic export when needed; no reports does not mean healthy.
5. Match the actual release and recording route to known fixes. 3.4.0 fixes failed-mic coupling and reports buffer-based health; it does not close initial Deepgram handshake completion/timeout handling. Do not promise the release fixes every silent recording.

The global event list is capped at 2,000, per-device at 300. It is not a guaranteed seven-day archive. No time-based pruning/complete denominator exists yet. Queue arrivals across await and lost-response replay need O2; current counts are observations, not exact incident totals. Share Diagnostics choice and content-free fields remain mandatory; no raw ring-log upload, transcript, audio, email, device name or unrestricted error description.

## Outstanding operator checks

Vercel failed-deploy/domain notifications, bot read-token usage and a rotation drill need recorded verification. Deepgram auto-recharge was deliberately deferred by Ian, not accidentally omitted. An external dead-man/mail-path check is proposed, not configured. Use synthetic provider inputs; never activate a license or send a test alert without appropriate explicit authorization.

Historical deployment/config evidence: [ops](../archive/ops-alerting-plan.md), [admin access](../archive/admin-stats-access-plan.md). Preserve timestamps; do not treat their old green results as current health.

## Prepared changes, not active yet (2026-10-29)

[O1–O4 code](../reference/monitoring-cloud-purchase.md) and the [QA/activation handoff](../releases/monitoring-cloud-purchase-qa.md) are ready locally. The deployed table above remains the baseline until deployment is recorded. UptimeRobot was inspected while signed in, with an HTTP monitor selected as the free-account approach, but no monitor exists yet. The session had expired at the final browser check; sign in again at activation. Its target will be `https://api.miniti.app/api/health/monitoring`, a minimal stored-health bit. Configure only after deployment and fresh job evidence; verify the alert contact and controlled inbox test separately. Do not mark provider acceptance as inbox delivery.

## Alert drill-down and age

Incident emails now link to `/admin?device_id=<UUID>#client-diagnostics` through dashboard login (backend `2458ddb`). Old API links redirect for HTML browser navigation; API reads retain authentication and JSON responses. Filtering matches both uppercase legacy and lowercase canonical IDs.

The 2026-10-30 11:45 run sent four recording alerts based on 2026-10-29 events on 3.4.0, not four new failures at send time. Shipped 3.4.0 does not emit the strong `recording_recovered` event; later legacy healthy/reconnect events do not prove transcript recovery. Distinguish evidence age, receipt delay and current failure. [Next-release alert plan](../plans/incident-alert-clarity.md) records the limitation.

For stale cloud counts or early webhooks, use [sync/delivery investigation](../plans/sync-and-delivery-reliability.md): check actual remote presence and event type/revision before interpreting a recent "Last synced" timestamp or a receiver's cloud lookup as proof of successful completion.

## Active model probes, 2026-11-01

Both managed Luna groups are now enabled. The hourly OpenAI check probes GPT-5 mini, GPT-5.4 mini and Luna once each; central insights routing adds Luna only while either opt-in is enabled. Luna uses reasoning none, previous models keep low reasoning, and all probes use tiny synthetic inputs with `store: false`. Read `checks.openai.data.models` and its `checked_at` before claiming fresh per-model evidence. HTTP success proves access, not transcript accuracy. No customer text is used. The [3.6.0 activation record](../releases/3.6.0.md#both-luna-groups-activated-and-verified-2026-11-01) separates live API smoke results from later hourly observations.


## Local recording usage support, 3.7.0

Prepared locally; backend acceptance must deploy before the reporting client. Use the existing authenticated read-only admin usage/chart/CSV views to compare UTC day, engine and collection start. Local minutes do not consume Deepgram allowance. Keep global totals separate from installation-filtered totals: older clients, expired/offline reports, crash tails, and removed installation breakdowns can prevent reconciliation. Do not reconstruct missing duration from meeting content or optional diagnostics.

Removal uses existing authenticated installation revocation or account deletion, not manual counter subtraction. Revocation removes local per-installation lifetime/daily breakdowns and the latest hardware snapshot; deleting the account also removes its local account aggregate. Global duration totals remain, dedup receipts expire after 35 days, and existing billing/audit and activity policies are unchanged. The removal operation preserves membership until local cleanup succeeds, allowing server-side retry after a storage error; do not report complete cleanup from a failed API response. A revoked/moved installation cannot append or replay local usage under its old owner because ingestion rechecks ownership atomically. This runbook records behavior only; no customer account has been revoked or deleted for testing.
