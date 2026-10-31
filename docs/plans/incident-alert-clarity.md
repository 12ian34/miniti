# Incident alert clarity after 3.5.0

Status: **deployed on 2026-10-31** in backend `031c692`, independently before the 3.6.0 app rollout. Backend CI passed. [Release evidence](../releases/3.6.0.md) owns deployment verification; [roadmap](../roadmap.md) owns priority. O1–O6 were already delivered; this is a separate bounded correction, not a reopened monitoring programme.

## Evidence

The first new hourly incident run at 2026-10-30 11:45:35 UTC sent four recording alerts from retained 3.4.0 events on 2026-10-29: three iPhones (93, 10 and 7 retained failure events) and one Mac (17). It scanned 2,001 rows, marked coverage incomplete, and reported no email failure. These are diagnostic-event counts, not meetings or distinct failed attempts. Existing fleet checks reported no client errors in the preceding hour and no server errors in the preceding 24 hours; stored provider probes were healthy. This does not establish every user was healthy.

`clientIncidents.ts` scans retained history on initial rollout, classifies an unrecovered event within 24 hours of receipt as an incident, and sends each eligible device/family/version separately. Later legacy `audio_recovery_healthy`/`deepgram_connected` events exist for the four devices but cannot prove recovered transcription. The strong `recording_recovered` event was added for 3.5.0; shipped 3.4.0 (`d547e00`) does not emit it, despite the evaluator's version predicate accepting 3.4+. The legacy clients therefore leave recovery unknown. Receipt delay and event age are different: promptly delivered yesterday does not mean newly broken now.

Three iPhones had repeated transcript-starvation/reconnect sequences; one Mac had connection-error/degraded events. Actual speech loss versus noise triggering the watchdog remains unverified. Keep that recording investigation separate; do not classify a successful socket reconnect as restored speech or change the engine from these summaries alone.

## Deliverable

- Distinguish recent active failure evidence, a historical incident first discovered now, and recovery unconfirmed. Show occurrence and receipt times, source version/build where available, latest relevant evidence and age in the subject/body or immediate summary.
- Initial deployment/backfill should produce a bounded historical summary, rather than imply several simultaneous new outages. Persist rollout/watermark policy so redeploys do not resend history. New terminal/repeated failures still alert; do not silence them to eliminate noise.
- Count distinct attempts only with an actual attempt identity; otherwise say warning/error events, with legacy duplication/coverage caveats. Do not call 93 records 93 failed meetings.
- Match recovery capability to actual event evidence/schema, not an optimistic minimum version. Legacy healthy/reconnect may be reported as later connection evidence but must not close an incident as confirmed recovery.
- Group/cooldown transitions intentionally. Suppress repeat reminders when there is no fresh failure evidence; label any deliberate unresolved reminder honestly. Keep missing evidence, truncation, retention and mail failures visible.
- Preserve hourly cadence, authentication, content redaction, event-id receipts and provider failure coverage. No new telemetry SDK or raw-content collection.

## 3.6.0 classification and delivery policy

These are the implementation defaults for this bounded correction; a changed threshold must be recorded here before coding it. Preserve the existing three qualifying ten-second windows in ten minutes / terminal-event trigger and hourly cron. Separate whether an incident ever triggered from whether there is recent evidence it remains active.

| State | Rule and copy |
|---|---|
| Recent failure evidence | Latest qualifying occurrence is within two hours of the check, with no later trustworthy recovery. Say "Recent recording failures", not "recording is broken now". Two hours tolerates the hourly schedule; it is not continuous observation. |
| Historical, recovery unconfirmed | Incident triggered, but latest qualifying occurrence is older than two hours or only later legacy connection evidence exists. Say "Earlier recording problems, recovery unconfirmed" with last failure age and later connection evidence separately. |
| Recovered | A supported strong recovery event with required evidence is later than the triggering failure for the same device/episode. State exactly what recovered (for example audio delivery), not that all transcript/insight output is verified. |
| No recent evidence | Retention, missing data or a vanished group prevents a current assessment. Never convert this to recovery. |

Use occurrence time only when valid. Invalid/missing/skewed clocks use receipt time with that limitation explicitly labelled; do not invent historical timing. Delayed arrival is separately indicated. A fresh episode after recovery must re-satisfy the repeated-failure threshold or contain a terminal event; the later legacy healthy marker is not a reset that can hide real failures.

Recovery capability comes from the supported event schema/required fields. Shipped 3.4.0 lacks strong recording recovery; a version string alone is insufficient. `recording_recovered` with `pcm_sent=true` describes restored audio flow, not proof new words or AI output arrived. If later transcript evidence exists it can be displayed separately. Account-key recovery keeps its existing family-specific meaning.

### First rollout and repeat policy

Extend the existing incident state, rather than introduce a notification framework. Preserve `last_email_at`/kind, existing grouping, hourly run claim, send cap and retention. Add only the baseline and last-notified failure evidence needed for these rules:

1. Persist a rollout baseline and retain already-notified history. The four previously emailed historical incidents must not alert again just because the evaluator changes. Fresh qualifying failures remain eligible on the first run.
2. Previously unseen historical incidents may produce one bounded summary, clearly labelled historical, with at most 20 groups and an omitted count/admin link. An unsuccessful send must not mark its evidence notified. Keep unreported/omitted evidence visible; prioritize fresh terminal failures over historical summary mail.
3. No new qualifying failures since the last accepted alert means no unresolved reminder. Continuing fresh failures retain the existing daily repeat gate. Recovery is sent once for a previously alerted incident; a newly qualifying failure after recovery can alert again, including on the same date.
4. Compare stable event identities plus occurrence/receipt ordering where available; timestamps alone can miss same-time events. Legacy records remain approximate. Retain the three-window trigger and do not relabel event counts as failed meetings.
5. Preserve the 20 sends/run, 1,000-group bound and 30-day detailed-state retention. Coverage/truncation remains explicit. Do not advance notified evidence for failed or omitted mail.

Use the existing mail idempotency facility with keys tied to the notification's evidence, and advance notification state only after provider acceptance. Test failed sends and ordinary next-hour retries. An accepted response lost before state persistence can still produce a duplicate; document that limit rather than claim exactly-once inbox delivery. An episode store, separate durable notification-intent queue and general mail recovery subsystem are deferred. If a focused fixture exposes a defect that prevents the rules above, make the smallest state addition that fixes it and document why.

Keep the existing hourly run claim; do not introduce an unsafe lease/unconditional unlock. A new concurrency mechanism is not part of this copy/evidence correction.

## Implementation surfaces and regression cases

Primary files: `miniti-api/lib/clientIncidents.ts`, `clientDiagnostics.ts` (only if evidence normalization needs correction), `opsDigest.ts`, existing incident/ops tests and the operations/admin contracts. Preserve `/api/admin/ops-health` old fields where feasible and add explicit evidence/notification fields; admin/digest readers must tolerate older state. No client telemetry expansion is required. The already-fixed dashboard link and case-insensitive lookup stay intact.

Use fixed-clock fixtures and an injected mail sink, never production cron refresh:

- The four retained 3.4.0 patterns: historical wording, event counts and recovery unconfirmed, not four simultaneous new failures.
- First baseline with already-notified history, unseen history and a fresh terminal event; redeploy/retry sends no accepted-history duplicate.
- Two-hour boundary, prompt versus delayed receipt, invalid/future clocks, duplicated stable IDs, legacy repeats, and three actual trigger windows.
- Legacy connection/healthy after a trigger remains uncertain; strong PCM recovery says audio recovered; recovery before failure does not close a later episode.
- Fresh recurrence after recovery on the same day is not suppressed by the prior alert; ongoing failures obey the daily repeat gate; no new evidence means no reminder.
- Retention/truncation/missing groups, 20-send capacity, empty data and disabled incidents remain honest in admin health/digest output.
- Missing mail config, provider rejection/retry, accepted-response ambiguity, old schema decode and preservation of notification state on redeploy. No notified-watermark advancement on failure/omission.

Blocking checks are the focused evaluator/mail fixtures above, the full backend suite and the existing admin-link regression. Observe one normal hourly run after deployment; no general mail-outbox project or exhaustive crash matrix is required.

Golden text assertions cover subject/body age, occurrence/receipt times, warning/error event wording, unknown attempt counts and no content/credentials. Retain tests for the fixed login link and all existing provider checks. Run the full backend suite, tsc and lint; use isolated real Redis when atomic state transitions are added.

## Already fixed, not remaining work

Backend `2458ddb` is deployed: future incident links use `/admin?device_id=<UUID>#client-diagnostics`; HTML navigation to already-sent API links redirects through dashboard login, retaining the filter. JSON clients still get authenticated 401 responses. Device matching includes old uppercase IDs. Live redirect/login response checked; eight focused tests, tsc and lint passed. This does not implement the alert-quality changes above.

## Delivery

Backend-only correction selected alongside 3.6.0, independently deployable when ready; it does not wait for the app binaries and changes no app payload contract. [Release checklist](../releases/3.6.0.md) owns evidence. Rehearse with retained synthetic/legacy fixtures and compare old/new outputs; no production state edits or forced cron runs as a substitute for tests. Record the deployed revision and observed normal cron output. Rollback preserves existing notification state and never replays the whole historical scan as fresh incidents.


## Local implementation and independent review

`clientIncidents.ts` extends the existing incident record with evidence classification, first-rollout history state and last-notified failure evidence. Recent evidence uses occurrence time with a safe receipt-time fallback. Initial retained history gets one bounded summary; repeats require new failure evidence. Existing notification identities survive deployment. Recovery is confirmed only for verified macOS/iOS 3.5.0+ producers with `recording_recovered` and `pcm_sent: true`. Linux has no verified producer yet, regardless of its version; unknown platforms, malformed versions and older Apple reconnect evidence cannot establish recovery. Retained unsupported recovery claims become unconfirmed when their source events expire.

Independent review identified and fixed two delivery boundaries: an unsent post-baseline notification remains pending when it ages beyond two hours and later sends with historical wording; recurrence compares recovery occurrence with the notified failure occurrence, not the email send time. Four deterministic tests cover these cases, first-seen late events and recovery before an alert was accepted. Capacity is bounded by send attempts, including failures. No new queue or Redis atomic transition was introduced.

Final backend suite: **695 passed, 5 skipped**; type generation, TypeScript and lint clean. Production build and exact command evidence are in the release record. No alert was sent to a customer, no production state was reset, and no deployment was performed. The first normal deployed hourly run remains an operational release check.

Initial implementation commit: `467601e`; the 2026-10-31 capability correction is recorded in the release evidence. Full production build passed after the final fixes; public operational deployment remains pending.
