# Admin reports: hourly saved reports and a tabbed panel

Status: deployed to production 2026-11-11 (`miniti-api` commits `deab05e`, `9b60e7d`, `7cc625b` and `26d2c6f`, review fixes in the last). First manual run at 13:27 UTC: every part ok in 21.3 s with cold caches (787 device records, 365-day chart 12.8 s). First scheduled run at 13:30 UTC: every part ok in 5.1 s, provider caches kept. No 5xx since the deploy. Open: Ian's installations in the exclusion list (empty so far) and the 24-hour `/api/insights` and `/api/session` p95 comparison. Backend only, no app release. Priority is in [the roadmap](../roadmap.md#operator-reporting-backend-only). Current route and storage contracts live in `../miniti-api/docs/agents/04-api-reference.md` (saved admin reports) and `03-patterns.md` (counter keys); this plan keeps the reasoning.

### As built, and where it differs from the design below

- Counters: `insights_daily:{date}` field `{installation}|{mode}|{language}|{platform}` and `recording_language_daily:{date}` field `{installation}|{language}|{platform}`. The installation is in the field, so exclusions are exact and one write replaces the separate per-device hash. Raw daily counters follow the existing no-expiry policy rather than 400 days.
- Devices: the hourly job rebuilds the full devices report (779 records today, about $1 a month of KV reads) instead of the incremental active-set reads. Revisit when the device count grows a lot. Account emails and Polar billing emails are attached on read, never stored.
- Usage chart: days three or more days old are cached per day (refreshed daily for 35 days, then every 30 days); the hourly chart went from 472 ms to 25 ms in a local run. Snapshots are gzip in KV with a 900 KB guard.
- Provider caches (ledger, costs) are refreshed by the job only when older than 55 minutes.
- Overview shows last 7 days vs the previous 7, top languages and report problems. Money is the former costs modal, inline. Health shows the job status.
- Not built yet: Accounts quick filters (near limit, old clients, inactive paying), a one-off Deepgram request-history language backfill, and an `admin-stats.mjs` `fresh=1` flag. Exclusions start empty.

### Validation

945 backend tests, types, lint and a production build pass. The page was checked in a local dev server against a throwaway Redis with fake data (all five tabs rendered, no new console warnings; one existing style warning predates this work). An independent Fable review found no customer-path or compatibility issues; its seven small findings are fixed in `26d2c6f`.

### Deploy

Pushing `miniti-api` main deploys. After deploy: run the cron once (or Refresh now), check Health shows every part ok, seed exclusions with Ian's installations, then compare `/api/insights` and `/api/session` p95 latency over 24 hours. Rollback switches: `ADMIN_REPORTS_SNAPSHOTS=off`, `REPORT_COUNTERS=off`.

## Goal

Better backend reports about how people use miniti, without slowing customer requests or adding meaningful cost. Hourly freshness is enough. No new app tracking, no analytics SDK and no app release.

## Current state (checked 2026-11-10 against `miniti-api` 255bef1)

- `app/admin/page.tsx` is one 3,770-line page: usage chart, recording coverage, device table, Mac hardware diagnostics, a costs and revenue modal and a device detail modal.
- Reports are rebuilt when the page is opened. `buildDevicesReport` calls `kv.keys('device:*')` and then reads every device hash. `buildUsageChart` reads one key per day for each series, with concurrency capped at 24 since the 2026-11-04 edge crash.
- Only `/api/admin/costs` and `/api/admin/ledger` cache their results, for an hour.
- Existing crons: `cloud-maintenance` 04:00, `deepgram-health` :15, `ops-health` :45, `weekly-digest` Monday 07:00. Functions have a 60 second limit.
- Data already stored durably: daily usage, registration, active-device and docs lookup counters; Deepgram and on-device minutes per day and per device (on-device since 3.7.0, with a labelled collection start); OpenAI tokens per day per model (`openai_usage_daily:{date}:{model}`) and per device; Jev usage; device hashes with version, platform and tier; Apple and Polar subscription state; client diagnostics and server errors.
- Language: `/api/session` receives the selected Deepgram language and `/api/insights` receives the insight language, but neither stores it. It only reaches Vercel runtime logs, which are short-lived and are not a report source. Deepgram's request history has the language per request, but it is a provider API, slow to page through and not filterable by our accounts.
- Insight mode is passed to `recordOpenAIUsage` but only used in an error log. The daily counter is keyed by model, not mode.
- `scripts/admin-stats.mjs`, its skill and the curl cookbook call `/api/admin/{devices,costs,ledger,usage-chart,client-events,ops-health}`.

## Design

### 1. One hourly report job

- New `GET /api/cron/admin-reports` at `30 * * * *`, between the two existing hourly jobs. Authenticated with the existing `cronAuth`.
- One lock key with a short TTL so runs never overlap. If the lock is held, exit.
- Builds each tab's report and writes it as its own saved snapshot (`admin_report:v1:{tab}`), with `generated_at`, `source_window`, `coverage` notes and job stats (runtime, KV commands, rows read, truncated yes/no).
- If any part fails, keep the last good snapshot and mark that part stale. Never replace a good report with an empty one.
- Budget per run: finish well under the 60 second limit, with read concurrency at or below the existing 24. If the work grows past the budget, stop, save what is complete and mark the rest truncated.
- The admin page and `/api/admin/*` read saved snapshots only. There is one "Refresh now" button, limited to once every 5 minutes, which runs the same job.

### 2. Incremental reads, not full rescans

- Days before yesterday do not change, apart from late uploads. The job saves each finished day once into a compact daily rollup (`report_daily:{date}`) and then reads only today and yesterday each hour.
- Once a day, at the 04:30 run, recompute the last 3 days to pick up delayed on-device reports and offline diagnostics.
- Device data: each hourly run rereads only devices in today's active set and today's registrations (both already stored). A full device scan runs once a day, using cursor `SCAN` rather than `KEYS`. This is the biggest cost saving, because the device count grows and the active count is much smaller.
- Rollups and snapshots expire after 400 days. Existing raw counters keep their current retention.
- Provider calls (Polar, Apple, Deepgram usage, OpenAI costs) move into the job, reusing the existing one-hour cache logic. No provider call happens when the page is opened.

### 3. Two new counters, written when requests already happen

Language and insight mode cannot be reported reliably without storing them. Both counters are added to writes that already happen, so customer requests do no extra round trip.

- **Insight requests by mode, language and platform.** In `recordOpenAIUsage`, add one `HINCRBY` on `insights_daily:{date}` with field `{mode}|{language}|{platform}`, alongside the existing parallel writes. It is best-effort and swallows its own errors, like the current writes.
- **Deepgram minutes by language.** Save the language on the accounting session at `/api/session` start (it is already parsed there), then add the duration to `deepgram_language_daily:{date}` at the existing session end write. Count minutes, not requests, so reconnects do not inflate the totals.
- On-device minutes by language are not counted, because the local usage report does not carry a language. Show this as a known gap rather than changing the app.
- Collection starts at deploy. Earlier days show "not collected". Deepgram request history can be used once, by hand, to backfill a rough language history, labelled as an estimate. It is not part of the hourly job.

### 4. Internal and test traffic

- A server-side exclusion list of account IDs and installation IDs (stored in KV, editable from the admin panel, with an audit timestamp). Never guess exclusions from names or emails.
- Every report shows totals with and without exclusions, and how many records were excluded.
- Seed the list with Ian's own devices and accounts before the first comparison.

### 5. Tabs

| Tab | Question | Contents |
|---|---|---|
| Overview | How is miniti doing? | Active accounts and installations, recording minutes, paying subscriptions, revenue, costs and open problems, each compared with the previous period. Snapshot age. |
| Usage | What are people using? | Languages (Deepgram minutes and insight requests), Deepgram vs on-device minutes, insight modes, docs lookups, platforms, app versions and version adoption, new vs returning installations, weekly retention. |
| Accounts | Who needs attention? | Searchable installations and accounts with plan, allowance used, last activity, version and recent errors. Filters for heavy usage, near the limit, old clients and inactive paying accounts. Moves the current device table and detail modal here. |
| Money | Is it sustainable? | Revenue, provider costs, margin, MRR, cost per recorded hour, free vs Pro consumption, top accounts by cost, month-end forecast. Actual and estimated figures are labelled separately, as is Apple revenue coverage. Moves the current costs modal here. |
| Health | What is failing? | Latest ops-health and Deepgram-health results (read from their own saved results, not rerun), client incidents by version, server errors, report job freshness and job cost. Mac hardware diagnostics move here. |

Shared controls: 7 days, 30 days, this month, custom range; platform and plan filters; "exclude internal" toggle (on by default); CSV export per table; "Updated at" on every tab. Each tab loads only its own snapshot.

### Definitions that need to be precise

- **Active installation:** started a managed recording, reported on-device duration or made an insights request that day. Background calls such as `/api/usage`, `/api/version` and token refresh do not count.
- **Retention:** an installation active in its first week that is active again in a later week. Cohort by first active week, not registration, because registration can happen without use.
- **Account attribution:** report activity against the installation, and against the account it belonged to on that day where that is stored. Never move past activity to an installation's current account. When account ownership (B0) lands, readers switch to its canonical device records. Until then, use `installationActivity` so upper and lower case device IDs count once.
- **Coverage:** BYOK, diagnostics turned off, older clients and days before collection are shown as gaps, never as zero.

## Privacy

- Only aggregates and the fields the admin panel already shows. No meeting content, titles, names or transcript-derived data.
- Language codes and insight modes are request parameters the backend already receives. Storing daily counts of them is operational usage data, not behavioural analytics. Before deploying, check the privacy policy and in-app privacy text still describe this accurately. No change to Share Diagnostics.
- Snapshots store account and installation IDs, not emails. The Accounts tab looks up emails per account when opened, as it does today.

## Performance and cost

- Customer requests gain one best-effort `HINCRBY` on insights and one on session end, both in parallel with existing writes. No reads are added to customer requests.
- Opening the admin panel becomes one snapshot read per tab instead of hundreds or thousands of KV reads and live provider calls. This also removes the risk of the 2026-11-04 crash returning as history grows.
- The hourly job reads a few dozen counter keys plus today's active devices. The daily run adds one full device scan. Record actual KV commands and runtime in the snapshot and in the release notes for this work, and compare them with the current page-open cost. Do not claim it is cheaper until measured.
- 720 hourly runs a month are billed as normal Vercel function time.

## Delivery

Each step is a separate commit, reviewed before the next, and deployable on its own.

1. **R0 Baseline.** Measure current admin route latency, KV commands per page open, device count, and p95 latency for `/api/insights` and `/api/session`. Seed the exclusion list.
2. **R1 Counters.** The two new counters, with tests. Deploy early so language and mode history starts collecting while the rest is built.
3. **R2 Job and snapshots.** Hourly job, lock, stale handling, rollups, incremental device reads, refresh button. Existing `/api/admin/*` endpoints return the same response shapes from snapshots, so `admin-stats.mjs`, its skill and the curl cookbook keep working unchanged.
4. **R3 Tabs.** Split `page.tsx` into the five tabs and move existing sections into them without changing their numbers.
5. **R4 New reports.** Languages, modes, engine split, version adoption, retention, concentration, forecast, exclusions, CSV.

## Acceptance

- Tests: lock prevents overlap; a failed part keeps the previous snapshot and marks it stale; truncation is reported; rollups are idempotent when rerun; late data is picked up by the 3-day recompute; counters are correct under concurrent requests; exclusions apply consistently across tabs.
- Snapshots match the current live reports for the same window (devices, minutes, costs) before the old on-request code is removed.
- After deploy, p95 latency for `/api/insights` and `/api/session` over 24 hours is within normal variation of the R0 baseline, and the job's measured runtime and KV commands are recorded.
- `node scripts/admin-stats.mjs` output is unchanged apart from the new fields.
- Backend typecheck, lint and full tests pass.

## Rollback

- `ADMIN_REPORTS_SNAPSHOTS=off` makes admin routes build reports on request as they do today.
- Removing the cron entry stops the job. Snapshots expire on their own.
- The new counters are additive and can be disabled with `REPORT_COUNTERS=off` without touching billing, allowance or cost counters.

## Out of scope

- PostHog or any analytics SDK, language selector or screen tracking, and any app or Linux client change. No backend contract the clients use changes, so Linux needs no tracking issue. Linux installations appear in the platform breakdown.
- Atomic registration and the paginated device registry ([registration plan](backend-registration-and-registry.md)). When that lands, the daily full scan switches to the registry.
- Measured cost and cache economics ([usage cost plan](usage-cost-and-cache.md)). The Money tab displays the existing figures and does not change prices or budgets.
- Alerting changes. Health only displays the existing checks.

## Open decisions for Ian (defaults used in the build)

1. Exclusion list: confirm it starts with your own devices and accounts only, or name other internal or test installations.
2. Retention definition: confirm "active" means recorded or used insights, not just opened the app.
3. Roadmap position: this is backend only and independent of 3.9.0 and account ownership. Suggest scheduling it straight after the 3.9.0 backend deploy, with R1 first so the data starts collecting.
