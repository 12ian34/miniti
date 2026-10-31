# Remaining reliability: Watch retries and single-use links

Status: planned, not implemented. Version: unassigned. Scope reconciled 2026-10-30 after splitting customer-reported sync/delivery work into its own bounded plan. [Roadmap](../roadmap.md) owns priority; this file owns completion. One release may include several completed plans. Ordered backend deployments inside a plan are not separate unfinished product releases.

## Deliverable and boundary

Finish R4 and R8 in a later bounded reliability release. R5–R7 moved to the 3.6.0 [sync/delivery plan](sync-and-delivery-reliability.md) on 2026-10-30; that plan is their sole implementation owner. R1, narrowed R2 and R3 already shipped; the wider AI-consent audit is deferred, not silently re-added here.

## Prerequisites and decisions

Preserve 3.4.0 authorization generations, permission guards and sync fences. R5/R6 ordering is now owned by the 3.6.0 plan. R8 needs a real isolated Postgres concurrency test. No ownership migration or unrelated settings redesign.

## Implementation contract

### R4: Watch retry scheduling

`WatchImportService.kick` selects both queued and waiting-for-minutes jobs, then calls itself after every run. `retryLater` sets queued, so an offline failure immediately retries; exhausted minutes repeatedly request grants until another refusal can turn the job into failed.

Persist retry eligibility (attempt count and next eligible time, with backward-compatible ledger decoding). Use bounded backoff for transient failures; network recovery or activation can trigger an eligibility check, not bypass the delay unconditionally. Waiting-for-minutes is blocked until an entitlement/usage change or explicit retry. Continue eligible independent jobs instead of selecting the same blocked first job. Coalesce timer/activation/file-arrival/manual triggers into one worker. Keep audio, receipts and the existing saved-meeting duplicate guard intact; avoid spinning in the background. R2's permission block is a separate reason to wait.

Tests: offline immediate failure makes one attempt until eligible; persistent limit makes no loop; a blocked first job does not starve a runnable second; relaunch preserves eligibility; simultaneous triggers run one job; manual retry is bounded; no duplicate meeting or duplicated session-end charge after recovery. Exercise the actual importer with injected clock, grant/transcription transport and receipts. Real iPhone QA includes airplane mode, exhausted minutes, relaunch and foreground/background transitions.

### R5: coalescing an in-flight webhook

Moved, not completed: [sync/delivery R5](sync-and-delivery-reliability.md#r5-immutable-in-flight-webhook-completion-identity) owns the fix and held-sender tests. Complete it before R6. This anchor remains for historical links; do not implement a second competing outbox design here.

### R6: useful manual webhook retry

Moved and implemented locally, release QA pending: [3.6.0 resend contract](sync-and-delivery-reliability.md#r6-resend-the-current-saved-meeting) owns the production-body rebuild, new delivery identity, error states and tests. Do not revive bodyless terminal items here.

### R7: History responses belong to the request's revision

Moved and implemented locally, release QA pending: [3.6.0 response-authority contract](sync-and-delivery-reliability.md#r7-history-responses-belong-to-their-input-revision) owns revision/generation checks and the saved-model/export regressions. This anchor preserves old links.

### R8: atomic single-use link consumption

Reproduced from production `loginLinks.ts`: two concurrent `consumeLoginLink` calls both return success because lookup and unconditional update are separate operations.

Add a store operation that atomically claims an unconsumed, unexpired row of the expected purpose and returns it, using conditional `UPDATE ... RETURNING` in Postgres. Only that winner can issue the web session or perform email confirmation. Match semantics in the in-memory store and check expiry/purpose at consumption time. Preserve non-consuming approval-page previews and existing public unknown/expired/consumed responses without exposing account existence. Inspect every caller of the generic consume helper.

Do not blindly replace device-enrollment's inspect/bind/consume sequence: its Redis binding and Postgres link are separate stores, and lost-response recovery must remain possible for the same proven installation. Any change there needs an explicit recoverable claim/result contract and its own scenarios; the bounded fix here covers the generic web sign-in/confirmation consumption race. Tests: concurrent claims yield one winner/session, wrong purpose, expiry at the boundary, consumed link and confirmation failure. Run a real isolated Postgres concurrency test as well as the fake store test.

## Acceptance and delivery

Adopt the real-worker and atomic link-consumption regressions above. Assert persisted models and single-use outcomes. Delivery/History audit cases T03/T08/T10 and relevant T16 cases follow their moved 3.6.0 owner; this plan retains Watch airplane-mode/relaunch and isolated Postgres concurrency QA. Existing audio/receipts and user-configured private-mode exports stay intact.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

Rollback: decode old Watch ledgers and preserve pending audio/jobs. Outbox rollback belongs to the 3.6.0 plan. Keep R8 session/confirmation response shapes and device-enrollment recovery contract. [Original evidence](../archive/reliability-follow-up-plan.md).
