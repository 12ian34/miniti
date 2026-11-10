# Account minutes-window transition candidate

2026-11-10. Engineering proposal and offline executable reference for B1/B2, under the confirmed D3/D4/D5/D10 policies. This does not activate account billing or close the account-period gate. The [ownership plan](../plans/account-ownership.md) remains authoritative; [settlement authority](ownership-settlement-design-2026-11-10.md) and [adoption/correction](ownership-adoption-contract-2026-11-10.md) remain separate requirements.

## Separate the three decisions

1. **Ownership:** B1 establishes the immutable owner of each purchase. This model accepts only an already reconciled registry of that account's owned subscriptions. It cannot discover ownership, trust provider metadata, resolve a backfill collision or consume customer-supplied account IDs.
2. **Entitlement:** provider status/grace and consuming-platform eligibility determine the current limit. Apple still does not grant Mac Pro; both rails do not add two 5,000-minute allowances. The model's `eligible` input is account-level provider eligibility, not permission for a particular device to record. Provider status/time validation and entitlement enforcement remain adapters to implement.
3. **Usage window:** all the account's managed minutes share one accounting window identity. A selected subscription supplies its scheduling evidence. Changing the selected subscription is distinct from creating a new allowance.

Candidate precedence preserves the current device-level Polar-first rule and makes the account result independent of member traversal. Among eligible purchases on one rail, use B1's earliest `boundAt`, then the exact opaque purchase ID for equal timestamps. A stale/future period on that winner is unresolved; do not fall through to another purchase or free allowance. A complete, stable registry snapshot produces the same winner in either input order. This does not claim identical history when different incomplete snapshots arrive at different times, nor make local bind timestamps independent of webhook arrival order. Provider/backfill ordering and registry reconciliation remain prerequisites.

## Persisted state and transitions

The candidate adds an immutable accounting-window ID separate from mutable scheduling evidence: selected source, provider start, next boundary, original window opening and observation time. The account's current-period pointer continues to address `usage:account:{acct}:{period}`. The period segment would be an opaque server-owned window ID, not a value re-derived from whichever rail is currently selected. This revises the plan's proposed rail/start key derivation, not the namespace, and remains a proposal until the integrated period contract is accepted. Adapters must choose an idempotent ID and retain prior IDs, receipts and historical source decisions; the oracle's caller-supplied IDs do not prove that persistence.

| Input / transition | Reference decision | Balance, credit and admitted work |
|---|---|---|
| First migration seed into an already resolved paid/free account | Initialize one window; external seeding supplies existing effective opening | Initialization is not a zero-balance instruction; retain B0/D10 opening and per-device claim |
| Same source and same period | Retain | No reset |
| Add a secondary rail while Polar remains selected | Retain | No second allowance |
| Replace selected paid rail, including cancel/expiry followed by another eligible rail | Retain same window ID; schedule from the new source | No copying, zeroing or reseeding; pending admissions still name the same window |
| Paid to free | Retain same ID; schedule the next UTC month boundary | Usage and credit carry until that boundary; current free limit applies separately |
| Free to paid | **Pending classification, not implemented** | Distinguish genuine first paid activation from restore/reactivation before deciding whether to open a paid allowance |
| Same paid source, verified later non-overlapping current billing period | Rollover once | New ID starts a new allowance; old window remains for late settlements and correction |
| Same free source, next UTC month | Rollover once | New window, no old migration credit; missed empty months need not acquire balances |
| Same provider start, corrected future end | Retain ID and update boundary | No inferred renewal |
| Eligible but elapsed/future period, stale period or overlapping period correction | Pending reconciliation | No speculative reset or free fallback |

A later verified same-source period may skip cycles with no observed activity. Repeated observation of that period retains the newly opened ID. The model rejects a caller reusing the immediately previous ID, but only storage can reject every historical ID collision or make a lost-response retry atomic. Pending is a refusal to decide, not a new production HTTP response or a guarantee of uninterrupted recording.

Changing scheduling source never changes an existing admission's owner or window. Because the balance stays under the same ID during a switch, an in-flight charge does not need a second debit or copied carry balance. At a genuine rollover, a later authorized end updates the old window only, under B2's deliberately changed admission-period semantics. Read/limit checks use the current window; lifetime telemetry remains distinct.

## Preserve the existing first-paid allowance

The shipped `linkDeviceToSubscription` resets minutes when there is no stored Polar period start or when a new start arrives. Apple does likewise for an eligible new Apple period when Polar does not take precedence (`lib/usage.ts`). A generic rule that retained all free usage on first upgrade would therefore change how many paid minutes the buyer receives. This candidate does **not** select that change.

The next extension must model a verified first-paid activation separately from restoring/reactivating an already applied purchase period. Preserve the first paid allowance, while preventing repeated restore or rail toggling from resetting it again. It needs a durable per-account/purchase/period application receipt under the same revision as the accounting-window transition, including lost reply, first bind during seed, prior cancellation, another active rail and delayed activation. Do not infer a first grant merely because the current scheduling source is free. No product decision is requested by this candidate; preservation of the shipped first-paid outcome is the implementation requirement.

The candidate also waits for current provider-period evidence rather than invoking the shipped passive date advancement. This can affect availability during delayed or missing renewal delivery. Before activation, specify authenticated refresh/reconciliation and client error/retry behavior for stale active/grace records; do not ship the pure model's pending states as a blanket new recording block. Neither status eligibility nor a safe availability policy is implemented here.

## B0, correction and lookup boundaries

The selected B0 opening remains gross sum minus the smaller current contribution. Free 200 through December 1 plus active paid 400 through November 14 yields gross 600, credit 200 and effective 400. A verified November 14 renewal opens a fresh paid window and clears the credit; the free snapshot does not add 200 back. The test composes the period decision with the existing journal oracle. No claim is made that this chooses the B0 boundary for ambiguous competing active twins; B0 field conflicts/source proof still require resolution before adoption.

Source changes preserve gross/credit in the same window. Corrections continue to replay the original account seed component, not replace an unrelated destination or current-period total. The account transition record must be included in the correction/reconciliation history before a real adapter is accepted.

The 100 free docs lookups use their independent account/UTC-month ledger and selected activation credit. This minutes model neither seeds nor resets lookup counters. Pro/BYOK lookup eligibility and tier-at-admission remain with the lookup contract.

## Executable scope and remaining gates

Backend `scripts/account-period-reference.mjs` is an offline candidate, with no runtime imports, IO, environment or wall clock. `scripts/account-period-reference.test.mjs` uses synthetic IDs/clocks and composes with the existing journal model for credit and late-charge examples. The 64-record registry bound is a model input bound, not a production cap. Amount precision, serialized state decoding and full historical receipt integrity remain outside it.

Required before accepting a production resolver: first-paid activation/restore receipts; complete owner-filtered registry snapshots and provider ordering; actual status/grace/expiry eligibility; safe refresh behavior when period data is stale; fenced revision CAS and before-write validation; historical window-ID uniqueness and atomic replay; counters and state transition committed together; mirrored old-client usage/reset compatibility; real storage concurrency and correction replay. No new endpoint, Redis key, migration, provider request or account state is written by this package. The [release evidence](../releases/3.9.0.md#account-period-transition-reference) owns exact test and review status.
