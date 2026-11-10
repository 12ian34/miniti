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
| `lib/managedAccounting.ts` | Lua finalization writes the exact `storageDeviceId` captured by a v2 root | Resolve that captured spelling inside the transaction without recreating a renamed twin |
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

## Membership and recovery boundaries

`writeInstallation` is shared by create/migrate/recovery/email enrollment. It writes the installation, membership and device mirror, so callers that appear to repair credentials can also replace ownership evidence. `moveInstallation` takes ordered account locks, updates destination membership/installation/source membership, invalidates the refresh family and mirrors account identity. Its current last-device path tombstones the source account. `revokeInstallation` marks credentials revoked, removes local-usage/accounting identity, removes membership and marks the device mirror revoked. `deleteAccount` purges under its lock before revocation/tombstone. These existing semantics must be replaced only through the selected B1/B2/B3 contracts, not incidentally during B0 normalization.

Current v2 and authenticated legacy finalization require the installation still belongs to the original active account. Merely retaining `accountId` in a receipt does not authorize late settlement after a move. The new contract needs a bounded, replay-safe authorization mechanism that permits charging admitted work without exposing the old account's receipt to the destination. Current revoke cleanup of accounting roots also needs reconciliation with that contract.

## Decisions and evidence still needed

D3 subscription transfer, D4 two-rail period selection, D5 no merge and D9 orphan disposition remain governed by the owning plan. Ian confirmed D10 on 2026-11-10: effective current usage is the larger counter through migration credit. D6 is also confirmed: one notice to verified email per paid-account transition to zero devices, none without verified email. Delivery deduplication and counter/journal implementation remain unbuilt. Other pending questions are not approval. No current read-time twin heuristic establishes historical disjointness: current `accountUsage` chooses the larger minutes record, which cannot prove whether two historical counters overlap.

Before AO0 closes: finish reader/SQL/provider-event inventory and real-storage fixture mapping; count twins, subscription collisions and orphaned accounts in a separately authorized bounded inventory; settle policies and deterministic period selection; specify journal coverage for every operation above, race-safe membership/settlement and correction commands; rehearse failure/retry and measure migration volume against the 48-hour transition budget. No production inventory, provider request, migration write or ownership-policy implementation occurred here.
