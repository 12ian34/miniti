# Account ownership cutover: re-plan

2026-11-15. Draft for Ian. Replaces the cutover and backfill parts of [account ownership § B1](account-ownership.md#b1-subscriptions-owned-by-the-account-miniti-api). The ownership rules themselves (one owner per purchase, fixed at first bind, no merging, coexisting rails) do not change. Nothing here is built or deployed.

## Status

| Item | State |
|---|---|
| Release split | Decided (Ian, 2026-11-15): 3.10.0 ships the non-ownership work; account ownership moves to 3.11.0 |
| Production inventory, counts only | Done 2026-11-15, read-only, nothing stored |
| This plan | Draft, not reviewed |
| Code | Not started. Backend branch `ao2-account-subscriptions` (head `f66ace8`) holds the earlier attempt; what to keep and delete is listed below |

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

## The new approach

**Existing subscriptions get their owner from a table a person reviewed, not from code.**

1. **Export.** A read-only script lists every subscription a device record names, with the one account that holds it, its status and period. Eleven rows today. Kept outside the repository.
2. **Review.** Ian looks at the table. Anything not held by exactly one account is decided by hand.
3. **State from the provider, not from device fields.** For each Polar row, read the subscription from Polar (status, period, its own modification time). For each App Store row, read Apple's status for the transaction if the App Store Server API key is configured; if it is not, write the status the record holds with no time and let the next notification or receipt set it, checking the five rows by eye.
4. **Apply once.** A one-shot operator script binds each row with the existing binding script. It re-reads each row immediately before binding and stops if anything changed since the review (a different holder, a second holder, a different status).
5. **Everything after that is a new purchase**, owned by the account that started its checkout, or by the account that presents it.

**What this removes:** the inventory, the legacy owner rule, "contested" and "waiting" records, the backfill's two phases, the maintenance window, the reset path, and reading device fields to initialise a record. None of it is needed for eleven known rows, and it was where every review found its defects.

**What stays from the first attempt** (reviewed repeatedly, no open finding):
- the binding script: owner fixed at first bind, every deciding check inside the write;
- ordering of states by the provider's own time, with an ended state standing against an untimed or equal-time activation;
- one lock per subscription for the record and the device fields;
- reconciliation and the ops check;
- the random sequence test, reduced to the rules that remain.

## Order of work

Each step is its own review and its own deploy. Nothing is switched on until the step before it is accepted.

| Step | What | Why here |
|---|---|---|
| R1 | The update-required gate for old apps on account changes (attach, email join, restore into an account, new account on a signed-out device id), with Apple and Linux client tests | The original plan puts this before the writers. Without it a device that moves still carries Pro. The seventh review reproduced that |
| R2 | Writers keep the record beside the device fields: webhooks, verify, restore. No legacy rule: a purchase with no record is new | Small once the inference is gone |
| R3 | The export script and the one-shot apply script, rehearsed on a copy of production data | The cutover itself |
| R4 | One-way parts follow stored state, not the flag: dormancy and checkout capture | Sixth and seventh reviews: turning the flag off could delete an owning account |
| R5 | Requests on the old shared key: no purchase can be gained or refreshed once ownership is in force. None of the 291 account-less records holds one | Seventh review: shared-key refresh bypassed ordering |
| R6 | Crash and retry tests on real storage for the record, the device fields and the delivery mark | The reviewer's sign-off list |
| R7 | Apply the table in production, then reconciliation clean for 24 hours | Ian's go-ahead |
| R8 | Pro read from the account's records | Last, as before |
| R9 | Usage ledger, on the accepted minutes-window model | After ownership is settled |

Lookups per account and dormant accounts do not depend on any of this and can go out separately once reviewed on their own.

## Decisions recorded (Ian, 2026-11-15)

- **Minutes window:** keep today's behaviour in all five open points (the model's defaults): the purchase in use sets the allowance; a new allowance each month while renewal evidence is missing; a new start more than two days before the period ends is a correction; a paid allowance in use during a free month counts against it; one minutes window when comp covers a Mac beside an App Store subscription.
- **A deleted account's subscription** stays tied to the deleted account. A new account cannot claim it by itself. Support can reassign it by hand; that needs a small operator tool (the owner is otherwise immutable), added to R3.

## Open points

- Whether the App Store Server API key is configured, which decides how the five App Store rows get their state (step 3).
- The admin device list is the source of the counts above. The export script must read the same thing the apply script re-checks, and must look for subscriptions that no device names any more (a cancelled Polar subscription clears its id from the device, so none is visible today; a reactivation of one is then a new purchase by the rules above).
- Row counts will have changed by R7. The procedure does not depend on the number, only on a person reviewing it.

## What happens to the existing branch

`ao2-account-subscriptions` is not merged. For R2, start a new branch from `main` and carry over the files listed under "what stays", without `subscriptionBackfill.ts`'s inventory, `legacyDecision`, `recordFromInventory`, the preparing state and the script arguments that only served them. `ao1-device-records` (one record per device) is separate: the ledger (R9) needs it, the steps before do not.
