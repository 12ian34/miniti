# Validation evidence and unresolved checks

This is an evidence register, not another priority backlog. [Roadmap](../roadmap.md) decides when work ships; each plan owns its regression tests. Record date, platform/build, setup, result and source. Distinguish passed, failed, not recorded, not applicable and explicitly waived. Never tick a historical check just because a release shipped.

| Area | Reconciled evidence / remaining check | Owner |
|---|---|---|
| 3.5.0 | Mac build 142 live with Sparkle check; backend/site deployed. iOS submitted 2026-10-30 12:28 UTC, availability unconfirmed. Ian reported grouped device/provider QA good; no itemised independent evidence is invented. UptimeRobot setup is included in that report; health 200 alone proves neither external configuration nor inbox delivery. | [Release record](../releases/3.5.0.md) |
| 3.6.0 preparation | S1–S3/R5–R7 and alert clarity implemented locally. Review corrections supersede build 143 with signed build 144; Mac 1,135 and iOS 1,073 executed, three skips each, zero failures. The release record owns package evidence and interrupted-test settings cleanup. Exact customer-session reproduction and physical device/receiver QA remain open. | [Release checklist](../releases/3.6.0.md), [sync/delivery plan](../plans/sync-and-delivery-reliability.md) |
| 3.4.0 | Release build and QA observations, unchecked device scenarios and macOS 26 waiver are retained verbatim with their dates. Mac live and iOS upload are different evidence. | [Release record](../releases/3.4.0.md) |
| Migrated/locked keys | macOS 27 observations exist; macOS 26 was not measured. The -128 cancel result is known, not a new absent credential. Verify macOS 26 recovery before A3. | [Account access](../plans/account-access.md) |
| Store recovery | September plan records Ian’s Mac corrupt-store drill passing and an iOS simulator drill. The older roadmap’s Mac “still owed” claim is superseded. Physical iPhone verification is not established by the simulator. | [September record](../archive/p0-hardening-batch-2026-09-plan.md#status), [testing](../reference/testing.md) |
| Meeting search | Weeks-old 1:1 by name/date/transcript-word manual check has no recorded result. | [Search record](../archive/meeting-search-plan.md#status) |
| Calendar start | Late-join/no-show manual check has no recorded result. | [Calendar record](../archive/calendar-auto-start-waits-for-call-plan.md#status) |
| Granola | Real export parsed by standalone harness. App picker/ZIP, second import and cross-device cloud deduplication checks remain unchecked. | [Import record](../archive/granola-import-plan.md#manual-checks-owed) |
| Watch | Paired simulator end-to-end exists; physical 5/30/60-minute background, offline/reconnect, interruption and battery matrix is not fully recorded. | [Watch reference](../reference/watch.md) |
| Local models | Some Mac handoff/live observations exist; complete multilingual/real-call/phone thermal matrices and default-on readiness do not. No inferred model-quality pass. | [Local models](../reference/local-models.md) |
| Cloud | Old-store migration, actual client connectors and hardware/update-path evidence must be checked individually against the original delivery record. Some remain unverified; do not redo a destructive test on the personal account. | [Cloud history](../archive/cloud-sync-plan.md#as-built-and-shipped-2026-10-16-the-nuances-a-future-agent-needs) |
| Auth enforcement | Production mode/adoption and broad legacy-key retirement are not established by source defaults. Inspect deployment settings and usage before a separate retirement decision; preserve direct late migration and token/HMAC rotation overlap. | [Backend environment](../../../miniti-api/docs/agents/02-environment.md), [account reference](../reference/accounts.md) |
| Admin/operations | Read-token bot/rotation checks and Vercel console notifications lack recorded completion. Production test mail is a separate authorized action. | [Operations](operations.md) |
| Long sessions | Full 60+ minute Instruments baseline and large-history budgets remain work, not completed by signpost instrumentation. | [Performance plan](../plans/history-and-session-performance.md) |
| Docs Insights | Source implements docs_topics/docs counters/lookup/catchup. Reconcile each historical acceptance clause with handlers/tests, particularly topics not calling MCP and actual quota/degraded behavior. Unchecked boxes are not proof of missing routes or verified live behavior. | [Backend patterns](../../../miniti-api/docs/agents/03-patterns.md), [historical spec](../archive/docs-insights-api-spec.md) |

Retain reusable hardware scenarios in reference/testing and focused contracts. A new release records its own evidence without overwriting old measurements. Linux parity and actual App Store availability need their own evidence sources.


## 3.6.0 preparation, 2026-10-30

[3.6.0 evidence](../releases/3.6.0.md) owns S1–S3/R5–R7 and incident-clarity validation. Implementation and independent review are complete locally; simulator/full-suite, SQLite-upgrade and native-control renders are separate from physical audio, receiver and two-device QA. The 2026-10-31 review fixes supersede candidate 143 with build 144; a fresh read-only App Store Connect check still found latest build 142. No availability or deployment can be inferred from these local results.
