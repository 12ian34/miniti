# Redis client maintenance

Status: scoped future work, not implemented; version unassigned. Reconciled 2026-10-27. Priority is in [the roadmap](../roadmap.md). This is a bounded deliverable, not an ongoing maintenance programme. Confirm design and release scope before implementation.

## Scope

Replace @vercel/kv with a supported direct client only after verifying current maintenance needs. Inventory every command, result conversion, Lua eval, environment binding and test double. Preserve canonical writers and billing semantics.

## Dependencies and exclusions

Original P1.8. Schedule after ownership migrations stabilize; never combine with authentication, registration, metering, registry or prompt behavior changes. This plan is independently shippable from the other infrastructure migration.

## Acceptance and rollback

Command/result parity against isolated real Redis, atomic script semantics, numeric/Boolean normalization, all route tests, preview observation and dependency-only rollback. Record the exact runtime/package baseline and deployment flags. Keep runtime-only/dependency-only changes reversible without reverting data migrations.


## Release contract

Record before/after evidence and run the affected backend checks and both Apple bundles for shared client changes. Update current reference docs and the per-platform release record. Preserve existing data and compatible old clients. Shared backend changes require Linux tracking. No deployment is authorized by this document. Close the whole stated scope when shipped; unrelated discoveries become separate roadmap items.
