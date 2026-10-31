# Cloud sync and account boundaries

Shipped baseline: 3.0.0 sync/API/MCP, 3.3.0 account switch, 3.4.0 account-email UX and in-flight generation fences. The authoritative backend wire/storage contract is [08-cloud.md](../../../miniti-api/docs/agents/08-cloud.md); [patterns](patterns.md#cloud-sync-300) covers client mechanics.

## Current behavior

Cloud is optional, default off and managed Pro only. Its switch belongs to the account; another device observes changes on its next usage check. Private mode pauses only this device and excludes newly private recordings; deliberately configured exports remain allowed. Email recovery/management is available without Pro/cloud and is distinct from data/API/MCP rollout guards.

`MeetingSyncDocument` carries an additive versioned document; the engine fingerprints finished meetings and preserves unknown fields. The released 3.5.0 client excludes current/deleted meetings; the local 3.6.0 eligibility split is described below. Pulls commit locally and may auto-export Markdown, but do not enqueue CRM/webhooks. Local deletes persist tombstones; server tombstones win. A 413 marks an oversized meeting skipped until changed. Sync uses millisecond-normalized stamps to avoid repeated revision churn. Old rows/store migrations must retain data.

`CloudSyncEngine.PassContext` captures account and generation. Check after every await before applying responses, statuses, errors or cursors. Cursor writes use the captured account. Reset, account change and credential replacement invalidate outstanding passes; stale work hands over without pausing the new account. Cancellation alone is not the fence.

Account changes clear revisions/fingerprints/tombstones and the old cursor before status refresh. Local meetings stay, and a later pass can upload them to the next account under today’s behavior. This is a remaining provenance problem, not an R3 regression: [meeting ownership](../plans/meeting-ownership.md) adds explicit copy authority. Never infer old ownership from revision counters.

3.5.0 adds Cloud/Local controls in live and saved meeting views plus calendar-title rules. There is no Home checkbox. [Selective cloud privacy](../plans/selective-cloud-privacy.md) retains the delivered contract.

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

## Delivered follow-ups (3.5.0)

Monitoring O1–O6, C1 and B6d shipped with macOS 3.5.0 and the deployed backend/site. iOS is submitted. See the [contract](monitoring-cloud-purchase.md) and [release evidence](../releases/3.5.0.md).

Selective-privacy availability correction (3.5.0): finished alone is not evidence of a cloud copy while cloud is unavailable. The toggle queues removal only for known prior sync/pending deletion, an in-flight upload of that meeting, or a finished meeting currently eligible to sync. Known cloud copies still queue removal offline. Explicit restore intent stays durable, but the status names the gate preventing sync instead of showing an endless generic pending upload. A zero-revision legacy tombstone is not shown as a known cloud copy while cloud is unavailable.

## Local 3.6.0 implementation, not released

In 3.4.0 and 3.5.0, automatic passes can refresh the successful-pass timestamp while leaving cached server count/bytes stale, and a stopped `currentMeeting` remains excluded until the session clears. The local S1/S2 implementation separates three things:

- **Outbound eligibility:** `cloudUploadProtectedMeetingID` protects starting, recording, resuming and final transcript commit. Once the stopped transcript is durable, that meeting may upload while still selected and while final AI runs. Later durable AI updates dirty it again. A failed stop save retains protection and exposes persistence retry.
- **Inbound authority:** `cloudProtectsIncoming` still protects the selected meeting and every meeting with final AI running from pulled documents/deletes and conflict replacements. The engine remembers genuinely newer incoming rows skipped by protection; release coalesces their reconciliation. A protected local row missing from the manifest also retains a release-time recheck. Credential/account invalidation requests a manifest under the replacement authority before clearing old deferred IDs. Echoes of its own accepted uploads and lifecycle notifications with no skipped rows do not trigger extra manifests. This is intentionally stricter than outbound eligibility.
- **Status freshness:** successful pass time and successful count-fetch time are separate. Content changes mark status dirty; explicit refresh, missing/dirty status or a five-minute age trigger a read. A failed count read preserves accepted uploads and the previous count with a stale indication. An unsaved model edit discovered after a pull, manifest or batch await aborts that pass with “Waiting for local edits to save”; it preserves the prior completed-check time and cursor, emits no success, and retries after a durable save or poll. A held response invalidated by an already-committed edit likewise preserves the completed-check time and immediately reruns; a failed rerun cannot leave a false successful check behind. Pending uploads/removals, protected meetings, local-scan failure and oversized rows also prevent a misleading all-clear label. Pending captions omit zero-count operations.

An expired change-feed cursor gets one immediate manifest recovery per sync invocation. If the recovered cursor also expires, the engine retains reconciliation for the next poll or explicit action and shows an unfinished check; it does not chain automatic retry runs.

Completion-marker-only commits do not dirty cloud content or schedule scans. Real transcript/AI commits still do.

Settings says Last checked for the last completed pass and Cloud count checked for the count; neither is proof that a particular meeting uploaded. Webhook delivery remains independent of cloud acknowledgment and contains the transcript and available summary itself. [The 3.6.0 plan](../plans/sync-and-delivery-reliability.md) owns acceptance; [release evidence](../releases/3.6.0.md) owns test/device gates. These changes do not alter account ownership, privacy choices, tombstone authority or the backend sync schema.
