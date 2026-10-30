# Operations, diagnostics and support

Current deployed behavior as reconciled 2026-10-27. Future changes are in [logging and monitoring](../plans/logging-and-monitoring.md), not promises made by this runbook. Backend [runbook](../../../miniti-api/docs/agents/05-runbook.md) and [environment contract](../../../miniti-api/docs/agents/02-environment.md) own command/config details.

## Read health without triggering checks or mail

From `miniti-api`, use `node scripts/admin-stats.mjs summary`, `ops`, `deepgram`, `digest`, or `events` with the documented filters. The [admin-stats cookbook](../../../miniti-api/scripts/admin-stats-curl.md) is the read-only HTTP equivalent. Prefer stored state for inspection; refresh options run probes and can send alert/recovery mail. Do not print .env, cookies or tokens.

Auth: ADMIN_READ_TOKEN is read-only for GET admin routes. The script can instead use a session cookie obtained with the server-only admin secret. Mutations require a session and appropriate Origin; never give the bot the mutation secret. Token rotation takes effect on deployment. There is no requirement to build an admin MCP.

## What currently alerts

| Check | Schedule / rule |
|---|---|
| Deepgram | Hourly at :15. Read balance and make a real listen handshake with a granted token; close on 101 without audio. Low below configured balance threshold (default $25); provider refusal critical. Grant 200 alone does not prove listening works. |
| Ops | Hourly at :45. Client/server error counts, OpenAI, Resend, Neon, KV, Polar config, cron ages and spend. |
| Client errors | At least 5 error-level events from at least 2 devices in an hour. Warnings and one blocked user can be missed. |
| Server errors | At least 5 recorded 5xx/uncaught route errors in an hour. Content-free fixed details. |
| Providers | Explicit provider refusal is critical; rate limiting warns. Network/5xx unknown is currently recorded without email. Sustained unknown alerting is built locally but not deployed. |
| Spend | Warn at 80%, critical at 100% of configured budgets; values are operational settings, not permanent product costs. |
| Digest | Monday 07:00 UTC. Money, usage, provider/cron health, alerts and restore outcomes. A missing digest requires investigation; it is not an independent dead-man monitor. |

New warn/critical emails immediately on a check run; repeat critical every 6 hours, warning daily, one recovery. Spend repeats slower. There can be almost an hour before an incident is evaluated. Resend failure can prevent its own alert; there is not yet an independent mail/cron sentinel.

Polar config trims/validates known malformed UUID-shaped env input, reads subscriptions with an organization filter and uses a narrow unknown-key validation probe; never activates a license. Product ID shape is checked, not ownership or successful activation. The success wording currently overstates this and is assigned to O4. Restore outcomes supply actual restore evidence: any provider_config in 7 days makes the check critical after successful probe reads; three provider_unavailable outcomes warn. A green check is not an end-to-end purchase/restore test.

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
