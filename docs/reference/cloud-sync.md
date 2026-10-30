# Cloud sync and account boundaries

Shipped baseline: 3.0.0 sync/API/MCP, 3.3.0 account switch, 3.4.0 account-email UX and in-flight generation fences. The authoritative backend wire/storage contract is [08-cloud.md](../../../miniti-api/docs/agents/08-cloud.md); [patterns](patterns.md#cloud-sync-300) covers client mechanics.

## Current behavior

Cloud is optional, default off and managed Pro only. Its switch belongs to the account; another device observes changes on its next usage check. Private mode pauses only this device and excludes newly private recordings; deliberately configured exports remain allowed. Email recovery/management is available without Pro/cloud and is distinct from data/API/MCP rollout guards.

`MeetingSyncDocument` carries an additive versioned document; the engine fingerprints finished meetings, preserves unknown fields, and excludes current/deleted meetings. Pulls commit locally and may auto-export Markdown, but do not enqueue CRM/webhooks. Local deletes persist tombstones; server tombstones win. A 413 marks an oversized meeting skipped until changed. Sync uses millisecond-normalized stamps to avoid repeated revision churn. Old rows/store migrations must retain data.

`CloudSyncEngine.PassContext` captures account and generation. Check after every await before applying responses, statuses, errors or cursors. Cursor writes use the captured account. Reset, account change and credential replacement invalidate outstanding passes; stale work hands over without pausing the new account. Cancellation alone is not the fence.

Account changes clear revisions/fingerprints/tombstones and the old cursor before status refresh. Local meetings stay, and a later pass can upload them to the next account under today’s behavior. This is a remaining provenance problem, not an R3 regression: [meeting ownership](../plans/meeting-ownership.md) adds explicit copy authority. Never infer old ownership from revision counters.

The existing per-meeting Keep off the cloud action is post-creation. [Selective cloud privacy](../plans/selective-cloud-privacy.md) adds the pre-recording choice and title rules; do not claim this already exists.

## Operational gotchas

- Redis caches sequence values using Lua; durable meetings, changes, links and tokens live in Postgres. Do not assume a Redis pre-check and a Postgres write form one transaction.
- Tests must not start the app’s real sync engine against its real store or Keychain. Attach an isolated test host without starting it when testing bookkeeping only; use held transports for actual pass races.
- Tombstone retention is 30 days; an older offline device may re-upload. Do not silently purge local history to reconcile it.
- Unknown 409s in old clients become revision-conflict retries, and fixed oldest-first batches can starve newer work. A different error can fail the whole pass. Future ownership enforcement must be gated by tested platform versions.
- Keep per-account imports’ external-source/id deduplication; no global cross-account merge. Voice embeddings never enter cloud documents.
- Generic web/email link consumption has the R8 race; [reliability](../plans/reliability.md) owns it. Device-enrollment bind/consume has different cross-store retry requirements.

## Intentional limits and future choices

Foreground polling is the current delivery mechanism; APNs, web History, API write scopes and server-side Coaching are not built. They are candidates in the roadmap, not unfinished core sync. Linux parity has its own implementation status. Live connector and copied-old-store checks must have actual evidence, not inferred passes.

Original schema/design, cost snapshot, nuanced delivery notes and regression matrix are retained in [the archived cloud record](../archive/cloud-sync-plan.md). Costs and open questions there are dated; revalidate before making capacity decisions.

## Local follow-ups, not released (2026-10-29)

Monitoring O1–O4, selective cloud privacy C1 and purchase return B6d are implemented in the working tree. See the [code/compatibility contract](monitoring-cloud-purchase.md) for file ownership, additive wire fields, limits and remaining QA. Do not infer deployment from local implementation.

Local selective-privacy availability correction (2026-10-30, unreleased): finished alone is not evidence of a cloud copy while cloud is unavailable. The toggle queues removal only for known prior sync/pending deletion, an in-flight upload of that meeting, or a finished meeting currently eligible to sync. Known cloud copies still queue removal offline. Explicit restore intent stays durable, but the status names the gate preventing sync instead of showing an endless generic pending upload. A zero-revision legacy tombstone is not shown as a known cloud copy while cloud is unavailable.
