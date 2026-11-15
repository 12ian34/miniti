# Ownership adoption and correction contract, 2026-11-10

AO0 engineering follow-through under the [ownership plan](../plans/account-ownership.md) and unchanged [3.9.0 scope](../releases/3.9.0.md). This specifies the B0/B2 arithmetic and journal boundary. It is not a production adapter, a migration command, AO0 completion or permission to change live records. The [source inventory](ownership-source-inventory-2026-11-10.md) remains the writer/reader map. Current backend application source is `a5c93d8c`; the reference scripts are separate from `app/` and `lib/` and have no runtime callers.

## Domain and selected policy

Establish a journal baseline for new, single-spelling and twin records alike. One installation has at most two legacy usage hashes, the proven lowercase and uppercase UUID spellings. A different UUID is never a twin. Authenticated installation/account identity, source-owner evidence and provider subscription identity must be resolved independently; numerical similarity establishes none of them. An ownership conflict stops adoption before any write.

For a captured server time, test each twin's reset boundary **before** comparing its minutes. `resetAt <= now` contributes zero current minutes. Missing, invalid or unrecognized boundaries/counters are unresolved, not a zero balance. This intentionally differs from the current other-member reader, which first selects the larger raw twin and can then discard a current smaller contribution. Both current windows contribute even if their end dates differ; selecting the resulting period still requires the B1/B2 period resolver. The selected B0 rule uses the active-subscription holder's boundary, otherwise the later one. A genuine reset clears the merged credit and opens a new period. Original twin snapshots remain for provenance/correction, not automatic carry into a renewed paid period. The previous blanket ban on an earlier reset was inconsistent with that rule and is withdrawn; two-rail selection and downgrade behavior still need explicit resolution.

For current contributions `a` and `b`, D10 stores gross `a+b`, credit `min(a,b)` and effective usage `max(a,b)`. A single record has zero credit. Lifetime counters are retained as their historical **gross sum**; they are not corrected by D10 and are not claimed to represent deduplicated real consumption. All allowance responses, old-client gates and seeds consume effective minutes. New charges increase gross and lifetime without increasing credit. A reset creates a new period with zero gross and credit; it does not erase the previous period or lifetime.

The offline [reference model](../../../miniti-api/scripts/ownership-reference.mjs) accepts already-decoded nonnegative finite numbers and explicitly supplied time/period identities. Its numerical ceiling is an oracle input bound, not a new public limit. Production Redis accepts some historical signed/string forms: their normalization, precision and exceptional disposition must be tested before adoption. Never silently clamp corrupt or negative historical values into free allowance. The model neither chooses a subscription rail nor authenticates a late settlement.

Docs lookups are separate. Before the selected lookup activation, retain the explicitly specified legacy diagnostic counters. At activation, the new account/UTC-month balance starts at zero with the planned one-time pre-activation credit. Do not apply this minutes oracle as another lookup seed, or give lookup counters a subscription-cycle reset. No new docs allowance is implemented here.

## Journal operations and correction semantics

The planned production journal needs a schema version, monotonically increasing per-device sequence, operation identity, payload digest, captured period/owner references, committed effect and receipt identity. A baseline entry must retain **both** original hash snapshots (or immutable durable references with integrity checks), including the original lowercase hash. Archiving only the uppercase twin cannot support correction of a rule that combined the two incorrectly. Preserve source-owner evidence before overwriting auth mirrors. Private snapshots and identifiers belong in restricted operational storage, never tracked fixtures or ordinary logs.

| Operation | Meaning to preserve on replay | Atomic companions / acceptance requirement |
|---|---|---|
| Adopt baseline | Frozen original contributions, period decisions, gross and credit, lifetime and field-specific merge decisions | Canonical record, baseline marker, immutable source snapshots and journal commit together; conflict or validation failure writes none |
| Charge minutes | Accepted **delta**, admitted period/owner and operation identity | Device/account counters, receipt/root finalization and charge record stay one transaction; do not replay cumulative response totals as deltas |
| Start session | Exactly one `sessionCount` increment for a newly admitted root | Root/index insertion and journal entry commit with the increment; replay/renewal has no new increment |
| Replace effective minutes | Absolute administrator intent for the displayed balance; gross becomes requested effective value plus retained credit | Revision precondition prevents stale replacement; lifetime is unchanged unless a separately named operation changes it. After B2, target the authoritative account adjustment, not a device mirror alone |
| Reset / provider period change | Explicit old/new period identities and which counters reset, with event ordering evidence | A stale provider or passive-reset snapshot cannot rewind the current period or overwrite a concurrent charge. Credit clears only for the new period; history remains |
| Metadata patch | Named fields and conflict rules, never a whole-hash stale replacement | Manual labels, flags, auth mirror, verification freshness and provider state each have their existing owner/order checks. Unknown fields require an explicit disposition |
| Cost/diagnostic increment | Its own counter/unit and idempotency semantics | Must route to the adopted key without becoming another allowance charge. Preserve global/day/platform diagnostics under their existing contract |
| Seed account | The device's effective contribution at a precise sequence and period, plus gross/seedCredit and a permanent source-account claim | Account opening balance, `usageLedgerSince`, device claim and per-device seed contribution commit together; a later destination seed excludes the claimed device |
| Correct baseline | A replacement opening derived from retained evidence and a reviewed rule, then replay later operations by meaning | Revision/CAS and idempotency cover the device correction, any source-account seed adjustment, audit record and receipt together; no deleting/recreating the canonical record |

The reference model executes the minutes, reset, effective replacement, seed and correction rows. It does **not** implement metadata, provider, diagnostic, session-root or cross-store transactions. The table is their required contract, not evidence that those writers are already converted.

A correction is not “restore the old hash and add all later numbers.” For example, an administrator setting the visible balance to 50 must still leave 50 plus later charges after a baseline correction. Replaying that replacement as a delta would change the administrator's meaning. A reset similarly leaves the newer period alone when an earlier opening is corrected.

### Correction after account seeding

B2 must retain an immutable original per-device seed component and separately ordered correction records with device journal sequence, source account and account period, device period, gross and credit. A single aggregate opening plus `usageClaimedBy` is insufficient for later correction. Recompute the component **at its original seed sequence**, not using the device's current balance. Produce signed deltas for gross, seedCredit and effective opening. Apply those deltas to the source account's opening component, preserving every other device seed and every later account charge. They are not automatically a delta to the final ledger: if an account-level absolute replacement occurred after the seed, replay that account history with the corrected component so the later administrator intent still wins. A later period rollover must likewise remain separate. The model returns the seed-component change only; account-history replay and its atomic adapter remain required implementation work. A zero effective delta may still require a gross/credit adjustment for reconciliation.

Example: original gross 600, credit 200; a pre-seed charge of 10 makes the seed 410 effective. A later device-mirror charge of 20 is not part of that seed. Correcting the original gross to 500 with credit still 200 changes the seed to 310, an account adjustment of −100. It does not set the account's total to the device's current 330. With no later account-level absolute replacement, if other seeds contributed 70 and later account charges 90, account usage changes from 570 to 470. Claim ownership remains A even after the installation moves to B. A seed made after an intervening reset is unaffected by a correction to the older opening.

The model returns this adjustment; it never writes an account ledger. The production correction must commit it with the canonical correction and a deduplicated correction record, or reject the operation without changes. If the claimed account/period, source snapshot, journal segment or attribution is missing, stop with an unresolved correction. Never guess a destination, erase subsequent charges or silently fall back to device sums. Account deletion/tombstone and retained billing-history treatment require the B3 authorization/deletion tests before this command exists.

Original receipts remain immutable after correction. An exact retry returns its original receipt and does not apply the correction again. A separate current-usage read shows the corrected balance; a receipt's old cumulative total is not reconciliation input. The same operation identity with a different payload is a conflict. A correction must not replace successful payment/session receipts to make their old totals look current.

## Storage and concurrency requirements before implementation

1. Adoption, every subsequent writer and the correction path share the canonical-device revision boundary. Updating header normalization or the normal `getOrCreateDevice` path alone is insufficient. The current `atomicHash.compareHash` ignores selected touch fields, so its expected whole-hash contract must be reconciled with the new journal/revision fields; do not nest a non-atomic adopt call before an old CAS or plain HSET.
2. Validate all key types, numeric values, snapshot/version expectations, destination archive keys, index bounds and operation payloads **before the first Lua write**. Redis script execution is atomic with respect to other clients but does not roll back earlier writes after a script error. Test wrong types in every companion key, not only the device hash.
3. Pre-B0 v2 roots retain an uppercase `storageDeviceId`. Resolve that captured alias to the canonical record inside the new transaction without altering root account/session identity or recreating the twin. Read legacy receipts under both spellings for the planned transition window; never rewrite receipt contents merely to change a key spelling. Current legacy receipt TTL is 30 days, v2 35 days. The proposed dual-read window is not permission to shorten either existing TTL.
4. Account seed/correction/transfer needs atomic revision checks across the relevant device/account records, or tested fencing at every commit. The existing 120-second lease and owner-safe unlock do not by themselves prevent an expired worker from committing. B1 subscription ownership and B5 connections must be established before any membership/source-evidence overwrite, including revoked-ID re-creation.
5. Subscription reverse indexes must converge with adoption through either the same bounded transaction or a durable, idempotent reconciliation record. A best-effort pass after renaming the hash is not proof that renewals cannot miss the device. Unknown/unbounded fan-out stops readiness rather than extending one script without limit.
6. Journal/source snapshots retain at least the planned 90-day correction window; attribution and receipts preserve their separate 35-day minimum where specified. Refresh/expiry rules must keep snapshots and required journal segments together. Corrections beyond retained coverage may preserve current counters or remain unresolved, but cannot reconstruct history from cumulative receipts. Never silently truncate a full journal. Measure cardinality and use bounded scan/checkpoint tooling with sequence/hash continuity checks before applying a reviewed result through revision CAS.
7. Production journal loading must reject a missing or mismatched committed receipt before returning an idempotent replay. The oracle does not validate receipt integrity: a manually damaged journal can yield an undefined receipt. Its JavaScript number arithmetic also exhibits floating-point drift. Choose and test exact accounting units/conversion boundaries before production implementation; a blanket integer conversion must not silently round existing legacy fractional minutes. These are known model limits, not storage behavior proven safe.
8. The pure model is an oracle for a small synthetic device history. Its whole-journal projection is intentionally unsuitable for a production request path. Production writers append one bounded event; correction prepares a bounded verified plan off the request path, then compares the ending revision atomically. No network/provider call belongs inside that commit boundary.

## Operation-to-real-storage acceptance map

All rows below are **pending**, including tests against disposable Redis. The oracle's sequential replay is not concurrency, durability, Lua or provider evidence.

| Production entry / source | Required discriminating storage scenario |
|---|---|
| `usage.ts` creation, passive reset, `touchDevice` and entitlement CAS | Race uppercase first write, lowercase first write, metadata touch and reset with one charge. One adoption, no lost fields/charge, no recreated twin; expired lease worker fails its fence |
| `managedAccounting.ts` START and FINISH scripts | Start before adoption, finalize after; start races baseline; lost start/end reply; both key spellings; root/receipt/index wrong-type fault before first write; exact once and same accepted duration |
| `legacyAccounting.ts`, live/prerecorded session routes | Existing uppercase session and lowercase retry, correct legacy zero behavior and duration cap; raw-spelling receipt hit; sessionCount and finalization remain atomic with their journals |
| `usage.ts` direct increments and docs lookup writers | Every indirect caller routes through adoption; retries have a stable operation identity, not a fresh id per retry; docs activation epoch and reservations use their independent zero-opening contract |
| Polar/Apple linking, downgrade, recompute and callback fan-out | Renewal/reset races charge/correction; stale and replayed event; ownership conflict; reverse-index reconciliation resumes after failure; no old snapshot overwrites a newer period |
| `costs.ts` OpenAI/Jev and metadata writers | New operational counters reach canonical hash; private content is absent; no change to allowance or provider-cost counting semantics |
| Admin replacement/label/disabled | Replacement racing charge conflicts/recomputes; a later correction preserves the absolute intent. Manual label and disabled flag survive adoption; no mirror-only post-seed update |
| `clientAuthStore` create/revoke/move/recovery | Seed and claim race attach/reused-ID creation; source evidence retained; B cannot seed A's balance; correction targets A's original component after move |
| Correction / seed tools (not implemented) | Two corrections, lost reply, restart, journal gap, expired snapshots, wrong account period, missing claim, post-seed charges, reset between baseline/seed and multiple-device aggregate; no partial device/account commit |

## Executed evidence and remaining AO0 gates

Run from `miniti-api`: `node --test scripts/ownership-reference.test.mjs`. The suite uses synthetic names and explicit clocks. It checks D10 and boundary eligibility, 441 small counter pairs, old-client effective arithmetic, malformed input rejection, lost-response replay, immutable receipts, absolute replacement, resets, late-period arithmetic, one-time seed claims and correction deltas. It also compares corrected histories with histories built from the corrected baseline first, across seed/reset/replacement orderings. No environment file, credentials, database, provider or network is used. Tests of a “late charge” validate arithmetic only; they do not authorize that charge.

Still open: deterministic two-rail period selection and period switching, exact raw Redis decoding/precision, all production journal/adoption adapters, concurrency/fencing and resource bounds, late-settlement authorization, provider first-bind correlation, D6 notice outbox/deduplication, exhaustive indirect callers, private collision/orphan inventory and D9 disposition, correction commands and rehearsal. B0/B2 and AO0 are not accepted by this model. The 48-hour transition budget, 24 green reconciliation hours, compatible public clients and separate release authorization remain unchanged.

## As built for AO1, 2026-11-15: what replaces the typed journal

The first device-record layer was built in `miniti-api` on branch `ao1-device-records` (not deployed, switch off by default) and reviewed by Astra in several rounds. It keeps the arithmetic above and departs from this contract in the ways below. Where this section and the text above disagree, this section describes the code.

**No journal entry per charge.** The journal holds the adoption baseline and each correction, for audit. Three stored facts do the work the typed replay was meant to do:

- **The originals.** Adoption keeps both original hashes unchanged for 90 days (`device_adoption:{id}`) and archives the uppercase twin (`device:merged:{ID}`).
- **`usageEpoch`.** A counter on the device record that moves, in the same write, every time the current minutes are cleared (passive reset, a new Polar or App Store period) or set by the operator, and never for a charge or for a boundary that moves while the minutes stay (a downgrade). "Same epoch as at adoption" means the minutes still continue from the opening. Reset dates cannot say this: a downgrade moves the date and keeps the minutes, and a first subscription can clear the minutes and keep the date.
- **A fence on the old key.** Adoption leaves a text value at the uppercase key. Redis refuses any hash command on it, so a write still aimed at the old spelling fails when it commits and no record can appear beside an adopted one. A failed accounting write is retried by the client; best-effort telemetry writers that swallow errors lose that one increment.

**What a correction can do.** It recomputes the opening from the stored originals at the adoption instant and applies the difference in one script. If the epoch is unchanged, the difference is added to the current minutes, which keeps every later charge. If the epoch has moved, the current minutes are left alone and only lifetime changes. The same correction id applies once.

**What a correction cannot do, by decision.**

- It does not replay operations, and it cannot reconstruct period history that was lost.
- A corrected rule that changes the period itself is refused. If a wrong boundary has already reset the minutes, the repair is the operator setting the minutes with the admin edit. That starts a new balance (the epoch moves) and does not change `resetDate`; a wrong period field needs its own repair.
- After account seeding (B2) a correction must also revise the device's seed component on its source account, or refuse a seeded device. Neither exists yet. This layer must not be described as meeting that part of the contract.

**Operator minutes edit.** The admin edit sets the effective minutes and moves the epoch in one compare-and-set. The adoption credit ends with it, so gross equals effective afterwards. The table above said gross keeps the retained credit; the code does not, because the credit describes the opening the edit has just replaced.

**Stored value.** The canonical `minutesUsed` holds the effective minutes (the larger of two current records). Gross for reporting is that plus `migrationCredit` while `migrationCreditEpoch` equals `usageEpoch`. No existing reader had to change.

**Activation order.** Four steps, in this order, each one an operator action:

1. Deploy the code with the switch off. Nothing changes.
2. Turn the switch on. Nothing is adopted yet, because the store is not prepared. From this moment a request under an irregular id spelling (neither all lowercase nor all uppercase; the API accepts such ids, the apps do not send them) no longer starts a new record: it is routed to the device's uppercase or lowercase record. A record that already exists under an irregular spelling keeps serving.
3. Wait until every request admitted before step 2 has finished on every serving deployment (longer than the longest request, 60 seconds, and until no older deployment serves traffic). After that no irregular record can come into being. Then repair any that exist by a reviewed repair.
4. Run the merge pass. It prepares the store, which refuses while any irregular record exists, and only then are devices adopted, by their own writes and by the pass.

Step 3 is the reason for the order: a request admitted before step 2 could otherwise write an irregular record after preparation had looked, and adoption would merge the two regular records around it. The ops check `device_twins` reports any irregular record it finds while the switch is on, but detection does not undo an adoption; the wait is what prevents it.

The switch must never be turned off again once devices have been adopted: uppercase requests would resolve to the fenced key and fail.

**What the fence does and does not guarantee.** It guarantees that no write reaches the uppercase key of an adopted device. It does not cover a third, irregular spelling; the activation order above is what keeps one from appearing.
