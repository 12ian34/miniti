# Remaining reliability: Watch retries and single-use links

Local implementation update (2026-11-04): the selected 3.8.0 changes are present in the working tree. The [release evidence](../releases/3.8.0-evidence.md#local-implementation-evidence) owns commands, results and remaining manual/runner gates. This does not change the released 3.7.0 baseline or authorize publication.

Status: selected for next-release planning by Ian on 2026-11-04, implemented locally, automated validation recorded; manual/runner gates remain. Version: 3.8.0, assigned by Ian on 2026-11-04. The [roadmap](../roadmap.md#next-release-after-370) owns priority; the [combined checklist](../releases/3.8.0.md) coordinates scope, decisions and evidence. This file owns the complete implementation contract.

## Deliverable and boundary

Finish R4 and R8 in the planned release after 3.7.0. R5–R7 moved to the 3.6.0 [sync/delivery plan](sync-and-delivery-reliability.md) on 2026-10-30; that plan is their sole implementation owner. R1, narrowed R2 and R3 already shipped; the wider AI-consent audit is deferred, not silently re-added here.

## Prerequisites and decisions

Preserve 3.4.0 authorization generations, permission guards and sync fences. R5/R6 ordering is now owned by the 3.6.0 plan. R8 needs a real isolated Postgres concurrency test. No ownership migration or unrelated settings redesign.

## Implementation contract

### R4: Watch retry scheduling

`WatchImportService.kick` selects both queued and waiting-for-minutes jobs, then calls itself after every run. `retryLater` sets queued, so an offline failure immediately retries; exhausted minutes repeatedly request grants until another refusal can turn the job into failed.

Persist retry eligibility (attempt count and next eligible time, with backward-compatible ledger decoding). Use bounded backoff for transient failures; network recovery or activation can trigger an eligibility check, not bypass the delay unconditionally. Waiting-for-minutes is blocked until an entitlement/usage change or explicit retry. Continue eligible independent jobs instead of selecting the same blocked first job. Coalesce timer/activation/file-arrival/manual triggers into one worker. Keep audio, receipts and the existing saved-meeting duplicate guard intact; avoid spinning in the background. R2's permission block is a separate reason to wait.

Tests: offline immediate failure makes one attempt until eligible; persistent limit makes no loop; a blocked first job does not starve a runnable second; relaunch preserves eligibility; simultaneous triggers run one job; manual retry is bounded; no duplicate meeting or duplicated session-end charge after recovery. Exercise the actual importer with injected clock, grant/transcription transport and receipts. Real iPhone QA includes airplane mode, exhausted minutes, relaunch and foreground/background transitions.

### R5: coalescing an in-flight webhook

Delivered in 3.6.0: [sync/delivery R5](sync-and-delivery-reliability.md#r5-immutable-in-flight-webhook-completion-identity) owns the fix and held-sender tests. R5 and R6 shipped together. This anchor remains for historical links; do not implement a second competing outbox design here.

### R6: useful manual webhook retry

Delivered in 3.6.0, with device waivers retained in its release record: [3.6.0 resend contract](sync-and-delivery-reliability.md#r6-resend-the-current-saved-meeting) owns the production-body rebuild, new delivery identity, error states and tests. Do not revive bodyless terminal items here.

### R7: History responses belong to the request's revision

Delivered in 3.6.0, with device waivers retained in its release record: [3.6.0 response-authority contract](sync-and-delivery-reliability.md#r7-history-responses-belong-to-their-input-revision) owns revision/generation checks and the saved-model/export regressions. This anchor preserves old links.

### R8: atomic single-use link consumption

Reproduced from production `loginLinks.ts`: two concurrent `consumeLoginLink` calls both return success because lookup and unconditional update are separate operations.

Add a store operation that atomically claims an unconsumed, unexpired row of the expected purpose and returns it, using conditional `UPDATE ... RETURNING` in Postgres. Only that winner can issue the web session or perform email confirmation. Match semantics in the in-memory store and check expiry/purpose at consumption time. Preserve non-consuming approval-page previews and existing public unknown/expired/consumed responses without exposing account existence. Inspect every caller of the generic consume helper.

Do not blindly replace device-enrollment's inspect/bind/consume sequence: its Redis binding and Postgres link are separate stores, and lost-response recovery must remain possible for the same proven installation. Any change there needs an explicit recoverable claim/result contract and its own scenarios; the bounded fix here covers the generic web sign-in/confirmation consumption race. Tests: concurrent claims yield one winner/session, wrong purpose, expiry at the boundary, consumed link and confirmation failure. Run a real isolated Postgres concurrency test as well as the fake store test.

## 3.8.0 retry policy and link-consumer matrix

### Watch scheduler

Persist `attemptCount`, `nextEligibleAt`, `lastFailureKind` and an owner reference when a job first obtains a managed grant; decode older ledgers with zero attempts/no deadline. Transient pre-completion failures use 5, 15, 60 and 300 second delays, then 300 seconds up to eight automatic failed attempts. After the eighth, retain audio and show a retryable failed state. Honor a later valid Retry-After. Success at a durable stage resets that stage's failure count. Inject the clock; no sleeping tests.

One worker and one foreground wake timer select the oldest eligible complete job. A blocked first row never hides later eligible work. Activation, new files and network recovery re-check eligibility without bypassing it; there is no background polling loop. iOS suspension may delay work until the next permitted activation. A wall-clock change never causes an immediate busy loop; retain a minimum five-second delay after a transient failure and cap a restored future deferral to five minutes unless it is a valid server Retry-After.

Minutes exhaustion and absent permission wait for a relevant observed state change or an explicit retry, not the timer. Explicit retry performs one eligibility attempt and then obeys the same limits; coalesce repeated taps and apply a five-second minimum between user-triggered attempts. Permission must actually be granted before sending audio. A changed usage snapshot only wakes quota-blocked jobs when admission may have improved, not on every polling response.

Persist the session-end report/receipt before clearing a session reference; save the imported meeting and its recording-ID duplicate guard before declaring completion or deleting audio. Resume failed summaries without retranscribing/recharging saved audio. Owner changes pause or terminate an old managed grant safely; never bill the current account for a previous owner's in-flight work. Do not invent provenance for an old queued job that has never obtained a grant. Test crash boundaries after grant, transcription, meeting save, report enqueue and receipt delivery. This extends existing R4 save/charge-once acceptance; it does not introduce a new Watch wire protocol.

### Link operations

| Caller / purpose | 3.8.0 contract |
|---|---|
| `/signin`, `web_signin` | Atomic conditional claim by token digest, purpose, unconsumed state and expiry. Exactly one winner may issue a web session. |
| `/signin/confirm`, `confirm_email` | Same claim before email confirmation. Conflicting ownership keeps the existing error and never transfers another account's email. |
| `/signin/approve` deny, `device_enroll` | The generic consume helper is also called here. Preserve refusal and use atomic claim semantics; test a refusal racing an approval. |
| `/signin/approve` approve | Conditional approval only while the expected-purpose row is unconsumed/unexpired. A losing approval must not display success after refusal. Preview GET remains non-consuming. |
| `clientAuthStore` restore/attach and `consumeLoginLinkById` | Preserve existing inspect/bind/consume and same-proven-installation lost-response recovery. Do not replace this cross-store path with generic consume-before-bind. |

Add the conditional claim/approve methods to both Postgres and memory-store interfaces. Use Postgres `UPDATE ... WHERE ... RETURNING`, with expiry checked at execution, not only at an earlier lookup. Avoid SQL transaction assumptions across Redis/Postgres. A generic claim that wins but fails during session issuance or email confirmation stays consumed; show a recoverable failure and let the user request a fresh link. Never automatically unconsume it. A lost response must not issue a second session on replay; do not claim atomic delivery of the browser cookie itself.

Real Postgres tests send concurrent claims, check one session-issuance/confirmation side effect, and cover expiry, purpose mismatch, refusal/approval, side-effect failure and replay. Preserve safe unknown/expired/consumed copy without account enumeration. Device binding regression tests must prove unchanged same-installation retry behavior; a broader cross-store enrollment redesign is outside 3.8.0.

## Next-candidate integration

Revalidate R4 against `MinitiMobile/WatchImportService.swift` and R8 against current `loginLinks.ts` and all its callers before implementation. List generic sign-in/confirmation and device-enrollment consumers separately. Stage 1 [metering](managed-reconnect-metering.md) must retain prerecorded Watch duration semantics and save/charge-once behavior. Stage 3 [account access](account-access.md) supplies the signed-out/revoked and permission states the importer must respect; neither quota nor permission failures are ordinary timed retries. The [combined checklist](../releases/3.8.0.md) owns integrated validation and rollout.

## Acceptance and delivery

WR1 and LK1 also own their [3.8.0 audit](../releases/3.8.0-planning-audit.md) rows: queue/timer and indexed-claim bounds, truthful rendered Watch states, affected public docs and screenshot retention/replacement. Record measured results and real-store concurrency evidence; planning bounds are not test results.

Adopt the real-worker and atomic link-consumption regressions above. Assert persisted models and single-use outcomes. Delivery/History audit cases T03/T08/T10 and relevant T16 cases follow their moved 3.6.0 owner; this plan retains Watch airplane-mode/relaunch and isolated Postgres concurrency QA. Existing audio/receipts and user-configured private-mode exports stay intact.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

Rollback: decode old Watch ledgers and preserve pending audio/jobs. Outbox rollback belongs to the 3.6.0 plan. Keep R8 session/confirmation response shapes and device-enrollment recovery contract. [Original evidence](../archive/reliability-follow-up-plan.md).


WR1 ninth-review implementation: complete saved parts bypass a new grant; receipt-based unused sessions settle zero; Dismiss retains owed receipts until durably queued. Full-worker cancellation/resume/BYOK coverage is included. Corrupt checkpoints remain explicit recovery cases with audio retained. See the [build 155 disposition](../releases/3.8.0-evidence.md#ninth-review-corrections-and-testing-distribution-2026-11-06).
