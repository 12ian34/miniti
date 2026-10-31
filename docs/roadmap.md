# Roadmap

The single priority index for miniti Apple apps and shared `miniti-api` work. Reconciled after the macOS 3.5.0 release on 2026-10-30; iOS 3.5.0 is submitted, not confirmed live. Each linked plan owns its bounded scope, decisions and completion evidence; this file owns ordering. Linux keeps its own release line and implementation tracker, with explicit shared-contract handoffs.

## Baseline

3.4.0 delivered enrollment/key repair, truthful restore/email errors, Account/email UX, Sending/consent, credential concurrency fixes, R1 private-mode locking, narrowed R2 History/Watch consent, R3 cloud response fences and failed-microphone recovery. Core account ownership has **not** migrated. [Release evidence](releases/3.4.0.md) records Mac build 141 live, iOS upload evidence, actual device checks and the macOS 26 waiver; upload is not independently verified App Store availability.

Current behavior and gotchas: [accounts](reference/accounts.md), [cloud](reference/cloud-sync.md), [audio](reference/audio.md), [Settings](reference/settings.md), [Watch](reference/watch.md), [patterns](reference/patterns.md). Existing alerts and support access: [operations](runbooks/operations.md). Do not use archived plans as current policy.

## Delivered: 3.5.0 build 142

macOS is live, including Sparkle verification from 3.4.0. The backend and purchase-return website are deployed. iOS build 142 was submitted at 12:28 UTC on 2026-10-30 with automatic release after approval; availability remains unverified. The following scope is delivered on Mac and awaiting Apple approval on iOS, not a new implementation backlog.

- [Logging and monitoring O1–O6](plans/logging-and-monitoring.md): incident alerts, durable diagnostics, useful local timelines, Help reports and Home feedback with shared submission limits.
- [Selective cloud privacy C1](plans/selective-cloud-privacy.md): live/saved Cloud–Local controls, title rules and honest availability/removal states.
- [Purchase return B6d](plans/purchase-return.md): Mac checkout return and server-confirmed Pro.
- Included UX cleanup: Sending into Privacy, Models under Setup, Help/support details, About acknowledgements, accurate CAM++ status, two-row API mode choices and shared Home control typography. Contracts live in [Settings](reference/settings.md); evidence is in the [QA handoff](releases/monitoring-cloud-purchase-qa.md).

Delivery evidence and Ian's reported device QA live in [3.5.0](releases/3.5.0.md); the [QA handoff](releases/monitoring-cloud-purchase-qa.md) retains detailed checks without converting unitemised user confirmation into independently observed passes. Outstanding release administration: confirm iOS availability, then bump only `IOS_LATEST_VERSION` and close the iOS record. UptimeRobot setup/mail QA is user-reported in the release record; health HTTP 200 alone is not independent confirmation. Alert links were fixed and deployed separately in backend `2458ddb`.

## Selected release: 3.6.0, sync, delivery and alert clarity

Ian assigned this scope to **3.6.0** on 2026-10-30. Both plans are implemented locally. The 2026-10-31 review fixes supersede build 143 and are undergoing fresh validation and packaging as build 144; physical-device QA and authorized rollout remain. Nothing from 3.6.0 has been published or deployed. The [3.6.0 checklist](releases/3.6.0.md) owns combined tests, device QA and deployment evidence.

- [Automatic sync and completed webhook delivery](plans/sync-and-delivery-reliability.md): Charlie on 3.4.0 reports needing Sync now, a recent sync timestamp with an unchanged count, and webhooks arriving before AI/cloud work. Code confirms stale count refresh and early `meeting.saved` delivery; the stopped-meeting eligibility exclusion is also established in code; Charlie’s exact sequence still needs reproduction. Owns S1–S3 and R5–R7: immutable in-flight delivery, resend from current saved data, and rejection of stale History AI results. These share one persistence/revision contract and must not be duplicated in another plan.
- [Incident alert clarity](plans/incident-alert-clarity.md): distinguish historical evidence, current failures and unconfirmed recovery; correct event-count language and legacy capability assumptions. The already-deployed login-link fix is baseline, not unfinished work.
- Reproduce the repeated iPhone transcript-starvation/reconnect traces before selecting a recording-engine change. No evidence yet establishes silence versus lost speech or a 3.5.0 regression.

These bounded fixes precede account access work because they affect trust in saved meetings, exports and operational alerts. Do not wait for the ownership migration or force webhooks to depend on optional cloud sync.

Scope confirmed after review: keep all S1–S3/R5–R7 in 3.6.0. The webhook carries the saved transcript and available summary without requiring cloud lookup. Use the existing outbox plus a small completion marker, preserve AI request timeouts without a new global deadline, and keep alert clarity independently deployable.

## Recommended delivery order

3.6.0 is assigned to the two complete plans at order 1. Later versions remain unassigned; multiple complete plans may share a version. Ordering is not permission to deploy. A production incident can change priority explicitly.

| Order | Plan | Why here / dependency | State |
|---|---|---|---|
| 1 | [Sync and delivery](plans/sync-and-delivery-reliability.md), [alert clarity](plans/incident-alert-clarity.md) | Resolve the reported automatic-sync/count and webhook-readiness paths; make deployed alerts actionable. Includes R5–R7 so stale AI cannot contaminate the corrected delivery path. | Review fixes implemented for build 144; fresh validation, device QA and rollout remain |
| 1, enabling work | [Test foundation](plans/test-foundation.md) | Reliable runners, real storage and shared contracts before money/ownership migrations. Use the existing runner/storage evidence; implement only prerequisites needed by the selected fixes before broader migration work. | Scoped, not built |
| 2 | [Account access and recovery](plans/account-access.md) | Finish A2f → A3/A3a → A4/B6b and B6c labels, preserving existing users before changing what accounts own. Backend first; explicit sign-out choice decision and macOS 26 evidence required. | Planned, decisions/QA gates open |
| 3 | [Watch retry and single-use link reliability](plans/reliability.md) | Close R4 and R8 with bounded tests. R5–R7 belong to 3.6.0; R8 requires real Postgres concurrency. Do this before broader migrations complicate reproduction. | Planned |
| 4 | [Account ownership](plans/account-ownership.md) | B0–B3 make device changes stop moving/removing Pro and consumed usage. Requires access protection, real-storage tests, policy decisions and rehearsed migration/correction tools. | Planned, not implementation-ready until decisions settle |
| 5 | [Meeting ownership across accounts](plans/meeting-ownership.md) | B4 adds provenance and deliberate copies after lifecycle is stable. Client compatibility must precede server refusal enforcement. | Planned |
| 6 | [Integration ownership](plans/integration-ownership.md) | B5 adopts existing connections without silently routing a device to another person’s CRM/calendar. Depends on stable canonical identity/lifecycle. | Planned |
| 7 | [Registration and device registry](plans/backend-registration-and-registry.md) | Finish atomic admission and bounded admin reads using the established canonical writer. Bring admission forward only with an explicit writer/dependency redesign if abuse makes it urgent. | Scoped, design reconciliation required |
| 8 | [Durable checkpoints](plans/durable-checkpoints.md) | Reduce finalized transcript loss after a hard exit, with measured write cost and disk-backed recovery tests. | Scoped |
| 9 | [History and long-session performance](plans/history-and-session-performance.md) | Establish sustained resource budgets and optimize measured large-history/Coaching costs without changing results. Can supply baseline measurements for order 8. | Scoped |
| 10 | [Usage costs and prompt caching](plans/usage-cost-and-cache.md) | Replace historical economics with actual cohort/cost/cache evidence. Collect measurements earlier; pricing changes are excluded. | Scoped |
| 11 | [Backend runtime](plans/backend-runtime.md), then [Redis client](plans/redis-client.md) | Separate maintenance deliveries after behavior/data migrations stabilize. Revalidate upstream need first; never bundle them with auth or billing changes. | Scoped, revalidation required |

### Independent customer improvements

Delivered in macOS 3.5.0: selective cloud privacy, purchase return and O1–O6. Backend/site are deployed; iOS is submitted (purchase return is Mac-only). See the [shared QA handoff](releases/monitoring-cloud-purchase-qa.md).

These implementation records retain their contracts and QA history; they are not active future work. Remaining evidence and iOS availability belong to the release record.

| Plan | User outcome | Boundary |
|---|---|---|
| [Selective cloud privacy](plans/selective-cloud-privacy.md) | Choose Cloud/Local in live or saved meetings; title rules keep matching recordings off miniti cloud. | C1, distinct from private mode, recording filters and B4 provenance. |
| [Return after purchase](plans/purchase-return.md) | Polar checkout returns to Account through Open miniti and server-confirmed Pro. | B6d, no automatic account switch or entitlement granted by a URL; iOS remains StoreKit. |

### Planned later: bot-free video recording

Selected product direction by Ian, 2026-10-29; not part of the delivered 3.5.0 scope or selected next reliability release and not implemented. Mac first: optional capture of a selected meeting window plus audio, local storage, History playback linked to transcript timestamps, and MP4 export. Recording must continue when another app is foreground or covers the meeting window. Minimising the meeting window is an accepted limitation: video may pause, audio/transcription should continue, and the state must be clear. Browser meetings should use a dedicated window; switching tabs changes the captured content.

Before implementation, write a bounded plan and prove background capture with Zoom, Teams and Google Meet, including audio/video/transcript timing, pause/resume, interruptions, recoverable files, disk limits and permissions. ScreenCaptureKit supports covered-window capture; compatibility on supported macOS versions remains unverified. Hosted video/sharing and iOS/Linux video are outside the first Mac scope. Public summary: `../minitidotapp/roadmap/index.html` and `llms-full.txt`. [Apple capture behaviour](https://developer.apple.com/videos/play/wwdc2022/10155/).

## Release-sized plan rules

- A plan is a complete deliverable with scope/exclusions, decisions, prerequisites, tests, rollout/recovery and completion evidence. It may contain ordered backend deployments and observation gates.
- If a plan is too large, split it into supported independently shippable states **before implementation**. Do not silently deliver half and leave a permanently active umbrella.
- Once implementation starts, independent discoveries become new backlog items. A release blocker requires an explicit scope amendment and regression, not an unbounded review queue.
- Tests belong to the feature they protect. The test-foundation plan does not defer billing/permission tests until a later “test release”.
- Built, tested, deployed, uploaded, available and device-verified are different states. Track platform evidence separately; never tick historical QA by inference. [Validation register](runbooks/validation.md).
- A backend push to main deploys production. Follow its runbook and [RELEASE.md](../RELEASE.md); no doc status update authorizes a push or mail to a customer.
- Close delivered plans and move their durable contracts into reference docs. Archive the implementation record; keep only a short shipped baseline here.

## Candidates, not active release commitments

Keep these visible without pretending the old sketches are ready to build. Selecting one requires a fresh bounded plan and success criterion.

| Area | Remaining idea / constraint | Evidence |
|---|---|---|
| Audio accuracy | Fixture-backed short-interjection improvement; evaluate UtteranceEnd only as a measured fallback. Filler sidecar is a separate unselected experiment. | [Audio](reference/audio.md), [lifecycle](reference/recording-lifecycle.md) |
| Local models | Local insights; iOS transcription hardware/thermal feasibility; model pinning/distribution before default-on; voice-print quality/privacy T13. | [Local models](reference/local-models.md), [local AI research](research/local-ai-research.md), [transcription research](research/local-transcription-research.md) |
| Jev | Calibration before default-on; other classifier uses only after a task-specific evaluation. Existing naming/nudge shipped. | [Integration history](archive/jev-system-one-plan.md), local/gitignored evaluation `docs/research/jev-eval-report-2026-09-21.md` |
| Cloud | APNs, web History, write scopes, server-side Coaching, passkeys and storage-policy refinement. None is needed to call existing sync shipped. | [Cloud reference](reference/cloud-sync.md) |
| CRM | Opportunity-field mappings and deeper workflow automation. Tasks/previews and automatic notes already exist. Twenty self-hosting is demand-led. | [Feature reference](reference/features.md) |
| Product | Useful entity-to-CRM actions, App Store localization/submission automation, optional template sync/versioning. No decorative entity highlighting or unbounded prompt editor. | [Historical roadmap](archive/roadmap-through-3.4.0.md) |
| Auth enforcement | Verify deployed per-platform enforcement, supported legacy clients and remaining broad-key use. Only then scope retirement; preserve inactive users’ direct migration and secret-rotation overlap. Do not infer observe/require from old defaults. | [Accounts](reference/accounts.md), [validation](runbooks/validation.md) |
| Further testing | T11/T12 recovery/UI/accessibility, T13 model quality and remaining T16 CRM partial failures, after their owning feature scope is chosen. Wider R2 AI-entry-point audit remains explicitly deferred. | [Test disposition](archive/README.md#test-audit-disposition) |
| Structural simplification | Revalidate each selected finding against current code. Audit recommendations are not approved work. | [August audit](research/structural-simplification-audit-2026-08-16.md) |
| Android | Re-plan auth, versions, platform behavior and current policies before any implementation. Never ship the old shared-secret design. | [Historical Android proposal](research/android-original-plan.md) |
| Linux | Existing shipped client, not a new spike. Reconcile Granola, cloud, calendar, auth/UX and other parity against its own tracker before claiming gaps closed. | [Linux AGENTS](../../miniti-linux/AGENTS.md), [Linux PLAN](../../miniti-linux/PLAN.md) |
| Windows | Demand and architecture/capture/distribution spike before selecting a product implementation. | [Historical platform discussion](archive/roadmap-through-3.4.0.md#p34-windows) |

## Documentation ownership

| Location | Purpose |
|---|---|
| [AGENTS.md](../AGENTS.md) | Agent entry point and essential conventions |
| `docs/roadmap.md` | This sole priority index |
| `docs/plans/` | Bounded future deliverables and their completion contracts |
| `docs/reference/` | Shipped behavior, architecture and durable gotchas |
| `docs/runbooks/` | Operating/support/validation procedures; release commands remain in root RELEASE and Fastlane |
| `docs/releases/` | Version/build/platform QA and deployment evidence |
| `docs/research/` | Dated evaluations and unselected proposals |
| [Archive disposition register](archive/README.md) | Every old plan’s replacement, remaining work and evidence status; not a second roadmap |

Backend wire/storage truth remains in [miniti-api docs](../../miniti-api/docs/agents/README.md). Public user docs/changelog remain separate. The cleanup preserves historical evidence but removes it from the path an agent follows to decide what to build next.
