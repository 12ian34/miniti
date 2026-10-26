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
| Polar license-key path: `POLAR_ORGANIZATION_ID` and `POLAR_PRODUCT_ID` normalised only for the one known mistake (a trailing literal backslash-n, which `.trim()` does not remove) and then validated as UUIDs at startup; an authenticated read-only `polar_config` check that the configured organisation and product belong to the token's account (`GET /v1/organizations/{id}`, `GET /v1/products/{id}`), hourly; the unknown-key validate call kept only as a narrow negative probe ("Polar rejects as expected"), never read as "restore works"; no activation is ever made by a probe; `/api/restore` outcomes counted by error code (`polar_config` is `critical` at once) and shown in the digest | **built 2026-10-26** in `miniti-api` (`lib/polar.ts` `polarConfigId`, `classifyActivationFailure`; `lib/opsHealth.ts` `probePolarConfig`; `lib/opsStore.ts` restore outcomes; 15 new tests), not deployed; the digest line is still to add | Found when Ian's license key restore failed on 2026-10-26: the production value had been pasted into Vercel with a trailing literal `\n`, Polar answered 404 to every activation, and the only trace was a `console.error`. Same shape check for every id-shaped env value (`POLAR_PRODUCT_ID`, Apple ids, `DEEPGRAM_PROJECT_ID` if set): a value that is not the expected shape is `critical` and emails |
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
| `client_errors` | at least 5 error-level diagnostics in the hour from at least 2 devices | One device's errors are that device's environment. Two or more at once is a release or a provider |
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
- [ ] Next Monday: the digest arrives at 07:00 UTC without a manual trigger.
- [ ] Vercel team settings: deployment failed notifications on (Ian).
- [ ] When the app fix ships: break a handshake on purpose (wrong key in a test build) and confirm both the diagnostic and, with a second device, the client error mail.
