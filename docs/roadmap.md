# Roadmap

Post-163 UI refinement, 2026-11-09: Mac folder disclosures use full-row targets and miniti surfaces; Home groups setup, models and feedback at bottom left; its matching full-height right sidebar has the calendar toggle and Cmd-] hint at bottom right, plus a visible calendar label on its collapsed rail. These changes are not in DMG/TestFlight 163. Fresh validation and packaging are required before publishing this revised candidate. Physical QA remains in progress; App Privacy is owner-confirmed complete.

Post-162 Home refinement, 2026-11-09: Ian is performing physical-device QA; no waiver was given. New source moves language/recording above the bottom controls, aligns the iOS footer and gives Mac Home an independent collapsible right calendar sidebar. Build 162 remains a historical testing artifact and must not be published as this revised candidate. Build 163 is signed, verified and available as a DMG and internal TestFlight build. Full local suites and the corrected remote CI run pass.

Release authorized, 2026-11-09: Ian requested the full coordinated release across repositories. Build 163 includes the final Home and folder setup/journey changes. Full local Apple validation and signed-package verification pass; TestFlight 163 is available. Public Apple release remains pending the physical-QA disposition. Ian confirmed the App Store privacy correction on 2026-11-09. This authorization supersedes earlier preparation-only publication restrictions. Unverified physical gates remain distinct from automated passes; the release checklist owns their disposition. No public availability is claimed by this note.

The single priority index for miniti Apple apps and shared `miniti-api` work. Reconciled on 2026-11-09 through frozen build 162: both full hosted suites and all 30 iPhone journeys pass. Signed packages verify and TestFlight 162 is available; the compatible backend is deployed after migration 002. The release checklist owns artifact availability and remaining release gates. Mac and iOS 3.7.0 build 149 remain the public Apple baseline. Each linked plan owns scope and completion evidence; this file owns ordering. Linux keeps its own release line and implementation tracker.

## Baseline

3.4.0 delivered enrollment/key repair, truthful restore/email errors, Account/email UX, Sending/consent, credential concurrency fixes, R1 private-mode locking, narrowed R2 History/Watch consent, R3 cloud response fences and failed-microphone recovery. Core account ownership has **not** migrated. [Release evidence](releases/3.4.0.md) records Mac build 141 live, iOS upload evidence, actual device checks and the macOS 26 waiver; upload is not independently verified App Store availability.

Current behavior and gotchas: [accounts](reference/accounts.md), [cloud](reference/cloud-sync.md), [audio](reference/audio.md), [Settings](reference/settings.md), [Watch](reference/watch.md), [patterns](reference/patterns.md). Existing alerts and support access: [operations](runbooks/operations.md). Do not use archived plans as current policy.

## Delivered: 3.5.0 build 142

macOS is live, including Sparkle verification from 3.4.0. The backend and purchase-return website are deployed. iOS 3.5.0 build 142 was independently confirmed READY_FOR_SALE on 2026-10-31. The following scope is delivered on both platforms, not a new implementation backlog.

- [Logging and monitoring O1–O6](plans/logging-and-monitoring.md): incident alerts, durable diagnostics, useful local timelines, Help reports and Home feedback with shared submission limits.
- [Selective cloud privacy C1](plans/selective-cloud-privacy.md): live/saved Cloud–Local controls, title rules and honest availability/removal states.
- [Purchase return B6d](plans/purchase-return.md): Mac checkout return and server-confirmed Pro.
- Included UX cleanup: Sending into Privacy, Models under Setup, Help/support details, About acknowledgements, accurate CAM++ status, two-row API mode choices and shared Home control typography. Contracts live in [Settings](reference/settings.md); evidence is in the [QA handoff](releases/monitoring-cloud-purchase-qa.md).

Delivery evidence and Ian's reported device QA live in [3.5.0](releases/3.5.0.md); the [QA handoff](releases/monitoring-cloud-purchase-qa.md) retains detailed checks without converting unitemised user confirmation into independently observed passes. iOS availability is confirmed and `IOS_LATEST_VERSION` advanced to 3.5.0 then, and to 3.6.0 on 2026-11-01; the 3.5.0 iOS record is closed. UptimeRobot setup/mail QA is user-reported in the release record; health HTTP 200 alone is not independent confirmation. Alert links were fixed and deployed separately in backend `2458ddb`.

## Delivered: 3.6.0, sync, delivery, alert clarity and managed AI

macOS **3.6.0 build 146** is released on 2026-10-31. The verified Retina DMG, Sparkle appcast, website and public docs are live. iOS build 146 became available on 2026-11-01 at 00:27:33 UTC, confirmed through Apple’s public UK App Store lookup. Backend alert clarity and the two Luna opt-ins are deployed, with both Luna groups enabled on 2026-11-01. Both remote Apple suites and backend CI passed. Ian explicitly waived the physical iPhone Settings gesture and clean cloud retest; previous webhook/resend waivers remain waivers, not passes. The [3.6.0 release record](releases/3.6.0.md) owns exact deployment, submission, checks and limitations. Test-foundation work and unrelated concurrent planning remain separate.

- [Automatic sync and completed webhook delivery](plans/sync-and-delivery-reliability.md): Charlie on 3.4.0 reports needing Sync now, a recent sync timestamp with an unchanged count, and webhooks arriving before AI/cloud work. Code confirms stale count refresh and early `meeting.saved` delivery; the stopped-meeting eligibility exclusion is also established in code; Charlie’s exact sequence still needs reproduction. Owns S1–S3 and R5–R7: immutable in-flight delivery, resend from current saved data, and rejection of stale History AI results. These share one persistence/revision contract and must not be duplicated in another plan.
- [Incident alert clarity](plans/incident-alert-clarity.md): distinguish historical evidence, current failures and unconfirmed recovery; correct event-count language and legacy capability assumptions. The already-deployed login-link fix is baseline, not unfinished work.
- [Managed Luna](plans/lightweight-luna.md): selected 2026-10-31. Four lightweight tasks plus full/incremental standard summaries, with separate default-off opt-ins and rollback. Other quality modes and BYOK stay unchanged; the legacy incremental fallback takes precedence. Implementation and validation are recorded in the release checklist; both opt-ins are active from 2026-11-01. The Retina dark green DMG is published with Mac 3.6.0.
- Reproduce the repeated iPhone transcript-starvation/reconnect traces before selecting a recording-engine change. No evidence yet establishes silence versus lost speech or a 3.5.0 regression.

These bounded fixes precede account access work because they affect trust in saved meetings, exports and operational alerts. Do not wait for the ownership migration or force webhooks to depend on optional cloud sync.

Scope confirmed after review: keep all S1–S3/R5–R7 in 3.6.0. The webhook carries the saved transcript and available summary without requiring cloud lookup. Use the existing outbox plus a small completion marker, preserve AI request timeouts without a new global deadline, and keep alert clarity independently deployable.

<a id="next-release-on-device-transcription-usage-tracking"></a>

<a id="selected-next-release-370"></a>

<a id="delivered-370-on-mac-and-backend-ios-submitted"></a>

## Delivered: 3.7.0 on Mac, iOS and backend

[Publication evidence](releases/3.7.0.md#publication-2026-11-04) records Mac build 149 available on 2026-11-04, backend deployed before the reporting client and iOS build 149 submitted with automatic release. A later read-only App Store Connect check confirms iOS 3.7.0 READY_FOR_SALE; the release record preserves both observations. Earlier local-only statements in dated implementation records are historical. The release record retains actual tests, device observations and limitations; publication does not turn missing evidence into a pass.

| Delivered scope | Implementation owner |
|---|---|
| Isolated hosted tests, reliable runners, real storage and shared wire coverage | [Test foundation](plans/test-foundation.md) |
| Bounded Stop drain, coordinated recovery, truthful source/outcome status and bounded AI failure context | [Recording reliability](plans/recording-reliability-followup.md) |
| Durable managed local/private duration reporting, separate from diagnostic consent and Deepgram allowances | [On-device usage](plans/on-device-usage-tracking.md) |
| BYOK model update, supported backend fallbacks and probes | [Model retirement](plans/gpt-5-mini-retirement.md) |
| Provider rejection details and routing-aware operator messages | [Operator emails](plans/operator-alert-emails.md) |
| Local-speaker failure handling, pre-start fallback and optional coarse device diagnostics | [Local speakers](plans/local-speakers-default.md) |

Local speakers remain off by default; Your voice remains opt-in. Default-on still awaits M1 testing, with no release assigned. Mid-session provider speaker restoration was explicitly deferred. Historical iPhone incident causes remain unproven. Linux model retirement delivery is tracked independently in its PLAN.md; Apple publication is not Linux distribution evidence.

<a id="next-release-after-370"></a>

### Selected next release: 3.8.0

Build 163 includes the bottom Home recording controls, equal iOS footer cells and independent collapsible Mac calendar sidebar. Full local checks pass: Mac 1,376 total with nine intentional skips; iOS 1,297 with five; all 31 iPhone UI journeys pass. Signed/notarized DMG and distribution IPA verification passes. Internal TestFlight 163 is VALID and available to Ian; App Store 3.8.0 selects 163 without submission. The draft GitHub DMG round-trip matches the verified bytes. Both remote Apple suites and documentation contracts pass on `259f9606`, after correcting a test-only desktop-height assumption in the new Mac resize test. Packaged application inputs remain unchanged. Physical QA is in progress with no waiver; Ian confirmed the App Store privacy-label correction on 2026-11-09. No public Apple release has occurred. The [release checklist](releases/3.8.0.md) owns exact rollout evidence and remaining gates.

The [release-planning audit](releases/3.8.0-planning-audit.md) records the source-backed regression, compatibility, UX/design, performance and security requirements, plus exact docs/website/changelog/screenshot owners. Apply the [planning workflow](runbooks/release-planning.md) again after material scope changes and at implementation completion. Automated checks, bounded synthetic measurements and iPhone rendered evidence are recorded; physical comparisons, the remaining device matrix and publication gates stay explicit.

1. [Managed reconnect metering](plans/managed-reconnect-metering.md): preserve recording duration across provider credential renewal. A 74-minute QA meeting counted about five seconds after a late reconnect. Preserve owner fencing and replay safety, and count recordings beyond four hours without stopping them; no historical back-charge.
2. [Mid-session speaker restoration](plans/local-speakers-default.md#mid-session-restoration-next-release-after-370): safely restore provider separation after local failure in a cloud-transcribed recording. Use the same reconnect owner, preserve identities and truthful degraded state. Local-only sessions stay local; no audio replay or default-on change.
3. [Account access/recovery and device labels](plans/account-access.md), with [bounded recovery/UI coverage](plans/recovery-ui-coverage.md): unreadable credentials, throttled retries, explicit choices and recognizable devices. Ian confirmed explicit first-use/sign-out choices; existing enrolled users retain their account. No account-ownership migration.
4. [Watch retry and single-use link reliability](plans/reliability.md): fair persisted import backoff and atomic generic web sign-in/confirmation consumption. Preserve recoverable device-enrollment approval semantics.
5. [Browser detection and manual-start association](plans/browser-call-detection.md): truthful sensor uncertainty, late calendar starts and non-destructive association. Physical browser coverage remains unverified.
6. [Folders and completion](plans/folders-and-meeting-completion.md): editable automatic folders with local matching and optional cloud sync; saved results in place without a Done action. New meetings file automatically; older history requires Preview and Apply. A continuing call does not automatically split at a calendar boundary.
7. [Home setup](plans/home-setup-guide.md): optional checklist with actual configuration checks, per-task hiding/restoration, calendar recommendation, separate local audio choices and Mac Markdown/index destination.
8. Bounded review corrections: off-main Mac audio hardware lifecycle, paid Watch checkpoints, same-revision folder refresh and dual-case legacy migration. These fix the selected package; B0 account-record merging remains order 4 below.

Metering precedes new reconnect behavior. Account and Watch/link work retain their ordered integration gates. Selected work is implemented locally and the latest scoped code review reports no blockers. Build 163 execution evidence is summarized above. Required tests use Testing isolation; physical/hardware tests stay explicitly opt-in and release evidence stays separate. Existing ownership/performance/product work remains queued below.

## Recommended delivery order

3.6.0 delivered order 1. 3.7.0 delivered orders 1a/1b on Mac and backend, with iOS now available. 3.8.0 contains orders 1c/1d, 2 and 3 through 3c; subsequent versions remain unassigned. Ordering does not authorize deployment. A production incident can change priority explicitly.

| Order | Plan | Why here / dependency | State |
|---|---|---|---|
| 1 | [Sync and delivery](plans/sync-and-delivery-reliability.md), [alert clarity](plans/incident-alert-clarity.md), [managed Luna](plans/lightweight-luna.md) | Resolve the reported automatic-sync/count and webhook-readiness paths; make deployed alerts actionable. Includes R5–R7 so stale AI cannot contaminate the corrected delivery path. | Mac and iOS build 146 released; backend deployed with both Luna groups enabled. Explicit waivers and remaining evidence are in the release record |
| 1a/1b, 3.7.0 | [Delivered foundation/recording/reporting/models/alerts](#delivered-370-on-mac-and-backend-ios-submitted) | Preserve the shipped contracts and regression coverage. | Mac and iOS build 149 released; backend deployed. Evidence above. |
| 1c, 3.8.0 | [Managed reconnect metering](plans/managed-reconnect-metering.md) | Fix duration loss on grant renewal before adding a new reconnect trigger; prove replay/ownership and expiry bounds. | 3.8.0 implemented locally; v2/legacy regression and isolated Redis evidence in release record |
| 1d, 3.8.0 | [Mid-session speaker restoration](plans/local-speakers-default.md#mid-session-restoration-next-release-after-370) | Restore provider separation safely after local failure through the one recovery owner. | 3.8.0 transition implemented locally; physical speaker recovery QA pending; default-on/M1 stays separate |
| 2 | [Account access and recovery](plans/account-access.md) | Finish A2f → A3/A3a → A4/B6b and B6c labels, preserving existing users before changing what accounts own. Backend first; explicit sign-out choices confirmed on 2026-11-04. macOS 26 evidence or an explicit waiver remains required. | 3.8.0 choices, recovery and labels implemented locally; hosted suites pass and iPhone journeys have full/targeted evidence; Mac runner and manual QA gates remain |
| 2, regression work | [Recovery and UI coverage](plans/recovery-ui-coverage.md) | T11/T12 truthful journey assertions and a bounded UI/accessibility harness alongside access/recovery, after test isolation. Protect consent, Settings, restore and record/stop/history before ownership changes. | 3.8.0 isolated UI targets/lanes added; build 162 passes all 30 iPhone journeys in one full run. Mac runner authorization remains a gate |
| 3 | [Watch retry and single-use link reliability](plans/reliability.md) | Close R4 and R8 with bounded tests. R5–R7 belong to 3.6.0; R8 requires real Postgres concurrency. Do this before broader migrations complicate reproduction. | 3.8.0 Watch retries and atomic links implemented locally; real-storage tests pass, physical Watch QA pending |
| 3a, 3.8.0 | [Browser detection and association](plans/browser-call-detection.md) | Repair start evidence and manual-session ownership before broader automation. | Implemented locally; synthetic regressions pass, physical matrix pending |
| 3b, 3.8.0 | [Folders and completion](plans/folders-and-meeting-completion.md) | Add bounded organisation and completion through existing persistence owners. | Implemented locally; folder UI regressions have passing build-162 iPhone evidence. Physical and mixed-version sync QA remain in the release record |
| 3c, 3.8.0 | [Home setup guide](plans/home-setup-guide.md) | Stage optional setup after explicit account access without changing existing choices. | Implemented locally; automated suites pass, signed upgrade remains manual |
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

Added to the delivery order at Ian's request on 2026-10-31. The full T01–T17 review remains tracked work. The bounded test foundation shipped with Mac 3.7.0 and the backend, with iOS now available; other feature regressions retain the positions below and no version assignment. This does not expand the delivered 3.6.0 release. The [original audit](archive/test-quality-and-coverage-plan.md) retains evidence and detailed acceptance criteria; the [disposition register](archive/README.md#test-audit-disposition) maps it to current owners.

| Audit work | Delivery position and owner | Completion evidence |
|---|---|---|
| T01/T06/T07/T14 and applicable T17 | Order 1a, [test foundation](plans/test-foundation.md) | Failing tests fail the runner; isolated settings/credentials; real insights-handler, Redis/Postgres and cross-client contract checks execute; brittle checks removed only with appropriate replacement evidence. |
| T03 and R7 part of T08 | Order 1, [3.6.0 sync/delivery](plans/sync-and-delivery-reliability.md) | Preserve the released Mac and iOS real-sender, in-flight update, current-data resend and stale-History regressions; release evidence remains separate. |
| T11 truthful journey assertions and T12 UI/accessibility | Order 2, alongside [account access](plans/account-access.md) | A bounded Mac/iOS UI harness covers consent visibility/cancellation, Settings navigation, recovery/restore and record/stop/history. Include compact iPhone, iPad, minimum Mac size, large text, keyboard/VoiceOver and relevant web-account interaction; retain feature-owned rendered QA. |
| T10 and remaining R8 part of T08 | Order 3, [Watch/link reliability](plans/reliability.md) | Complete import saves/meters once, retries do not spin or starve; concurrent single-use links verified against real Postgres. |
| T02/T04/T05 and ownership parts of T08 | Order 4, [account ownership](plans/account-ownership.md), before cutovers | Exact cap/revoked-sibling assertions, concurrent usage charged once, Apple/Polar purchase and notification lifecycle tests. Existing-account behavior is tested before migration. |
| Remaining T16 CRM tests | Order 6, [integration ownership](plans/integration-ownership.md) | OAuth routes and note-success/task-failure retries obey an explicit duplicate-prevention contract before connection adoption changes. Diagnostics evidence stays with [logging](plans/logging-and-monitoring.md). |
| Remaining T09/T11 disk and lifecycle coverage | Order 8, [durable checkpoints](plans/durable-checkpoints.md) | Released-store fixtures, actual disk reopen/process interruption, controlled start/cancel/reconnect/flush/handoff and stale-session boundaries; hardware-only checks named separately. |
| T15 and sustained T09 checks | Order 9, [history/session performance](plans/history-and-session-performance.md) | Repeatable long-session and large-history resource measurements with agreed budgets. |
| T13 | Order 9a, model quality and biometric privacy | Real populated voice data excluded from exports; normal prose allowed; versioned word/speaker/grounding/false-match evaluations with measured tolerances and no paid-provider requirement for routine CI. |
| Remaining T17 | With each replacement above | Test titles match assertions; no marketing-word or arbitrary constant mirrors presented as behavioral coverage; dated counts, skips and manual boundaries remain accurate. |

The [UI/recovery scope](plans/recovery-ui-coverage.md) is now bounded for 3.8.0. Model-quality work still needs its own bounded implementation plan before coding. Revalidate dated audit findings against current behavior. Keep production behavior in its existing feature plan; do not recreate the original umbrella as a competing implementation owner. Shipped R1/narrowed R2/R3 tests remain required regressions. The wider R2 AI-entry-point audit remains separately deferred and is not silently approved by this scheduling change.

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
| Latest release | Core orders 1a/1b, Mac and iOS 3.7.0 released | Recording recovery/finishing, truthful speaker failures and BYOK compatibility. Preserve platform availability. |
| Next | 3.8.0: core order 1d, then 2, 3, 3a, 3b and 3c | Restore speaker separation during cloud-transcribed recordings after local separation fails, then easier account recovery/device management, then Watch import/sign-in link reliability, clearer browser detection and association, editable folders/completion in place, and a staged Home setup guide. Metering correctness comes first internally; usage accounting and diagnostic internals stay out of public feature copy. |
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

## Additional 3.8.0 product scope, 2026-11-04

[Folders and meeting completion](plans/folders-and-meeting-completion.md) adds FO1 and MC1 to the selected candidate. Integrate completion after recording ownership/metering work; folders require their own persistence and grouping design. Both are implemented locally with flat folders, bounded local matching, explicit preview, optional cloud catalog sync and saved completion in place. Expanded validation is recorded in the release checklist.

[Browser call detection](plans/browser-call-detection.md), CD1, is also selected for 3.8.0: investigate and fix missed Google Meet starts in confirmed Arc and other intermittent browser cases, with truthful fallback and physical browser verification. Prioritise reproduction and policy before expanding automation defaults; integrate with MC1 through the existing recording owner.

CD1 includes broad mainstream Mac browser support, with the validation inventory and coverage gates in its owning plan.

CD2 is selected for the expanded 3.8.0 scope: [manual-start association and duplicate prompts](plans/browser-call-detection.md#manual-start-association-and-duplicate-prompts-cd2). Reconcile late call detection, unlinked calendar events and stale start notifications before MC1. The original four workstreams are locally implemented; FO1/MC1/CD1/CD2 are implemented locally with passing expanded automated checks; physical browser evidence remains a release gate.

SG1 is also selected for 3.8.0: the [Home setup guide](plans/home-setup-guide.md) replaces overlapping account/calendar prompts with optional inline choices and working email actions. It preserves existing choices and adds supported-Mac transcription controls. The 2026-11-05 UX refinement adds smoother hiding, broader folder previews and Mac file/index setup using the existing export preferences. Separate local-transcription and local-speaker recommendations are recorded in the Home setup discussion; no default migration is selected. Local implementation and new evidence are tracked in the release record.

3.8.0 setup revision, 2026-11-05: Ian approved the vertical checklist in the Home setup plan. Recording access, calendar, account recovery and Mac file/audio choices use visible state checks and one expanded task. No new default migration or publication; the release record owns validation.

## Bounded follow-ups after 3.8.0

The [current release checklist](releases/3.8.0.md) owns remaining release gates; this list does not waive them. Deliberately deferred review suggestions are follow-ups without a version commitment: device-name refresh/blank-label polish, queued sync rerun latency and compaction/launch-save optimization, browser error-page and alert presentation, unreadable Watch-part salvage UI, pre-grant Watch owner assignment, and automatic reuse of an audio worker only after verified cleanup. Version-parser boundary coverage belongs with future mixed-version compatibility work. B0–B5 ownership migrations retain their existing priority and decisions. No new feature or follow-up is silently folded into the candidate.

### Backend device-ID audit follow-ups

Claude's read-only audit on 2026-11-06 found no required pre-3.8.0 change; its disposition is in the [retrospective decisions](releases/3.8.0-retro.md#decisions). The following backend work is deferred without a version commitment:

- **Attach subscription conflict guard:** `attachToDestination` and `destinationHasRailConflict` in `miniti-api/lib/clientAuthStore.ts` read lowercase device records, missing uppercase Apple usage records. This predates 3.7.0. A spelling-only repair would wrongly reject devices sharing one subscription. Read both spellings and compare subscription identity: reject only a different `polarSubscriptionId` or Apple original transaction on the same rail. Cover the moving device and destination members, both UUID spellings, shared-subscription acceptance and distinct-subscription rejection for both providers. Keep this bounded correction separate from B0 account merging.
- **Lowercase twin hashes, Low:** `revokeInstallation` writes a lowercase `device:` hash containing only `enrollmentState`; attach writes one containing only `accountId`. The audit found no readers of those fields, but `adminDevices.ts` counts every `device:*` key and inflates `total_devices`. Include write handling and safe treatment of existing twins in the device-ID helper package. Verify one installation counts once without dropping real usage, entitlement or ownership data.

Backend implementation owns these fixes and their regression tests. Polar's preservation of `external_customer_id` case remains unverified. Compare a real webhook payload with the originally supplied ID when checking provider behavior; keep payloads and customer identifiers outside the repository. The audit report is source evidence, not a production-provider verification.


### Build-156/157 review follow-ups, recorded 2026-11-07

The [3.8.0 deferred register](releases/3.8.0.md#scoped-build-156157-review-2026-11-07-record-only) owns the bounded folder recovery/coverage, audio action/diagnostic/coverage, account reset decision, Watch receipt/Dismiss/coverage and setup-help/reactivation findings. They are recorded only, not extra 3.8.0 scope. Prioritize within the existing reliability and test-foundation sequence after release; no new public roadmap promise. The cloud exclusion undo data-loss fix, Resume placement, ID lookup and measured setup/permission work stay in the current candidate.
