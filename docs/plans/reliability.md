# Watch retries, delivery, History and single-use links

Status: planned, not implemented. Version: unassigned. Scope reconciled 2026-10-27. [Roadmap](../roadmap.md) owns priority; this file owns completion. One release may include several completed plans. Ordered backend deployments inside a plan are not separate unfinished product releases.

## Deliverable and boundary

Finish R4–R8 as one bounded reliability release. R1, narrowed R2 and R3 already shipped; the wider AI-consent audit is deferred, not silently re-added here.

## Prerequisites and decisions

Preserve 3.4.0 authorization generations, permission guards and sync fences. R5 precedes R6. R8 needs a real isolated Postgres concurrency test. No ownership migration or unrelated settings redesign.

## Implementation contract

### R4: Watch retry scheduling

`WatchImportService.kick` selects both queued and waiting-for-minutes jobs, then calls itself after every run. `retryLater` sets queued, so an offline failure immediately retries; exhausted minutes repeatedly request grants until another refusal can turn the job into failed.

Persist retry eligibility (attempt count and next eligible time, with backward-compatible ledger decoding). Use bounded backoff for transient failures; network recovery or activation can trigger an eligibility check, not bypass the delay unconditionally. Waiting-for-minutes is blocked until an entitlement/usage change or explicit retry. Continue eligible independent jobs instead of selecting the same blocked first job. Coalesce timer/activation/file-arrival/manual triggers into one worker. Keep audio, receipts and the existing saved-meeting duplicate guard intact; avoid spinning in the background. R2's permission block is a separate reason to wait.

Tests: offline immediate failure makes one attempt until eligible; persistent limit makes no loop; a blocked first job does not starve a runnable second; relaunch preserves eligibility; simultaneous triggers run one job; manual retry is bounded; no duplicate meeting or duplicated session-end charge after recovery. Exercise the actual importer with injected clock, grant/transcription transport and receipts. Real iPhone QA includes airplane mode, exhausted minutes, relaunch and foreground/background transitions.

### R5: coalescing an in-flight webhook

Reproduced with production `DeliveryOutbox`: v1 is being sent, enqueue v2 under the same item ID, v1 succeeds, `apply` removes the item and v2 never goes out.

Give each payload revision its own completion identity, or keep one immutable in-flight item plus one coalesced successor. A completion can settle only the revision it sent. Newer content must survive successes, retries and terminal failures of the older revision. Preserve stable delivery IDs for retries of identical content; new content must not accidentally be deduplicated as the old payload by receivers. Persist the successor before considering it accepted. Deletion/discard must not resurrect it.

Tests with a suspended sender: enqueue v2/v3 during v1; v1 delivered/retry/rejected; persist/reload; deletion while outstanding; changed destination under the existing routing policy. Assert payloads delivered, not only queue length.

### R6: useful manual webhook retry

Terminal failures intentionally discard the transcript body. `retryNow` makes the item pending without rebuilding it, so the production sender rejects it as "missing body". The old test replaces that sender with one that accepts any item and misses the failure.

Keep terminal payload disposal. Make the UI action explicitly resend the current saved meeting: fetch it safely, encode its current permitted payload and create a new delivery identity. Do not resurrect trimmed text or a deleted meeting, and do not claim to replay a historical body that no longer exists. If the meeting or destination is unavailable, explain why and leave discard available. Define the event used for this current-state resend and cover receiver compatibility. CRM retries keep rebuilding from saved data. Implement after R5 so resends cannot be lost through coalescing.

Tests using the production sender's body requirements: terminal 4xx and retry exhaustion, resend succeeds with a nonempty current payload, edited/trimmed meeting, deleted meeting, removed endpoint, encoding/save failure, reload, and unchanged CRM retry. Never retain transcripts indefinitely to make the test pass.

### R7: History responses belong to the request's revision

`generateInsightsForMeeting` captures the transcript but checks only deletion before applying an answer; trim remains available during generation. A late answer can restore insights based on removed text and mark them current. Final-insight generation already captures `transcriptRevision`.

Capture meeting ID, transcript revision, requested mode, relevant template identity and request generation. Validate before any model write, freshness stamp, markdown export or webhook. A superseded/deleted/trimmed request is discarded without clearing a newer request's loading state. Apply the same discipline to saved-meeting topic/template paths that can race an edit. Preserve the existing user-wins rule for manual speaker edits.

Tests: delayed summary/questions/Sales/template response followed by trim, correction, undo, template change, deletion or a newer request. No stale data/freshness/export; unchanged revision applies normally. Use a real in-memory meeting and delayed service response.

### R8: atomic single-use link consumption

Reproduced from production `loginLinks.ts`: two concurrent `consumeLoginLink` calls both return success because lookup and unconditional update are separate operations.

Add a store operation that atomically claims an unconsumed, unexpired row of the expected purpose and returns it, using conditional `UPDATE ... RETURNING` in Postgres. Only that winner can issue the web session or perform email confirmation. Match semantics in the in-memory store and check expiry/purpose at consumption time. Preserve non-consuming approval-page previews and existing public unknown/expired/consumed responses without exposing account existence. Inspect every caller of the generic consume helper.

Do not blindly replace device-enrollment's inspect/bind/consume sequence: its Redis binding and Postgres link are separate stores, and lost-response recovery must remain possible for the same proven installation. Any change there needs an explicit recoverable claim/result contract and its own scenarios; the bounded fix here covers the generic web sign-in/confirmation consumption race. Tests: concurrent claims yield one winner/session, wrong purpose, expiry at the boundary, consumed link and confirmation failure. Run a real isolated Postgres concurrency test as well as the fake store test.

## Acceptance and delivery

Adopt the real-worker, held-sender and held-response regressions above. Assert actual delivered payloads and persisted models. Incorporate T03/T08/T10 and the delivery portion of T16; run airplane-mode/relaunch Watch QA and export retry against a controlled endpoint. Existing audio/receipts and user-configured private-mode exports stay intact.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

Rollback: decode old ledgers and preserve pending work; a rollback cannot discard a persisted successor or resurrect deleted payloads. Keep R8 session/confirmation response shapes and device-enrollment recovery contract. [Original evidence](../archive/reliability-follow-up-plan.md).
