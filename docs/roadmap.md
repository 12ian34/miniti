# Roadmap

The single priority index for miniti Apple apps and shared `miniti-api` work. Reconciled after the macOS 3.5.0 release on 2026-10-30; public roadmap ordering reconciled on 2026-10-31. macOS 3.6.0 released on 2026-10-31; iOS 3.6.0 became available on 2026-11-01. Each linked plan owns its bounded scope, decisions and completion evidence; this file owns ordering. Linux keeps its own release line and implementation tracker, with explicit shared-contract handoffs.

## Baseline

3.4.0 delivered enrollment/key repair, truthful restore/email errors, Account/email UX, Sending/consent, credential concurrency fixes, R1 private-mode locking, narrowed R2 History/Watch consent, R3 cloud response fences and failed-microphone recovery. Core account ownership has **not** migrated. [Release evidence](releases/3.4.0.md) records Mac build 141 live, iOS upload evidence, actual device checks and the macOS 26 waiver; upload is not independently verified App Store availability.

Current behavior and gotchas: [accounts](reference/accounts.md), [cloud](reference/cloud-sync.md), [audio](reference/audio.md), [Settings](reference/settings.md), [Watch](reference/watch.md), [patterns](reference/patterns.md). Existing alerts and support access: [operations](runbooks/operations.md). Do not use archived plans as current policy.

## Delivered: 3.5.0 build 142

macOS is live, including Sparkle verification from 3.4.0. The backend and purchase-return website are deployed. iOS 3.5.0 build 142 was independently confirmed READY_FOR_SALE on 2026-10-31. The following scope is delivered on both platforms, not a new implementation backlog.

- [Logging and monitoring O1–O6](plans/logging-and-monitoring.md): incident alerts, durable diagnostics, useful local timelines, Help reports and Home feedback with shared submission limits.
- [Selective cloud privacy C1](plans/selective-cloud-privacy.md): live/saved Cloud–Local controls, title rules and honest availability/removal states.
- [Purchase return B6d](plans/purchase-return.md): Mac checkout return and server-confirmed Pro.
- Included UX cleanup: Sending into Privacy, Models under Setup, Help/support details, About acknowledgements, accurate CAM++ status, two-row API mode choices and shared Home control typography. Contracts live in [Settings](reference/settings.md); evidence is in the [QA handoff](releases/monitoring-cloud-purchase-qa.md).

Delivery evidence and Ian's reported device QA live in [3.5.0](releases/3.5.0.md); the [QA handoff](releases/monitoring-cloud-purchase-qa.md) retains detailed checks without converting unitemised user confirmation into independently observed passes. iOS availability is confirmed and `IOS_LATEST_VERSION` is 3.5.0; the 3.5.0 iOS record is closed. UptimeRobot setup/mail QA is user-reported in the release record; health HTTP 200 alone is not independent confirmation. Alert links were fixed and deployed separately in backend `2458ddb`.

## Delivered: 3.6.0, sync, delivery, alert clarity and managed AI

macOS **3.6.0 build 146** is released on 2026-10-31. The verified Retina DMG, Sparkle appcast, website and public docs are live. iOS build 146 became available on 2026-11-01 at 00:27:33 UTC, confirmed through Apple’s public UK App Store lookup. Backend alert clarity and the two Luna opt-ins are deployed, with both Luna groups enabled on 2026-11-01. Both remote Apple suites and backend CI passed. Ian explicitly waived the physical iPhone Settings gesture and clean cloud retest; previous webhook/resend waivers remain waivers, not passes. The [3.6.0 release record](releases/3.6.0.md) owns exact deployment, submission, checks and limitations. Test-foundation work and unrelated concurrent planning remain separate.

- [Automatic sync and completed webhook delivery](plans/sync-and-delivery-reliability.md): Charlie on 3.4.0 reports needing Sync now, a recent sync timestamp with an unchanged count, and webhooks arriving before AI/cloud work. Code confirms stale count refresh and early `meeting.saved` delivery; the stopped-meeting eligibility exclusion is also established in code; Charlie’s exact sequence still needs reproduction. Owns S1–S3 and R5–R7: immutable in-flight delivery, resend from current saved data, and rejection of stale History AI results. These share one persistence/revision contract and must not be duplicated in another plan.
- [Incident alert clarity](plans/incident-alert-clarity.md): distinguish historical evidence, current failures and unconfirmed recovery; correct event-count language and legacy capability assumptions. The already-deployed login-link fix is baseline, not unfinished work.
- [Managed Luna](plans/lightweight-luna.md): selected 2026-10-31. Four lightweight tasks plus full/incremental standard summaries, with separate default-off opt-ins and rollback. Other quality modes and BYOK stay unchanged; the legacy incremental fallback takes precedence. Implementation and validation are recorded in the release checklist; both opt-ins are active from 2026-11-01. The Retina dark green DMG is published with Mac 3.6.0.
- Reproduce the repeated iPhone transcript-starvation/reconnect traces before selecting a recording-engine change. No evidence yet establishes silence versus lost speech or a 3.5.0 regression.

These bounded fixes precede account access work because they affect trust in saved meetings, exports and operational alerts. Do not wait for the ownership migration or force webhooks to depend on optional cloud sync.

Scope confirmed after review: keep all S1–S3/R5–R7 in 3.6.0. The webhook carries the saved transcript and available summary without requiring cloud lookup. Use the existing outbox plus a small completion marker, preserve AI request timeouts without a new global deadline, and keep alert clarity independently deployable.

<a id="next-release-on-device-transcription-usage-tracking"></a>

## Selected next release: 3.7.0

Selected implementation and automated validation are complete locally on 2026-11-03. [Combined evidence](releases/3.7.0.md#combined-local-validation-2026-11-03) records full macOS/iPhone 16 suites, backend/storage/wire/Linux checks and real-model fixtures, separately from remaining physical/provider/disclosure and release checks. Nothing is released by this status update.

The [3.7.0 implementation/release checklist](releases/3.7.0.md) owns cross-plan execution stages, integration tests and outstanding evidence. Plans own their implementation contracts; this roadmap remains the priority index. Reviewed together on 2026-11-03: all managed recording duration (including local/private) is accounted independently of Share diagnostics; BYOK reporting stays off; Your voice remains opt-in.

Ian assigned version 3.7.0 on 2026-11-02. The selected package includes the previously queued test foundation, the recording and reporting work accepted on 2026-11-02, and the GPT-5 mini retirement migration, operator-email improvements and Mac local-speaker failure handling/device diagnostics added on 2026-11-03. Ian subsequently kept local separation off by default for 3.7.0 and deferred default-on until M1 testing. This is planning scope, not implementation or release evidence; app build numbers, backend latest-version metadata and downloads remain on the released versions.

| Workstream | Scope for 3.7.0 | Owner |
|---|---|---|
| Test foundation, selected before this chat | Isolated settings/credentials/test data; reliable failure reporting and controlled async fixtures; real Redis/Postgres contract tests; insights endpoint coverage; shared Apple/backend wire fixtures; documentation/release consistency checks and justified brittle-test cleanup. T01/T06/T07/T14 and applicable T17, not the entire T01–T17 backlog. | [Test foundation](plans/test-foundation.md) |
| Recording and transcript reliability | Bounded final flush even when text is initially empty; reproduce and correct reconnect coordination; distinguish connection recovery from resumed words; preserve ordinary silence and test interruption/stop boundaries. | [Recording follow-up](plans/recording-reliability-followup.md) |
| Truthful diagnostics and status | Correct iOS microphone-only readiness; meaningful recording/transcription outcomes; actual-engine and attempt context; preserve allowed gap/recovery evidence through backend sanitization. | [Recording follow-up](plans/recording-reliability-followup.md) |
| Client AI failure investigation | Explain live/final failures separately from backend HTTP success; retain bounded failure-stage/request context and test transport, decoding, cancellation and result-application boundaries. Preserve saved-AI and webhook authority. | [Recording follow-up](plans/recording-reliability-followup.md#7-backend-completion-does-not-explain-client-ai-failure) |
| Local transcription usage | Count all managed local/private recording duration independently of Share diagnostics; BYOK reporting stays off. Durable retries and total/Deepgram/local reporting preserve allowances/cost inputs and disclose coverage. | [Usage tracking](plans/on-device-usage-tracking.md) |
| Accurate activity reporting | Case-insensitive active-device counts and consistent chart/filter/digest joins; preserve numeric usage and billing records. This is not the full account/device migration. | [Recording follow-up](plans/recording-reliability-followup.md) |
| GPT-5 mini retirement | Before 2026-12-11, use Luna none for summaries/lightweight tasks and GPT-5.4 mini low for other AI tasks and fallbacks across managed/BYOK; update hourly probes/model descriptions and preserve historical accounting. Linux ships on its own version line. | [Model retirement](plans/gpt-5-mini-retirement.md) |
| Clear operator alerts | Preserve provider rejection details; explain observed failure, possible impact, healthy checks and next action in readable alert/recovery emails. Keep existing cadence and notification rules. Backend-only. | [Operator emails](plans/operator-alert-emails.md) |
| Mac local speaker reliability and device diagnostics | Fix failure handling, pre-start provider separation and truthful degraded status; retain bounded opt-out-aware hardware/engine diagnostics. No reconnect solely for mid-session speaker restoration in 3.7.0. Preserve existing choices, off default, iOS defaults and voice flags. Default-on still awaits M1 testing. | [Local speaker reliability](plans/local-speakers-default.md) |

Other existing work remains queued after this package, without a release version: account access/recovery and device labels (with recovery/UI coverage), then Watch retry scheduling and atomic single-use sign-in/confirmation links, then account/meeting/integration ownership. Video remains planned later. These are not silently added to 3.7.0 by naming this release. Luna is already enabled; the retirement migration does not expand normal managed Luna routing. Audio buffering/replay remains excluded.

Evidence reconciliation (2026-11-03): the recording plan now records a second no-transcript attempt on the same iPhone, six further stall/restart episodes, continued incorrect iOS outcomes and five client AI warnings despite successful retrieved backend requests. Ian requested coverage of missing issues: bounded client AI failure investigation is explicitly included above, and the operator-email plan includes probe-validity investigation alongside error retention. These are unresolved observations and planned acceptance criteria, not implemented fixes. Internal evidence does not change the public product-roadmap order or add a public feature promise.

Selected by Ian on 2026-11-02 for 3.7.0: [on-device usage tracking](plans/on-device-usage-tracking.md) adds local recording minutes to backend reporting and separates total, Deepgram and on-device minutes in the admin dashboard. Preserve managed allowance and Deepgram cost accounting. This needs both an app update and an additive backend change; historical local minutes are not recoverable from existing usage counters.

The selected test foundation remains first. This bounded reporting change follows it in the next release scope, before account-access work. It is internal usage accounting, so it does not add a public roadmap feature or change the public product sequence.

Additional scope selected by Ian on 2026-11-02: [recording reliability and diagnostic follow-up](plans/recording-reliability-followup.md) covers bounded final flushing of initially empty transcripts, reproduction-led reconnect coordination, truthful recovery status, correct iOS source checks, diagnostic context and case-insensitive activity reporting. The plan records performance/cost expectations and validation gates; audio buffering/replay is excluded from the first delivery. The iPhone root cause remains unproven. This work shares the next release with local-minute tracking, after test foundation; Luna routing and allowances remain unchanged.

### Next release after 3.7.0

Ian confirmed on 2026-11-03 that automatic mid-session speaker restoration moves to the release immediately following 3.7.0, with its version number unassigned. The [bounded follow-up](plans/local-speakers-default.md#mid-session-restoration-next-release-after-370) owns safe provider-diarization transition, identity preservation, bounded failure handling and physical validation. 3.7.0 retains honest degraded separation, pre-start fallback and protection of manual identities/voice learning. This follow-up does not select default-on, cloud fallback for local-only recordings or audio replay.

The full bounded foundation, model retirement, durable usage, hardware diagnostics and complete operator-email work remain in 3.7.0. Internal sequencing does not move any of them to a separate maintenance release. The customer-facing product sequence is unchanged.

## Recommended delivery order

The [GPT-5 mini retirement migration](plans/gpt-5-mini-retirement.md), selected on 2026-11-03, shares order 1b after test foundation and must reach users before 2026-12-11. Reserve distribution/App Review time and track Linux delivery separately. Ian approved Luna none for summaries/lightweight tasks and GPT-5.4 mini low for the rest and fallbacks; implementation and validation remain open.

3.6.0 delivered order 1. Version 3.7.0 contains orders 1a and 1b; later versions remain unassigned. Multiple complete plans may share a version. Ordering is not permission to deploy. A production incident can change priority explicitly.

| Order | Plan | Why here / dependency | State |
|---|---|---|---|
| 1 | [Sync and delivery](plans/sync-and-delivery-reliability.md), [alert clarity](plans/incident-alert-clarity.md), [managed Luna](plans/lightweight-luna.md) | Resolve the reported automatic-sync/count and webhook-readiness paths; make deployed alerts actionable. Includes R5–R7 so stale AI cannot contaminate the corrected delivery path. | Mac and iOS build 146 released; backend deployed with both Luna groups enabled. Explicit waivers and remaining evidence are in the release record |
| 1a, 3.7.0 first | [Test foundation](plans/test-foundation.md) | Complete T01/T06/T07/T14 and applicable T17 cleanup: isolated runners, insights-route coverage, real storage and shared contracts. The full bounded foundation precedes account-access and ownership work. | Selected follow-up 2026-10-31; assigned 3.7.0 on 2026-11-02, foundation locally validated, remote CI/release pending |
| 1b, 3.7.0 | [On-device usage tracking](plans/on-device-usage-tracking.md) | Count local recording minutes separately from managed Deepgram usage, expose the split in admin reporting, and preserve quota/cost semantics. Follow test isolation; additive backend before the reporting client. | Local backend/Apple/admin implementation validated; release/device/deletion checks pending |
| 1b, 3.7.0 | [Recording reliability and diagnostics](plans/recording-reliability-followup.md) | Protect pending transcript output, validate reconnect coordination and distinguish capture/connection/transcript recovery. Correct source/engine evidence and activity counts; share validated engine identity with usage tracking. | Initial drain/reconnect/source fixes local; remaining outcomes/activity work and physical reproduction pending |
| 1b, 3.7.0 | [GPT-5 mini retirement](plans/gpt-5-mini-retirement.md) | Remove retiring BYOK, backend fallback and monitoring dependencies before 2026-12-11; use foundation coverage and coordinate Linux's independent release. | Selected 2026-11-03 for 3.7.0; Luna/GPT-5.4 mini split implemented and locally validated; rollout pending |
| 1b, 3.7.0 | [Operator alert emails](plans/operator-alert-emails.md) | Retain missing error evidence and make existing operational alerts actionable without claiming unverified customer outages. Share central model routing with the retirement work. | Implemented and locally validated, not deployed; backend-only |
| 1b, 3.7.0 | [Mac local speaker reliability](plans/local-speakers-default.md) | Correct failure handling; coordinate recovery and device diagnostics with the reliability plan. Keep default off and preserve existing choices and iOS/voice settings. | Failure handling and hardware snapshots implemented locally; physical checks pending. Default-on deferred until M1 testing, no later version assigned |
| 1c, release after 3.7.0 | [Mid-session speaker restoration](plans/local-speakers-default.md#mid-session-restoration-next-release-after-370) | Build on 3.7.0's single recovery owner and degraded-state handling to restore provider separation safely after local failure. | Selected 2026-11-03 for the following release; version unassigned; separate from default-on/M1 decision |
| 2 | [Account access and recovery](plans/account-access.md) | Finish A2f → A3/A3a → A4/B6b and B6c labels, preserving existing users before changing what accounts own. Backend first; explicit sign-out choice decision and macOS 26 evidence required. | Planned, decisions/QA gates open |
| 2, regression work | [Recovery and UI coverage](#test-audit-follow-through) | T11/T12 truthful journey assertions and a bounded UI/accessibility harness alongside access/recovery, after test isolation. Protect consent, Settings, restore and record/stop/history before ownership changes. | Planned 2026-10-31; write bounded implementation scope before starting; version unassigned |
| 3 | [Watch retry and single-use link reliability](plans/reliability.md) | Close R4 and R8 with bounded tests. R5–R7 belong to 3.6.0; R8 requires real Postgres concurrency. Do this before broader migrations complicate reproduction. | Planned |
| 4 | [Account ownership](plans/account-ownership.md) | B0–B3 make device changes stop moving/removing Pro and consumed usage. Requires access protection, real-storage tests, policy decisions and rehearsed migration/correction tools. | Planned, not implementation-ready until decisions settle |
| 5 | [Meeting ownership across accounts](plans/meeting-ownership.md) | B4 adds provenance and deliberate copies after lifecycle is stable. Client compatibility must precede server refusal enforcement. | Planned |
| 6 | [Integration ownership](plans/integration-ownership.md) | B5 adopts existing connections without silently routing a device to another person’s CRM/calendar. Depends on stable canonical identity/lifecycle. Include remaining T16 OAuth and partial-send/retry regressions before changing connection ownership. | Planned |
| 7 | [Registration and device registry](plans/backend-registration-and-registry.md) | Finish atomic admission and bounded admin reads using the established canonical writer. Bring admission forward only with an explicit writer/dependency redesign if abuse makes it urgent. | Scoped, design reconciliation required |
| 8 | [Durable checkpoints](plans/durable-checkpoints.md) | Reduce finalized transcript loss after a hard exit, with measured write cost, disk-backed recovery and remaining T11 released-store migration/process-interruption tests. | Scoped |
| 9 | [History and long-session performance](plans/history-and-session-performance.md) | Establish sustained resource budgets and optimize measured large-history/Coaching costs without changing results. Can supply baseline measurements for order 8. | Scoped |
| 9a | [Model quality and biometric privacy coverage](#test-audit-follow-through) | T13 versioned ASR, diarization, voice-print and insights evaluations plus populated-biometric export checks. Reuse existing corpora and measured baselines; required checks for an earlier model change stay with that change. | Planned 2026-10-31; write bounded implementation scope before starting; version unassigned |
| 10 | [Usage costs and prompt caching](plans/usage-cost-and-cache.md) | Replace historical economics with actual cohort/cost/cache evidence. Collect measurements earlier; pricing changes are excluded. | Scoped |
| 11 | [Backend runtime](plans/backend-runtime.md), then [Redis client](plans/redis-client.md) | Separate maintenance deliveries after behavior/data migrations stabilize. Revalidate upstream need first; never bundle them with auth or billing changes. | Scoped, revalidation required |

### Test audit follow-through

Added to the delivery order at Ian's request on 2026-10-31. The full T01–T17 review remains tracked work. The bounded test foundation is assigned to 3.7.0 on 2026-11-02; other feature regressions retain the positions below and no version assignment. This does not expand the delivered 3.6.0 release. The [original audit](archive/test-quality-and-coverage-plan.md) retains evidence and detailed acceptance criteria; the [disposition register](archive/README.md#test-audit-disposition) maps it to current owners.

| Audit work | Delivery position and owner | Completion evidence |
|---|---|---|
| T01/T06/T07/T14 and applicable T17 | Order 1a, [test foundation](plans/test-foundation.md) | Failing tests fail the runner; isolated settings/credentials; real insights-handler, Redis/Postgres and cross-client contract checks execute; brittle checks removed only with appropriate replacement evidence. |
| T03 and R7 part of T08 | Order 1, [3.6.0 sync/delivery](plans/sync-and-delivery-reliability.md) | Preserve the released Mac and submitted iOS real-sender, in-flight update, current-data resend and stale-History regressions; release evidence remains separate. |
| T11 truthful journey assertions and T12 UI/accessibility | Order 2, alongside [account access](plans/account-access.md) | A bounded Mac/iOS UI harness covers consent visibility/cancellation, Settings navigation, recovery/restore and record/stop/history. Include compact iPhone, iPad, minimum Mac size, large text, keyboard/VoiceOver and relevant web-account interaction; retain feature-owned rendered QA. |
| T10 and remaining R8 part of T08 | Order 3, [Watch/link reliability](plans/reliability.md) | Complete import saves/meters once, retries do not spin or starve; concurrent single-use links verified against real Postgres. |
| T02/T04/T05 and ownership parts of T08 | Order 4, [account ownership](plans/account-ownership.md), before cutovers | Exact cap/revoked-sibling assertions, concurrent usage charged once, Apple/Polar purchase and notification lifecycle tests. Existing-account behavior is tested before migration. |
| Remaining T16 CRM tests | Order 6, [integration ownership](plans/integration-ownership.md) | OAuth routes and note-success/task-failure retries obey an explicit duplicate-prevention contract before connection adoption changes. Diagnostics evidence stays with [logging](plans/logging-and-monitoring.md). |
| Remaining T09/T11 disk and lifecycle coverage | Order 8, [durable checkpoints](plans/durable-checkpoints.md) | Released-store fixtures, actual disk reopen/process interruption, controlled start/cancel/reconnect/flush/handoff and stale-session boundaries; hardware-only checks named separately. |
| T15 and sustained T09 checks | Order 9, [history/session performance](plans/history-and-session-performance.md) | Repeatable long-session and large-history resource measurements with agreed budgets. |
| T13 | Order 9a, model quality and biometric privacy | Real populated voice data excluded from exports; normal prose allowed; versioned word/speaker/grounding/false-match evaluations with measured tolerances and no paid-provider requirement for routine CI. |
| Remaining T17 | With each replacement above | Test titles match assertions; no marketing-word or arbitrary constant mirrors presented as behavioral coverage; dated counts, skips and manual boundaries remain accurate. |

The newly selected UI/recovery and model-quality work must each become a bounded implementation plan before coding, revalidating the dated audit against current behavior. Keep production behavior in its existing feature plan; do not recreate the original umbrella as a competing implementation owner. Shipped R1/narrowed R2/R3 tests remain required regressions. The wider R2 AI-entry-point audit remains separately deferred and is not silently approved by this scheduling change.

### Independent customer improvements

Delivered in macOS 3.5.0: selective cloud privacy, purchase return and O1–O6. Backend/site are deployed and iOS 3.5.0 is confirmed available (purchase return is Mac-only). See the [shared QA handoff](releases/monitoring-cloud-purchase-qa.md).

These implementation records retain their contracts and QA history; they are not active future work. Remaining evidence and iOS availability belong to the release record.

| Plan | User outcome | Boundary |
|---|---|---|
| [Selective cloud privacy](plans/selective-cloud-privacy.md) | Choose Cloud/Local in live or saved meetings; title rules keep matching recordings off miniti cloud. | C1, distinct from private mode, recording filters and B4 provenance. |
| [Return after purchase](plans/purchase-return.md) | Polar checkout returns to Account through Open miniti and server-confirmed Pro. | B6d, no automatic account switch or entitlement granted by a URL; iOS remains StoreKit. |

### Planned later: bot-free video recording

Selected product direction by Ian, 2026-10-29; not part of the delivered 3.5.0 scope or selected next reliability release and not implemented. Mac first: optional capture of a selected meeting window plus audio, local storage, History playback linked to transcript timestamps, and MP4 export. Recording must continue when another app is foreground or covers the meeting window. Minimising the meeting window is an accepted limitation: video may pause, audio/transcription should continue, and the state must be clear. Browser meetings should use a dedicated window; switching tabs changes the captured content.

The [bounded video plan](plans/bot-free-video.md) now owns the local deliverable, engineering estimate, optional hosted phase and acceptance/rollback gates (2026-10-31). First prove background capture with Zoom, Teams and Google Meet, including audio/video/transcript timing, pause/resume, interruptions, recoverable files, disk limits and permissions. ScreenCaptureKit supports covered-window capture; compatibility on supported macOS versions remains unverified. Hosted video/sharing and iOS/Linux video are outside the first Mac scope. Public summary: `../minitidotapp/roadmap/index.html` and `llms-full.txt`. [Apple capture behaviour](https://developer.apple.com/videos/play/wwdc2022/10155/).

## Later product sequence

Ian accepted this proposed ordering on 2026-10-31 to reconcile all ten existing public roadmap ideas. It follows the core delivery order above, including internal prerequisites. Video remains a selected later direction with a bounded proposal; the other nine items remain exploratory. Ordering an idea does not select its implementation, assign a version or promise a date. Demand, feasibility and explicit prioritisation can change the sequence.

| Order after core work | Idea | Customer outcome / reason for position | State and scope boundary |
|---|---|---|---|
| 1 | [Bot-free Mac video](plans/bot-free-video.md) | Replay a meeting window alongside its transcript and export an MP4. Already selected as a later direction. | Planned later; local Mac capture first, background capture required, minimisation may pause video. See [video scope](#planned-later-bot-free-video-recording). |
| 2 | Insight editing | Review and edit summaries, action items and other generated insights before sharing or sending to CRM. Useful across existing workflows. | Exploring; scope saved edits, regeneration authority and export consistency before implementation. |
| 3 | Custom coaching templates | Reusable coaching profiles for meeting types, with talk-ratio/pace targets and feedback focus. Builds on personal coaching. | Exploring; distinct from shipped AI insight templates. |
| 4 | Coaching goals | Weekly targets and progress tracking make those coaching profiles actionable. | Exploring; define baseline, measurement and relationship to existing trends. |
| 5 | Multilingual code-switching | Transcribe a conversation that moves between languages. Improves the core recording experience. | Exploring; evaluate provider/model support and mixed-language accuracy; existing single-language selection is shipped. |
| 6 | Offline AI insights | Generate summaries and questions locally on supported Macs, extending existing local transcription and speaker separation. | Exploring; [local AI research](research/local-ai-research.md) owns evidence. Quality/hardware feasibility required; configured calendar, CRM and webhook connections remain separate. |
| 7 | Entity detection with CRM lookup | Open useful Attio results for people, companies and products mentioned in a meeting. | Exploring; English and Mac first, task usefulness required. No decorative highlighting. |
| 8 | Android | Bring recording and meeting insights to Android. Proposed first new platform expansion. | Exploring; [historical proposal](research/android-original-plan.md) requires fresh auth, capture and distribution planning. |
| 9 | Windows | Bring recording and meeting insights to Windows. | Exploring; demand and capture/distribution feasibility before choosing an architecture. |
| 10 | Team coaching | Compare personal metrics with agreed team benchmarks. | Exploring; requires a separate team, consent, permissions and sensitive-data sharing plan. No implied sharing of current personal coaching data. |

## Public roadmap projection

The website is a customer-facing projection of this index. Keep `../minitidotapp/roadmap/index.html` and the Current roadmap section of `../minitidotapp/llms-full.txt` aligned whenever priority or release status changes; reconcile the short `llms.txt` testing summary when release status changes. No generator or independent website backlog owns priority.

| Public section | Source and order | Customer-facing scope |
|---|---|---|
| Latest release | Core order 1, macOS and iOS 3.6.0 released | Automatic sync, clearer status, completed webhook processing/current-data resend and saved-edit protection. Preserve platform availability and release gates. |
| Next | Core order 1b recording reliability, then 2 and 3 | More reliable transcription recovery and finishing, then easier account recovery/device management, then Watch import and sign-in link reliability. Test foundation happens first internally; usage accounting and diagnostic internals stay out of public copy. |
| Later | Core orders 4, 5, 6, 8 and 9, then later product item 1 | Stable Pro/usage ownership, deliberate meeting copies, connection management, interrupted-recording protection, History/long-session performance, then bot-free Mac video. |
| Exploring | Later product items 2–10, in order | Retain every public idea with its exploratory status and no release dates. |
| Recently shipped | Release evidence and changelog | The full shipped-feature showcase, with per-platform availability and a link to the full changelog. Preserve the feature list and per-feature emojis. Show changelog-backed first-ship dates, noting later additions/platform launches separately. |

Test infrastructure, registration internals, operational alerts, runtime/database migrations and cost accounting retain their full positions above but are omitted from public feature copy. Use outcomes rather than plan IDs, storage mechanics, customer reports or model rollout flags. Record the separate 3.6.0 availability dates: macOS 2026-10-31 and iOS 2026-11-01. Both Luna opt-ins were separately activated on 2026-11-01; do not imply a new app binary or an unmeasured speed improvement.

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
| Local models | Mac local speaker separation default-on is deferred beyond 3.7.0 until M1 testing; the [speaker plan](plans/local-speakers-default.md) retains the evidence path, with no later version assigned. Offline insights follows the [later product sequence](#later-product-sequence); iOS transcription hardware/thermal feasibility and model pinning/distribution before default-on remain candidates. T13 quality/privacy coverage is ordered above. | [Local models](reference/local-models.md), [local AI research](research/local-ai-research.md), [transcription research](research/local-transcription-research.md) |
| Jev | Calibration before default-on; other classifier uses only after a task-specific evaluation. Existing naming/nudge shipped. | [Integration history](archive/jev-system-one-plan.md), local/gitignored evaluation `docs/research/jev-eval-report-2026-09-21.md` |
| Cloud | APNs, web History, write scopes, server-side Coaching, passkeys and storage-policy refinement. None is needed to call existing sync shipped. | [Cloud reference](reference/cloud-sync.md) |
| CRM | Opportunity-field mappings and deeper workflow automation. Tasks/previews and automatic notes already exist. Twenty self-hosting is demand-led. | [Feature reference](reference/features.md) |
| Product | Insight editing, coaching profiles/goals/team work, code-switching and useful entity-to-CRM actions follow the [later product sequence](#later-product-sequence). App Store localization/submission automation and optional template sync/versioning remain additional candidates. No decorative entity highlighting or unbounded prompt editor. | [Historical roadmap](archive/roadmap-through-3.4.0.md) |
| Auth enforcement | Verify deployed per-platform enforcement, supported legacy clients and remaining broad-key use. Only then scope retirement; preserve inactive users’ direct migration and secret-rotation overlap. Do not infer observe/require from old defaults. | [Accounts](reference/accounts.md), [validation](runbooks/validation.md) |
| Wider AI consent audit | Broader R2 AI-entry-point audit beyond the shipped History/Watch guards remains deferred. T11/T12/T13 and remaining T16 are now assigned positions in the test follow-through above. | [Test disposition](archive/README.md#test-audit-disposition) |
| Structural simplification | Revalidate each selected finding against current code. Audit recommendations are not approved work. | [August audit](research/structural-simplification-audit-2026-08-16.md) |
| Android | Later product item 8; re-plan auth, versions, platform behavior and current policies before any implementation. Never ship the old shared-secret design. | [Historical Android proposal](research/android-original-plan.md) |
| Linux | Existing shipped client, not a new spike. Reconcile Granola, cloud, calendar, auth/UX and other parity against its own tracker before claiming gaps closed. | [Linux AGENTS](../../miniti-linux/AGENTS.md), [Linux PLAN](../../miniti-linux/PLAN.md) |
| Windows | Later product item 9; demand and architecture/capture/distribution spike before selecting a product implementation. | [Historical platform discussion](archive/roadmap-through-3.4.0.md#p34-windows) |

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

3.7.0 local progress (2026-11-03): test foundation, model retirement and operator-email changes are implemented locally, with initial stop/drain/reconnect fixes under validation. Durable usage reporting and shared diagnostic acceptance are now local; hardware snapshots, speaker failure handling and activity/outcome reporting are also local. Recovery-generation and AI failure context remain open. [The release record](releases/3.7.0.md) owns current evidence; no distribution or deployment has occurred. Scope and the next-release speaker-restoration deferral are unchanged.
