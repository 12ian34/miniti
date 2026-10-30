# Backend runtime migration

Status: scoped future work, not implemented; version unassigned. Reconciled 2026-10-27. Priority is in [the roadmap](../roadmap.md). This is a bounded deliverable, not an ongoing maintenance programme. Confirm design and release scope before implementation.

## Scope

Inventory Edge routes, Web Crypto, SDK construction, request/header behavior and cold-start assumptions. Revalidate the upstream deprecation and current supported runtime before choosing a migration. Move selected routes to Node with no auth, billing or product changes.

## Dependencies and exclusions

Original P1.8. Schedule after ownership migrations stabilize; never combine with authentication, registration, metering, registry or prompt behavior changes. This plan is independently shippable from the other infrastructure migration.

## Acceptance and rollback

Route-level compatibility tests, old-client auth/proofs, Apple JWS verification, preview latency/cold-start measurements, deployment observation and a route-by-route rollback. Record the exact runtime/package baseline and deployment flags. Keep runtime-only/dependency-only changes reversible without reverting data migrations.


## Release contract

Record before/after evidence and run the affected backend checks and both Apple bundles for shared client changes. Update current reference docs and the per-platform release record. Preserve existing data and compatible old clients. Shared backend changes require Linux tracking. No deployment is authorized by this document. Close the whole stated scope when shipped; unrelated discoveries become separate roadmap items.
