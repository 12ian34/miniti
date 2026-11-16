# Account ownership, the simple version: build detail

2026-11-16. Adopted by Ian the same day, with three changes he asked for: the duplicate device records are merged first and as soon as possible, the notice email is back in, and an old purchase the backend has never seen needs no special handling. Astra reviewed this note on 2026-11-16: the pause and the account records are workable, the minutes handling and the hourly repair as first written were not safe, ready after fixes. Those fixes are in the text below and listed under [Astra's review](#astras-review). The minutes design was then replaced, on Ian's suggestion the same day, by one counter per account per billing period that starts from zero at the switch. Astra re-checked the whole note with that design the same day (sound, ready after named fixes), then reviewed it once more with the checklist, audit and roadmap as a set: device-record work can start, and six contract fixes were needed before the ownership code. All of those are now in the text and listed under [the re-check](#the-re-check) and [the final review](#the-final-review). It replaces the [transition protocol](account-ownership-cutover.md#transition-protocol), and the [3.11.0 checklist](../releases/3.11.0.md) is written around it: the checklist has the slices, stages, gates and estimate; this note has the design.

Written at Ian's request for two things at once: the build detail the checklist lacked, and a simpler way to reach the same outcomes for a service with few users.

Everything about today's code below was read from backend `main` (`f81d321`) and the app's `main` on 2026-11-16. Line numbers are from that day; function names are what to trust.

## Contents

1. [The outcomes, unchanged](#the-outcomes-unchanged)
2. [Why it can be simpler](#why-it-can-be-simpler)
3. [What is dropped and what replaces it](#what-is-dropped-and-what-replaces-it)
4. [Backend: storage](#backend-storage)
5. [Backend: who is Pro](#backend-who-is-pro)
6. [Backend: purchases](#backend-purchases)
7. [Backend: the hourly check](#backend-the-hourly-check)
8. [Backend: minutes](#backend-minutes)
9. [Backend: emptied accounts, lookups, old apps](#backend-emptied-accounts-lookups-old-apps)
10. [Backend: what the apps are told](#backend-what-the-apps-are-told)
11. [The switch](#the-switch)
12. [The app](#the-app)
13. [Tests](#tests)
14. [Order, reviews, estimate](#order-reviews-estimate)
15. [Limits accepted](#limits-accepted)
16. [Decisions for Ian](#decisions-for-ian)
17. [Astra's review](#astras-review)
18. [Found while reading](#found-while-reading)

## The outcomes, unchanged

1. Pro belongs to the account. Signing out or changing devices no longer moves or removes it.
2. Minutes belong to the account. A device that leaves does not take its minutes away, and a device that joins does not bring any.
3. An emptied account stays and can be signed back in to.
4. Free accounts get 100 docs lookups per account per month.
5. On iPhone and iPad, Pro comes only from the server. An App Store subscription that belongs to another account says so.
6. An app too old to describe the new rules cannot change account until it is updated.
7. A paid account whose last device leaves gets one email.

## Why it can be simpler

The reviewed plan keeps the service fully live while ownership changes underneath it. Nearly all of its machinery exists for that: one-way floors, a pause state, a first-bind protocol with waiting purchases, commit scripts for every membership write, a 48-hour window with 24 clean hours, provider-event ordering, and a usage ledger seeded while recordings finish.

Production on 2026-11-16: 11 subscriptions, 259 accounts with a device, 3 accounts with more than one device, 47 devices active in a week, about one purchase a month. At that size three cheaper tools do the same job:

- **A short pause.** For about 30 minutes, account changes and purchases answer "try again shortly". Recording is untouched. Inside the pause nothing can race the table, so the protocol for races is not needed.
- **Check everything.** With 259 accounts, the plan of every account can be computed under the old rule and the new rule and compared, in seconds. That replaces 24 hours of watching.
- **Ask the provider.** With 11 subscriptions, an hourly job can re-read each one from Polar or Apple. That replaces ordering delivered events.

And minutes do not need a ledger or any moving of minutes between devices. The account gets its own counter for each billing period, starting from zero at the switch. A counter that never belonged to a device has nothing to carry when a device leaves or joins.

## What is dropped and what replaces it

| In the reviewed plan | Here | Why that is enough |
|---|---|---|
| Canonical device records merged and activated first (AO1) | Kept, and done first, now, as its own piece of work (Ian: as soon as possible). The code exists on `ao1-device-records` | Everything below is then written against one record per device, through that work's helpers. For the few pairs the merge lists as conflicts, today's rule (the larger of the two spellings) still applies |
| Floors F1 to F5, pause state, revisions, leases | One stored mode (`device` or `account`) and a maintenance flag | The switch happens once, inside the pause |
| First-bind protocol, waiting entries, reviewed fingerprints | The table is applied inside the pause. Afterwards a purchase with no record simply belongs to the first account that shows it | Nothing can present a purchase during the pause, and every purchase the backend knows gets its owner inside it. So a purchase with no record afterwards is one nobody held |
| Commit script for every membership write | Unchanged membership code. Each frozen function checks the flag inside its lock, just before its first write, and a three-minute wait lets requests in flight finish | No membership write runs while the table is applied |
| 48-hour window, 24 clean reconciliation hours | About 30 minutes, with a full before and after comparison of every account | The whole population can be checked |
| Ordering provider events by provider time | Events are applied as today, and an hourly job re-reads every subscription from its provider | A wrong state normally lasts about an hour, longer while a provider is down; today there is no check at all |
| Usage ledger, minutes-window model, seeding, a second pause | One counter per account per billing period, read from the subscription record. Everyone starts from zero at the switch (Ian, 2026-11-16) | Nothing to migrate and nothing to move when devices come and go. The per-device counters keep running underneath as before |
| Two go-lives and two wordings for minutes | One go-live, one wording | Minutes and Pro switch together |
| Shared key measured and refused on all platforms | Purchase binding simply needs an account. The wider shut-off stays a roadmap candidate | A shared-key caller has no account, so it cannot own a purchase |
| Notice email when a paid account has no devices | In 3.11.0, switched on by Ian after the changeover | The script exists on the old branch and is small |
| Stage contract with state, revision, usage value | One number on `/api/usage` | The apps only need to know which wording is true |
| Five review points | Two: this note, then the code | Less to review |

Kept as they are: the reviewed table and its export, the rule that an owner never changes, the reassign tool for support, the old-app refusal, lookups per account, server-only Pro on iOS, the old-app check before the switch, and Linux as issues only.

## Backend: storage

New keys. Nothing existing is renamed or removed.

| Key | Type | Fields |
|---|---|---|
| `sub:{rail}:{id}` | hash | `owner` (account id; set once, by the table or by the first account that proves it holds the purchase; only the support tool can change it), `rail`, `id`, `status`, `periodStart` and `periodEnd` (the provider's current billing period, for both rails), the fields today's overlay copies between devices (Polar: `polarCustomerId`, `polarSubscriptionId`, `subscriptionStatus`, `currentPeriodStart`, `polarSubscriptionStartedAt`; Apple: `appleOriginalTransactionId`, `appleSubscriptionStatus`, `applePeriodStart`, `applePeriodEnd`, `appleEnvironment`), `startedAt`, `boundAt`, `boundBy` (`table`, `purchase` or `support`), `rev` (a number every write of the record raises, whoever writes it), `checkedAt` (last successful provider read), `ownerDeleted`, `excluded`. `excluded` is changed only by the support tool. Deletion and a first bind to a deleted owner set `ownerDeleted`; other provider writes preserve it, and only support reassignment clears it |
| `auth:account:{id}:subs` | set | `{rail}:{id}` for each purchase the account owns |
| `auth:account:{id}:subsrev` | string (a number) | Raised by every write that can change which of the account's purchases is chosen: a bind, a support change, a state or period update of a record it owns, the owner's deletion. The charge scripts and the operator edit check it |
| `ownership:deleted:{accountId}` | string | Durable `1` marker written before deletion scans owned purchases. No expiry; contains only the opaque account id and flag. First binding checks it atomically so a late purchase keeps its captured owner and deleted-owner status after the ordinary tombstone expires |
| `ownership:state` | hash | `mode` (`device` until the switch, then `account`), `switchedAt`, `maintenance` (`on` or `off`), `applied` (the keys the table apply created, so undo can remove exactly those) |
| `minutes:{accountId}:month:{YYYY-MM}` | string (a number), kept 70 days | Every minute charged to the account in that UTC calendar month, from the switch on |
| `minutes:{accountId}:period:{rail}:{id}:{start}` | string (a number), kept 70 days past the period | Every minute charged to the account in that billing period of that purchase. `start` is the period start as whole seconds |
| `minutes:device:{deviceId}:month:{YYYY-MM}` | string (a number), kept 70 days | Every minute that device recorded in that calendar month, from the switch on, whatever account it was in. Used only so a free allowance cannot be renewed by starting a new account |
| `checkout:return:{checkoutId}` | existing, 7 days today | Already holds the device and account that started a Polar checkout. Kept for 30 days so a late first event can still be attributed |

`ownership:state.mode` is read two ways. Readers (the plan and usage shown to a request) use a helper that caches it for 5 seconds; for those 5 seconds after the switch a reader may still answer by the old rule, and the freeze is still on then. Anything that writes by the mode reads it inside its own script, uncached: the two scripts that charge a recording, and `recordPurchase`. `maintenance` is read uncached, inside the lock, immediately before each frozen write.

## Backend: who is Pro

Today (`lib/usage.ts`, `lib/accountEntitlement.ts`): a device is Pro from its own subscription fields, else from another live device on its account that has an active subscription (the sponsor), else from complimentary Pro. `getOrCreateDevice` works out the device's own paid state and writes tier, reset date and the monthly reset from it before the sponsor is looked at; `withAccountEntitlement` then copies the sponsor's fields onto the device in memory.

In `account` mode the record decides, always. A device's stored purchase fields never grant anything by themselves; at most they say which of the account's purchases this device prefers.

One resolver in two steps, used by every reader and by charging.

`accountPurchases(accountId, now)`, the same for every device of the account:

1. Take the account's records that are not excluded and not owner-deleted and whose state is active by today's test per rail (Polar `active`; Apple `active`, `grace` or `billing_retry`).
2. Per rail, if more than one is left, keep the one with the latest period end, then the latest start, then the smaller id. An account with two active purchases on one rail is reported by the ops check; it is a customer paying twice.
3. Return at most one purchase per rail, each with its billing period and the minutes counter for that period, and the account's `subsrev` as read.

`planFor(purchases, platform, preferred)`, for one device:

1. Keep the purchases that cover the platform by today's rule (Polar every platform, App Store iOS only).
2. Pick the one the device's stored fields name, if it is among those; otherwise Polar before Apple. That keeps today's order (a device's own purchase first) and makes the rest defined; today the sponsor is whichever device the store returns first.
3. Return that purchase, its period, its counter and the reset date. None: the calendar month, and complimentary Pro if the account has it.

Charging uses the first step, so a recording on any device counts in the period of each rail's purchase; a Mac recording does count in the App Store period that the account's iPhone is shown. Showing and limits use the second.

Cost, stated instead of promised: learning that an account owns nothing is one read of its set; an account with purchases adds one read per purchase, at most a handful. Both are measured before and after; if the first shows up, the count of purchases is kept on the account record that requests already read.

Where it is applied:

- **At the start of `getOrCreateDevice`, before anything is written.** If the device's stored fields name a purchase that its account does not own, or that the record says is not active, or the device has no live installation, those fields are treated as absent for the whole request. So the tier, reset date and monthly reset that get written for the device's own counter are those of a device without its own purchase, and a stale "active" on the device cannot outlive the record. For a device whose own purchase is owned and active, nothing changes from today.
- **In `withAccountEntitlement`, in place of the sponsor device.** The chosen record's fields are copied onto the in-memory device with the same field lists the sponsor copy uses, plus the record's period end as the reset date. This is a deliberate difference from today for a device that is Pro through its account: today it keeps its own first-of-the-month date; now every device of the account shows the billing period.
- **Then complimentary Pro**, unchanged.

To keep stored fields honest, when a device ends up in an account that does not own the purchase its fields name (on attach, and on restore or create into a different account), a new `clearDevicePurchase(deviceId, rail, purchaseId)` empties that device's fields for that rail (the same fields `downgradeSubscriptionDevices` empties for Polar; the status and id fields for Apple) and removes it from that purchase's reverse set. It is one script, and it writes only if, at that moment, the device's installation is live in the account it was called for, the device's fields still name that purchase, and the record's owner is a different account. Both removals happen together or not at all, running it twice does nothing more, and it is also run when an enrolment or a move is replayed, so a first attempt that stopped before it is completed by the retry.

Other readers:

- `accountTier` in `lib/apiTokens.ts` uses the first step with no device (any active purchase), then complimentary Pro. An account with no device keeps API, MCP and cloud.
- `deviceTier` in `lib/cloud.ts` needs no change; it calls `withAccountEntitlement`.
- `purchaseReturnStatus` in `lib/purchaseReturn.ts` reads raw device fields today. In `account` mode it answers `ready` when the checkout succeeded and its subscription has a record owned by the caller's account.
- `/api/subscribe` keeps using `hasPaidEntitlement` on the overlaid record.
- The admin report (`lib/adminDevices.ts`) keeps reading raw device fields; they describe the owner's devices.
- The same-rail check on attach (`destinationHasRailConflict`) is removed in `account` mode: a moving device brings no purchase.

In `device` mode none of this runs.

## Backend: purchases

One new function, `recordPurchase(rail, id, state, presenterAccount)`, in a new `lib/subscriptionRecord.ts`. One script per purchase:

1. Mode is `device`: do nothing, return `off`.
2. The record is excluded: change nothing, return `excluded`. No owner, no state, and the caller links no device. A presenter gets `409 subscription_not_eligible`.
3. A record exists with an owner: update the state fields and both period fields, raise `rev` and the owner's `subsrev`. Never touch `owner`, `excluded` or `ownerDeleted`. Return `ok` if there is no presenter or the presenter is the owner, else `elsewhere` (also when the owner was deleted: another account cannot claim it).
4. No record, or a record with no owner yet, and there is a presenter: set `owner`, add the purchase to that account's set, store the state, raise that account's `subsrev`, return `bound`. In the same script, set `ownerDeleted` if the durable deletion marker is present. This is the decided rule: one owner per purchase, fixed at first bind.
5. No record and no presenter: store the state with no owner. The first account to prove it holds it becomes the owner under rule 4.

A presenter is an account that proves it holds the purchase, never a guess from where a device happens to be:

| Path | Presenter |
|---|---|
| App Store verify (`app/api/apple/verify/route.ts`) | The caller's account, with a signed transaction |
| Licence restore (`app/api/restore/route.ts`) | The caller's account, with the licence key |
| Polar webhook, `subscription.active` and `subscription.updated` | The account stored under the event's checkout id in `checkout:return:{checkoutId}`, if the event carries one and the entry exists. Otherwise none: the record is stored without an owner. Whether Polar's subscription event carries the checkout id is confirmed on a sandbox checkout before this is built |
| Purchase return (`app/api/subscribe/status`) | The caller's account, when Polar says that checkout succeeded, the purchase is the checkout's subscription, and the caller is the account and device that started it (the checks the route makes today). This is what binds a Polar purchase whose webhook carried no usable checkout id. A customer who never returns to the app and whose event carried no checkout id leaves the record without an owner; the ops check warns after a day and support sets the owner with the tool |
| Polar `subscription.canceled` and `subscription.revoked`, every Apple notification | None. They only change state |

Answers: `elsewhere` returns `409 subscription_owned_elsewhere`; a caller with no account returns `401 enrollment_required`.

After `recordPurchase`, the existing link and downgrade functions run as today, but only for devices that belong to the owner. They are the only thing that may reset a device's minutes for a new period, exactly as today. The record is written first; if the device write is lost, the provider's retry of the same event repeats it. Both downgrade paths atomically recheck the current purchase id and, in account mode, the installation's current account against the purchase owner. Polar removes only the downgraded device aliases from the reverse set, preserving concurrently linked devices.

Deleting an account first writes the durable deletion marker, then sets `ownerDeleted` on each record it owns. A bind before the marker is covered by the scan; a bind after it reads the marker in its atomic write. This preserves support reassignment even when a late first webhook arrives after deletion and the ordinary 30-day tombstone later expires. No billing call is made, as today. A new account cannot claim such a purchase; support can, with the reassign tool.

A renewal, a resubscription or a plan change keeps the same id and so keeps its record and owner. One Apple ID used on two miniti accounts gives the first account the purchase and the second the card; that is the decided rule. Family-shared transactions get a test that pins which transaction id is bound.

## Backend: the hourly check

`GET /api/cron/subscription-check`, with cron auth, scheduled hourly, switched off during the pause.

For every `sub:*` that is not excluded: note the record's `rev`, read the purchase from its provider, and write the state only if `rev` is still the same. If a webhook landed in between, this run leaves the record alone and the next run looks again. A failed provider read changes nothing and is counted.

The operator export verifies the signed identity of a Sandbox transaction even when it uses a retired sandbox product, but that row can only be excluded. Ordinary verify and hourly reconciliation retain strict current-product validation.

Provider reads: Polar `GET /subscriptions/{id}` through a new `getSubscriptionById` in `lib/polar.ts`; Apple's App Store Server API status read, sandbox host for a sandbox record (the key was verified on 2026-11-16). Apple's numbers map to today's words: 1 active, 2 expired, 3 billing_retry, 4 grace, 5 revoked.

**It never touches device records.** The first version of this note had it "make the owner's devices agree" by calling the link functions. Those functions clear a device's minutes when they see a period for the first time, so the first run would have wiped the minutes of every device that had been Pro through another device. In `account` mode the record is what decides Pro; device fields are only what the admin report shows, and events keep those current as they do today.

It also reads Polar's full subscription list each hour and creates an ownerless record for any subscription that has none, so a purchase whose events were all lost is still found. Apple has no such list; an Apple purchase reaches the backend through verify or a notification.

It reports to the existing ops check as `subscriptions`: records read, records it changed (an event was missed or arrived out of order), reads that failed, the age of the oldest successful read, records with no owner, accounts with two active purchases on one rail, and records whose owner's devices show a different state. Any read older than three hours, or an ownerless active record older than a day, is a warning.

A wrong state is normally corrected within the hour. It can last longer while a provider is down or its read lags its own event; the ops check shows the age.

## Backend: minutes

Today (`lib/accountUsage.ts`): an account's minutes are this device's counter plus the counter of every other live device on the account. So a device that signs out takes its minutes away and a device that moves brings them along. Each device's counter resets by its own date: the 1st of the month for a free device or one that is Pro through its account, the billing period end for the device that holds the subscription.

In `account` mode the account has its own counters. Decided by Ian on 2026-11-16: the period stays tied to the billing date, and everyone starts from zero at the switch.

**Which period.** From the resolver in [who is Pro](#backend-who-is-pro), so the purchase that makes a device Pro is also the one whose billing period counts its minutes:

- A purchase was chosen: its billing period, `periodStart` to `periodEnd` from the record.
- The period end has passed and the record is still active (no renewal has arrived yet): a provisional period, one month at a time from the old end, using the same month arithmetic as `advanceResetDate` in `lib/usage.ts`, for at most twelve months. This applies to Apple `grace` and `billing_retry` too. After twelve, or if a date cannot be read, the calendar month.
- No purchase (free, or complimentary Pro): the UTC calendar month.

The counter is named by the period's start in whole seconds. When Polar renews on time the new period starts where the old one ended, so the provisional period and the real one are the same counter. When a renewal is late and the provider starts the new period later (a recovered App Store payment, for one), the real period is a new counter and the count restarts; that favours the customer and is accepted.

So "one counter per account per billing period" means: one per purchase period, plus one per calendar month. An account whose devices are Pro through different things (an App Store subscription on the iPhone, complimentary Pro on the Mac) shows each device the total for its own period, with its own reset date.

**Charging.** The two scripts that charge a recording (`FINISH_ACCOUNTING_LUA` in `lib/managedAccounting.ts`, and `FINISH_LEGACY_LUA` in `lib/legacyAccounting.ts`, which also takes prerecorded Apple Watch sessions) keep adding to the device counter exactly as now. In the same script, only when the script itself reads `mode` as `account`, and only on the branch that charges for the first time, they also add the minutes to:

- the account's month counter;
- the period counter of the account's chosen purchase on each rail (at most two, from the resolver's first step, whatever platform the recording device is); and
- the device's month counter.

What that needs in the scripts, stated because both are strict today:

- Both validate a fixed list of nine keys by type. The list and the loop grow to cover the new keys, and every new counter is checked to be a number, before the first write. A script error does not undo earlier writes.
- A replayed finish returns its stored receipt before any of this and adds nothing.
- The route passes in the counters' names and the account's `subsrev` as it read it. The script compares `subsrev` before charging, including when no purchase was chosen; if anything that could change the choice happened in between (a first purchase, a renewal, a revocation, a second purchase becoming the one chosen, a support change), it answers "changed" and the route works the names out again, the way it already retries when the device's reset date changes. Names are worked out again on every such retry.
- The device's own stored reset date, which the scripts compare today, stays the device's. The account's period and reset date are separate and are what the customer is shown.
- The legacy script builds its receipt today from the device counter plus the other devices' figure. In `account` mode the receipt's `minutes_used` is the account's figure for the device's period after this charge (with the free floor below), not the device's.

The account is the one the recording belongs to: the account in the session record for the first script, the signed-in account the second script already checks for the other. A request with no account (the old shared key) charges only the device, as today. `incrementUsage` in `lib/usage.ts` has no caller and is removed so nothing can charge around the scripts.

**Reading.** `withAccountUsage` in `account` mode sets the device's minutes to the account's counter for the period the resolver chose, in place of adding up devices. `/api/usage`, the limit check at session start and the session end answers all go through it.

**A free allowance cannot be renewed by starting over.** For a free account the figure used is the larger of the account's month counter and the asking device's own month counter. A device that recorded 400 minutes this month, signs out and starts a new account still has 400 used. The device's month counter is new and starts at the switch, like the others; it is not the old per-device counter, which for a Pro device follows the billing period and would bring the wrong minutes. Pro accounts use the account counter alone.

**At the switch** none of these counters exist, so every account and every device starts from zero. Nothing is copied. The old device counters are untouched and keep being written.

**Operator edit.** In `account` mode the admin minutes edit is an edit of the account: one script sets the account's month counter and the counter of each chosen purchase period to the figure, lowers each member device's month counter to at most the figure, and sets the device counter as today. The script is given the member list and `subsrev` the route read and writes only if both are still current; otherwise the route reads again and retries. So the figure holds whichever device asks and whether or not Pro later ends. Lowering a device's month counter is the one authorised exception to the free floor. An edit of a device with no account works as today.

**What needs no rule:** a device leaving, joining, moving or signing back in (the counter is the account's); account deletion (its counters go with it); a recording in flight when a device moves or is removed from another device (the backend refuses that finish today and it stays uncharged).

**Where a customer can come out differently from today**, all accepted:

- Pro ends mid-month (cancelled, expired, refunded): the free allowance for that month counts every minute recorded since the 1st. Today it counts the minutes since the last billing reset, which can be fewer.
- An upgrade mid-month starts the first billing period at zero for every device. Today devices that are Pro through the account keep their month's minutes.
- A device that is Pro through its account now resets on the billing date, not on the 1st.
- If a provider corrects a period's start, that period's count starts again.

The first version of this note carried minutes between devices and accounts ("left-behind minutes"). The review found six problems with that; none applies to an account counter.

## Backend: emptied accounts, lookups, old apps

**Emptied accounts.** In `attachToDestination`, the three lines that call `tombstoneAccount` when the source is left with no devices are removed, in both modes. This intentionally differs from `main` in `device` mode. The implementation also preserves paid time after a Polar cancellation scheduled for period end and fails closed on an unreadable ownership mode; the checklist records those reviewed differences. Signing out already leaves an emptied account alive today, so this makes attach behave the same. No cleanup job is added in 3.11.0.

**Notice email.** When an account that owns an active purchase and has a verified email is left with no live device, it gets one email saying Pro is still there and how to sign back in. It is found by looking, not by hooks on sign-out and sign-in: the hourly job goes through the accounts that own an active purchase (11 today) and, for each, counts its live devices. None, and no `emptySince` stored: store `emptySince` as now. None, `emptySince` stored and no notice sent for it: send, with the account and `emptySince` as the one idempotency key, and record it; a failed send is tried again each hour for 20 hours. At least one: clear `emptySince`, so the next time is a new departure. Nothing depends on the order of any writes or on a retry by the app, so a departure cannot be missed or undone by a late reply; the cost is that the email goes up to an hour after the last device left, and an account that is empty for less than an hour gets none. Only the email's text and sender are brought over from `lib/accountLifecycle.ts` on the old branch. It is behind `DORMANT_PAID_NOTICE`, off until Ian turns it on after the switch. It cannot be sent before the switch: today a paid account that loses its last device loses Pro with it.

**Lookups.** `lib/docsLookups.ts` from the old branch stands alone and is brought over as it is: 100 per account per UTC month from an instant set by `DOCS_LOOKUPS_ACCOUNT_SINCE`, reserved before retrieval, charged once, released on failure, with the changes it needs in `app/api/insights/route.ts` and `withAccountUsage`. `/api/usage` gains `docs_lookups_scope` and `docs_lookups_resets_at`. It deploys on its own date.

**Old apps.** In `account` mode, an app below 3.11.0 on Mac or iOS, and any Linux version, is refused on four operations: a move to another account (both kinds of attach), joining an existing account when it is not repair or replay, and create or migrate on a device id whose installation was revoked. A new device starting, the first enrolment of an old shared-key device, same-account repair and a replayed reply are never refused. The decision is made where today's code already tells these cases apart (`bindRestoredInstallation`, `createAccount`, `migrateLegacyDevice`, `attachToDestination`), inside the existing lock and immediately before the first write, so a sign-out or a move racing the request cannot change the answer after it is taken. The version comparison moves out of `app/api/version/route.ts` into `lib/`; a missing or malformed version is refused.

The answer is `426` with the error code `update_miniti_to_change_account`. An old app shows `Server error (426): update_miniti_to_change_account` for these operations, because `mapError` in `ClientAuth.swift` prints the code.

Rehearsal correction, 2026-11-16 (I13): an old iOS app with its local StoreKit flag set turns a session-start 402 into a temporary Pro-sync message. In `account` mode, when a free account reaches its limit, `/api/session` therefore returns `426 update_miniti_for_account_usage` to an iOS client below 3.11.0 (including a missing or malformed version), with “This account has used its free minutes. Update miniti from the App Store to check your plan.” The old recording API displays that message. Current iOS, Mac and `device` mode retain the existing quota response; below-limit old iOS recording remains allowed. This does not alter recording-finish charging. Native evidence is in the [audit](../releases/3.11.0-planning-audit.md#old-native-client-quota-guidance-2026-11-16).

## Backend: what the apps are told

| Where | Field or answer | Meaning |
|---|---|---|
| `GET /api/usage` | `account_owns: 1` | Present only in `account` mode. The app uses the new wording when it is 1 and shows update required for a number it does not know |
| `GET /api/usage` | `docs_lookups_scope`, `docs_lookups_resets_at` | With the lookups change |
| Attach, restore, create, migrate | `426 update_miniti_to_change_account` | Old app, in `account` mode |
| Session start at the free-account limit | `426 update_miniti_for_account_usage` | Old iOS only, in `account` mode; explicit App Store update guidance |
| Frozen routes during the pause | `503 maintenance`, with `Retry-After: 600` | Apps already show "temporarily unavailable, try again shortly" for a 503 |
| Apple verify, licence restore | `409 subscription_owned_elsewhere` | The purchase belongs to another account |
| Apple verify, licence restore | `409 subscription_not_eligible` | The purchase is recorded as one that never counts (a sandbox purchase excluded in the table). The app shows its existing failure text |

No auth vector changes. Two existing fields describe something new in `account` mode: `minutes_used` is the account's figure for the device's billing period, and `resets_at` is the end of that period. Old apps decode both as before; `UsageInfo` accepts a figure that drops to zero and a date that moves.

## The switch

One operator tool, `scripts/ownership.mjs`, growing out of today's `scripts/subscription-export.mjs`. Commands: `maintenance on|off`, `export`, `apply`, `compare`, `undo` (before the switch only), `switch`, `reassign`. Every command except `export` and `compare` writes, so each needs Ian's go.

**What the pause freezes.** Everything that can change who belongs to which account or which device names which purchase:

| Frozen | Where the check goes |
|---|---|
| Every enrolment: create (a new device too), restore by key and by email, migrate | `createAccount`, `bindRestoredInstallation`, `migrateLegacyDevice` |
| Moves | `attachToDestination` |
| Sign-out, removal from another device, removal from the web account page | `revokeInstallation` |
| Account deletion | `deleteAccount` |
| Checkout start, purchase return binding, licence restore, App Store verify | their routes |
| Both webhooks | their routes, answering 503 |
| Operator device edits and complimentary Pro | `app/api/admin/devices`, `app/api/admin/comp` |
| The hourly subscription check and the notice step | not scheduled until after the switch |

Each check is inside the function's lock, immediately before its first write, and answers `503 maintenance` with `Retry-After`. A request retried during the pause meets the same check. Token refresh, usage, recording and its accounting, sync and lookups keep working; they do not change membership or purchases. Recordings do keep finishing during the pause, on both sides of step 5: before it a finish charges the device only, after it the device and the account's counters, and each finish reads the mode inside its own script, so none is half one and half the other. A new user who installs during the pause cannot finish setup until it ends; at about 5 new devices a day that is unlikely in half an hour.

**How long to wait.** Functions under `app/api` are limited to 60 seconds by `vercel.json`. The web removal route is not under that path, so it gets its own 60-second limit. After `maintenance on` the wait is 3 minutes: no request that passed the check before the flag can still be writing.

**The table.** `export` is the union of four sources: purchases named by any device record, the two kinds of reverse set, any existing `sub:*` record, and Polar's full subscription list. Every purchase gets a row; a purchase seen by one source and not another is shown as such and needs a decision. If any provider read or list page fails, `apply` refuses to run.

Before the day: code deployed in `device` mode; Mac and iOS 3.11.0 public; the whole sequence rehearsed on a private copy of production; an old Debug build checked against the test backend.

On the day, at a quiet hour, with Ian present:

1. `maintenance on`. Wait 3 minutes.
2. `export`. Ian reviews the table: who owns each purchase. Each row is bind, exclude (mandatory for a Sandbox purchase), or leave for the first account that shows it (only for a purchase no account holds). This review is what makes ownership right; the comparison below cannot tell two accounts with each other's purchases apart, because both would still be Pro.
3. `apply`. Each row is written only if no record exists. The keys it creates are listed in `ownership:state`. A second run changes nothing. The mode is still `device`, and in that mode nothing reads or writes these records.
4. `compare`, read-only, with the mode still `device`. For every device with a live installation it works out the full answer `/api/usage` would give under the old rule and, by running the new resolver on the records just applied, under the new one: plan, limit, reset date, subscription status, and whether Pro comes through the account. Minutes are left out: they start from zero by decision. Every other difference is listed and reviewed. One kind is expected and intended: a device that is Pro through its account shows the billing period's reset date where today it shows the 1st of the month. It prints the new answers for Ian's own devices, one paid account on each rail and one free account. The other accepted difference is an expired, explicitly excluded Sandbox Apple purchase disappearing from subscription status on a device which stays free, names no Polar purchase, and has no other changed comparison field. Any other difference stops here.
5. `switch`. Mode becomes `account`. This is the point of no return.
6. Spot check on real devices: Ian's own, one paid account on each rail, one free account.
7. `maintenance off`.
8. Straight away: run the subscription check once by hand, so any event refused during the pause is made up from the provider; confirm in Polar that the webhook endpoint is still enabled; then schedule the hourly check.

`undo` exists only before step 5: it removes exactly the records and set entries `apply` listed. That is complete, because the mode never left `device`: no request behaved differently, no counter was created, no receipt was written under the new rule. From step 5 on there is no undo, by decision; recordings that finish between steps 5 and 7 are charged under the new rule like any later one, and the way forward is to fix on top of the records.

Refused webhooks: Polar retries a failed delivery, and Apple retries production notifications; Apple sends a sandbox notification only once, which matters to no customer. Step 8 does not depend on any retry arriving. A renewal that was refused and is retried later is applied by the existing link function, which compares period starts and so resets minutes once, not twice.

Afterwards, `reassign` moves a deleted account's purchase, or gives an owner to a record that has none, with an audit line.

## The app

Files are in `Miniti/` and compiled into both the Mac and iOS apps unless marked.

**Pro only from the server (iOS).** In `Miniti/Models/AppState.swift` the local App Store flag stops granting anything:

| Place | Today | Change |
|---|---|---|
| `isLimitReached` | Returns false when the local flag is set | Uses the server's answer only |
| `isPro` | Server Pro or the local flag | Server Pro only, on every platform |
| `shouldShowManagedSubscriptionPlaceholder` | Never shows "Checking…" when the flag is set | Follows the server |
| `displayMinutesLimit` | Hard-coded 5,000 when the flag is set | The server's `minutes_limit` |
| The message "Pro is active, but usage sync is still catching up…" | Shown on a limit refusal when the flag is set | Removed; the normal limit message shows |
| `lastAnsweredCompPro` | Hidden when the flag is set | Follows the server |

The flag itself stays, with one job: knowing there is an App Store subscription the server may not have credited yet.

**App Store changes reach the server (iOS).** Today `Transaction.updates` and `Transaction.currentEntitlements` in `AppStoreSubscriptionService` only refresh the local flag. They now also call `syncAppleEntitlementToBackend()`, with three attempts at growing intervals. Only identical work in progress is skipped: the same signed transaction (the whole signed text, which changes when a transaction is renewed or revoked) for the same account sign-in generation. An answer that arrives after the account has changed is discarded, and the state below is reset on every account change. A successful verify means the server processed it; the app shows Pro only when the usage refresh that follows says so. That function already posts to `/api/apple/verify`; it gains a result:

| Server answer | App state | What the user sees |
|---|---|---|
| Success | `processed` | Whatever the refreshed usage says |
| In progress, up to 30 seconds | `confirming` | "Confirming your subscription…" |
| `409 subscription_owned_elsewhere` | `ownedElsewhere` | The card below |
| Anything else after three attempts | `failed` | Today's message with Restore Purchases |

**The card.** A new `SubscriptionElsewhereCard` in `Miniti/Views/ManagedAccountViews.swift`, built from `MinitiCardBackground`, `MinitiControlLabel` and `ColorPalette` text roles, shown in the plan section of iOS Settings (Ian confirmed Settings-only placement on 2026-11-16):

- Title: "This App Store subscription belongs to another miniti account"
- Body: "Sign in to that account to use Pro here. You can keep recording on the free plan."
- Actions: "Sign in with email", "Use recovery key", "Manage subscription". The first two open the existing sheets; the third calls the existing `openManageSubscriptionPage`.

No alert at launch, no automatic retry beyond the three attempts.

Placement decision, Ian, 2026-11-16: keep the card in Settings for 3.11.0. The first-setup access choice appears only without an account, whereas verify requires one. No card is required in either setup branch. Every account change re-reads a locally held StoreKit entitlement so signing in after launch can receive the correct server answer.

**Wording.** `UsageInfo` in `Miniti/Services/MinitiAPIService.swift` gains `accountOwns` (from `account_owns`), decoded as tolerantly as its other fields. When it is absent the strings below stay as they are. When it is 1:

| Place in `ManagedAccountViews.swift` | New text |
|---|---|
| Switch account by recovery key (line 179) | "Enter the recovery key of the account to switch to. This device keeps its meetings and its calendar and CRM connections. Pro and minutes used stay with the account you are leaving, and you can sign back in to it. If the other account has Pro, this device gets it too." |
| Switch account summary (line 1737) | "Switch account signs this device in to another account by email or recovery key. It keeps its meetings. Pro and minutes used stay with the account you leave." |
| Join by email (line 2492) | "Enter the email on the account to join. miniti sends it a link; open it anywhere and press Approve. This device keeps its meetings and connections and joins that account. Pro and minutes used stay with the account you leave." |
| Sign out (line 439) | "This device can sign back in with the account's email or recovery key. Meetings stored on this device are not affected. Pro and minutes used stay with the account." |

When `accountOwns` is any number other than 1 (including 0), the app shows the update-required state in place of the switch and join sheets.

**Update required.** `ClientAuthError` in `Miniti/Services/ClientAuth.swift` gains `updateRequired` ("Update miniti to change accounts."), and `mapError` maps any 426 to it. The restore and email sheets show that text with an Update button: on Mac `UpdateService.shared.checkForUpdates()`, on iOS the App Store page. A 503 from an account operation during the pause already reads "Device authorization is temporarily unavailable. Try again shortly."; purchase screens show their own existing failure text. No new state is needed.

**Lookups.** Nothing. The count and limit already come from the server and no 10 is hard-coded.

**Work sent later.** Nothing. The session journal and the on-device usage queue already store the account, send only for the current account and block an account change while usage is waiting.

**Screens to check by eye:** iOS Settings with the card; the confirming state; the switch and join sheets with the new wording at the largest text size; the update-required state on Mac and iPhone.

## Tests

Written before the code review, as the review lessons require.

Properties, each a test and each also in one fixed-seed random sequence test over purchases, sign-outs, moves, sign-ins, deletions, provider events, recordings and retries:

1. Once a purchase has an owner, only the support tool changes it. An excluded record never gets an owner, a state or a linked device from any ordinary writer.
2. In `account` mode, a device is Pro exactly when the resolver finds its account an active purchase that covers its platform, or the account has complimentary Pro. Stored fields on the device never make it Pro when the record says otherwise.
3. A purchase with no owner takes the first account that proves it holds it, and no later presenter changes that. A Polar event with no usable checkout id never gives a purchase an owner.
4. The hourly check never changes a device record, and never overwrites a record a webhook wrote after its read began. Every writer of a record raises `rev`.
5. `recordPurchase` and the hourly check never reset a device's minutes. Only today's paths do: the monthly reset, a new provider period through the link functions, and the operator edit; a replayed renewal resets once.
6. An account's minutes for a period equal the sum of the recordings charged to that account in that period after the switch, whatever its devices did: signed out, signed back in, moved away, moved in, or were removed. The only other things that change the figure are an operator edit and a new period starting.
7. A recording is added to the device, the account's counters and the device's month counter in one script, on the first charge only: a retry or a replayed finish adds it once to each or to none, and the reply's figure is the account's. A purchase bound, renewed, ended or replaced between the route's read and the script makes the script answer "changed", never charge the old choice.
8. The period is that of the purchase the resolver chose, else the calendar month; a renewal that starts where the last period ended continues the same count, and any other new start begins one.
9. A free account's figure is never below what the asking device recorded since the 1st, counted from the switch, unless an operator edit lowered it.
10. Every old device counter receives every charge after the switch exactly as before it.
11. In `device` mode every route answers as `main` does, except that attach no longer closes the emptied account.

With a failure injected after each write, checked on the stored records and on the retry, not only on the reply: each enrolment case and the move under the freeze check, including `clearDevicePurchase` completed by the retry; `recordPurchase` then the device write; `apply`; `undo` after `apply`. For each charge script, which either runs whole or not at all: a wrong key type or a non-number counter is refused before any write, and a reply lost after the script ran is answered by the stored receipt with nothing added. For the notice: join, leave, then a late reply to the join; a departure the app never retries; two devices leaving in the same hour; a failed send.

On real Redis: 20 concurrent `recordPurchase` calls leave one owner; the hourly check racing a webhook; `apply` run twice.

Minutes fixtures: an account that upgrades mid-month; one whose Pro ends mid-month; a renewal on time and one that arrives late with a later start; a period end on the 29th to 31st; grace and billing retry; both rails with each device's preferred purchase; two active purchases on one rail; App Store on the iPhone with complimentary Pro on the Mac; a device that recorded 400 free minutes starting a new account; a device moving from a Pro account to a free one; a first purchase and a second purchase taking over, each landing between the route's read and the script; a Mac recording counted in the App Store period; an excluded record presented by verify and by licence restore; the legacy receipt's figure; the operator edit followed by a finish, a second device, a renewal and Pro ending.

Fixtures: the buying device; another device of the account; a device that moved; a device with stale stored fields; an account with both rails; complimentary Pro beside each; a purchase only in a reverse set; a purchase only in Polar's list; one Apple ID on two accounts; a family-shared transaction; a revoked device restoring into the same account against a live repair.

`compare` is itself tested: on a fixture where one account would lose Pro, and one where only a reset date would move, it must say so.

The tests the roadmap assigns to this work before any change (device cap and revoked sibling, usage charged once, the Polar and Apple purchase and notification lifecycle) are written first against today's behaviour.

App: the six places the local flag is removed; each verify answer to its state; a renewal sent though its original id was seen; an answer for a previous account discarded; wording by `accountOwns`; 426 to update required; an unknown `accountOwns`; one UI journey each on Mac and iPhone for the switch sheet and, on iPhone, the card.

## Order, reviews, estimate

The [checklist](../releases/3.11.0.md#delivery-order-and-dependencies) owns the order, the review points and the estimate. In short: device records first; then the backend in `device` mode with tests written first; one look by Astra once the record, the resolver, the callers and the first working minutes counters exist, because that is where ownership, choice and charging meet; the rest of the backend and the app; a final code review; the release; the switch with Ian.

## Limits accepted

- For about 30 minutes, once, account changes and purchases say try again shortly.
- A subscription's state can be wrong for about an hour if a provider event is lost or arrives out of order, longer while a provider is down. Today it can be wrong indefinitely.
- The four ways a customer's minutes can come out differently from today, listed under [Backend: minutes](#backend-minutes).
- A device removed from another device while it is recording loses that recording's minutes from the count, as today.
- Everyone's minutes for the current period start from zero at the switch.
- If a provider corrects a billing period's start, that period's count starts again.
- For about 30 minutes a new user cannot finish setup, and nobody can sign out, remove a device or delete an account.
- From the moment of the switch there is no way back to the old rule. The comparison run before it, with undo available until then, is the protection.
- An old purchase the backend has never seen belongs to the first account that shows it.
- Linux cannot change account after the switch until someone builds a compatible release (issues 29 and 30).

## Decisions for Ian

Made on 2026-11-16:

1. This design is adopted in place of the reviewed transition protocol, and goes to Astra.
2. No way back after the pause ends is accepted.
3. Device records are merged as soon as possible, ahead of everything else.
4. The notice email is in 3.11.0.
5. A purchase with no record belongs to the first account that shows it (left to engineering judgment).

6. Minutes: one counter per account per billing period, tied to the billing date (free accounts keep the 1st of the month), everyone starting from zero at the switch. This replaces the earlier decision to keep today's minutes behaviour in five named points; the design keeps those points where it can and says where it does not.
7. Device records deploy switched off and are switched on after their checks, each on Ian's go. Work starts on 2026-11-16; there is no fixed day between the two.

Still Ian's, later: the go for each deploy, the device-record activation, the day and hour of the switch, the table on that day, and turning the notice email on.

## Astra's review

2026-11-16, of the first version of this note, against the source. Verdict: ready after fixes; do not build it unchanged. What it found sound: an owner that never changes, records with no owner for purchases nobody has shown, a deleted owner keeping its purchase, server-only Pro on iOS, account-based API access, complimentary Pro last, the old-app answer, the Apple status words, keeping emptied accounts.

| # | Severity | Finding | What changed here |
|---|---|---|---|
| 1 | P0 | The move script changed the installation before the member sets; a failure between left a device no reader counts | No longer applies: minutes are an account counter, nothing is moved at a sign-out or a move ([Backend: minutes](#backend-minutes)) |
| 2 | P0 | The hourly check repaired device records with functions that clear minutes on a first-seen period | The check never touches device records |
| 3 | P1 | Left-behind minutes vanished for an account with one device | With finding 1. The new reader replaces the device sum, so the early return for one device is gone |
| 4 | P1 | An idempotent sign-out must still finish its cleanup | With finding 1 |
| 5 | P1 | A device removed remotely while recording | With finding 1 for the copy. The recording itself is refused and uncharged, as today; stated |
| 6 | P1 | One left-behind entry per device cannot hold two periods | With finding 1 |
| 7 | P1 | The pause did not freeze sign-out, removal, deletion, new devices, operator edits or jobs | The freeze table in [the switch](#the-switch) |
| 8 | P1 | Two minutes was not a proven drain | Check inside the lock before the first write; 60-second limit on the web route; 3-minute wait |
| 9 | P1 | The export must be a union of sources, and comparing plans does not prove owners | Four-source export; the table review is named as what proves ownership; compare covers the full usage answer |
| 10 | P1 | Attributing a Polar event by the device's current account can bind the wrong account | Attribution only by checkout id; otherwise no owner until the purchase return or a licence restore |
| 11 | P1 | Clearing fields in memory after `getOrCreateDevice` has written tier and reset date does not preserve today's behaviour; precedence across rails was not today's | The ownership test moves to the start of `getOrCreateDevice`; precedence stated; purchase return reads the record; `polarCustomerId` kept on the record |
| 12 | P1 | A provider read can overwrite a newer webhook; one hour was promised too firmly; a purchase with no record is never found | Write only if `rev` is unchanged; age reported; Polar's list read each hour |
| 13 | P1 | Refused webhooks are not guaranteed to come back | A check by hand straight after reopening, and the Polar endpoint confirmed |
| 14 | P1 | Undo was incomplete if anything could write under the new rule before reopening | The freeze holds through the switch; apply lists its keys |
| 15 | P2 | The old-app decision belongs beside the write | Made inside the lock, where the cases are already told apart |
| 16 | P2 | Sending App Store changes once per original transaction id drops renewals; success is not Pro | Only identical signed text already in progress is skipped, per sign-in generation; Pro only from refreshed usage |
| 17 | P2 | The notice needs its join handling and delivery step | Listed |
| 18 | P2 | Several test properties could not fail | Rewritten |

### The re-check

Later on 2026-11-16, of the note with the fixes above and the account minutes counter. Part of the same review: the 13-line fix to the device-record merge, verdict commit as it is. For the note: the account-counter approach is sound; ready after named fixes. Its status for the 18 above: 1, 2, 3, 5, 6, 10, 12, 13 and 15 closed; 4, 7, 8, 9, 11, 16, 17 and 18 partly; 14 not closed. What it added, and what changed here:

| Severity | Finding | What changed here |
|---|---|---|
| P1 | The free floor used the old device counter, which for a Pro device follows the billing period, and it contradicted starting everyone from zero | A new device month counter, written by the charge scripts from the switch on |
| P1 | The switch was not a write boundary: recordings finish during the pause and the mode was cached, so zeroing and undo were not defined (also earlier findings 7, 8, 14) | The charge scripts read the mode inside the script; undo deletes every `minutes:` counter; the claim that nothing writes before reopening is corrected |
| P1 | The Polar record had no period end, and reset dates do change for devices that are Pro through the account (also 9) | `periodStart` and `periodEnd` on every record; one resolver; the reset-date difference is named as expected in `compare` |
| P1 | The charge scripts validate nine fixed keys, and the legacy receipt is built from the device counter | The script contract under [Backend: minutes](#backend-minutes) |
| P1 | A device's own stored fields could keep granting Pro after the record ended (also 11) | The record's state decides for a device's own purchase too; stored fields only express a preference |
| P1 | "At most two purchases" did not follow from one owner per purchase | The resolver chooses one per rail by a stated rule; two active on one rail is reported |
| P2 | Advancing a late period: from the end or the start, month ends, the twelve-month stop, grace and billing retry; and customer effects were claimed to match today | Stated exactly; the four differences from today are listed, not denied |
| P2 | A record can change between the route's read and the charge | The script checks each record's `rev` and the route retries |
| P2 | The operator edit did not say which totals change | One account-wide script |
| P2 | Clearing a device's purchase fields was vague, and "switching back gives today's figures" was too broad | `clearDevicePurchase` defined; the property is narrowed to the old counters still receiving every charge |
| P2 | Skipping an App Store transaction already seen can skip its revocation (also 16) | Only identical signed text in progress is skipped |
| P2 | A notice can be missed if the first attempt stops before the hook (also 4, 17) | Hooks are repeatable and run on every path, replay included |
| Contradictions | Two minutes against three; "at most an hour"; a property that ruled out resets that exist; "no field changes meaning"; "nothing writes" before reopening; zero start against the floor | Each corrected |

Not sent back for another check: these are the reviewer's own smallest fixes, and the code review covers the result.

### The final review

2026-11-16, evening, of this note with the checklist, the audit and the roadmap as a set. Verdict: device-record work can start today; start the ownership code after the contract fixes below. It found the earlier findings closed except where listed here.

| Severity | Finding | What changed here |
|---|---|---|
| P1 | Checking the revision of the chosen records misses a first purchase or a different purchase becoming the chosen one | A revision per account, `subsrev`, raised by anything that can change the choice and checked by the charge scripts even when nothing was chosen |
| P1 | Undo after the switch was not a complete contract: reads under the new rule write differently, and receipts outlive deleted counters | The mode changes only at the point of no return. `compare` runs the new rule without switching. Undo exists only before the switch, where nothing has behaved differently |
| P1 | Notice hooks were repeatable but could run out of order, and a departure with no retry was never seen | No hooks: the hourly job finds accounts with a purchase and no live device, with one key per departure |
| P1 | An excluded record could still be claimed under the first-presenter rule | Excluded is a terminal answer in `recordPurchase`; every writer keeps `excluded` and `ownerDeleted` |
| P1 | `clearDevicePurchase` checked the owner, then wrote | One script that checks the installation, the device's fields and the record's owner as it writes; both removals together; run on replays |
| P1 | The operator edit's member list and chosen periods could be stale | The script checks the member list and `subsrev` and the route retries; the edit is named as the one exception to the free floor |
| P2 | The resolver filtered by platform before choosing, but charging needs one purchase per rail | Two steps: account-wide choice per rail for charging, per-platform choice for showing |
| P2 | "One extra read" did not follow from the resolver | The actual reads stated, to be measured |
| P2 | "Nothing changes for users" at publication is not true: the app already takes Pro only from the server | Said so in the checklist and the QA list |
| P2 | Three different totals for the estimate | The checklist owns it |
| P2 | Properties stated absolutely that have exceptions; failure injection "between increments" of an atomic script | Exceptions named; the tests are a refusal before any write and a lost reply after |
| P3 | A row still said transaction id; "can be switched back" without its limit | Corrected |

Also taken from this review into the checklist: a look by Astra midway through the backend, the audit and roadmap rows that still named the first plan's steps, and the dates.

## Found while reading

Existing behaviour, not caused by this work, each to be checked before being called a defect:

- **Polar cancellation.** The webhook treats `subscription.canceled` as an immediate downgrade. If Polar sends that event when a customer cancels at period end, paid time is cut short. With 6 Polar subscriptions and none cancelled yet, it has not happened. Worth checking against Polar's documentation before the first cancellation.
- **App Store minutes reset.** `computePaidEntitlementState` takes the reset date from the App Store period end on every call. If a subscription is still active or in billing retry after that date has passed, the minutes may be zeroed on every request. Read from code, not reproduced.
- **API and MCP plan check.** `accountTier` looks only at the first device of the account. An account whose only subscription is from the App Store and whose first device is a Mac reads as free. The change above removes this.
- **The Polar webhook stores no delivery id and compares no time**, so a late event can undo a newer one. The hourly check bounds this to an hour.
- **A failed account deletion shows no message** in the app, and deletion is not blocked during a recording.
- **The pinned Polar API version** in `lib/polar.ts` is past its own stated deprecation date.
