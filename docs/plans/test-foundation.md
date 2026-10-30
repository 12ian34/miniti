# Trustworthy test infrastructure and service contracts

Status: planned, not implemented. Version: unassigned. Scope reconciled 2026-10-27. [Roadmap](../roadmap.md) owns priority; this file owns completion. One release may include several completed plans. Ordered backend deployments inside a plan are not separate unfinished product releases.

## Deliverable and boundary

Bounded T01/T06/T07/T14 infrastructure and insights-route coverage, plus T17 evidence cleanup only where replacement tests exist. Add documentation-link and release-metadata consistency checks to CI. Feature-specific regressions stay with their feature plans.

## Prerequisites and decisions

Use the dated audit as evidence, not current test counts. Do not drop useful tests or require paid live-provider calls for routine CI. Test databases must be isolated from production.

## Implementation contract

## T01: test infrastructure that reports failures and isolates state

**Files:** `scripts/coverage.sh`, `MinitiTests/TestSupport.swift`, `MinitiTests/TestRunSetup.swift`, test-host dependency setup, both CI workflows, backend `test/setup.ts`, `tsconfig.json` and any dedicated test type-check configuration.

- Preserve `xcodebuild` failure through the coverage pipeline. Keep coverage artifacts when useful, but return a failing status when tests fail. The main Apple CI gate already handles failure correctly; preserve that behavior.
- Replace shared mutable delayed URLProtocol behavior with per-test/session scripts, synchronized request capture and cancellation that cancels pending work. Capture the intended response for its request. Use explicitly suspended continuations or controllable scheduling for race tests instead of sleep-based guesses.
- Inject isolated defaults, credential storage, outbox paths and model containers before AppState/service initialization. Restoring the live defaults domain at bundle completion is insufficient when a test crashes. Keep real microphone/device switching tests in an explicit hardware lane.
- Give the KV double controlled time and supported expiration semantics, or explicitly route those cases to real Redis. Keep mocks narrow and preserve existing coercion behavior. Add a separate type check for backend tests so production exclusions do not leave test helpers unchecked.

**Complete when:** a deliberately failing test makes coverage execution fail; cancelled responses cannot call a later test's handler; tests run repeatedly in changed order without shared-state leakage; isolated test failures cannot alter the installed app's settings or credentials; tests and helper types compile. Record remaining hardware prerequisites and skip reasons.

## T07: shared contracts against real storage

**Files:** backend `lib/cloudStore.integration.test.ts`, `lib/cloudStore.ts`, `test/setup.ts`, CI and database test setup.

- Run the same behavioral contract against the memory and PostgreSQL implementations: revisions, conflicts, tombstones, external duplicates, search/pagination, tokens, email, web sessions and OAuth clients/grants/codes/refresh families.
- Add simultaneous writes, single-use link/code consumption, revocation and injected failure after a write. Exercise schema migration from representative prior database schemas in disposable instances.
- Use isolated Redis for TTL expiry, NX/admission locks, idempotency records, rate windows and failure recovery. Existing explicit token timestamp checks remain useful; the gap is backend storage semantics.
- Add an explicit CI integration job using disposable services or a dedicated test database. The required job fails if its database is unavailable instead of silently skipping. Keep optional live-provider tests outside ordinary PR gates.

**Complete when:** ordinary fast tests stay fast, the storage job actually executes, and its report names the real adapter, concurrency cases and cleanup result. No production database or shared account data is used.

## T06: insights endpoint behavior

**Files:** backend `app/api/insights/route.ts`, a new route test file, existing `lib/insights.test.ts` and relevant rate/quota helpers.

- Call the real handler with provider responses controlled at the outbound boundary. Cover missing/invalid device proof, revoked/disabled installs, invalid bodies and rate-bucket isolation. Refused requests must not contact providers or increment billable counters.
- Exercise the supported full/incremental modes, including standard, MEDDPICC, questions, templates, docs, investigations, speaker names, catch-up, docs topics and template drafts. Assert the selected dispatch and response contract rather than exact model prose.
- Cover timeout, malformed provider responses, fallback preservation, request sequence/revision metadata, applied/stale/degraded outcomes and cost/usage recording. Meter docs lookups according to the actual success/no-result/error contract, including retries.
- Add missing direct catch-up coverage while preserving existing generation/parsing tests and pinned model routing contracts.

**Complete when:** changing a handler guard, dispatch, quota boundary or fallback metadata breaks a relevant route test; provider failures preserve valid previous state and never claim successful fresh generation.

## T14: shared wire fixtures and cross-language compatibility

**Files:** `MeetingSyncDocumentTests`, Swift `ClientAuthTests`, backend sync-document/auth fixtures and CI.

Choose one versioned canonical fixture source with a reproducible import/check into the other repo. Enforce equivalence in CI without assuming a sibling checkout exists. Round-trip actual Swift-produced documents through backend validation/storage/response and back through Swift decoding. Exercise unknown fields, nulls, date/numeric coercion, schema versions and old supported clients. Verify Swift-produced request-proof vectors in the backend and reject altered bytes.

**Complete when:** an incompatible wire/auth change or divergent fixture fails a cross-repository contract check; harmless normalization is explicit. Keep independent golden-vector assertions on both sides.

## T17: retire brittle checks and make claims accurate

| Existing check | Change | Preserve |
| --- | --- | --- |
| ColorPalette compact height/padding/radius and Coaching width/height equal literal constants | Consolidate/remove numeric mirrors once T12 protects the intended layouts; keep an exact value only where it is an explicit compatibility contract | Semantic color separation, shared roles, conversion/cycling logic and actual platform adaptation |
| Version route asserts current marketing words and latest release number | Use a controlled release fixture; remove current-prose assertions | Forced versus optional updates, platform/minimum-version handling and download response contract |
| Journey names claim relaunch, no save and ordering | Repair under T11 or rename to the tested boundary | Degraded-backend save/history behavior |
| Revoked-device and four-hour cap cases | Strengthen under T02 | Existing foreign-account, rollover and sequential replay coverage |
| Voice-print export checks search for “voice” | Replace under T13 | Biometric privacy and normal prose export |
| Classify test promises 502/504 but exercises only 502 | Add an actual timeout/504 case or narrow the title | Existing upstream error mapping |
| Sync test promises every route is disabled but calls only manifest | Table-test the relevant route guards or narrow the title | Disabled-feature refusal contract |

Do not delete no-crash Unicode regressions just because they have no explicit assertion. Keep bundled license/acknowledgement checks, model pins, stable wire values, crypto vectors, KV string/boolean coercion and empty/non-final transcript cases. Shared macOS/iOS source is intentional platform coverage. Parameterize repetitive examples only when failure diagnostics remain clear.

Update [testing.md](../reference/testing.md), screenshot documentation and the backend runbook with actual test boundaries, current dated execution results, skip reasons and commands. Historical measurements stay labelled. Replace stale claims such as a test count presented as current or “view wiring covered” when only launch readiness was checked.

**Complete when:** removed assertions have a documented reason/replacement, names describe what executes, and test reports distinguish unit, handler, real-store, UI, hardware and provider evidence.

## Acceptance and delivery

Demonstrate that intentional representative failures fail the runner, concurrent storage operations exercise real Redis/Postgres semantics, fixtures stay equal across clients and backend, and clean runs are reproducible. Required integration jobs must not silently skip. Retain hardware-only gates and report coverage with date/commit.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

Rollback: test-only changes should not affect production. Restore a previous job only with explicit recording of the coverage lost; never mask an error to make CI green. [Audit and T01–T17 mapping](../archive/README.md#test-audit-disposition).
