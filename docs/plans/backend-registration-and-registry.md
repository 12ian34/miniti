# Atomic registration and a paginated device registry

Status: scoped future work, not implemented; version unassigned. Reconciled 2026-10-27. Priority is in [the roadmap](../roadmap.md). This is a bounded deliverable, not an ongoing maintenance programme. Confirm design and release scope before implementation.

## Scope and prerequisites

Own the remaining original P0.1 phase 2: centralized atomic device creation/admission and bounded admin registry/index reads. Admin auth is already shipped. This does not own B0 record adoption or B2 session finalization. Prefer implementation after the account-ownership canonical writer is established; integrate with its adoption script rather than creating a competing writer. If abuse makes admission urgent earlier, explicitly revise the dependency and all writer contracts first.

The older phase below is retained as a design input. An existing UUID is not proof of an authorized returning installation. Preserve current create limits for revoked/unauthenticated requests; any existing-device retry exemption must prove the existing authenticated/idempotent operation. Do not reintroduce the revoked-device exemption removed in 4b41878.

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

## Acceptance and rollout

Concurrent creates yield one record/index membership and appropriate budget charges; ineligible/spoofed/revoked IDs do not bypass admission. Validate every Lua input/type before mutation. Reconcile legacy records by SCAN in a bounded backfill, shadow reads and then paginated cutover. No ordinary admin path should use KEYS after cutover. Test against real isolated Redis, interrupted backfills, old header spellings, proxy/IP normalization, NAT and IPv6. Require measured limiter/cardinality headroom.

Rollback retains canonical writes and durable registry data; turn reads back only to a reviewed bounded compatible path. Never undo B0 by recreating uppercase records. Do not bundle a Redis-client or runtime migration.


## Release contract

Record before/after evidence and run the affected backend checks and both Apple bundles for shared client changes. Update current reference docs and the per-platform release record. Preserve existing data and compatible old clients. Shared backend changes require Linux tracking. No deployment is authorized by this document. Close the whole stated scope when shipped; unrelated discoveries become separate roadmap items.
