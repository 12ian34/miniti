# Account ownership cutover: re-plan

**Superseded on 2026-11-16 by [the simple version](account-ownership-simple.md), which Ian adopted the same day.** Kept as the record of the first plan and of Astra's two reviews of it. What carries over: existing subscriptions get their owner from a table a person reviews, the production counts, and the decisions about owners. What does not: steps R1 to R9, the transition protocol (floors, waiting purchases, commit scripts, the 48-hour window), provider-time ordering and the usage ledger. Do not build from this file.

2026-11-15, reviewed with Ian on 2026-11-16. The [3.11.0 checklist](../releases/3.11.0.md) owns slices, stages and gates; this file owns the cutover approach and steps R1 to R9. Replaces the cutover and backfill parts of [account ownership § B1](account-ownership.md#b1-subscriptions-owned-by-the-account-miniti-api). The ownership rules themselves (one owner per purchase, fixed at first bind, no merging, coexisting rails) do not change. Nothing here is built or deployed.

## Status

| Item | State |
|---|---|
| Release split | Decided (Ian, 2026-11-15): 3.10.0 ships the non-ownership work; account ownership moves to 3.11.0. 3.10.0 shipped on Mac on 2026-11-16 |
| 3.11.0 scope | Subscriptions, usage and account lifecycle (Ian, 2026-11-16). Connections, meeting copies, CK1, HP1 and RG1 moved to 3.12.0 the same day. [Checklist](../releases/3.11.0.md) |
| Production inventory, counts only | Done 2026-11-15, read-only, nothing stored. Repeated on 2026-11-16 from raw records with Polar's list and one App Store Server API read; rows kept in a private file outside the repository |
| This plan | Reviewed with Ian, 2026-11-16: approach, order and the points below accepted. Astra reviewed the plan the same day and asked for a bounded re-plan before code: the reviewed table is kept, the live transition around it was not specified. The [transition protocol](#transition-protocol) below is that re-plan. Astra's re-check the same day: ready after named fixes; those fixes are in the protocol as it now reads, and the R0 design note must settle the points marked for it before any subscription code |
| Code | Not started, except a first read-only export script (untracked in `../miniti-api`). Backend branch `ao2-account-subscriptions` (head `f66ace8`) holds the earlier attempt; what to keep and delete is listed below |

## Why the first attempt did not converge

Seven reviews each found serious defects in a new place. The cause was the same every time: the code tried to work out, by itself and while the service was running, who owned each existing subscription and in what state, from device records that were never built to answer that. Each fix (read both spellings, a reverse set, a frozen inventory, a maintenance window, a one-way switch) closed one gap and opened another.

## What production actually holds

Read on 2026-11-15 from the admin device list. Counts only; no identifier was kept.

| | Polar | App Store |
|---|---|---|
| Subscriptions named by any device record | 6 | 5 |
| Held by exactly one account | 6 | 5 |
| Held by two or more accounts | 0 | 0 |
| Held only by devices with no account | 0 | 0 |
| Devices disagreeing on status or period | 0 | 0 |
| Status | 6 active | 4 active, 1 expired |

Also: 798 device records for 546 devices (252 devices have both spellings), 256 accounts, 3 accounts with more than one device, no account with two active subscriptions on one rail. 291 records have no account; none of them holds a subscription.

So the whole problem of inferring owners is eleven rows, and every row is unambiguous today.

Read again on 2026-11-16, this time from device records, installation records and reverse sets directly, compared with the providers:

- Still 11: 6 Polar, 5 App Store. Each is held by exactly one account. No device names both rails, no account holds two active subscriptions.
- Polar's own list has the same 6, all active, and no other subscription, active or ended. No subscription exists only in a reverse set. So nothing is hidden today.
- One Polar subscription is also named by two signed-out devices that have no account. Its owner is still the one account; the two devices must end up granting nothing (a test in R8).
- One App Store row is an expired sandbox purchase. Recommended left out of the table.
- The App Store Server API key works: one status read for a production transaction returned 200.
- 803 device records for 548 devices, 255 with both spellings, 259 accounts with a device.

## The new approach

**Existing subscriptions get their owner from a table a person reviewed, not from code.**

1. **Export.** A read-only script lists every subscription a device record names, with the one account that holds it, its status and period. Eleven rows today. Kept outside the repository.
2. **Review.** Ian looks at the table. Anything not held by exactly one account is decided by hand.
3. **State from the provider, not from device fields.** For each Polar row, read the subscription from Polar (status, period, its own modification time). For each App Store row, read Apple's status for the transaction from the App Store Server API (the key was verified on 2026-11-16; sandbox rows use the sandbox host). A row the provider cannot answer for is not applied; it goes back to Ian. The earlier fallback, writing the held status with no time, is removed.
4. **Apply once.** A one-shot operator script binds each row with the existing binding script. It re-reads each row immediately before binding and stops if anything changed since the review (a different holder, a second holder, a different status).
5. **A purchase is new only if the provider shows it started after the boundary** (the instant the cutover begins, stored once). A new purchase is owned by the account that started its checkout, or by the account that presents it. A purchase that started before the boundary and has no record is never bound by code: it waits, with no owner, for a reviewed row. See the [transition protocol](#transition-protocol).

**What this removes:** the inventory, the legacy owner rule, the old "contested" and "waiting" records that code tried to resolve by itself (the waiting entry in the transition protocol is a different thing: it holds no owner and only a reviewed row settles it), the backfill's two phases, the maintenance window, the reset path, and reading device fields to initialise a record. None of it is needed for eleven known rows, and it was where every review found its defects.

**What stays from the first attempt** (reviewed repeatedly, no open finding):
- the binding script: owner fixed at first bind, every deciding check inside the write;
- ordering of states by the provider's own time, with an ended state standing against an untimed or equal-time activation;
- one lock per subscription for the record and the device fields;
- reconciliation and the ops check;
- the random sequence test, reduced to the rules that remain.

## Order of work

Nothing is switched on until the step before it is accepted. Reviews are in bulk at the four points in the [checklist](../releases/3.11.0.md#delivery-order-and-dependencies), not one per step. Canonical device records (AO1) are merged and activated before R1, by Ian's decision of 2026-11-16, so the billing branch starts from a `main` that has them.

| Step | What | Why here |
|---|---|---|
| R1 | The update-required gate for old apps on account changes (attach, email join, restore into an account, new account on a signed-out device id), with Apple client tests. Linux is refused by decision (2026-11-16) and gets no client work | The original plan puts this before the writers. Without it a device that moves still carries Pro. The seventh review reproduced that |
| R2 | Writers keep the record beside the device fields: webhooks, verify, restore. No legacy rule and no guess: the [first-bind rule](#the-first-bind-rule) decides, and a purchase from before the boundary waits for a reviewed row | Small once the inference is gone |
| R3 | The export script and the one-shot apply script, rehearsed on a copy of production data | The cutover itself |
| R4 | One-way parts follow stored state, not the flag: dormancy and checkout capture | Sixth and seventh reviews: turning the flag off could delete an owning account |
| R5 | Requests on the old shared key: no purchase can be gained or refreshed once ownership is in force. Decided 2026-11-16: count shared-key requests for 7 days, then refuse the shared key on all platforms before the cutover. Two signed-out devices with no account still name a subscription (above) | Seventh review: shared-key refresh bypassed ordering |
| R6 | Crash and retry tests on real storage for the record, the device fields and the delivery mark | The reviewer's sign-off list |
| R7 | Set the boundary, export, Ian reviews, apply the table, then reconciliation clean for 24 hours | Ian's go-ahead |
| R8 | Pro read from the account's records | Last, as before |
| R9 | Usage ledger, on the accepted minutes-window model, in its own short pause after account changes have reopened | After ownership is settled |

Lookups per account and dormant accounts do not depend on any of this and can go out separately once reviewed on their own.

## Transition protocol

Added 2026-11-16 after Astra's plan review. It fixes what the table alone did not: who may bind while the table is being applied, what is stored when each one-way step happens, how a state read at apply time orders against later provider events, and which writes change an account's members. Nothing here is built. The design notes R0 and R9.0 in the [checklist](../releases/3.11.0.md#work-packages-and-slices) turn this into exact keys and scripts, and Astra reviews them before any code.

### One stored record of how far the cutover has gone

One key holds the ownership state. It is changed only by an operator command that names the revision it expects, so two operators or a retried command cannot both win.

| Field | Meaning | Rule |
|---|---|---|
| F1 boundary | The instant the cutover began. The gate is on and the first-bind rule below is in force | Set once, never cleared or moved |
| F2 table applied | Every reviewed row is bound or excluded and nothing is waiting | Needs F1 |
| F3 Pro from the account | Entitlement is read from the account's records | Needs F2 and 24 clean reconciliation hours |
| FD dormancy | An emptied account is kept, not retired | Any time; required before F4 |
| F4 account changes open | A compatible app may change account again; contract 1 | Needs F3 and FD |
| F5 ledger | Minutes are charged to the account's ledger | Needs F4, set inside its own short pause |
| paused | Account changes are refused for now | On or off at any time after F1; changes nothing else |
| revision, contract | A number that moves with every change; the contract the apps were built for | |

Floors only move forward. No code path clears one, and no flag overrides one: flags make code reachable, the floors decide behaviour. A pause never changes which floors apply, so a redeploy during a pause reads the same answers as before it. What an app is told is derived: no F1 is `legacy`; F1 without F4 is `preparing`; F4 is `account_v1`, with `usage` saying `device` until F5 and `account` after; `paused` is reported on top while the pause is on.

Builds: the code that reads this record (stage D5 in the checklist) must be the only build serving for at least 10 minutes before F1 is set, as in the device-record activation. After F1, no build older than D5 is ever redeployed or rolled back to; the runbook lists the allowed builds per floor.

### Where each check happens

A check that decides must be inside the write it protects. Today a membership change is several separate writes under a lock: attach adds the device to the destination's member set, then rewrites the installation, then removes it from the source's set, then updates the device's account field; create writes the recovery mapping and the account before the installation; repair runs the full installation writer; revoke does several cleanups one by one. Guarding only the installation write is not enough: a refusal there would leave a member-set entry behind, and a stop after it would leave the source set and the device field stale.

So for each transition R0 names the complete set of writes that is the transition (the installation record, both member sets, the device's account field, and the account and recovery mapping where the transition creates them) and commits that set in one script. The floor and revision check, the account's status and the device cap are checked in the same script. Anything done afterwards (revoking old tokens, removing accounting identity, clearing capabilities) carries the committed transition's number and does nothing if the membership has changed again since. A request admitted before F1 that reaches its commit after F1 is refused there, having written nothing, and can be retried. The table apply and the ledger seed each hold a lease and pass the revision they started under; any of their writes is refused once the revision has moved.

### Every write that changes who belongs to what

Read from `lib/clientAuthStore.ts` and the routes on backend `main` (`f81d321`). The enrolment functions branch on four facts, so the rule is given per combination, not per route. R0 turns every row into a test at each floor.

Enrolment (`createAccount`, `migrateLegacyDevice`, `restoreAccount`, `restoreAccountByEmailLink`):

| Installation for this device id | What the recovery key or link resolves to | What it is | From F1 until F4, or while paused | From F4 |
|---|---|---|---|---|
| Active, same account, same key | that account | A lost reply replayed. No membership change. It does issue tokens and can use up an email link | Allowed, every app version | Allowed |
| Active, same account, new key | that account | Same-account repair. No membership change, but it rewrites the installation, the member set and the device fields and revokes the old tokens | Allowed, every app version. Decided in the commit from the installation record and member set, never from the request. Refused if the account is deleted | Allowed |
| Active, another account | any | Refused today (`device_already_enrolled`) | Unchanged | Unchanged |
| None, and no device record | nothing yet (new account) | A new device starts | Allowed, every app version | Allowed |
| None, but a device record exists (an old shared-key device, through create or migrate) | nothing yet (new account) | First enrolment. The device gets its own new account; nothing moves between accounts. A purchase it names waits for a reviewed row; its minutes are its own | Allowed, every app version | Allowed |
| None or revoked | an account that has members | Create and migrate refuse today (`recovery_key_in_use`); restore joins the account | Join refused: update required for old apps, not ready for 3.11.0 | Join allowed for 3.11.0 and later |
| None or revoked | an account with no members | Today create and migrate "resume" into it. With dormant accounts this is a device joining an existing account by its recovery key | Refused like a join, unless the account was created by this same device's interrupted create and never had a member (R0 stores what proves that) | Allowed for 3.11.0 and later |
| Revoked | nothing yet (new account) | A new account on a signed-out device id | Refused, same answers | Allowed for 3.11.0 and later; the old account keeps everything |

A revoked installation keeps its old account id, and the device record keeps its account field. Neither counts as membership anywhere: a device belongs to an account only while its installation is not revoked and it is in that account's member set. The export, the seed and every reader use that test.

Other writes:

| Write | Callers | From F1 until F4, or while paused | From F4 |
|---|---|---|---|
| A device moves to another account | `attachInstallation`, `attachInstallationByEmailLink` | Refused: update required for old apps, not ready for 3.11.0 | Allowed for 3.11.0 and later |
| A device leaves (sign-out, removal from another device) | `revokeInstallation` | Allowed. Owner of any purchase does not change | Allowed |
| Account deletion | `deleteAccount` | Allowed. Its records are marked so they grant nothing; no billing call | Allowed |
| Tokens, challenges, recovery key rotation, adding an email, web sign-in, cloud switch | their routes | Not membership; unchanged | Unchanged |
| A purchase shown or changed | checkout start and return, licence restore, App Store verify, both webhooks | The first-bind rule below; never refused by app version | Same rule |
| Operator edits | admin device edits, complimentary Pro | Label and disable unchanged. Complimentary Pro is per account and unchanged. A minutes edit goes to the ledger once the account is on it. No admin edit changes a purchase's owner; only the reassign tool does, with an audit record | Same |

### The first-bind rule

A purchase has one identity and one start that never change: for Polar the subscription id and the time the subscription was created; for Apple the original transaction id and its original purchase date. A renewal, a resubscription or a plan change that keeps the same identity keeps its record and its owner. A later period, activation or renewal date is never used as the start. R0 writes this contract per provider and tests it with renewal, resubscription after expiry, plan change, refund and revocation.

For any purchase event or presentation, inside one script per purchase:

1. A record exists: its owner never changes. The state is updated by the ordering rule below. A presenter that is not the owner gets `409 subscription_owned_elsewhere` and no device field is written for it.
2. No record, and the provider's own signed data shows the purchase started more than one hour after F1: bind it as new. The hour is a margin for clock difference between this backend and the providers; R0 confirms it is ample or widens it.
3. No record, and it started before that, at exactly that instant, or the start cannot be proven: do not bind. Write a waiting entry for the purchase with who presented it and when, and a counter that moves with every new presenter. An ops check warns while any entry waits.

While a purchase waits, a presentation does not become evidence and does not grant anything new. Devices that already named the purchase before F1 keep having their fields refreshed, so the customer who has Pro keeps it. A device that did not name it before F1 gets no purchase fields from a waiting purchase. So the export taken after F1 shows only holders from before F1, and another account cannot gain Pro, even for a day, by presenting someone else's purchase during the window.

Waiting entries are settled only by a reviewed row. F2 and F3 cannot be set while one waits. After F3 a purchase with no record grants nothing through any reader, including the owner-filtered fallback; one that appears later (for example an old purchase the backend never saw) warns the operator the same hour and is settled by a supplemental reviewed row through the same tool. "Applied once" means each purchase is bound once, not that the tool runs once.

### Applying the table

1. F1 is set. Only then is the export taken that Ian reviews. From F1 no device can join another account and no waiting purchase can add a holder, so the export shows the holders from before F1.
2. Each row has a resolution: bind to a live account; bind to a deleted account (the record is written and marked so it grants nothing, which is the decided rule that a deleted account's subscription stays with it); or exclude (recorded with no owner, grants nothing; used for the sandbox purchase).
3. Each row carries what the reviewer saw: the owner account and whether it was live or deleted, and the waiting entry's counter if another account had presented the purchase. One script per row checks, in the same write: F1 set and the revision expected; no record yet, or an identical one; the owner account in the state the reviewer saw; the waiting counter unchanged. The provider's state is read just before and passed in.
4. If any of that changed, the row is refused, having written nothing, and goes back to Ian with the new facts. He resolves it again (for example confirming the original owner although another account presented it, or binding to the account that has since been deleted) and the new row satisfies the same check. No check is bypassed and no floor is cleared. What was presented and refused is kept for audit.
5. A refused row stops the run. Rows already bound stay: they are correct and immutable. A second run skips them and changes nothing.
6. The review covers who owns the purchase. A renewal or a status change between review and apply does not refuse the row, because state is taken from the provider at apply.

### Ordering provider events

Not established yet. This is the proposal R0 must prove or replace before any writer is built.

Proposal: every stored state carries the provider's own time for it (Polar: the subscription's `modified_at`; Apple: the signed date of the object the status came from). A state replaces the stored one only if its provider time is later; a state with no provider time never replaces a timed one. When this backend observed or received something is recorded for diagnostics and never used to order.

What the source shows is missing today: the Polar adapter returns neither `modified_at` nor the subscription's start, and the webhook reads the start but not `modified_at`; Apple notification decoding verifies the renewal information but does not expose its signed date, and takes the status from the notification type. And a later signature is not by itself proof of a later subscription-wide status: an expiry notice, a refund notice and a status read can each take their status from a different signed object.

So R0 must write down, per source (Polar webhook, Polar read, Apple notification, Apple verify or restore, Apple status read): which object the status comes from, which time on it orders it, whether that time is available, what happens at equal times and why that is safe, and how a record wrongly marked ended is healed. The reconciliation pass re-reads every record that is not excluded, ended ones included, not only live ones. Sandbox fixtures cover a late older event, an older activation after an end, a renewal after an end, a refund and a revocation, with separate provider, signing, observation and delivery clocks.

The alternative R0 weighs against it: treat every event only as a trigger, and take the state from a provider read made under the purchase's lock, so nothing delivered is ever ordered. Its risk is a provider read that lags its own webhook. If neither can be shown safe on sandbox purchases, the plan returns to review before any writer is built.

### The ledger, in its own pause

The ledger is not seeded in the first window. Account changes open at F4 with `usage: device`: minutes still follow the device, and the app says so. The ledger then gets a short pause of its own: pause, seed, set F5, resume with `usage: account`. If the ledger is late, the first window is not held up, and no app change is needed.

The rule in one line: **before an account is seeded, a device's minutes follow the device; after it is seeded, every charge needs an account it is attributed to.** Before the seed that is today's behaviour, including its two known effects: a device that leaves takes its minutes out of the account, and a device that moved from A to B between S4 and S5 brings its minutes into B's opening amount. Both are accepted and stated in the app's `usage: device` wording. After the seed neither can happen.

Every writer of quota minutes, read from source. R9.0 adapts each one:

| Writer | Today | For the ledger |
|---|---|---|
| Finalize of a recording (`FINISH_ACCOUNTING_LUA`, `lib/managedAccounting.ts`) | Charged once, at finalize, in one script that touches the device record. The recording's record names the account it started under | Charge that account's ledger if it is seeded, else the device as today, decided in the same script |
| Legacy session end (`finishLegacyAccounting`, `lib/legacyAccounting.ts`) | Its script checks the session's device and start time, not a start account. An end arriving after the device moved can be accepted for the new account | Store the account at session start, from stage D5 on. Charge that account. An end whose session has no stored account is refused once its device's account is seeded, never charged to whoever is signed in |
| Prerecorded session (Apple Watch, `session/prerecorded`) | Stores no account | Same as the legacy end |
| `incrementUsage` (`lib/usage.ts`) | Exported; no production route was found calling it | Removed, or routed like the others |
| Operator minutes edit | Sets the device counter | A correction on the ledger once the account is seeded |
| Local-duration reporting (`lib/recordingUsage.ts`) | Statistics only, not quota | Not part of seeding; stated so it is never counted |

What R9.0 must define, beyond the writers:

- **Each account has its own state, unseeded or seeded, and every reader follows it.** An unseeded account's usage is the sum of its member devices, as today. A seeded account's usage is its ledger. F5 only says that every account is seeded and changes what the apps are told; no reader depends on F5 itself, so a pass that is half done reads correctly.
- **Seed.** One script per account reads each member device's minutes and its period counter (`usageEpoch`), writes the opening amount, records on each device that its counter for that period was used by this seed, and writes a receipt. A charge lands wholly before or wholly after it. A second seed returns the receipt and writes nothing.
- **Charges are routed by the session's account, not by a mark on the device.** After a device leaves seeded A and joins seeded B, its old counter is a source for nobody (the mark says that period's counter was already used), and its new recordings start under B.
- **Accounts created after F5** are seeded in the write that creates them. The pause ends only when no account with a device is unseeded.
- **A period reset racing the seed** is on one side or the other, because the reset also writes the device record and moves `usageEpoch`; the receipt stores the epoch it read.
- **Receipts** say how long they are kept and what a replay after that returns.

R9.0 writes this out against the accepted minutes-window model and maps each of that model's open requirements (first-paid receipts, owner-filtered snapshots, eligibility by status and grace, stale period refresh, fenced revisions, window identity and replay, counters and state in one write, what old apps are shown, real-storage concurrency) to a slice and a test. Astra reviews the note and its tests before ledger code.

## Decisions recorded (Ian, 2026-11-15)

- **Minutes window:** keep today's behaviour in all five open points (the model's defaults): the purchase in use sets the allowance; a new allowance each month while renewal evidence is missing; a new start more than two days before the period ends is a correction; a paid allowance in use during a free month counts against it; one minutes window when comp covers a Mac beside an App Store subscription.
- **A deleted account's subscription** stays tied to the deleted account. A new account cannot claim it by itself. Support can reassign it by hand; that needs a small operator tool (the owner is otherwise immutable), added to R3.

## Decisions recorded (Ian, 2026-11-16)

- **Device records first.** `ao1-device-records` gets its last review and a rehearsal on a production copy, then is merged and activated before the subscription work.
- **Linux.** Nothing is built. Linux gets the update-required answer on account changes when the gate turns on; the work is filed as issues in the public Linux repository. Mac 3.11.0 public and iOS 3.11.0 available in the store are the only publication conditions for the gate.
- **Shared key.** As in R5 above.
- **The export and the App Store read** were approved and run the same day.

## Open points

Resolved on 2026-11-16: the App Store Server API key is accepted; no subscription exists that no device names; `ao1-device-records` is the base for the ledger and is activated first; the gate is staged in the checklist's stage table. What remains:

- Ian reviews the table on a same-day export before R7 (T-1 in the checklist), including the two notes above.
- The export must not use the admin device list: it shows one rail per device and takes the account from a mirror field. It reads raw records, and the apply script re-reads the same things.

Earlier text, kept for the record and superseded by the transition protocol where they differ. In particular: a reactivated or previously unseen purchase from before the boundary is not a new purchase, it waits for a reviewed row; and no status is ever written without the provider's time.

- App Store Server API credentials: `APPLE_ISSUER_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` are set in production (checked 2026-11-16, names only), but no backend code uses them and they have never been exercised. Whether the key is an in-app purchase key that the App Store Server API accepts is unverified. Step 3 starts with one read-only call for a known transaction; if it fails, the fallback in step 3 applies.
- The admin device list is the source of the counts above. The export script must read the same thing the apply script re-checks, and must look for subscriptions that no device names any more (a cancelled Polar subscription clears its id from the device, so none is visible today; a reactivation of one is then a new purchase by the rules above).
- Row counts will have changed by R7. The procedure does not depend on the number, only on a person reviewing it.

## What happens to the existing branch

`ao2-account-subscriptions` is not merged. For R2, start a new branch from `main` and carry over the files listed under "what stays", without `subscriptionBackfill.ts`'s inventory, `legacyDecision`, `recordFromInventory`, the preparing state and the script arguments that only served them. `ao1-device-records` (one record per device) is separate: the ledger (R9) needs it, the steps before do not. It goes first all the same (decision above), so every later step is written against one record per device.
