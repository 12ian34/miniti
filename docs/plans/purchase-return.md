# Return to miniti after buying Pro

Status: delivered on macOS in 3.5.0 build 142 on 2026-10-30, with backend and website deployed. iOS StoreKit is unchanged. This is the implementation record, not future build scope. [Release evidence](../releases/3.5.0.md) records Ian-reported QA and its limits; [roadmap](../roadmap.md) owns subsequent work.

## Deliverable and boundary

B6d: a verified Polar purchase returns through an HTTPS confirmation page to Account in the app. License keys remain a fallback. No ownership migration, entitlement policy change or new purchase rail.

## Prerequisites and decisions

Works independently of B1 using the existing entitlement contract; it must not promise durable ownership before B1. Polar callback/correlation support was checked against its primary API documentation before implementation. Coordinate miniti-api, minitidotapp and Linux.

## Implementation evidence and remaining gates

See the [QA handoff](../releases/monitoring-cloud-purchase-qa.md) for tested behavior, exact remaining checks and deployment order, and the [local code contract](../reference/monitoring-cloud-purchase.md) for file ownership and compatibility. Implementation is delivered; the release record supersedes earlier local-only status. Ian reported device QA good as a group, not an itemised independently observed run. Preserve those evidence limits and iOS availability separately.

## Implementation contract

#### B6d: return to miniti after buying Pro

**Approved 2026-10-27; built on 2026-10-29 and shipped on Mac with backend/site on 2026-10-30.** Charlie reported that buying Pro ends with a license key instead of a return to the app. This was delivered separately from the ownership migration. It can be implemented before B1; it must not claim to solve device-held subscription ownership or change account membership.

**Pre-implementation baseline (historical):** `miniti-api/lib/polar.ts:createCheckoutSession` passes the product and `external_customer_id` but no `success_url`. The webhook already links active purchases to the buying device. `AppState.openSubscribePage` opens checkout in the browser; `MinitiApp` has no billing return handler. A purchase begun in the app should not require manual license-key entry. Polar supports `success_url` with a checkout-id placeholder ([checkout API](https://polar.sh/docs/api-reference/checkouts/create-session)).

**Flow and contract:**

- Return to a fixed HTTPS confirmation page on miniti.app with **Open miniti** and instructions if the app is absent or too old. Use an explicit button so browser restrictions cannot strand the customer. Keep the receipt/license key as a restore fallback.
- Register a billing-specific callback, support warm and cold app launch, and open Settings, Account. Never put license keys, access tokens or recovery keys in the URL. The callback only requests a status check; it never grants Pro or triggers attach, restore or account switching.
- Capture attribution when checkout starts. Any checkout-status endpoint must authenticate the caller and verify that the checkout belongs to the installation and captured account, without exposing arbitrary checkouts by id. Verified backend payment/subscription state is authoritative; browser query parameters are untrusted.
- Show **Confirming your purchase…** while the webhook is pending, with one bounded refresh task (at most 30 seconds, respecting throttling). Once entitlement is confirmed, show **Pro is ready** and refresh the plan/allowance. Pending, failed, cancelled, offline and timed-out checks need honest states and a Retry action. Never loop forever, start another purchase or activate a license key automatically.
- Bind pending tasks and responses to the account and credential generation that started them. Sign-out/account switch cancels checking and prevents stale results from being applied. A return for another account asks the person to sign in to the purchasing account; it never transfers the purchase. B1 still owns the ownership migration and server-side checkout-during-transfer guarantees.
- Older clients retain the HTTPS page and instructions to reopen miniti or use existing restore. iOS keeps StoreKit's in-app purchase flow. Record the shared backend/page contract for Linux in B7 before deployment; use a platform-appropriate app link, never a macOS-only link for every buyer.

**Implementation surfaces:** backend checkout creation and any authenticated status route/tests; minitidotapp confirmation page and fallback; macOS URL registration/app delegate, AppState purchase/usage state, Account status UI and tests. No changes to license validity, prices, device caps or existing subscription owners.

**Regression and QA gates:** immediate/delayed webhook; warm/cold launch; duplicate callback coalescing; fabricated/foreign checkout; cancelled/unpaid checkout; offline, timeout and throttling; sign-out and A-to-B-to-A during a held check; absent app/old client; existing license restore; Linux fallback; iOS StoreKit unchanged. Use Polar's test environment. Confirm Pro only after server verification, then run both Apple bundles and affected backend/page checks before release.

## Acceptance and delivery

Run the callback/account-generation, webhook-delay, foreign checkout, absent/old app, throttling and offline scenarios above in the provider test environment. Check warm and cold macOS launch and Linux fallback. iOS retains StoreKit.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

Rollback: keep the HTTPS receipt/restore instructions functional; turn off the new app callback/status flow without altering purchases. [History](../archive/enrollment-identity-plan.md).
