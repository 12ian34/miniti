# Ownership source inventory, 2026-11-10

AO0 preparation for the unchanged [3.9.0 scope](../releases/3.9.0.md). Backend source inspected at `a5c93d8c282800d97a05d027ab2312af6e090ba8`. This is a source inventory, not live customer inventory, a migration rehearsal or AO0 acceptance. No backend source, data, credentials or provider configuration changed. The [ownership plan](../plans/account-ownership.md) owns policy, staging and completion.

## Device-hash writers

All paths below must participate in canonical adoption before B0 activates. Changing only request-header normalization is insufficient. `usage.ts` uses both `atomicHash.compareHash` and ordinary writes; every writer needs its own adoption/journal contract.

| Source owner in `miniti-api` | Current mutation | Required migration boundary |
|---|---|---|
| `lib/usage.ts`: `getOrCreateDevice`, `touchDevice` | Creates/normalizes raw-spelling hashes; passive resets; last-seen/platform/version and mode metadata | Adopt before CAS or plain writes; preserve manual labels and distinguish metadata from counter operations |
| `lib/usage.ts`: `incrementUsage`, `incrementDocsLookups` | Period/lifetime minutes, lookup counters, global/day/platform/device diagnostics | Atomic attribution and replay; diagnostics are not another account balance |
| `lib/usage.ts`: subscription linking, downgrade, entitlement recomputation | Subscription fields, period boundaries, renewal minutes reset, tier | Preserve provider-event ordering and account ownership; reset is a journalled operation, not merely an increment |
| `lib/apple.ts`: entitlement metadata helpers | Apple verification/webhook state on device hashes, plus subscription state | Canonical routing for metadata too; retained subscription owner independent of current device membership |
| `lib/costs.ts`: OpenAI/Jev recording | Direct per-device token/request increments alongside model/day totals | Must not recreate an uppercase twin after adoption; costs remain operational counters, not allowance charges |
| `lib/clientAuthStore.ts`: installation write/revoke/move | Enrollment/account mirror fields on device hashes | Adopt under the ownership transition protocol; keep original membership evidence until asset adoption is durable |
| `lib/managedAccounting.ts`: `START_ACCOUNTING_LUA` and finalization | Start increments `sessionCount` on `KEYS[3]`, the captured `device:{storageDeviceId}`; finalization writes minutes to that same spelling. `resolveUsageDeviceId` currently keeps an existing spelling | Adopt before both start and finish transactions; reconcile the captured spelling and resolver without recreating a renamed twin |
| `lib/legacyAccounting.ts` | Lua finalization writes counters, receipt and optional session deletion together | Preserve atomicity, authorization, exact session identity and existing retry semantics |
| `app/api/session/route.ts`, `session/prerecorded/route.ts` | Direct `sessionCount` increment after grant/session creation | Route these direct increments through adoption as well |
| `app/api/admin/devices/route.ts` | Direct replacement of minutes, disabled flag and label | Journal replacements with before/after meaning; never replay them as arbitrary increments |

The scan covered production `.ts` and script `.mjs`/`.ts` sources with `device:` references and followed the generic hash helper. The listed helpers fan out to usage, insights, session, provider verification/restore/webhooks, integration status/send/search, account and web readers. Runtime coverage, exhaustive indirect caller tests and live inventory counts remain open.

## Namespaces and payloads beyond `device:`

| Keys or embedded identity | Current source behavior | AO0 requirement |
|---|---|---|
| `accounting:v2:{lowerDevice}:{account}:{lowerRecording}` and `accounting:index:{lowerDevice}` | Root stores original account, normalized device and exact storage spelling; 35-day retention, bounded 4096-session index | Keep replay margin and original attribution. Define settlement authorization after a move, separately from permission to read the old receipt |
| `session:{session}` and `session_end:{device}:{session}` | Session payload retains spelling; live session TTL 4h, prerecorded 24h; legacy finalization receipt TTL is **30 days** | The plan's proposed 35-day transition dual-read window is a requirement, not the current legacy receipt TTL. V2 already uses 35 days. Do not shorten either path or reinterpret stored cumulative totals as individual charges |
| `usage_daily_by_device:{day}`, `docs_lookups_daily_by_device:{day}`, `active_devices_daily:{day}` | Hash fields/set members normalized lowercase; day/global/platform counters alongside them | Preserve diagnostics and deduplicate identity where required; never seed account usage from these historical aggregates |
| `local_usage:receipt:{lowerDevice}:{report}` | 35-day idempotency; report window 30 days; current membership checked atomically | Local duration is unbilled telemetry, not managed allowance. Keep separate attribution/deletion policy |
| `local_usage:daily_devices:{day}`, `local_usage:devices`, `local_usage:accounts` | Lowercase device fields; daily hashes/index expire 400 days; revoke removes device breakdowns across bounded 431-day keys, delete removes account breakdown | Preserve cleanup semantics and anonymous totals; do not merge these into billing counters |
| `polar_sub:{sub}:devices`, `apple_sub:{transaction}:devices` | Member spelling comes from linking caller | Normalize members without changing subscription identity; cross-account collisions require reviewed ownership mapping |
| `apple_sub_state:{transaction}`, provider event keys | Subscription/event keyed, not device keyed; device mirror updates are separate | Do not rename provider identity; preserve event ordering and idempotency |
| `auth:installation:{lowerDevice}`, account membership, refresh/challenge/replay records | Auth helpers normalize installation identity; proof/token data have their own expiry and account bindings | Keep cryptographic identity and replay contracts; an account move must not resurrect old credentials |
| `client_events:seen:{device}:{event}`, `client_events:device:{device}`, `client_capabilities:{lowerDevice}` | Diagnostics and capability snapshot ingestion; revocation removes capability snapshot | Classify separately from usage. Preserve bounded retention and current authentication checks |
| `ratelimit:{identifier}:{endpoint}:{bucket}` | Identifier may be device or IP; expiration derives from endpoint window plus 10s | Normalize only device identifiers; do not lowercase arbitrary opaque identifiers or change IP policy |
| `checkout:return:{lowerCheckout}` | Seven-day record captures account/device; device normalized at write | Durable subscription ownership must outlive this return-UX correlation record; do not infer historical owner after expiry |
| `{google,attio,twenty}:token:{device}` | Current token helpers use supplied spelling; refresh/store/disconnect all mutate them | B0 retains dual-spelling lookup until B5 account adoption. Callback, refresh and disconnect need ownership-safe routing too |
| Provider OAuth state payload `deviceId` | Twenty state has Redis TTL 600s. Google/Attio `save*OAuthState` currently use SET without expiry; callbacks do not check `createdAt` | The plan's universal ten-minute TTL is inaccurate. B5 must define stale/in-flight callback behavior explicitly; source inspection does not show which old states exist in production |
| Postgres meeting/device provenance, API tokens, cloud sequences and connections | Separate account/device columns and account-keyed namespaces | Reconcile through B4/B5 and cloud/API/MCP gates; a Redis device-key rename does not migrate SQL ownership |

## Readers and account-level dependencies

Static follow-through at the same backend source pin. These are migration entry points, not newly executed behavior or an exhaustive indirect-call proof.

| Source owner | Current read/decision | Required acceptance case |
|---|---|---|
| `usage.ts` / `getOrCreateDevice` | Applies account entitlement and usage overlays to the caller's device. Reads can create/touch/reset that device, so a read endpoint is not necessarily storage-read-only | Adoption before passive writes; candidate/account ledger yields the same response contract through `/usage`, session admission/end, insights/classify, subscribe/restore and integration preflight |
| `accountUsage.ts` / `otherDevicesUsage` | Traverses current active membership; selects the larger **minutes** record across UUID spellings, then takes both minutes and docs lookups from that selected record; then excludes the selected record if its reset date has elapsed. A stale larger twin can therefore hide a smaller current-period twin | D10 credit is a migration policy, not this read heuristic. Filter each twin by period before comparing contributions; add stale-larger/current-smaller fixtures. Different lookup values on the non-selected twin need explicit B2 treatment. No member change may move already-consumed account usage |
| `accountEntitlement.ts` / `findSponsor` | Walks active members, reads both spellings and takes an eligible device subscription; overlay is in memory | Account subscription reader must retain eligibility and owner filtering after the purchasing device moves or is removed; rollback cannot grant the destination a source-owned subscription |
| `cloud.ts` / `deviceTier`, `requireCloudDevice` | Tries device spellings and sponsorship before cloud Pro admission; returns authenticated account and normalized device | Read retained account entitlement while preserving proof, managed-mode, allowlist and account rate-limit gates |
| `apiTokens.ts` / `accountDeviceId`, `accountTier`, `requireApiToken` | Picks a sorted active installation; an account with no live device is free. PAT/OAuth read authorization requires Pro | A paid zero-device account needs account-level entitlement for API/MCP access. Preserve token scope, expiry, revocation, rate limits and account binding. Existing no-device-is-free test must change with B1/B3, not be silently deleted |
| `webAccount.ts` / `accountUsage` | Uses the first live installation and prefers an existing uppercase hash; returns null without any device | Paid zero-device web Account must show retained account allowance, period and subscription without fabricating a new device record |
| Polar webhook / `app/api/webhooks/polar/route.ts` | Active/updated events use customer external device ID and subscription reverse membership; cancellation/revocation updates linked devices | Durable owner attribution must route renewals after device moves/removal and preserve source ownership on first bind. Legacy external ID is a device reference, not permanent account proof |
| Apple / `applyAppleEntitlementToLinkedDevices` | Iterates original-transaction reverse device membership, writes device entitlement/freshness and persists subscription state/events | Preserve original transaction identity, environment and event ordering while adding account ownership; no move or restore may reassign a known owner |

The normal request path can still load a raw caller record while the other-member helper chooses the larger twin. Do not describe the existing reader as a complete canonicalization algorithm. Provider correlation, reverse-index races and all indirect readers remain subject to implementation tests.

## Postgres and account-bound assets

Read `db/migrations/001_cloud.sql`, `002_folders.sql` and the production `PostgresCloudStore` methods. PostgreSQL device columns are `uuid`; account IDs are text. UUID casing therefore is not a second SQL identity, but JSON payloads and Redis keys need separate treatment.

| Asset / production source | Existing owner boundary | Migration requirement |
|---|---|---|
| `meetings`, `cloudStore.putMeeting` | Primary key `(account_id, id)`; creator/updater UUID columns; update CAS and transcript-revision guard; conflict updates preserve the original creator | B4 explicit copies need new provenance/authorization semantics. Renaming a device hash must not move a meeting or rewrite its source account. Preserve CAS, trim guard, tombstones and external-source uniqueness |
| `meeting_changes`, `meeting_folder_catalogs`, `cloud:seq:{account}` | Account-scoped change queries/catalog; cached sequence is monotonic with 600s TTL | Keep source and destination cursors/folder ownership separate; explicit copies generate destination changes rather than importing a source cursor |
| `api_tokens`, OAuth codes/grants, web sessions | Account IDs bind access; token creator is a UUID provenance field, not the asset owner | Device sign-out/move must not migrate account tokens/grants/sessions to the new account. Retain current expiry/revocation checks and define zero-device paid access through the new account entitlement reader |
| `account_emails`, `login_links` | Verified email unique per account; email actor and enrollment-link device are UUIDs; links also retain account/purpose/expiry/consumption | D6 reads the retained verified account email. Notice transition identity/deduplication is new design. Do not infer ownership from an enrollment link after expiry or change generic one-time consumption semantics |
| `cloud.purgeCloudAccount` | Purges meetings/catalog/change feed, revokes tokens/grants and clears sequence cache; `everything` additionally removes email and revokes web sessions | Keep explicit deletion distinct from leaving/moving the last device. B3 dormancy must not call the deletion path; B4 copy is not account merging |

## Existing fixture starting points

These files were read to map later implementation checks, not run in this package. Their current passing status is not asserted here.

- `accountUsage.test.ts` and `accountEntitlement.test.ts`: current member aggregation, expired/reset periods, foreign/revoked members and platform eligibility. Add account-ledger/owner behavior instead of only changing mocked return values.
- `apiTokens.test.ts`: PAT/OAuth scope, expiry and Pro checks, including the current explicit zero-device-is-free expectation. Pair the changed expectation with retained paid account storage and revoked/deleted account cases.
- `cloudStore.integration.test.ts`: production Postgres through `SYNC_TEST_DATABASE_URL`, disposable account rows, conflict/change/delete/search paths. Requires an isolated configured database; no production connection or test was opened here.
- `cloudPrivacy.postgres.test.ts`: optional PGlite executes production SQL for CAS, trim guard, account isolation and racing writes. Add B4 provenance/copy/tombstone races and folder handling; this does not replace Neon transport evidence.
- Provider tests and migration real-storage fixtures still need an exact operation-to-test map for replay, first-bind attribution, index adoption, concurrent moves and partial failure. This table is a starting map, not AO0 closure.

## Membership and recovery boundaries

`writeInstallation` is shared by create/migrate/recovery/email enrollment. It writes the installation, membership and device mirror, so callers that appear to repair credentials can also replace ownership evidence. `moveInstallation` takes ordered account locks, updates destination membership/installation/source membership, invalidates the refresh family and mirrors account identity. Its current last-device path tombstones the source account. `revokeInstallation` marks credentials revoked, removes local-usage/accounting identity, removes membership and marks the device mirror revoked. `deleteAccount` purges under its lock before revocation/tombstone. These existing semantics must be replaced only through the selected B1/B2/B3 contracts, not incidentally during B0 normalization.

Current v2 and authenticated legacy finalization require the installation still belongs to the original active account. Merely retaining `accountId` in a receipt does not authorize late settlement after a move. The new contract needs a bounded, replay-safe authorization mechanism that permits charging admitted work without exposing the old account's receipt to the destination. Current revoke cleanup of accounting roots also needs reconciliation with that contract.

## Decisions and evidence still needed

Ian confirmed D3/D4/D5 on 2026-11-10: subscriptions stay with their owning account and users sign in there, Polar and App Store subscriptions may coexist, and account merging is not offered. Deterministic two-rail period selection and D9 orphan disposition remain open under the owning plan. Ian confirmed D10 on 2026-11-10: effective current usage is the larger counter through migration credit. D6 is also confirmed: one notice to verified email per paid-account transition to zero devices, none without verified email. Delivery deduplication and counter/journal implementation remain unbuilt. Remaining implementation and orphan-disposition questions are not approval. No current read-time twin heuristic establishes historical disjointness: current `otherDevicesUsage` chooses the larger minutes record for another member, which cannot prove whether two historical counters overlap.

Before AO0 closes: finish exhaustive indirect-reader/provider-event checks and operation-to-real-storage-fixture mapping; count twins, subscription collisions and orphaned accounts in a separately authorized bounded inventory; settle policies and deterministic period selection; specify journal coverage for every operation above, race-safe membership/settlement and correction commands; rehearse failure/retry and measure migration volume against the 48-hour transition budget. No production inventory, provider request, migration write or ownership-policy implementation occurred here.
