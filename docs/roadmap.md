# Miniti product and engineering plan

This is the single canonical inventory of future work, technical debt, known limitations, operational hazards, and larger product bets across the Miniti app and its managed backend. It consolidates the former app roadmap, the former `miniti-api` managed-service hardening plan, implementation caveats, test gaps, and specialist plan status as audited on 12 August and reconciled through 24 August 2026.

Completed user-facing work still belongs in [CHANGELOG.md](../CHANGELOG.md). Detailed implementation contracts remain in each repository's focused architecture documents; this file alone owns cross-repository priority, sequencing, decisions, and completion tracking. When an item names `miniti-api`, work in the sibling `../miniti-api` repository, read its `AGENTS.md`, update its implementation docs, and remember that pushing its `main` branch deploys production. The public `miniti-docs` repository is deliberately outside this inventory.

## How to use this plan

The evidence-validated [structural simplification audit](structural-simplification-audit-2026-08-16.md) records the full subsystem coverage contract, ranked structural recommendations, explicit skips, UI/UX regression assessment, dependencies, and required implementation validation. Its findings are audit evidence, not automatically approved roadmap commitments; promote an item into the prioritized plan when implementation is selected.

Priority means engineering urgency, not certainty that a product bet should be funded:

- **P0 — protect users and releases:** data integrity, privacy/security, regression prevention, and proven long-session stability. Do these before broad feature expansion.
- **P1 — reliable at scale:** work that prevents degradation as histories, integrations, and usage grow.
- **P2 — product expansion:** valuable bounded capabilities that build on the existing product.
- **P3 — strategic programmes:** large platform or architecture bets requiring validation and separate delivery plans.

Within a priority, order is intentional unless a production incident changes it. Every new item should name its platform, dependency, validation method, and completion criteria. When work ships, remove it from the active backlog, record it in the changelog if user-facing, and preserve only the relevant regression contract in the focused docs.

## Recommended execution order

1. Separate admin authentication from the shipped client credential immediately while managed-service baselining and long-session Deepgram grant verification run in parallel.
2. Make persistence startup recoverable, surface database failures, and close the webhook transport/logging privacy issue.
3. Add continuous build/test gates and critical UI/network automation.
4. Make managed device registration and session finalization atomic, then introduce anonymous recovery and device-bound authorization through staged enforcement.
5. Validate and tune 60+ minute performance, reduce the abrupt-kill checkpoint window, and correct filler counting/product wording.
6. Scale History search, harden outbound delivery, and measure prompt caching and current unit economics.
7. After those reliability gates, choose the next bounded product expansion from custom insight templates, deeper CRM automation, or entity detection based on user evidence.

## P0 — protect users and releases

### P0.1 Managed-service security, correctness, and scale programme

**Repositories:** `miniti-api` for server/admin/data changes; this `miniti` repository for macOS/iOS enrollment, credentials, recovery, and reconnect verification. Any public activation or account-recovery surface would additionally involve `minitidotapp`, but the selected anonymous recovery-key design is entirely in-app and does not currently require that repository.

**Goal:** Remove the shared client key as a security boundary, close known backend concurrency and scaling failures, and measure the remaining cache/reconnect gaps before changing them. Deliver small, independently deployable changes with production observation, explicit enforcement gates, and rollback paths.

#### Programme completion criteria

This programme is complete only when all of the following are true:

- A credential shipped in either app cannot read or mutate `/api/admin/*`. (Done 2026-09-13.)
- Billable managed endpoints do not rely on a reusable secret embedded in the app.
- One migration-capable app release per platform contains the complete key generation, silent migration, recovery, existing-device linking, and device-management flow; no user must install or launch an intermediate release.
- Existing supported macOS and iOS users can update directly to that release and migrate silently on their first later launch, even after months of inactivity, without login or browser activation.
- New managed installations can create or restore an anonymous recovery key entirely in-app, then receive a revocable, device-bound credential through an abuse-resistant bootstrap.
- Every supported macOS and iOS installation uses a unique P-256 key, proof of possession, short-lived scoped access tokens, rotating refresh credentials, replay protection, and server-side revocation.
- Existing device UUIDs and their usage, entitlement, label, integration, diagnostics, and administrative history survive migration; local meeting data is untouched.
- Existing free installations are never guessed to belong to one person; users can explicitly move an already-migrated installation into another recovery account, while verified Polar and Apple subscription identifiers provide automatic same-rail linking.
- New-device admission and device creation are one atomic operation across every registration path.
- Session finalization cannot record the same session twice, including concurrent requests and lost HTTP responses.
- Admin device reads are paginated and never call `KEYS device:*` in normal operation.
- Prompt-cache hit rate, cached tokens, latency, and cost are observable; prompt changes are retained only if they produce a measured improvement.
- Managed Deepgram reconnects are proven to refresh expired grants in unit and real reconnect testing, and the stale documentation gap is closed.

#### Current audit

| Workstream | Current state | Required outcome |
| --- | --- | --- |
| Admin authentication | **Done 2026-09-13.** `/api/admin/*` requires the `miniti_admin_session` cookie issued by `POST /api/admin/session` from `ADMIN_SECRET_KEY`; the client key gets `401`; the dashboard keeps nothing in `sessionStorage`. | Server-only admin authentication and a short-lived browser session. |
| Client authentication | Open. All installations share an extractable bearer value. | Anonymous recovery for account continuity and per-installation proof-of-possession credentials for API access. |
| New-device limiter | Broken. `/api/usage` creates the device before testing whether it is new. Other routes can also create devices. | One centralized, atomic registration/admission path. |
| Session finalization | Open. Check, usage increments, session deletion, and idempotency result are separate writes. | One atomic Redis finalization operation. |
| Device registry | Open. Admin listing uses `kv.keys('device:*')` and loads all records. | Explicit registry, secondary indices/counters, reconciliation, and pagination. |
| OpenAI prompt caching | Measurement gap. Caching is already automatic for the pinned models, but cached-token usage is not captured. | Baseline telemetry followed by evidence-based optimization. |
| Deepgram reconnect refresh | Implemented in the Swift client as of 20 July 2026, with a 60-second refresh skew and unit coverage. | Run closure verification and remove the stale backlog item. |

#### Architectural decisions

##### Admin and client trust are separate

Use distinct helpers and credentials:

- `checkAdminAuth()` protects `/api/admin/*` only.
- `checkLegacyClientApiKey()` exists only during client migration.
- `checkClientAccessToken()` validates new per-installation authorization.

No admin route may fall back to `API_SECRET_KEY`. Avoid a dual-key admin transition because every shipped client contains the legacy key. Set the new server environment values before deploying code that requires them.

##### Device-bound proof is the cross-platform foundation

The initial design deliberately proves possession and continuity of one installation; it does not claim to prove that the calling process is an authentic, unmodified Miniti binary. The cross-platform design therefore combines:

- a unique installation key;
- proof of possession on future requests;
- a constrained trust bootstrap;
- server-side quotas, rate limits, and revocation.

The selected bootstrap preserves a low-friction migration without an email account or browser sign-in:

1. Existing registered installations silently create and store an anonymous recovery key plus a P-256 installation key. The migration endpoint accepts the existing high-entropy Keychain device UUID only for a record created before the cutoff, requires proof of the proposed private key, permits one binding, and is tightly rate-limited. It does not require the extractable legacy client key, which adds no meaningful assurance and must not remain in the migration-capable binary.
2. A new user chooses **create recovery key** in the app. The app generates at least 120 random bits in a human-readable, checksummed form, stores it in Keychain before enrollment, creates its installation key, and asks the API to create an anonymous account and bind that installation atomically.
3. On a new Mac, the user chooses **restore with recovery key** and enters the same code in the app. The new installation generates its own private key; the recovery key authorizes enrollment only and is never the credential used for normal API requests.
4. Existing Polar license-key restore remains an alternative recovery path for a paid macOS subscription. After Polar validation it joins the device to the subscription's anonymous account and binds an installation key; the Polar key never becomes an ongoing API credential.
5. BYOK mode does not need managed-service enrollment. `/api/version` must not create a managed device record merely to report public version metadata.

The recovery key is an anonymous bearer capability, similar in role to a Mullvad account number. Store only a server-keyed digest for lookup, never log the raw value, rate-limit create/restore attempts by a privacy-preserving network bucket, and allow rotation. Default to five active devices per account with in-app device removal. Managed usage is charged to the anonymous account or paid subscription rather than multiplied by attached devices.

Because this creates a server-side account even without collecting identity, iOS must offer in-app account deletion. Deletion revokes every attached installation and removes the account and associated operational data except records retained for legal or financial reasons. It is distinct from cancelling an Apple or Polar subscription, which the confirmation UI must explain.

An installation key alone does not stop an attacker creating many free accounts. Atomic admission limits remain necessary, with a privacy-preserving proof-of-work gate available only if observed automated churn warrants it. This is still sufficient for the current P0: it removes the global reusable secret, provides account continuity without identity, limits credential sharing, makes individual installations revocable, and contains abuse with account-scoped quotas and server-side admission controls.

##### One client release, with a long-tail migration path

Backend work may use several independently deployable changes, but users need only one new app version on each platform:

1. Deploy admin-auth separation, the account/device-auth schema, enrollment endpoints, and dual legacy/new request verification before submitting either app.
2. Release one macOS version and one iOS version containing the complete silent migration, recovery-key, existing-device linking, account deletion, and device-management implementation. These releases use device-bound authorization for managed traffic and do not contain the reusable client secret.
3. Keep older versions working temporarily through the legacy path while measuring migration adoption. New versions do not need a second release when enforcement changes; `observe` → `prefer` → `require` is controlled server-side and independently per platform.
4. Once a platform reaches its agreed threshold, reject the legacy key on billable endpoints. An old client may still reach purpose-specific public version/update metadata, but must update before using managed features.
5. Keep the isolated, one-time migration endpoint available for eligible pre-cutoff device UUIDs after billable legacy access ends. A user returning months later updates straight from any older version to the migration-capable release and enrolls on its first launch; prior launch of an intermediate build is never a prerequisite.

The migration endpoint's eligibility set is fixed at the cutoff and cannot register a new device. Treat full device UUIDs as sensitive operational identifiers: never expose them in public logs, rate-limit attempts by privacy-preserving network bucket, alert on unknown/replayed UUIDs, and provide paid restore plus support handling for the rare legitimate Keychain-loss case. A calendar deadline may end support for an obsolete app version, but must not silently remove the direct migration path for an otherwise eligible inactive installation without an explicit product decision.

##### Unified device-bound session

After enrollment, use one protocol across platforms:

- The app stores its installation private key in the Secure Enclave when available, with a Keychain-backed P-256 fallback for unsupported hardware.
- The backend stores the public key and enrollment path: `legacy_migrated`, `anonymous_recovery`, or `polar_restored`.
- A challenge/response token endpoint verifies proof of possession and issues a short-lived access token bound to the installation key, device ID, platform, app version, and scopes.
- Expensive requests include a proof covering the access token, HTTP method, path, body hash, issued-at time, and a unique request ID. The backend rejects replays.
- Refresh credentials are rotating, device-bound, revocable, stored in Keychain, and never application-wide constants.

Reference for the required iOS recovery-account deletion surface: [in-app account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

#### Delivery phases

##### Phase 0 — Baseline and close stale findings

**Deliverables:**

- Record current daily registrations by platform/version and hashed IP bucket.
- Record active OS and app-version distribution so migration and enforcement thresholds reflect the installed base.
- Add or confirm counters for session-end replays, missing sessions, and failures between steps.
- Confirm every route that creates or touches device records. The current list includes version, usage, session, insights, subscription, Apple verification, CRM, calendar, and diagnostics routes.
- Run existing Swift credential-freshness tests and a manual reconnect after grant expiry on macOS and iOS.
- Confirm reconnect obtains a fresh `/api/session` grant and uses `Authorization: Bearer` before opening the replacement socket.
- Remove the Deepgram reconnect item from active work only after those checks pass.

**Exit:** At least seven normal production days of baseline data where volume permits, plus unit-test output and one successful real-device expired-grant reconnect per platform.

**Rollback:** None; this phase is observational.

**Dependency:** The observation window blocks Phase 2 admission enforcement and closure of the Deepgram finding, but it does not block Phase 1 admin-auth work. Begin Phase 1 immediately.

##### Phase 1 — Separate and harden admin authentication

**Backend:**

- Add `ADMIN_SECRET_KEY` and `ADMIN_SESSION_SECRET` as server-only environment variables.
- Add `POST /api/admin/session` and `DELETE /api/admin/session`.
- Compare the submitted admin secret in constant time, then issue a short-lived, signed `HttpOnly`, `Secure`, `SameSite=Strict` cookie.
- Validate same-origin `Origin` on state-changing admin requests.
- Replace `checkApiKey()` with `checkAdminAuth()` on every admin route.
- Add structured audit events for login success/failure, logout, and mutations without logging credentials.

**Dashboard:** Stop storing/sending the raw secret after login, remove it from `sessionStorage`, use the admin session cookie, and handle expiry explicitly.

**Tests:** Missing environment fails safely; the client key is rejected by every admin read/mutation; valid login creates correct cookie attributes; invalid/expired/tampered cookies and cross-origin mutations are rejected; logout invalidates the session.

**Rollout:**

1. Set both new Vercel variables.
2. Deploy the login/session implementation.
3. Verify a new dashboard session and every mutation.
4. Confirm the legacy client key receives `401` from every admin route.

**Rollback:** Restore the prior deployment only if necessary. Never retain or re-enable the client key as an admin fallback.

##### Phase 2 — Centralize atomic registration and build the device registry

Create one validated Redis Lua registration primitive through the currently available `kv.eval`. It must atomically:

1. Return an existing device without consuming a new-device allowance, or claim a new registration.
2. Increment/check the admission bucket.
3. Create the device hash.
4. Add the device to `devices:registry`, scored by creation time.
5. Update daily registration and active-device metrics.

Validate every input and existing Redis value type before mutation.

**Admission:**

- Prefer Vercel's `x-vercel-forwarded-for`; another proxy can overwrite `x-forwarded-for`.
- Normalize IPv4/IPv6 deliberately and evaluate IPv6 `/64` bucketing during observation.
- Store only an HMAC of normalized IP using a server-only rate-limit salt.
- Keep thresholds configurable. Start `observe`, then `enforce` only after reviewing NAT, carrier, IPv6 rotation, missing headers, and App Review traffic.
- Retries for one device never consume another allowance; concurrent attempts produce one record and registry member.
- `/api/version` and lightweight endpoints cannot create managed devices outside this primitive.

**Registry/read model:**

- Paginate `devices:registry`; never load every device into one response.
- Maintain `devices:pro`, active Polar subscription IDs, and active Apple transaction IDs as explicit indices.
- Maintain current-cycle/lifetime minutes, registration count, Pro count, and other dashboard aggregates in the same writes that update their sources.
- Fetch Polar/Apple detail only for the visible page unless reading a separately cached summary.
- Use stable cursors and bounded page sizes.

**Backfill/cutover:**

1. Idempotently SCAN existing `device:*` hashes into indices/counters.
2. Dual-write while admin still reads the legacy path.
3. Shadow-read and compare counts, sampled IDs, Pro membership, and totals.
4. Repair drift until clean.
5. Switch behind `DEVICE_REGISTRY_READ_MODE=registry`.
6. Retain an explicit repair command, never `KEYS` as normal fallback.

**Tests:** Existing/new/concurrent/retry/over-limit/shared-IP/IPv6/missing-IP cases; every creation-capable route; idempotent repair; cursor pagination without gaps/duplicates; counter updates across resets, admin corrections, entitlements, and creation.

**Rollback:** Restore legacy reads while keeping dual writes; return admission to `observe` without losing registrations. Reference: [Vercel request IP headers](https://vercel.com/docs/headers/request-headers).

##### Phase 3 — Make session finalization atomic

Add `finalizeSessionAtomic()` around one Redis Lua operation that:

- returns the stored final result immediately for replay;
- validates ownership before mutation when a live session exists;
- applies the already validated/capped duration exactly once;
- increments cycle, lifetime, daily, and global lifetime usage;
- deletes the live session;
- stores the complete replay response for 30 days;
- returns the new HTTP-response totals.

All failing validation/type checks happen before the first mutation. Entitlement reset and disabled-device checks may occur before the atomic operation, but only the script performs finalization increments and writes the idempotency result. Preserve missing-session behavior: the first bounded report may record with `session_finalized: false`; later reports replay without incrementing.

**Tests:** Concurrent identical requests increment once; lost response retries safely; missing/wrong-owner/expired/disabled/negative/server-elapsed-cap/four-hour-cap contracts remain; deliberate pre-mutation script failure changes nothing; pure duration/ownership/result logic remains independently tested.

**Rollout:** Shadow-compute expected results, enable via `SESSION_FINALIZATION_MODE=atomic`, and monitor duplicate prevention, script errors, missing-session rate, and usage deltas.

**Rollback:** Temporarily restore legacy routing only while investigating; retain atomic result keys so retries stay safe.

##### Phase 4 — Introduce anonymous recovery and device-bound authorization

**Status (2026-09-06):** backend protocol, enrollment, token, account routes, the one-time `/api/auth/migrate` path, and restore re-binding are implemented in `miniti-api` (flags still `observe`); the Linux app shipped device-bound auth in 0.3.0; the Apple migration-capable release is implemented in this repo for 2.7.0 (silent migrate on first launch, automatic account creation for new installs, restore in onboarding and Settings, device list, rotate, sign out, delete; no legacy key in the binary). Still open: Polar-restore enrollment, shared account-level usage counters, and the enforcement ladder. Phase 1 (admin-auth separation) shipped 2026-09-13. **2.8.0 (2026-09-11):** account-level Pro entitlement (`lib/accountEntitlement.ts`, `/api/usage` `entitlement_via_account`) and `POST /api/auth/account/attach` are implemented in `miniti-api`, and the Apple clients show sponsored Pro and offer "Move this device to another account" in Settings → Account.

**Backend protocol:** Add Node-runtime enrollment endpoints and edge-compatible access-token verification:

- `POST /api/auth/account/create`
- `POST /api/auth/account/restore`
- `POST /api/auth/account/recovery-key/rotate`
- `GET /api/auth/account/devices`
- `POST /api/auth/account/devices/attach`
- `DELETE /api/auth/account/devices/{installationId}`
- `DELETE /api/auth/account`
- `POST /api/auth/challenge`
- `POST /api/auth/migrate`
- `POST /api/auth/enroll`
- `POST /api/auth/token`
- `POST /api/auth/revoke`

Suggested Redis records:

- `auth:account:{accountId}` — tier, shared usage owner, device count, timestamps, and status; no required identity.
- `auth:recovery:{digest}` — server-keyed digest mapping to account ID, version, timestamps, and attempt state; never the raw recovery key.
- `auth:subscription:{source}:{subscriptionId}:account` — stable, rail-specific Polar/Apple-subscription-to-account mapping.
- `auth:account:{accountId}:installations` — bounded active installation IDs.
- `auth:challenge:{id}` — hashed, single-use, short TTL.
- `auth:installation:{deviceId}` — public key, enrollment path, platform/version, and timestamps/revocation.
- `auth:refresh:{tokenId}` — hashed rotating refresh credential and family/reuse state.
- `auth:replay:{installationId}:{jti}` — short replay TTL for proof-bearing requests.

Access tokens are short-lived, server-signed, scoped, and bound to the installation public-key thumbprint. Token and P-256 request-proof verification must work in existing Edge and Node routes.

**Existing-installation migration:**

- Ship the complete key generation/storage, recovery, existing-device linking, and device-management flow in the first migration-capable release on each platform; do not require an intermediate client version.
- Generate and store the recovery key before requesting migration so a lost response cannot lose the only copy.
- Permit one silent account creation/enrollment only for a pre-cutoff device record and a proof over the server challenge from the proposed installation key. Do not require or ship the legacy client key in the migration-capable release.
- Atomically bind device ID, account, existing usage/entitlement state, recovery digest, and public key.
- Reject key replacement without authenticated recovery/re-enrollment.
- Preserve the existing `device:{deviceId}` record and all device-keyed OAuth/integration records; local SwiftData meetings never participate in this backend migration.
- Record outcome by platform/version without raw keys/IPs. After the agreed adoption threshold, close legacy access to billable endpoints but retain the isolated one-time migration path for eligible inactive devices.

**Existing multi-device accounts:**

- Never infer that free devices share an owner from IP address, timing, labels, usage patterns, calendar data, CRM identity, or other heuristics. Each free installation can migrate safely on its own without blocking normal use.
- Let a user choose one recovery account and attach another already-migrated installation by authorizing the source with its current installation proof and the destination with the recovery key. `POST /api/auth/account/devices/attach` atomically moves the installation membership while preserving its device UUID, device record, integrations, label, history, and credentials.
- If the source recovery account becomes empty, revoke its recovery digest and remove it unless billing, legal, or audit retention requires a tombstone. Reject moves that exceed the destination device cap or create conflicting ownership/subscription state. A failed move changes neither account.
- Automatically join devices only through a freshly verified stable subscription identifier: Polar subscription ID for the macOS rail or Apple original transaction ID for the iOS rail. Namespace the mapping by rail. Apple entitlement must not unlock macOS and Polar entitlement must not unlock iOS, even when both installations belong to one recovery account.
- Existing users do not need to link devices to complete the security migration. Linking is an optional account/allowance consolidation action that can happen at any later time from any device.

**Existing usage transition:**

- Do not retroactively combine several current-cycle device counters into a smaller shared allowance or immediately lock out an existing user.
- When existing installations first join one account/subscription, preserve each installation's already-promised remaining allowance until the applicable common free reset or paid billing boundary. At that boundary, begin one shared usage counter for that account and entitlement rail.
- Keep per-device current/lifetime values readable for migration audit and historical admin reporting. New usage after the boundary increments the shared owner atomically; adding another device never starts a fresh allowance.

**Anonymous recovery-key creation/restore:**

1. First launch offers **create recovery key** and **restore with recovery key** without email, username, or password.
2. Create generates a versioned, checksummed key with at least 120 random bits and a distinct P-256 installation key. Store both in Keychain before idempotent account creation.
3. Restore normalizes the code, proves possession of the new installation key, verifies the keyed digest under strict rate limits, and atomically adds the installation below the device cap.
4. Both paths issue rotating device-bound credentials. Normal traffic never sends the recovery key.
5. Settings can reveal/copy after local confirmation, rotate the key, list devices, and remove lost devices. Rotation invalidates the prior recovery key without revoking existing installations.
6. Polar license restore remains an alternative for paid macOS recovery, maps one subscription to one anonymous account, and never persists the raw license as an API credential.
7. Free/paid usage is account/subscription-scoped; adding devices never multiplies allowances.
8. Settings provides account deletion that revokes installations, removes recovery/operational data, retains only legally required billing records, and explains that deletion does not cancel Apple/Polar subscriptions.

Lost free-account recovery keys are intentionally unrecoverable; the user may create a new account subject to admission limits. Polar remains the macOS paid recovery path. iOS StoreKit restoration must be designed explicitly rather than assuming Polar semantics.

**Admin-panel migration:**

- Complete Phase 1 server-only admin authentication before exposing any account/device-auth controls. The shipped client credential must receive `401` from every admin read and mutation.
- Preserve the current device row and its UUID, label, platform/version, last seen, usage history, subscription fields, disabled state, and diagnostics. Add account ID, enrollment state (`legacy`, `enrolled`, `revoked`, `migration_failed`), enrollment path/version, and last auth failure without displaying recovery keys, refresh credentials, private/public keys, or full proofs.
- Add an account-grouped view with expandable installations, shared usage and rail-specific entitlement state. Search by account ID, device ID, label, Polar customer/subscription, and Apple original transaction ID.
- Keep **disable installation** as the existing one-device access block. Add separately audited **revoke installation credentials**, **remove installation**, and **suspend account** actions. After shared-usage cutover, usage adjustment is account/rail-level; legacy current-cycle counters remain read-only audit fields.
- Show migration adoption and failures by platform/app version so `prefer`/`require` decisions are evidence-based. During rollout, dual-read legacy and account records and flag divergence before changing enforcement.
- Replace the normal `KEYS device:*` scan with the explicit paginated registry already required by Phase 3. Account grouping must not reintroduce an unbounded read.

**Enforcement:**

- `observe`: validate when present; legacy remains accepted.
- `prefer`: device auth is primary; legacy only for eligible old versions.
- `require`: managed billable endpoints require device auth.

Enforce `/api/session`, `/api/insights`, and Docs lookups first, then subscription/CRM/calendar by risk. Public version/update metadata and OAuth/webhook callbacks retain purpose-specific authentication. The first migration-capable release on each platform omits the obfuscated legacy key. After that release is proven and the platform reaches its adoption threshold, stop accepting the legacy key for billable endpoints; retain only the constrained late-migration verifier for pre-cutoff device UUIDs, retire all broader legacy helpers/environment use, and rotate any coupled server credentials.

**Tests/QA:** Shared Swift/TypeScript canonical request/body-hash fixtures; signature/binding/expiry/scope/replay/rotation/revocation/refresh-reuse; recovery format/normalization/checksum/digest/redaction/throttling/rotation/lost-response idempotency; concurrent restore/device cap; account-scoped usage; same-rail paid auto-linking and cross-rail non-unlocking; explicit free-device attach, rollback, orphan cleanup, and conflict rejection; current-cycle grandfathering and shared-counter boundary cutover; device record/integration/history preservation; Polar mapping/no raw persistence; account deletion/erasure/legal retention/fresh paid restore; concurrent one-time migration, pre-cutoff eligibility, unknown/replayed UUID rejection, and a months-late direct upgrade from every supported legacy version; absence of the legacy key from migration-capable binaries; Keychain/Secure Enclave persistence; admin grouping, pagination, authorization boundaries, and single-device versus account actions; real iOS and supported Intel/Apple-silicon Mac tests; App Review notes and review-safe account deletion before iOS enforcement.

**Rollback:** Move platform enforcement back to `prefer`; keep issued credentials valid. Never roll admin routes back to the client key.

##### Operator and infrastructure checklist

The implementation must leave a short, deterministic operator runbook. Code owns schema creation, Redis writes, backfills, validation, and rollback mechanics; the operator never hand-edits production Redis keys.

**Vercel environment:**

Before deploying code that requires each value, generate independent random secrets, store them in the password manager, and add them to both Preview and Production in the existing `miniti-api` Vercel project:

- `ADMIN_SECRET_KEY` — the admin-dashboard login secret.
- `ADMIN_SESSION_SECRET` — signs short-lived admin session cookies; never reuse the login secret.
- `CLIENT_AUTH_TOKEN_SECRET` — signs device-bound access tokens. Support a version/`kid` and an overlap mechanism before the first rotation rather than replacing it abruptly.
- `RECOVERY_KEY_HMAC_SECRET` — server-keyed recovery-code lookup; domain-separate it from token signing and version stored digests so rotation is possible.
- `NETWORK_BUCKET_HMAC_SECRET` — privacy-preserving admission/rate-limit buckets; never reuse the recovery-key secret.
- `CLIENT_MIGRATION_CUTOFF` — one immutable ISO 8601 timestamp defining which existing device records are eligible for the one-time silent path.
- `DEVICE_ADMISSION_MODE=observe`, `DEVICE_REGISTRY_READ_MODE=legacy`, `SESSION_FINALIZATION_MODE=legacy`, `CLIENT_AUTH_MODE_MACOS=observe`, and `CLIENT_AUTH_MODE_IOS=observe` as safe initial flag values. Validate allowed values at startup and fail closed on an invalid security mode.

Vercel applies new or changed environment variables to new deployments, so redeploy after each planned environment change. Do not change or remove the current `API_SECRET_KEY` during the compatibility window: old binaries still use it. New binaries must not contain it, admin routes must not accept it, and billable endpoints stop accepting it only at the platform-specific enforcement gate. Remove it from Vercel only after no deployed code needs it for any purpose.

Update `miniti-api/.env.example` and `docs/agents/02-environment.md` in the implementing PR. A developer who runs the API locally adds equivalent non-production values to the gitignored local `.env`; no real secret is committed. Existing OpenAI, Deepgram, Polar, Apple, CRM, Google, download-signing, and Upstash connection values remain unchanged unless the implementation audit finds a separate rotation need.

**Upstash Redis:**

- Continue using the existing Vercel-linked Upstash database and connection variables. This programme does not require a new database, manual schema creation, or dashboard-entered account/device records.
- Before backfill, record database size/request baseline, confirm the plan has enough memory and request headroom for the registry, account/install records, short-lived challenges/replay keys, refresh families, and migration telemetry, and confirm `EVAL` works through the production binding.
- Take the available backup/export or otherwise verify the documented recovery mechanism before the first structural backfill. Do not claim point-in-time recovery unless the actual Upstash plan provides it.
- Run the reviewed idempotent registry/account backfill command supplied by the code, first in Preview/test data and then against Production. Capture counts before/after, shadow-read comparison, drift report, duration, and any repair result. Never repair by manually editing keys in the Upstash console.
- Watch Redis storage, commands, latency, errors, eviction/rejection signals, replay-key volume, and rate-limit cardinality through rollout. Upgrade the Upstash plan only if measured headroom requires it.

**Manual deployment and release gates:**

1. Add the two admin secrets, deploy Phase 1, log into the production admin panel with the new credential, exercise each mutation, and verify the old client key receives `401` from all admin routes.
2. Add the client-auth/HMAC secrets, immutable cutoff, and safe initial flags. Deploy the additive auth/registry implementation to Preview, run its tests/backfill rehearsal, then deploy Production in observation mode.
3. Run the production idempotent backfill and review registry/account counts, entitlement links, usage totals, and divergence. Do not switch reads or enforcement while unexplained drift exists.
4. Flip registry/finalization modes only after their separate shadow checks. Each Vercel flag change requires a deployment and a recorded rollback value.
5. Ship the single migration-capable macOS release and single migration-capable iOS release through their normal independent release processes. Include account-deletion/recovery App Review notes on iOS. No Apple integrity capability, key, or environment setup is required.
6. Observe migration success/failure, inactive-device returns, multi-device linking, auth failures, usage deltas, and support reports by platform/version. The operator approves `observe` → `prefer` → `require` separately for macOS and iOS; these are backend deployments, not additional app releases.
7. After enforcement is proven, verify old versions receive the intended update path, confirm direct late migration still works, rotate any credential that was coupled to the old client secret, remove broad legacy auth code, and finally delete `API_SECRET_KEY` only when repository-wide search and production verification show nothing still reads it.

Keep exact values out of tickets, logs, screenshots, source control, and this roadmap. The release PR must include a redacted copy/paste checklist of variable names, target Vercel environments, initial values for non-secret flags, verification commands, expected results, owner, and rollback for every manual gate.

##### Phase 5 — Measure and optimize OpenAI prompt caching

Prompt caching is automatic for eligible requests on the pinned GPT-5 mini and GPT-5.4 mini generations. Do not treat “enable caching” as a task.

**Baseline:** Parse and record `usage.prompt_tokens`, `usage.prompt_tokens_details.cached_tokens`, model, mode, full/incremental strategy, prompt version, and latency; show aggregate hit ratio/cached-token share; never log prompt/transcript content; measure representative baselines by model/mode.

**Experiment:** Version stable mode prompts; put stable instructions/schema/examples before transcripts, rolling state, attendees, Docs chunks, and other dynamic content; verify the repeated prefix reaches cache eligibility without padding; consider `prompt_cache_key` only after measuring global rate and partition keys if one would exceed guidance; A/B test cached tokens, TTFT, latency, cost, fallback rate, and output-quality fixtures. Retain only measured improvements. Do not send GPT-5.6-only explicit breakpoint fields to older pinned models.

**Exit:** Cache metrics exist for every mode and each restructuring/cache-key experiment has a recorded keep/reject result.

**Rollback:** Revert prompt/cache-key changes while retaining usage telemetry. Reference: [OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching).

#### Cross-cutting observability

Emit structured events with platform and app version, never raw credentials, public keys, refresh tokens, IPs, transcripts, or prompts:

- `admin_auth_login`, `admin_auth_failure`, `admin_mutation`
- `device_registration_existing`, `device_registration_created`, `device_registration_limited`
- `device_registry_drift`, `device_registry_repaired`
- `session_finalize_original`, `session_finalize_replay`, `session_finalize_error`
- `client_auth_migration`, `client_auth_enrollment`, `client_auth_token_failure`, `client_auth_replay`
- `openai_cache_usage`
- existing Deepgram refresh/reconnect events, augmented only with credential age and refresh outcome

Alert on any successful admin request using legacy client credentials; registration rejection spikes; recovery create/restore throttling, checksum failures, and unknown-key attempts by privacy-preserving bucket; client-auth enrollment/token/replay failures after releases; finalization errors/divergence; registry drift; and cache-hit collapse after prompt changes. Native opt-in diagnostics policy and retention are specified separately under P1.4.

#### Cross-repository pull-request sequence

Keep changes independently reviewable and deployable:

1. Admin session authentication and dashboard migration.
2. Baseline telemetry and Deepgram closure verification begins in parallel; its observation window need not delay item 1.
3. Atomic registration and observe-only admission after sufficient baseline instrumentation exists.
4. Registry/index dual writes, backfill, shadow comparison, then paginated reads.
5. Atomic session finalization; this may proceed in parallel with registry work when reviews remain independent.
6. Device-auth protocol and backend token/proof verification.
7. One complete migration-capable Swift release per platform: installation keys, silent direct migration, recovery, existing-device attach, account deletion, and device management; no intermediate release and no legacy key in the new binaries.
8. Backend account grouping, same-rail paid auto-linking, grandfathered usage cutover, account/device admin views and actions, and migration observability.
9. Billable-endpoint enforcement and broad legacy-key retirement while retaining the constrained one-time path for eligible inactive installations.
10. Prompt-cache telemetry, followed by separate measured experiments.

Every PR updates the relevant `miniti-api/docs/agents/*` and/or Miniti focused docs, includes focused tests, states its feature flag/rollback, and does not bundle an `@vercel/kv` → `@upstash/redis` migration with behavioral work.

#### Decisions required before enforcement

- Final recovery-key alphabet/grouping/checksum, local reveal confirmation, rotation messaging, and lost-free-key support policy.
- Anonymous create/restore limits, default five-device cap/exceptions, privacy-preserving network-bucket retention, and proof-of-work threshold.
- Exact duration/representation of the grandfathered current-cycle allowance after existing devices are linked; never retroactively reduce an already-promised remaining allowance.
- Pre-cutoff eligibility date, minimum migration-capable app versions per platform, and the explicit policy for eventually retiring the long-tail one-time migration path. No plan may require an inactive user to have launched an intermediate version.
- Access-token lifetime and refresh rotation/reuse policy.
- Observe-to-enforce thresholds for new-device admission and device-bound authorization.
- Legacy support window after device-auth-capable releases ship.

### P0.2 Recover from SwiftData startup failure

**Built, unreleased (2026-09-13, for 2.9.0):** `PersistentStore.open()` replaces both `fatalError`s, tries a read-only open for export, classifies the failure without content, and renders `StoreRecoveryView` (try again, export diagnostics, export meetings, show database folder, get help). Debug `-MinitiStoreURL` flag and the manual drill are in [testing.md](testing.md); 13 automated cases in `PersistentStoreTests`. Still owed: the manual drill on a real Mac and iPhone. Tracking: [p0-hardening-batch-2026-09-plan.md](p0-hardening-batch-2026-09-plan.md).

**Why:** Both app targets currently call `fatalError` when their `ModelContainer` cannot open. Store corruption, an incompatible migration, or a disk failure can therefore make Miniti unlaunchable precisely when a user needs to recover or export their meetings.

**Work:**

- Replace the macOS and iOS startup crash with a safe, content-free recovery screen.
- Preserve the existing store; never delete or recreate it automatically.
- Offer retry, diagnostics export, and a clearly explained backup/export or support route.
- Investigate a read-only recovery/export path and a tested backup/restore procedure.
- Log the failure category without meeting content or secrets.

**Complete when:** Corrupt/unopenable test stores produce a usable recovery UI on both platforms, ordinary stores still launch normally, and a documented manual recovery drill succeeds.

**Owners:** `Miniti/MinitiApp.swift`, `MinitiMobile/MinitiApp_iOS.swift`, SwiftData startup and distribution tests.

### P0.3 Centralize and surface persistence errors

**Built, unreleased (2026-09-13, for 2.9.0):** every production `try? save()` and silent fetch now goes through `AppState.commit`/`fetchMeetings` (`AppState+Persistence.swift`): explicit revert, log with domain/code only, `persistence_*_failed` diagnostics event, and one root banner per platform with retry. A failed delete stays pending (SwiftData traps on `rollback()` of a cascade delete, so it is never rolled back), stale finalization no longer reports sessions it did not persist, corrections return `.saveFailed`, and a fetch failure keeps the previous history instead of rendering empty. 18 automated cases in `PersistencePolicyTests`; rule recorded in [patterns.md](patterns.md). Tracking: [p0-hardening-batch-2026-09-plan.md](p0-hardening-batch-2026-09-plan.md).

**Why:** The durable live-transcript save queue is hardened, but many direct pin, delete, title, speaker, Docs, and other SwiftData writes use `try?`. Some fetches also collapse failure into an empty/no-op result. A mutation can silently disappear, and a fetch failure can resemble missing history.

**Work:**

- Inventory every production `ModelContext.save()` and fetch call; distinguish genuinely optional decoding from data mutations.
- Route mutations through one observable save/error policy with structured logging.
- Retry only idempotent operations, roll UI state back where appropriate, and show a concise local error when user action did not persist.
- Keep the revision-fenced transcript save queue and deleted-meeting protections intact.
- Add failure-injection tests for pin, delete, rename, speaker edits, transcript trim, saved insight regeneration, and stale-interrupted-meeting finalization.

**Complete when:** No user-initiated persistence mutation silently ignores an error, fetch failure cannot masquerade as an empty history, and both test bundles cover representative failures.

### P0.4 Reduce abrupt-termination data loss

**Why:** Active recordings checkpoint every 60 seconds. Background, stop, Home, and normal termination save immediately, but a hard kill can lose roughly the latest checkpoint interval of finalized content. Unfinalized interim text remains a platform/protocol limit.

**Work:**

- Measure save cost before changing cadence.
- Prefer a coalesced/debounced durable checkpoint shortly after finalized transcript changes (target experiment: 5–10 seconds) rather than saving every fragment.
- Retain per-meeting coalescing, off-main diff planning, revision fences, background-task handling, and termination fail-open behavior.
- Stress forced termination, rapid meeting handoff, resume, deletion during an in-flight save, and long transcripts.

**Complete when:** The maximum expected finalized-content loss is explicitly documented and materially below 60 seconds without UI stalls, excessive writes, meeting resurrection, or cross-meeting payload loss.

### P0.5 Add continuous integration

**Built 2026-10-05:** `.github/workflows/tests.yml` runs `MinitiTests` (macOS) and `MinitiMobileTests` (iOS simulator) on `macos-26` with Xcode 26.6 for every push to `main` and every pull request, unsigned builds, Nemotron model and SwiftPM caches. First verified on the `ci` branch.

**Why:** There are no GitHub Actions workflows; release confidence currently depends on local Fastlane execution.

**Work:**

- Run the macOS XCTest bundle and Debug build.
- Run the iOS XCTest bundle and simulator Debug build using a resolvable simulator UDID/runtime.
- Add `git diff --check`, local documentation-link validation, and version/release-metadata consistency checks.
- Cache conservatively and make failures reproducible with the commands in [testing.md](testing.md) and [fastlane/RUNBOOK.md](../fastlane/RUNBOOK.md).
- Keep signing, notarization, App Store upload, and production deployment out of untrusted pull-request jobs.

**Complete when:** Every change receives deterministic build/test status for both targets and branch protection can require it.

### P0.6 Automate critical UI and network regressions

**Built, unreleased (2026-09-13, for 2.9.0):** `MinitiAPIService(session:auth:)`, `InsightsService(session:)`, and `DeepgramService.sessionConfiguration`/`endpointURL` seams; `AppState` skips all launch-time network from the XCTest host; shared `StubURLProtocol` in `TestSupport.swift`; `MinitiAPIServiceTransportTests` (every status class, token refresh, revocation, timeout/offline, cancellation), `CalendarEventDecodingTests` (the 2.7.0 wire-format regression), `MeetingJourneyTests` (stop → save → history, kill → relaunch → resume, pin survives relaunch), six-series Coaching chart tests, `scripts/screenshots/smoke.sh` as the launch gate with an iOS ready marker and two new scenes, `code_coverage: true` on both Fastlane test lanes plus `scripts/coverage.sh`. No XCUITest target by decision. Coverage re-measured in [testing.md](testing.md). Tracking: [p0-hardening-batch-2026-09-plan.md](p0-hardening-batch-2026-09-plan.md).

**Why:** Coverage was last measured around 18% at v1.17.0. SwiftUI views are effectively untested, hardware audio is mostly manual, and network paths need controlled mocking. Recent Coaching layout, chart, focus, and navigation regressions demonstrate the gap.

**Work:**

- Add a small UI smoke/snapshot target for launch, Home, record → stop → save → History, interrupted-session recovery, and Settings.
- Cover Coaching focus/stats/history, six separate charts and axes, grounded example sizing/metadata/hover behavior, and large/empty histories.
- Cover macOS back/forward gestures while `search meetings` is focused, plus the rule that other active text editors suppress navigation.
- Mock API/WebSocket failure classes with `URLProtocol` or an equivalent injectable transport: timeout, offline, 4xx, 5xx, malformed data, cancellation, retry, and stale response.
- Preserve the manual Bluetooth, mic/system echo, reconnect, long-transcript, iOS background, Live Activity, and BBC World Service matrices in [testing.md](testing.md).
- Re-measure coverage and replace the stale percentages with dated results; do not chase a vanity percentage at the expense of critical paths.

**Complete when:** The highest-value user journeys and recent regression classes fail automatically before release, and manual-only hardware boundaries are explicitly named.

### P0.7 Finish the 60+ minute Instruments validation

**Why:** Privacy-safe signposts already cover transcript cache rebuilds and save planning/apply/commit, but the final long-session profile remains unfinished.

**Work:**

- Profile a 60+ minute mixed-source macOS meeting and a long iOS meeting using Points of Interest, Time Profiler, Allocations, and SwiftUI instruments.
- Exercise continuous transcript growth, insights cadence, Coaching computation, saved-history navigation, scrolling, pane collapse/resize, periodic saves, and audio-route recovery.
- Record budgets for CPU, memory growth, main-thread stalls, view invalidations, save-plan/apply/commit latency, and battery/thermal behavior.
- Test hundreds of saved meetings and six Coaching chart series; downsample only rendering if measured, while keeping exact statistics, sequence semantics, accessibility, and hover values.
- Store a repeatable fixture/procedure and compare future profiles to the baseline.

**Complete when:** Results and budgets are documented, no unbounded growth or unacceptable main-thread work remains, and a repeat run can detect regression.

### P0.8 Correct overlapping filler counts and product wording

**Shipped in 2.8.0 (2026-09-11):** longest non-overlapping matching (`TrainingMetrics.countFillerOccurrences`) in per-speaker stats and the live nudge, fixtures for overlap/repeat/hyphen/Spanish/empty cases, "detected fillers" wording with a floor caveat. Still open from the list below: the separate mic-only sidecar experiment (not planned).

**Why:** Filler phrases are counted independently, so an entry such as “uh huh” can also count as “uh”. Nova-3 also under-transcribes hesitations substantially, making the result a lower bound rather than a true count.

**Work:**

- Implement longest, non-overlapping token matching across configured phrases.
- Add English, Spanish, hyphenated, repeated, overlapping, punctuation, and user-customized regression cases.
- Audit defaults against Deepgram’s actual filler vocabulary before adding variants.
- Use honest UI/help wording such as “detected fillers” and avoid presenting the number as exhaustive.
- Evaluate a mic-only filler sidecar/local detector only as a separate measured experiment; Flux cannot replace the meeting stream because it lacks required diarization, multichannel, and language support, and a sidecar doubles mic-stream cost.

**Complete when:** No utterance is double-counted, existing customization still works, tests cover overlap, and the UI does not overstate model accuracy.

### P0.9 Secure webhook transport and diagnostics

**Shipped in 2.8.0 (2026-09-11):** HTTPS required with a loopback-only `http://` exception, enforced at send time and in both Settings views; logs carry scheme + host only and the full URL is a redaction pattern; transport and redaction tests in `WebhookPayloadTests`. Settings copy states that the payload includes the transcript and attendee names.

**Why:** Webhook payloads can contain the full transcript and attendee information, yet Settings currently accepts `http://`. Failure/non-2xx logs can include the complete URL, which may expose an embedded secret in exported diagnostics.

**Work:**

- Require HTTPS by default; if local HTTP development is retained, make it an explicit narrowly scoped development exception.
- Redact query strings, credentials, tokens, and sensitive path components from all webhook logs.
- Review existing diagnostics redaction for URLs as well as API keys.
- Add validation, redaction, and transport tests on both platforms.
- Document that webhook recipients receive sensitive meeting data and provide a clear test-delivery result.

**Complete when:** Production UI cannot casually send meeting data over plaintext transport, exported logs contain no webhook secrets, and tests prove both contracts.

### P0.10 Reconcile stale and conflicting local documentation

**Why:** Contradictory local guidance causes regressions even when the implementation is correct.

**Work:**

- Correct [distribution.md](distribution.md), which still describes optional blue `/api/version` update banners; supported clients now use only the mandatory minimum-version gate, with Sparkle on macOS and the App Store on iOS for normal updates.
- Verify the shipped managed Docs MCP backend and either complete the unchecked [Docs Insights acceptance checklist](docs-insights-api-spec.md#acceptance-checklist) or label any genuinely outstanding backend item.
- Verify that the deployed managed backend supports `mode="catchup"`; the client intentionally degrades to “not available yet” against older backends, so local documentation should state the actual production baseline.
- Re-measure and date [testing.md](testing.md) coverage.
- Clarify that Attio/Twenty note sync already exists; remaining CRM work is durable delivery, opportunity-field mapping, tasks, and deeper workflow automation.
- Reconcile [ANDROID_PLAN.md](../ANDROID_PLAN.md) with current platform behavior before implementation: it still proposes a normal update banner and lockstep macOS/iOS/Android versions, while normal banners have been removed and Apple platforms may ship independently. Also update stale platform-scope statements such as Calendar being macOS-only.

**Complete when:** Local documents agree with `AGENTS.md`, shipped work is not presented as future work, and every unchecked acceptance item is genuinely open.

## P1 — reliable at scale

### P1.1 Scale History search and grouping

**Why:** Transcript search scans and joins finalized transcript text across meetings. iOS recomputes the same query through multiple derived properties and includes avoidable nested membership checks. This will become visible with hundreds of long meetings.

**Work:**

- Debounce search on both platforms and compute one cached result snapshot per query/revision.
- Build immutable searchable projections off the main actor; consider a persisted lightweight index only after profiling.
- Replace nested grouping membership checks with sets/maps.
- Preserve title/date/transcript scoring, snippets, match counts, pins, deletion, accessibility, and macOS search-focus navigation behavior.
- Benchmark empty, short, and long queries over realistic 10/100/1,000-meeting fixtures.

**Complete when:** Typing and scrolling remain responsive on the large fixture, work is not repeated per body property, and search semantics have regression tests.

### P1.2 Make webhooks and automatic CRM sync durable

**Built, unreleased (2026-10-05, for 2.11.0):** `Miniti/Services/DeliveryOutbox.swift`, a persisted queue (Application Support `deliveries-outbox.json`) for webhooks (encoded body kept only until delivery) and automatic Attio/Twenty sends (payload rebuilt from the saved meeting at send time). Backoff 30 s, 2 min, 10 min, 30 min, 2 h, then terminal; 24 h max age; 429/5xx/transport retry, other 4xx reject, CRM no-unique-match skip; one `meeting.updated` per meeting (superseded in place); `X-Miniti-Delivery-Id` and `X-Miniti-Attempt` headers; kicked on enqueue, timer, and app activation; deleted meetings drop their items. Settings rows per kind with retry and discard. `DeliveryOutboxTests` (9). Not yet: connectivity-aware retry on network path change.

**Why:** Webhooks and automatic Attio/Twenty exports are detached best-effort calls. Network failure is logged but not persisted, retried, or visible, so an automation can be silently lost.

**Work:**

- Introduce a persisted outbox containing destination, meeting/revision, event type, attempt state, and safe error metadata.
- Add idempotency keys, bounded exponential backoff with jitter, terminal failure rules, and connectivity-aware retry.
- Show delivery state and a manual retry/cancel action without blocking meeting save or finalization.
- Coalesce superseded `meeting.updated` events safely and keep deleted-meeting/privacy behavior explicit.
- Avoid retaining unnecessary transcript copies longer than required.

**Complete when:** Offline/timeout/server-error tests recover without duplicate external records, users can see terminal failures, and saving a meeting never waits on a third party.

### P1.3 Improve short-interjection handling carefully

**Why:** Strict diarization gating can absorb or misattribute single-word backchannels such as “yeah”, “right”, or “mm-hmm”. Relaxing it indiscriminately would reintroduce false speaker switches.

**Work:**

- Build recorded/decoded fixtures for short local and remote interjections, echo, simultaneous speech, low confidence, and reconnect boundaries.
- Evaluate the documented confidence-gated relaxation only for already-confirmed speaker IDs (starting threshold: average speaker confidence at least 0.85).
- Evaluate consuming `UtteranceEnd` as the approximately one-second fallback currently enabled but ignored; keep `speech_final || is_final` behavior and strict stream ordering.
- Measure attribution gains and false-switch regressions before shipping.

**Complete when:** A fixture-backed threshold improves real interjections without degrading echo reconciliation, ordering, or speaker stability.

### P1.4 Add device-identity fallback observability

**Why:** Managed mode relies on a stable Keychain-backed device ID with a UserDefaults fallback. Repeated fallback on real devices could affect quota identity, CRM/OAuth state, and supportability.

**Work:**

- Keep the detailed `DebugLogger` ring local. Do not upload raw logs or mirror them into backend runtime logs.
- Extend the existing opt-in `Share Diagnostics` event queue and `/api/client-events` path with a small allowlisted vocabulary, starting with `device_id_keychain_fallback` and `device_id_keychain_recovered`.
- Include only bounded operational fields such as Keychain status code, read/write phase, whether an existing fallback was reused, platform, OS/app version, severity, and a random diagnostics-session correlation ID.
- Never include transcript/prompt text, meeting titles, attendees, emails, API keys, OAuth payloads, file paths, full URLs, raw device IDs in event details, or unrestricted `localizedDescription` values. Remove `meeting_id` unless a concrete support flow proves it necessary.
- Enforce the schema and redaction on both client and server. Unknown event names/detail keys should be rejected or dropped rather than stored generically.
- Send errors/degraded states and recovery transitions, not routine heartbeats. Deduplicate identical events per launch/cooldown and retain the existing bounded durable queue for offline delivery.
- Replace count-only Redis retention with time-based pruning: target 14–30 days for pseudonymous detailed events and up to 90 days for aggregate counts by event/version/platform. Low-volume records must not persist indefinitely merely because list limits were not reached.
- Add rate limits that account for IP/device churn and alert only on meaningful version/platform spikes.
- Treat P0.1 Phase 1 as a prerequisite for broader admin visibility; this work does not use Vercel Runtime Logs as its event store.

**Complete when:** Support can distinguish first creation, normal retrieval, fallback, and recovery without meeting content or secret-bearing fields; retention expires by age; opt-out clears unsent events; and tests prove allowlisting, redaction, deduplication, queue recovery, and expiry.

### P1.5 Maintain large-history Coaching performance

This is distinct from the one-time Instruments pass. Keep a benchmark fixture for hundreds or thousands of meetings, including missing talk-ratio data and all six metric series. Preserve six separate metric scales, plain numeric y-axes, adaptive numeric meeting ticks, centered `meeting` labels, equal sequence spacing, hover values, latest markers, and VoiceOver summaries. Introduce rendering downsampling only when measured and never alter aggregate values.

### P1.6 Recalculate managed-mode unit economics

**Why:** The financial model in [monetization.md](monetization.md) is explicitly historical. It predates the current $5/5,000-minute Pro tier, multichannel Deepgram billing, and the split between incremental `gpt-5-mini` and non-incremental `gpt-5.4-mini`. It must not guide pricing or capacity decisions.

**Work:** Recalculate blended transcription, multichannel, LLM, storage, payment, support, and infrastructure cost using current prices and observed user distributions. Model free, typical Pro, and heavy Pro cohorts; include reconnects, failed requests, Playbook usage, platform fees, VAT, and negotiated-volume scenarios. Use P0.1 Phase 5 cache/call telemetry and actual Deepgram billing rather than planning assumptions. Define margin/cost alerts and revisit limits or pricing only from current evidence.

**Complete when:** A dated model describes current gross margin and worst-case exposure per tier, the admin/backend can report the inputs needed to monitor it, and legacy figures are unmistakably archived.

### P1.7 Remove or adopt the unused limit-reached screen

**Done 2026-10-05:** `LimitReachedView` and its preview deleted; the file is now `LimitWarningBanner.swift` holding only the live banner Home uses.

`Miniti/Views/LimitReachedView.swift` is currently unreferenced; shipped limit handling is inline in the macOS and iOS meeting views. Either delete the dead screen and its preview or deliberately make it the shared limit experience with cross-platform tests. Do not modify it under the assumption that users can see it.

### P1.8 Plan backend runtime and Redis-client maintenance

Two upstream deprecations are real but must not be opportunistically bundled into P0.1 behavioral work:

- Next.js 16.3 warns that the Edge Runtime is deprecated. Inventory every edge route, Web Crypto dependency, latency/cold-start assumption, and Vercel header behavior; then migrate deliberately to `nodejs` only with route-level tests, preview observation, and rollback.
- `@vercel/kv` is deprecated even though the existing Upstash-backed integration still works. Plan a direct `@upstash/redis` migration across every command, generic/result conversion, Lua `eval`, test stub, and environment binding. Run parity tests and a preview/shadow validation before production cutover.

**Complete when:** Each migration has an independent design/PR sequence and no unresolved deprecation warning remains; neither is mixed into atomic registration, finalization, authentication, registry, or prompt-cache changes.

## P2 — bounded product expansion

### P2.1 Custom insight templates

Allow user-defined specialist views beyond Summary, Questions, Coaching, Sales, and Playbook. Candidate templates include BANT, SPIN Selling, customer-success check-ins, interview scorecards, and stand-up notes.

Start with a constrained section/prompt schema, preview, validation, safe token/input limits, versioning, export, and clear managed/BYOK routing. Avoid an unconstrained prompt editor that can silently break structured parsing. This is likely the best user-visible expansion relative to implementation effort.

**Status (2.6.0):** the first cut shipped as the built-in template pack (BANT, SPIN, interview scorecard, customer check-in, stand-up, 1:1) behind `mode=template` with the definition sent per request and the section/length limits enforced on both sides.

**Built, unreleased (2026-09-13, for 2.9.0):** the user-defined editor (Settings → Templates on both platforms: name, summary, up to 8 sections with title and guidance, live validation against the shared limits, preview against a past meeting, duplicate a built-in, JSON export/import, `CustomInsightTemplates.swift`), custom templates in the More menu, meetings keep a copy of their template (`Meeting.templateDefinitionJSON`) so history and exports survive edits and deletes, and template sections in Attio/Twenty notes (`AttioMeetingPayload.template`, `formatMeetingNoteContent`). No free-text prompts and no cross-device sync by design. Tracking: [p0-hardening-batch-2026-09-plan.md](p0-hardening-batch-2026-09-plan.md).

### P2.3 Deeper CRM workflow automation

Build on the existing macOS Attio/Twenty search, manual send, and uniquely matched automatic note export:

- map MEDDPICC, action items, owners, and next steps to opportunity fields;
- create/update tasks with explicit preview and conflict behavior;
- support reliable delivery through the P1 outbox;
- let users choose mappings and automation scope;
- record exactly what changed and make retries idempotent.

Attio is the likely first deep integration. Twenty self-hosted OAuth is not currently exposed and should be a separate demand-led item.

### P2.4 Entity detection with actionable CRM UX

Only pursue Deepgram entity detection if it ships with a useful click-through action. The proposed macOS-first, English-only experience persists a deduplicated person/organization list and shows “mentioned in this meeting” chips that open the existing Attio search flow.

The prior implementation sketch is retained: add `detect_entities=true` only for English streaming queries, decode `entities` on `DeepgramResponse.Alternative`, canonicalize/deduplicate them, and persist JSON on `Meeting` alongside other generated collections. Non-English meetings should skip the feature cleanly rather than failing transcription.

Do not ship decorative entity highlighting. Do not adopt Deepgram’s pre-recorded summarization, topics, intent, or sentiment merely for parity; they are English-only, duplicate current pinned OpenAI work, and do not independently improve the product.

### P2.5 App Store localization and submission automation

The Fastlane runbook retains two explicit follow-ups:

- expand App Store metadata and screenshot localization beyond `en-US` based on actual market demand;
- optionally add structured review/submission configuration beyond release notes so fewer App Store Connect steps are manual.

Keep generated listing copy platform-appropriate, never include macOS-only bullets in iOS metadata, and retain a human review before submission or automatic release.

### P2.7 Adjustable calendar filters with a "what would be skipped" preview

**Shipped in 2.8.0 (2026-09-11):** Settings → Calendar → Meeting filters on macOS and iOS (toggles per rule, editable title prefixes, next-7-days preview with reasons), `include_filtered=true` + `skipReason` on `/api/google/events` (miniti-api be59ba2). Remaining: Linux parity (12ian34/miniti-linux#11).

**Why:** 2.8.0 drops out-of-office, focus-time, working-location, and birthday events and a fixed list of time-block title prefixes (backend `isNonMeetingTitle`, client `CalendarEvent.isRecordableMeeting`) so they never raise reminders, auto-start, or the next-meeting handoff. The list is a guess at common labels; people name time off differently, and nobody can see what is being hidden.

**Work (all platforms; Linux tracking issue 12ian34/miniti-linux#11):**
- Settings → Calendar: a toggle per Google event type and an editable list of title prefixes, seeded with the shipped defaults.
- A preview that fetches the next 7 days from the connected calendar and lists each event that would be skipped with the reason, before the filters are trusted.
- `miniti-api`: an unfiltered variant of `GET /api/google/events` (for example `?include_filtered=true` returning a `filtered_reason` per event) so the preview can show what the server would drop; the client applies its own list on top.
- Keep the server defaults as the floor for older clients.

**Complete when:** a user can add "Gym" or remove "Lunch" from the list, see the next week's skipped events with reasons, and the Linux app shares the same prefixes and preview.

### P2.6 Join links, speaker-clone hardening, and inline dictionary corrections

**Shipped:** v2.7.0 on macOS 2026-09-10; iOS submitted the same day. Plan: [join-links-speaker-clones-inline-corrections-plan.md](join-links-speaker-clones-inline-corrections-plan.md).

Client implementation for calendar join actions, mic-speaker gating/promotion, implicit-You policy, and dictionary corrections is in this tree. The second-pass review and fixes of 2026-09-10 are recorded in the handoff section at the top of [join-links-speaker-clones-inline-corrections-plan.md](join-links-speaker-clones-inline-corrections-plan.md); `miniti-api` was deployed on 2026-09-10 (Meet links pasted into descriptions, speaker-names prompt assertion); remaining before release: Ian's manual matrix. Linux tracking: [#1](https://github.com/12ian34/miniti-linux/issues/1), [#2](https://github.com/12ian34/miniti-linux/issues/2), [#3](https://github.com/12ian34/miniti-linux/issues/3).

**Complete when:** plan regression contracts hold, both XCTest hosts pass, and the release notes for 2.7.0 are approved.

### P2.8 Cloud sync, cloud storage, and API/MCP access

**Platforms:** macOS and iOS first, Linux on its own line. **Repositories:** `miniti-api` (Neon Postgres store, `/api/sync/*`, `/api/v1/*`, `/api/mcp`, tokens, purge hooks) and this repository (additive schema, `SyncEngine`, Settings → Cloud, private mode interplay). Plan: [cloud-sync-plan.md](cloud-sync-plan.md). **Shipped 2026-10-16 in 3.0.0** (macOS build 130 live, iOS 130 in review); the plan's "As built" section holds the nuances and the not-built list (APNs push, write scopes, web History, Linux parity).

**Goal:** optional, default-off copy of a user's meetings on the account, synced to every enrolled device and readable by the user's own tools through a REST API and an MCP server. Existing users see nothing until they turn it on; private mode pauses it and keeps private meetings off it for life.

**Dependencies:** a durable store (Redis runs with eviction), a staged-rollout kill switch and allowlist, a tested lightweight migration of the 2.12.1 store on both platforms, a privacy-policy rewrite (the live text says there is no cloud archive), and the Linux contract note.

**Complete when:** the plan's regression contract holds, both XCTest hosts and `miniti-api` tests pass, the manual matrix in the plan has run on Ian's own account, and the privacy policy and docs page are live before the switch is offered to Pro.

## P3 — strategic programmes

### P3.1 Local mode programme

Local insights and local transcription are separate decisions. Do **not** add `local` as a third `AppMode`: managed/BYOK currently combine transcription credentials and insight routing, but a user may legitimately use managed Deepgram with local insights. Add an independent insight-provider preference and, later, a separate transcription-provider choice. Detailed research and source links remain in [local-ai-research.md](local-ai-research.md); this section owns delivery and priority.

#### Stage A — evaluate on-device insights

- Build a repeatable harness using 30–50 anonymized or synthetic representative transcripts: short/30/60–90-minute, every supported language, single/multiple speakers, all insight modes, ambiguous/corrected/contradictory actions, and sensitive content.
- Compare the current cloud baseline first with Apple's Foundation Models system model on macOS 26+, then with at least one small and one medium MLX model only if the Apple path leaves a real compatibility or quality gap.
- Measure grounding/hallucination, action/decision precision and recall, summary usefulness, question specificity, MEDDPICC evidence, schema reliability, language/guardrail failures, TTFT/total latency, process/Metal memory, energy/thermal state, audio/UI interference, cancellation, retry, and fallback.
- Test at minimum an 8 GB M1, a 16 GB Apple-silicon Mac, and a 24 GB+ Mac. Intel and unsupported/disabled Apple Intelligence installations retain cloud behavior.
- Prototype standard final summary, title, actions, and topics first. Apple's guided generation is preferred over hand-authored JSON, but its 4,096-token context requires measured speaker-turn chunking, structured partial extraction, bounded merging, and a smaller live recent window.

**Gate:** Do not begin product integration until the evaluation records per-feature, per-language, and per-hardware quality/performance thresholds and the Foundation Models path passes final standard insights without disrupting recording.

#### Stage B — separate provider architecture and privacy semantics

- Add an insight-provider preference: **Automatic**, **On-device**, **Managed cloud**, **OpenAI with my key**, and later **Downloaded local model**.
- Introduce a provider protocol returning the existing live/final insight structures. Implement managed API, BYOK OpenAI, Apple Foundation Models, and later MLX providers without weakening meeting-ID, transcript-revision, request-sequence, cancellation, stale-response, background-finalization, or save-queue protections.
- Define guided structures for standard insights, questions, speaker names, MEDDPICC, Playbook topics, and grounded answers.
- Provide two explicit privacy contracts: **Local only** never uploads a transcript for insights even after failure; **Prefer local, allow cloud fallback** may use the selected cloud route when local inference is unavailable/fails. Never silently upload under Local only.
- Describe this accurately: local insights are not a fully local meeting while audio still goes to Deepgram.
- Keep evaluation telemetry content-free and opt-in where required: provider, hardware bucket, duration/token counts, latency, peak memory, thermal state, outcome category, and fallback—never transcript or generated insight content.

#### Stage C — stage feature coverage

Ship only features that independently meet their evaluation gate, in increasing risk order:

1. Final summary, title, action items, and topics.
2. Live rolling summary.
3. Speaker naming and Playbook topic extraction.
4. Suggested questions.
5. Grounded Playbook answers.
6. MEDDPICC.

Coaching is already local computation and needs no provider work. Keep cloud as the default/fallback until representative transcript evaluation passes. MEDDPICC remains last because it depends on evidence aggregation across a long conversation.

#### Stage D — downloadable MLX models only if justified

- Use MLX only on Apple silicon and determine eligibility from architecture, physical memory, `MTLDevice.recommendedMaxWorkingSetSize`, disk space, thermal/Low Power state, a first-run benchmark, recording state, and memory pressure—not merely whether weights load.
- Treat 8 GB/1B–3B, 16 GB/3B–8B, and 24 GB+/7B–14B as test hypotheses, not promises.
- Select a licensed/version-pinned model and implement resumable on-demand downloads, integrity verification, disk checks, deletion/upgrades, tokenizer/model supply-chain controls, model-specific evaluations, idle unload, and bounded Metal caching.
- Requiring Ollama/LM Studio/Python/a localhost server may remain an advanced prototype or power-user integration, but is not the default consumer experience.
- macOS 27's common `LanguageModel`/`MLXLanguageModel` abstraction may shape the interface, but cannot become a production dependency while the shipping toolchain/support floor does not provide it.

#### Stage E — investigate local transcription separately

Local transcription is the larger possible cost saving and the larger regression risk. Deepgram remains the dominant direct cost, especially because macOS mic+system capture bills two channels; local insights alone do not justify larger managed minute allowances.

Built 2026-10-09 for 2.12.0 behind a default-off macOS setting, see [local-transcription-plan.md](local-transcription-plan.md) for the status table (manual validation, model pinning, iOS, and default-on remain open). Research captured the same day in [local-transcription-research.md](local-transcription-research.md): the leading candidate is NVIDIA Nemotron 3.5 ASR Streaming Multilingual 0.6B, already shipped inside the pinned FluidAudio 0.17.4 package as `StreamingNemotronMultilingualAsrManager`, covering all 11 languages with token timings for the existing diarizer. Apple SpeechTranscriber covers 6 of 11 languages and needs macOS 26 / iOS 26. Built the same day for 2.12.0 (macOS, default off), together with private mode (Settings → Privacy: both engines on this Mac, every cloud AI feature off) and the settings regrouping. Local insights (Stage D above) are what private mode needs next to get summaries back; until then a private meeting is transcript, speakers and coaching only.

- Evaluate Apple's `SpeechAnalyzer`/`SpeechTranscriber` on supported systems and whisper.cpp as a separate Apple-silicon path. Revalidate whisper package maintenance, licensing, model distribution, latency, and Xcode compatibility rather than adopting the old Ollama/whisper MVP by default.
- Measure word error rate across every supported language, interim/final latency/timestamps, punctuation, filler handling, key terms/custom vocabulary, background/assets, and contention with local insights.
- Preserve mic-versus-system “You”/remote separation on macOS, but do not ship a remote-speaker regression silently: neither Apple Speech nor Whisper supplies Deepgram-equivalent multi-speaker remote diarization. Evaluate sherpa-onnx or CoreML speaker embeddings/clustering separately.
- iOS mic-only multi-speaker attribution is a harder case and may retain cloud transcription even if macOS gains a local option.

#### Explicit non-goals and guardrails

- No Python runtime, pyannote, whisperX, or mlx-whisper dependency in the consumer app.
- No distributed `exo` inference; target one supported Mac.
- Do not claim cloud-equivalent MEDDPICC quality from small models without evidence.
- Do not promise local support from a marketing model name alone; dynamically check OS, Apple Intelligence/model availability, locale, memory, disk, and runtime conditions.
- Do not conflate cost/privacy claims: local insights remove OpenAI calls, while a fully local meeting additionally requires local transcription and diarization.

### P3.2 Android

The detailed [Android build plan](../ANDROID_PLAN.md) is ready but implementation has not started. V1 is a phone-first, native Kotlin/Jetpack Compose, mic-only app matching the practical iOS feature set. Validate BYOK microphone capture → Deepgram streaming first because audio format, WebSocket, permissions, and foreground-service behavior are the riskiest pieces.

Required backend work includes accepting `X-Platform: android`, an Android minimum-version gate/download URL, platform release notes, and admin visibility. Google Play Billing is intentionally v1.1+; tablet optimization, system-audio capture, KMP, translations, analytics SDKs, and elaborate dependency-injection frameworks are out of scope for v1. Internal Play testing precedes production.

Before starting, revalidate the plan’s API/model versions, Play policies, background-recording requirements, subscription strategy, and parity scope; the plan is a 2026 snapshot, not permission to copy stale constants blindly.

### P3.3 Linux

Separate repo: [`../miniti-linux`](../../miniti-linux) (sibling of this tree). Locked: Tauri 2 + Rust, macOS feature-parity intent, GitHub Release binary tarball + AUR (no Flatpak/AppImage), Polar Pro + BYOK. Canonical plan: that repo’s `AGENTS.md` / `PLAN.md`. Phase 0 is a PipeWire dual-capture → Deepgram spike on Arch + an Ubuntu 22.04-built binary. Backend needs `X-Platform: linux`, `LINUX_MIN_VERSION`, and a GitHub Releases download URL when a client exists. Do not implement inside this Apple repo.

### P3.4 Windows

Validate user demand and distribution/support costs before selecting architecture. Candidate implementation is native C++/Qt or Electron, with WASAPI loopback for system audio and the existing managed/BYOK services. Write a separate architecture spike covering capture reliability, updater/signing, local persistence, background behavior, accessibility, and shared API compatibility before estimating delivery. Linux Tauri/Rust learnings (capture recovery, dual-channel, Polar, API headers) should inform the Windows spike when relevant.

### P3.5 TypeSafe Jev for live classification

Not selected for delivery. Jev is a System One decision model (typed yes-probability, choice, or score; no generated text) that could replace or sit in front of local phrase heuristics and some GPT classification, not summaries or other prose.

Detailed fit, non-fits, privacy/proxy constraints, and the eval gate are in [jev-system-one-plan.md](jev-system-one-plan.md). If this is ever funded, the first slice is an offline eval of the Sales-conversation nudge and investigation-moment banner against the current heuristics, then a managed `miniti-api` proxy with the phrase lists as fallback. Do not put a Jev call on every transcript finalize. Do not replace call-lifecycle, Coaching metrics, or in-room inference. Linux needs a same-day tracking issue for any new managed classifier contract.

### P3.6 Apple Watch recording

**Platform:** watchOS companion to iOS, with Mac access through existing optional Pro cloud sync. **Planned 2026-10-18, not built; delivery priority/version unassigned.** The user selected recording on the watch with transcript and notes generated afterwards. Capture must work offline without the phone nearby; the paired iPhone handles transfer receipt, processing, account configuration, and history.

Detailed feasibility research and implementation contract: [apple-watch-plan.md](apple-watch-plan.md). Dependencies are a watch target, durable watch-to-phone file delivery, a saved-audio transcription/import path, and managed admission/accounting based on audio duration rather than live-session elapsed time. The production upload architecture is selected after the spike. Shared backend/sync changes require same-day Linux tracking before implementation.

**Validation and exit:** prove a 60-minute physical-watch background recording, offline/reconnect transfer, partial-audio recovery, idempotent import and billing, managed/BYOK processing, privacy/retention gates, and optional Mac sync. Both existing app test bundles and watch-specific validation must pass before TestFlight/release. The next work item is the physical-watch capture/transfer spike; this planning entry does not authorize a release.

## Known limitations and watchlist

These are not all immediate projects, but they must remain visible in product claims, support, testing, and future design.

### Audio and transcription

- Echo reconciliation is deliberately conservative. Distorted playback leakage may still appear as “You”; more aggressive removal risks deleting genuine interruptions.
- Mixed mic/system finals can settle for up to 350 ms, while ambiguous mic echo reconciliation can take up to four seconds. Rare late genuine mic speech may insert into already-finalized text.
- Short interjections may be lost/misattributed until P1.3 proves a safe improvement.
- Nova-3 filler results are a floor, not a complete count; Flux is not a drop-in meeting transcription replacement.
- `SpeechStarted` and `UtteranceEnd` frames are enabled but ignored. `UtteranceEnd` is only a candidate fallback, not automatically a bug fix.
- Dual-channel macOS capture roughly doubles Deepgram minutes; mic-only, system-only, and iOS remain mono.
- Local mode Whisper has no native diarization, and current energy separation only distinguishes audio source, not every person.

### Platform behavior

- iOS cannot wake the app to auto-start a calendar meeting; calendar auto-start only operates while foregrounded.
- Compact Dynamic Island width is controlled by the system.
- The product is intentionally dark-mode only. Light mode is not an accidental omission or active backlog item unless product strategy changes.
- Hardware callback cessation, Bluetooth profile handoffs, real microphones, and system-audio routes cannot be fully represented by unit tests and retain a manual matrix.
- Hard kill and unfinalized interim words remain best-effort platform/protocol boundaries even after checkpoint improvement.

### Integrations and privacy

- Webhooks include sensitive meeting content; transport/redaction is P0 and reliable delivery is P1.
- Automatic CRM export currently skips zero or ambiguous matches rather than guessing.
- Twenty self-hosted connection is not exposed in the app.
- Google, CRM, StoreKit/Polar, and managed API behavior span the sibling `miniti-api` repository; changes require its own `AGENTS.md`, tests, rollout, and backward-compatibility review.
- The managed client API key is not a secret; server-side controls remain authoritative.

## Non-negotiable engineering and release guardrails

These are constraints, not backlog items. Any related change must preserve them or deliberately replace them with stronger tested behavior.

### Data and concurrency

- `AppState.modelContext` must be wired from the first appearing root view on both platforms or saves silently no-op.
- Never read a SwiftData model across a task hop; snapshot value data before suspension because deleted model access can trap.
- Every delete must mark the meeting deleted before removing it so an in-flight save or regeneration cannot resurrect it.
- Never replace the per-meeting revision-fenced save queue with a global latest payload or cancel its shared worker during a single-meeting delete.
- Do not overwrite JSON-backed SwiftData fields when encoding fails.
- Keep high-frequency audio/transcript state out of broad `AppState` invalidation, avoid main-actor tasks per audio buffer, and never scan/filter the full growing transcript from per-final callbacks.
- Preserve ordered off-main Deepgram parsing and connection-generation/socket guards so stale reconnect results cannot apply.

### Backend runtime and data

- Read `../miniti-api/AGENTS.md` and its relevant `docs/agents/*` contract before backend work; this roadmap owns priority, not route implementation detail.
- Edge routes are evaluated during build. Never construct SDK clients at module scope when they require runtime environment variables.
- Redis `hgetall` values may return numeric and Boolean fields as strings; normalize explicitly before arithmetic or entitlement decisions.
- Apple JWS verification depends on Node `crypto` and certificate-chain validation, so Apple verification/webhook routes remain `nodejs` unless a deliberately tested replacement exists.
- Route tests call handlers directly and share an in-memory KV shim; reset it for every test to preserve isolation.
- Validate all Redis/Lua inputs and existing value types before the first mutation. Keep creation, finalization, idempotency, indices, and counters atomic according to P0.1.
- Do not use `KEYS device:*` in normal production reads after registry cutover, and do not silently fall back to it when an index drifts.
- Do not combine Edge-runtime or Redis-client migrations with security, registration, finalization, registry, auth, or prompt-cache behavior changes.

### UX and accessibility

- Use `ColorPalette` and `MinitiDesignSystem`; do not hardcode colors or fork shared component measurements.
- Native `Button`/`Menu` controls retain action, focus, disabled, shortcut, and accessibility ownership.
- Respect Reduce Motion, dynamic type/interface scale, iPhone compact navigation, and regular-width iPad adaptation.
- Coaching retains six semantically distinct metric colors and six independent chart scales; never combine incompatible units into one chart.
- macOS back/forward gestures must ignore vertical scrolling, sheets, momentum, and ordinary text editing, while allowing and blurring the focused meeting-search field on committed navigation.

### Distribution and secrets

- Back up the Sparkle private key outside the repository. Losing it prevents installed clients from verifying future updates.
- Keep Sparkle at 2.9.3 or newer (currently 2.9.5) because older cache naming collides with Miniti’s `.app`-suffixed bundle ID.
- Preserve `SUEnableInstallerLauncherService` and the sandbox mach-lookup exceptions or Sparkle can download but fail installation with `-60005`.
- Never re-sign the outer app without `Miniti.entitlements`; verify the sandbox entitlement in the final DMG. The v1.24.0 failure made existing history appear missing by changing the app’s container identity.
- Sign/notarize/staple the final DMG bytes before generating the Sparkle signature; re-check the live download length and SHA-256 against local output.
- Treat a stale Sparkle `sign_update` symlink after DerivedData cleanup as an environment failure, not a reason to bypass signing.
- macOS and iOS versions may diverge, and iOS lanes auto-increment build numbers unless `build:N` is supplied. Update per-platform backend minimums independently.
- Deepgram project credentials used to mint short-lived tokens need the documented grant permissions and operational rotation/expiry review; never embed managed provider secrets in the client.
- A future machine migration must restore Developer ID/Apple Distribution private keys and Xcode account access before release work.

### Required release validation

- Run both shared XCTest bundles because the same test sources compile against both hosts.
- Build macOS and an iOS simulator target.
- Run the relevant manual regression matrices in [testing.md](testing.md), especially audio hardware, long transcript, Coaching, Settings, navigation, Smart meetings, and Live Activity.
- Follow [RELEASE.md](../RELEASE.md) and [fastlane/RUNBOOK.md](../fastlane/RUNBOOK.md); do not improvise signing or notarization commands.
- For `miniti-api` changes, run `npm test`, `npm run lint`, and `npm run build`, plus the phase-specific preview/shadow/production checks in P0.1. A push to its `main` branch deploys production, so do not also issue an unnecessary production deploy.

## Shipped foundations — do not re-add as future work

The following former roadmap items are complete and form the baseline for future changes:

- ordered off-main Deepgram parsing and speaker segmentation;
- reduced audio callback allocation churn, reusable DSP storage, ring-buffered source history, and bounded meter publication;
- power-aware live-insight cadence with maximum-age escape hatches and failure cooldowns;
- incremental finalized transcript rendering and throttled interim/auto-scroll presentation;
- Reduce-Motion-aware adaptive waveform cadence;
- cached transcript/persistence projections and removal of repeated full-array hot-path scans;
- privacy-safe performance signposts (the long validation remains P0.7);
- revision-fenced async save durability, per-meeting coalescing, iOS background-task leasing, and macOS deferred termination;
- unified macOS system-audio callback-stall watchdog;
- Docs MCP/Playbook specialist view (backend acceptance status still needs P0.10 verification);
- Smart meetings and reliable macOS reopening; [its plan](smart-meetings-plan.md) is retained as a regression contract;
- macOS call-app lifecycle detection, consent-preserving start prompts, reversible automatic endings, red menu-bar timing, and the floating recording surface; [its plan](call-lifecycle-and-recording-presence-plan.md) is retained as a regression contract;
- cloud shared-microphone diarization with collision-free mic identities, neutral identity handling for mic-only and multi-person rooms, reconnect continuity, and diagnostic-only environment inference; [its plan](automatic-in-room-diarization-plan.md) is retained as a regression contract and field-validation watchlist;
- local Sales-conversation suggestions plus foreground floating-surface routing for question and Coaching nudges, with dismiss and per-type disable actions;
- searchable adaptive Settings, regrouped in 2.12.0 into Setup, Meetings, Connections, Privacy, Support with single-word tabs; [its plan](settings-redesign-plan.md) is retained as a regression contract;
- the Coaching focus/stats/history redesign and separate per-metric chart model;
- calendar-event prep notes plus explicit, locally suggested in-app OpenAI investigations;
- iOS Live Activity transcript controls and tap-through to the active meeting;
- macOS back/forward trackpad navigation across Home, Coaching, and meeting history;
- Attio/Twenty task previews with deadline, assignment, and per-task inclusion controls;
- signing, notarizing, and stapling the DMG itself before appcast publication.

## Backlog maintenance

- This file owns priority, sequencing, decisions, and completion status across both `miniti` and `miniti-api`. Focused docs own current implementation detail and regression rules; do not create another competing roadmap in either repository.
- Add newly discovered production risks here even when they arise from code rather than an inline `TODO`.
- Do not use production `TODO` comments as the planning system. At the August 2026 audit there were no material production `TODO`/`FIXME`/`HACK` markers; the meaningful debt was in behavior and documentation.
- Re-rank after incidents, measured performance results, user research, revenue evidence, platform-policy changes, or significant backend cost changes.
- For product bets, record the user problem and success metric before implementation. For reliability work, record the failure fixture and prove it no longer reproduces.
