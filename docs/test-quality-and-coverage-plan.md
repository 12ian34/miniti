# Test quality and coverage plan

Planned 2026-10-27 following Ian's 2026-10-26 review request across `miniti` and `miniti-api`. This plan captures every recommendation from that review: repair misleading assertions, cover missing user and backend flows, improve test isolation, and retire low-value checks. No implementation or release is assigned by this document. Cross-repository priority remains in [roadmap.md](roadmap.md), P0.12.

The useful parser, authentication, serialization, persistence-failure, transport and lifecycle tests stay. The main investment is proving behavior across boundaries, especially money, privacy, asynchronous work, real storage and UI interaction. Test count and aggregate coverage percentage are not completion criteria.

## Audit baseline

Reviewed app `af470aa` and backend `4b41878`: 30 Swift test files plus two support files, registered in both Apple test targets, and 56 backend test files. Platform guards intentionally produce different case counts. The backend run passed 634 tests with three skipped: two PostgreSQL integration tests and one live Jev test. The review did not rerun the Apple bundles, hardware tests or live providers. Historical results in [testing.md](testing.md) remain dated evidence.

Experiments used an isolated backend copy, without changing either working repository:

| Experiment | Result | Regression required |
| --- | --- | --- |
| Change the session duration cap from four hours to two | All 634 tests still passed | Exact charge at and around the cap |
| Remove revoked-device filtering from account entitlement and usage aggregation | All 634 tests still passed | Explicit revoked sponsor and usage-bearing sibling |
| Send two concurrent end requests for one ten-minute session through the real handler and existing KV test double | Both responses succeeded; stored usage was 20 minutes | Exactly one ten-minute charge, including concurrency and retries |

The concurrency result demonstrates the handler race with the test double, not a production load measurement. Reproduce it against isolated Redis in T07 as well. The sync-document JSON copies were compared and matched at review time; T14 prevents future drift.

## Ownership and boundaries

- [Roadmap P0.1, phase 3](roadmap.md#phase-3--make-session-finalization-atomic) owns atomic session finalization. T02 supplies its regression requirements.
- [Reliability R1–R8](reliability-follow-up-plan.md) owns the private-mode, consent, cloud-account, Watch retry, outbox and stale-response fixes. T03/T08/T10 supply coverage; do not create competing implementations.
- [Account, Sending and consent UX](account-sending-consent-ux-plan.md) owns U2/U1/B6a. T12 supplies automated interaction and rendered validation alongside its device QA.
- [Enrollment identity](enrollment-identity-plan.md) owns credential recovery and account ownership. Preserve its compatibility and rollout decisions when adding purchase/account tests.
- Configured webhook and CRM exports remain allowed in private mode. Tests must not impose a blanket network ban or pretend that changing a preference replaces an already-running engine.
- Managed endpoint tests use device-bound bearer/proof authentication. Keep explicitly supported legacy compatibility cases separately; never add a shared client secret to the app.
- Use isolated stores, credentials, audio fixtures and provider doubles. Real-provider and hardware runs use designated test environments. This plan creates no scheduled job and authorizes no production deployment.

**Post-3.4.0 reconciliation, 2026-10-27:** auth generation/lifecycle, narrowed History/Watch consent, cloud response fencing and failed-mic regressions added during 3.4.0 provide part of the evidence relevant to T08/T09. They do not complete this broader programme. Inventory/reuse those tests before adding more; do not reimplement the shipped production fixes. O2 diagnostics-queue coverage belongs with the proposed ops follow-up.

## Status and sequence

Every slice is planned. Priority here means implementation order within this testing programme, not a new product roadmap classification. Finish the small harness prerequisites, then money/privacy regressions; do cosmetic cleanup last. A known-bug regression should fail before its fix and pass with it. Do not merge a permanently red suite, weaken the assertion or silently skip it to claim completion.

| ID | Priority | Slice | Repository/platform | Depends on | Status |
| --- | --- | --- | --- | --- | --- |
| T01 | First | Honest exits and isolated, deterministic test helpers | Both; macOS/iOS | None | Planned |
| T02 | First | Exact and concurrent usage; revoked devices | Backend | T01 where needed; P0.1 phase 3 for atomic fix | Planned |
| T03 | First | Real webhook retry and in-flight coalescing | App; macOS/iOS | T01; R5 before R6 | Planned |
| T04 | First | Apple purchase and entitlement lifecycle | Both; iOS plus sponsorship rules | T01; existing billing contract | Planned |
| T05 | First | Polar purchase and entitlement lifecycle | Backend; macOS purchase rail | T01; existing billing contract | Planned |
| T06 | First | Insights route orchestration | Backend | T01 | Planned |
| T07 | First | Real storage contracts and failure recovery | Backend | T01; feeds T02/T04–T06/T08 | Planned |
| T08 | First | Consent, private mode, account and response races | Both; macOS/iOS | T01; R1/R2/R3/R7/R8 | Planned |
| T09 | Next | Recording start, reconnect, stop and handoff | App; macOS/iOS | T01; T08 permission policy | Planned |
| T10 | Next | Complete Watch import and retry lifecycle | App/backend; watchOS/iOS | T01; R2/R4 | Planned |
| T11 | Next | Honest meeting journeys, disk recovery and upgrades | App; macOS/iOS | T01 | Planned |
| T12 | Next | UI interaction, accessibility and rendered design | App/backend web | T01; U2/U1/B6a as implemented | Planned |
| T13 | Next | Voice-print privacy and model quality | Both; supported local-model hardware | T01; versioned corpus | Planned |
| T14 | Next | Cross-repository wire contracts | Both | T01 | Planned |
| T15 | Next | Long-session performance and resource bounds | App; macOS/iOS | T09/T11; P0.7 measurement | Planned |
| T16 | Next | CRM partial failures and diagnostics ingestion | Both/backend | T01; T03 for delivery integration | Planned |
| T17 | Last | Remove brittle checks and reconcile coverage claims | Both | Replacement evidence from relevant slices | Planned |

Small assertion repairs in T02/T11 can land before broader integration work. T07 is developed alongside the money and account slices so real storage verification does not become a final deferred step. Run the appropriate existing suite after each slice; run both Apple bundles and the full backend checks on combined changes before marking the programme complete.

## T01: test infrastructure that reports failures and isolates state

**Files:** `scripts/coverage.sh`, `MinitiTests/TestSupport.swift`, `MinitiTests/TestRunSetup.swift`, test-host dependency setup, both CI workflows, backend `test/setup.ts`, `tsconfig.json` and any dedicated test type-check configuration.

- Preserve `xcodebuild` failure through the coverage pipeline. Keep coverage artifacts when useful, but return a failing status when tests fail. The main Apple CI gate already handles failure correctly; preserve that behavior.
- Replace shared mutable delayed URLProtocol behavior with per-test/session scripts, synchronized request capture and cancellation that cancels pending work. Capture the intended response for its request. Use explicitly suspended continuations or controllable scheduling for race tests instead of sleep-based guesses.
- Inject isolated defaults, credential storage, outbox paths and model containers before AppState/service initialization. Restoring the live defaults domain at bundle completion is insufficient when a test crashes. Keep real microphone/device switching tests in an explicit hardware lane.
- Give the KV double controlled time and supported expiration semantics, or explicitly route those cases to real Redis. Keep mocks narrow and preserve existing coercion behavior. Add a separate type check for backend tests so production exclusions do not leave test helpers unchecked.

**Complete when:** a deliberately failing test makes coverage execution fail; cancelled responses cannot call a later test's handler; tests run repeatedly in changed order without shared-state leakage; isolated test failures cannot alter the installed app's settings or credentials; tests and helper types compile. Record remaining hardware prerequisites and skip reasons.

## T02: exact billing, concurrent finalization and revocation

**Files:** backend `app/api/session/end/route.test.ts`, `app/api/session/prerecorded/route.test.ts`, `lib/accountEntitlement.test.ts`, `lib/accountUsage.test.ts`, and P0.1 phase 3 production changes.

- Replace `minutes_used <= 240` with exact stored and returned values for below/at/above the cap. Freeze time for live elapsed-time caps; distinguish prerecorded audio length, missing-session behavior, paused/zero reports and ownership rejection.
- Recreate the ten-minute concurrent request failure. Cover sequential replay, simultaneous requests, a lost successful HTTP response, retries after partial failure, and unrelated sessions/devices proceeding independently. Check current/lifetime/account usage and finalization state without charging twice.
- Add a genuinely revoked paid sibling to the sponsorship test and a revoked sibling with nonzero usage to account aggregation. Preserve foreign-account, legacy, rollover and platform-specific Apple sponsorship cases.

**Complete when:** lowering the cap to two hours and removing either revoked-device filter each make a targeted test fail; the concurrency regression charges ten minutes once through both the handler double and isolated Redis contract. Implement finalization under the existing atomicity plan rather than adding a test-only lock.

## T03: webhook retries deliver real, current data

**Files:** `MinitiTests/DeliveryOutboxTests.swift`, `Miniti/Services/DeliveryOutbox.swift`, AppState delivery sender wiring. Implementation owners: R5/R6.

- Replace the manual-retry sender that always returns `.delivered` with the real sender path or a boundary double that rejects missing bodies and captures delivered bytes.
- Preserve terminal payload disposal. Manual resend rebuilds the current saved meeting with a new delivery identity, as R6 specifies. Assert that trimmed text stays removed, deleted meetings cannot reappear, and a missing/changed destination is handled explicitly.
- Suspend v1 delivery; enqueue v2/v3 before releasing v1 success, retry or rejection. Assert that the newest update survives and is delivered correctly. Include reload, deletion and explicit resend while work is pending.

**Complete when:** a terminal failure followed by manual resend sends a valid current payload; old completions cannot erase newer updates; persistence, backoff and CRM sender behavior remain covered.

## T04 and T05: purchases become the correct entitlements

**Apple files:** backend `lib/apple.test.ts`, `app/api/apple/verify/route.ts`, `app/api/webhooks/apple/route.ts`; client StoreKit service and entitlement integration tests.

- Test the actual signed transaction and notification verification boundary: malformed/tampered JWS, untrusted or invalid certificate chains, wrong bundle/product, environment handling and invalid dates according to the selected contract. Inject a test trust anchor or use stable signed fixtures without bypassing signature verification.
- Exercise purchase/restore through verification into persisted Pro and usage responses. Cover active, grace, billing retry, expiry, refund/revocation, renewal preferences, duplicates, out-of-order notifications, partial writes and retry recovery.
- Verify all linked devices and platform sponsorship rules. Add a StoreKit test configuration and purchase/restore/transaction-update journey on iOS, including user cancellation, pending purchases and backend unavailability. Keep local entitlement-state unit tests as supporting coverage.

**Polar files:** backend `lib/polar.test.ts`, `app/api/webhooks/polar/route.test.ts`, subscribe/portal/restore handlers and entitlement helpers.

- Preserve signature, missing-secret and renewal propagation tests. Add cancellation versus effective expiry, revocation/refund, duplicate/out-of-order delivery and recovery after a partial device update.
- Cover checkout/portal authentication, ownership and provider failures; retain restore configuration and identity safeguards. Confirm that restoring a purchase follows the existing account contract.

**Complete when:** each lifecycle transition changes only the intended devices/account state, old events cannot incorrectly restore Pro, failed deliveries can recover, and a cancelled or unsuccessful purchase never claims entitlement. Record test-environment StoreKit QA separately from mocked route success.

## T06: insights endpoint behavior

**Files:** backend `app/api/insights/route.ts`, a new route test file, existing `lib/insights.test.ts` and relevant rate/quota helpers.

- Call the real handler with provider responses controlled at the outbound boundary. Cover missing/invalid device proof, revoked/disabled installs, invalid bodies and rate-bucket isolation. Refused requests must not contact providers or increment billable counters.
- Exercise the supported full/incremental modes, including standard, MEDDPICC, questions, templates, docs, investigations, speaker names, catch-up, docs topics and template drafts. Assert the selected dispatch and response contract rather than exact model prose.
- Cover timeout, malformed provider responses, fallback preservation, request sequence/revision metadata, applied/stale/degraded outcomes and cost/usage recording. Meter docs lookups according to the actual success/no-result/error contract, including retries.
- Add missing direct catch-up coverage while preserving existing generation/parsing tests and pinned model routing contracts.

**Complete when:** changing a handler guard, dispatch, quota boundary or fallback metadata breaks a relevant route test; provider failures preserve valid previous state and never claim successful fresh generation.

## T07: shared contracts against real storage

**Files:** backend `lib/cloudStore.integration.test.ts`, `lib/cloudStore.ts`, `test/setup.ts`, CI and database test setup.

- Run the same behavioral contract against the memory and PostgreSQL implementations: revisions, conflicts, tombstones, external duplicates, search/pagination, tokens, email, web sessions and OAuth clients/grants/codes/refresh families.
- Add simultaneous writes, single-use link/code consumption, revocation and injected failure after a write. Exercise schema migration from representative prior database schemas in disposable instances.
- Use isolated Redis for TTL expiry, NX/admission locks, idempotency records, rate windows and failure recovery. Existing explicit token timestamp checks remain useful; the gap is backend storage semantics.
- Add an explicit CI integration job using disposable services or a dedicated test database. The required job fails if its database is unavailable instead of silently skipping. Keep optional live-provider tests outside ordinary PR gates.

**Complete when:** ordinary fast tests stay fast, the storage job actually executes, and its report names the real adapter, concurrency cases and cleanup result. No production database or shared account data is used.

## T08: permission and asynchronous state transitions

Use suspended transport work and assert both local models and outbound requests. The policy and production fixes stay in R1/R2/R3/R7/R8.

| Owner | Regression to add | Required observable result |
| --- | --- | --- |
| R1 | Private-mode changes during an active Deepgram session, pending start and local fallback | Actual engine/routing and displayed state follow the agreed transition contract; a preference change alone is not treated as an engine switch |
| R2 | Withdraw consent, then invoke History regeneration, template drafting, Watch import and other content-dispatch actions | No forbidden Deepgram/OpenAI request; expected refusal/deferred state; configured webhook/CRM exports still allowed |
| R3 | Start account A pull/upload, attach B, then complete A's request, error or retry | No A response changes B's store, cursor, entitlement or UI state; credentials and recovery behavior remain valid |
| R7 | Start generation, then trim transcript, change template or delete the meeting before completion | Stale response cannot overwrite newer content or resurrect a deleted meeting |
| R8 | Consume one web/email link concurrently and retry after a response loss | Exactly one permitted consumption under the defined replay contract, verified in real PostgreSQL |

**Complete when:** each case fails on the audited behavior where applicable and passes with its owning fix. Include both successful and failing late completions. Idle account reset and presentation-only consent tests remain supporting tests, not substitutes.

## T09: recording lifecycle through the transport boundary

**Files:** Deepgram/audio service seams, AppState recording actions, `MeetingHandoffTests`, transport and lifecycle tests.

Feed scripted audio packets and WebSocket events through the actual session coordinator. Test start pending then stop/cancel/double start, expired grant refresh, reconnect after a lost connection/response, bounded buffering, trailing final transcript flush and repeated stop. During handoff, late old-session audio/transcript/summary work must stay out of the new meeting. Check saved segments and usage, not only `isRecording`.

Add iOS interruption, background/foreground and audio-route-change cases where injection is possible. Keep physical microphone/system-audio, Bluetooth, permissions and OS behavior in a named hardware matrix, including supported minimum OS versions and current release versions. Pure watchdog and credential freshness tests remain useful.

**Complete when:** deterministic start-to-save cases run without live microphones/providers, token refresh reaches the new socket, final segments are saved once and stale sessions cannot alter the replacement meeting. Record remaining device-only results separately.

## T10: complete Watch import

**Files:** `WatchImportTests`, Watch inbox/worker and prerecorded service, backend prerecorded grant/end tests. Retry scheduling belongs to R4 and permission handling to R2.

Drive segment/manifest arrival through grant, upload/transcription, meeting save, insights eligibility, duration metering and receipt. Include duplicates and out-of-order segments, process restart, missing/corrupt audio, an empty transcript, response loss after save/metering, permission/private-mode refusal and user removal. Verify one meeting and one charge across retries.

Use a controlled clock for offline and out-of-minutes deferrals. Multiple activation/file-arrival/manual triggers must coalesce into one worker; a blocked first job must not starve eligible work. A resent manifest must not undo a terminal state. Preserve existing protocol, AAC stitching and inbox persistence tests. Keep real Watch Connectivity transfer and the simulator fallback as separate QA paths.

**Complete when:** the real worker completes a full fixture import once, deferred work does not spin, eligible jobs proceed, and Watch receipts reflect persisted outcomes.

## T11: meeting journeys, persistence and upgrades

**Files:** `MeetingJourneyTests`, `PersistentStoreTests`, persistence policy, SwiftData fixtures and a small process-recovery harness.

- Make “saves nothing” fetch and assert zero meetings after completion. Make “sorts first” exercise the actual history presentation ordering and assert IDs in order. Identify the intended final-insights request by endpoint/body instead of asserting any request happened.
- Rename in-memory fresh-AppState tests to describe their actual boundary. Add a disk close/reopen test for pinning and interrupted drafts; use a separate process termination/relaunch test for crash/checkpoint durability.
- Load representative stores created by released schemas, upgrade with the current model, and verify meeting/transcript fields, metadata, deletion state and export behavior. Preserve corrupt-file byte-for-byte and explicit failure tests.

**Complete when:** journey names match their assertions, store migrations preserve fixture data, and a controlled process interruption recovers only durable content within the documented checkpoint bound. Do not claim zero loss of unfinalized provider text.

## T12: real UI interaction and design checks

**Files:** a small XCUITest target, existing screenshot scenes/scripts, SwiftUI accessibility identifiers, backend browser tests for account pages, `design.md` contracts and U2/U1/B6a implementation.

- Add launch/Home, consent Allow/Not now/Cancel, record/stop/history, recovery/restore and Settings search/Configure journeys. Assert visible and hittable actions, navigation destination and resulting state. Use a dedicated test launch mode with isolated data and controlled services.
- Capture minimum supported Mac window size, ordinary desktop, compact iPhone and regular-width iPad, including long content and large accessibility text. Add a consent scene; ensure the smoke matrix includes iPad. Keep approved baselines for a small stable set of layouts and inspect failures.
- Assert consent actions remain outside the scroll body, content is reachable, modal cancel preserves state, settings jumps work on both platforms, tab hit areas fill their segments, and Coaching prose/metric units/axes do not clip. Cover keyboard focus/shortcuts, VoiceOver order/labels, contrast and Reduce Motion through automation where reliable and a recorded manual matrix otherwise.
- Add browser interaction for sign-in/account device removal, token/session revocation and connected-app actions, with compact widths and keyboard use. Preserve existing HTML escaping, secret-exclusion, CSRF and authorization tests.

**Complete when:** an obscured consent action, broken settings destination or representative compact layout fails an automated check; snapshots are reviewed rather than blindly regenerated. The existing launch smoke proves render readiness only. TextKit layout and semantic color tests remain valuable. This slice extends the earlier decision to rely on smoke/manual QA with a bounded UI target, not a screenshot of every view state.

## T13: biometric privacy and model quality

**Files:** `VoicePrintTests`, `VoicePrintIntegrationTests`, on-device transcription/diarization tests, existing transcription/diarization POCs and backend Jev evaluation corpus; a small insights evaluation corpus.

- Populate a recognizable voice vector and store metadata, then exercise cloud, webhook and Markdown exports. Check actual schemas and the absence of biometric sentinel data. Include normal transcript text containing “voice” so privacy assertions do not ban ordinary language. Keep matching/collector/storage tests.
- Version consented/public/synthetic audio and transcripts with expected words, speaker identity and grounded facts. Reuse existing corpora where appropriate. For ASR/diarization/voice prints, measure word error, speaker attribution and false matches, including unknown speakers. “Has words/two speakers/two confident matches” remains smoke coverage only.
- Evaluate summaries/actions for grounding, correct attribution, unsupported claims and missed commitments; include empty, adversarial and multilingual examples. Evaluate Jev decisions against labels. Use budgets/tolerances selected from measured baselines, not invented thresholds or exact prose snapshots.
- Record model/prompt/package versions and compare when they change. Provide an explicit periodic/on-demand evaluation command; scheduling is separate. Keep live model spend and nondeterminism out of ordinary fast PR tests.

**Complete when:** populated biometrics never enter outbound payloads, ordinary text exports normally, and each engine has a measured, versioned quality baseline with a regression threshold and a reproducible evaluation command.

## T14: shared wire fixtures and cross-language compatibility

**Files:** `MeetingSyncDocumentTests`, Swift `ClientAuthTests`, backend sync-document/auth fixtures and CI.

Choose one versioned canonical fixture source with a reproducible import/check into the other repo. Enforce equivalence in CI without assuming a sibling checkout exists. Round-trip actual Swift-produced documents through backend validation/storage/response and back through Swift decoding. Exercise unknown fields, nulls, date/numeric coercion, schema versions and old supported clients. Verify Swift-produced request-proof vectors in the backend and reject altered bytes.

**Complete when:** an incompatible wire/auth change or divergent fixture fails a cross-repository contract check; harmless normalization is explicit. Keep independent golden-vector assertions on both sides.

## T15: sustained sessions and large histories

Extend [P0.7](roadmap.md#p07-finish-the-60-minute-instruments-validation) with repeatable 30–60+ minute scripted sessions, both audio sources, reconnects and large histories. Measure memory progression, audio/backpressure queue bounds, transcript handling and save latency, UI responsiveness and History scroll/search. Include cancellation and teardown so retained tasks/models are visible.

Use privacy-safe signposts and representative release/device profiling. Establish tolerances from baseline measurements before gating them; avoid machine-sensitive timing assertions in fast unit tests. Keep current bounded-transcript and chart-size tests.

**Complete when:** a repeatable report identifies hardware/build/data size, resource trends and accepted limits, and a dedicated performance lane detects sustained growth or an agreed budget breach. Physical audio QA remains explicit.

## T16: remaining integration boundaries

**CRM:** preserve Attio/Twenty selection, deadline, assignment and stale-insight payload tests. Add Attio OAuth start/callback/status/search route coverage and partial-send cases where the note succeeds but a task fails. Retry must follow an explicit duplicate-prevention/reconciliation contract for already-created objects. Check actual delivered payloads and current meeting state through the outbox boundary.

**Diagnostics:** add `/api/client-events` ingestion tests for authentication, accepted event schemas, bounded payload sizes, redaction and malformed input. Read back representative events through admin filters; an empty-list authorization test does not establish ingestion or sanitization. Keep ops alert/digest fixtures and verify the relevant event integration without sending real notifications.

**Complete when:** partial CRM failures cannot silently duplicate completed work on retry, and diagnostics ingestion rejects or sanitizes unsupported/sensitive content according to its documented schema while retaining useful operational facts.

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

Update [testing.md](testing.md), screenshot documentation and the backend runbook with actual test boundaries, current dated execution results, skip reasons and commands. Historical measurements stay labelled. Replace stale claims such as a test count presented as current or “view wiring covered” when only launch readiness was checked.

**Complete when:** removed assertions have a documented reason/replacement, names describe what executes, and test reports distinguish unit, handler, real-store, UI, hardware and provider evidence.

## Validation and completion record

For each slice, update its status row with the implementation commit, command, platform/adapter, passed/failed/skipped counts and remaining manual boundary. Record the targeted broken behavior that the regression detects. Apply mutation checks narrowly: the cap and revoked filters from the audit are useful seeds; do not create a global mutation-score target.

Backend code changes require tests, lint, test/production type checks and the production build, plus the affected real-store contract. Shared Swift changes require both test targets; platform-specific UI/audio changes require the named simulator/device scenarios. Documentation-only changes need link and diff validation, not application builds.

The programme is complete when T01–T17 have their stated evidence, the known failure reproductions pass with their owning production fixes, required storage/UI jobs actually run, and residual hardware/provider coverage is explicitly recorded. Passing existing suites or adding tests without testing their assertions is insufficient. Keep this plan, the roadmap, both agent entry points and focused testing docs in sync; do not rewrite old changelog entries for test-only work.
