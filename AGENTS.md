# Miniti

macOS + iOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio (macOS) or mic-only (iOS), streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI. Three tiers: free managed (500 min/month), pro managed ($5/month, 5000 min/month), or BYOK (own API keys, unlimited). Pro purchase rail is platform-specific: Polar.sh on macOS and StoreKit auto-renewable subscription on iOS.

This file is the canonical entry point for AI coding agents working on Miniti. It points at focused docs for each concern. Don't dump new long-form prose here — add it to the right `docs/*.md` instead.

## Tech stack

- SwiftUI + SwiftData (macOS 14.2+ / iOS 17+)
- Xcode 27.1 release toolchain, Swift 6 concurrency
- Deepgram Nova-3 streaming (WebSocket)
- Optional on-device speaker diarization: NVIDIA Nemotron-3-Diarization via the FluidAudio Swift package (Core ML, Apple silicon), default off, replaces Deepgram's diarizer per word when active. Optional on-device transcription (2.12.0, macOS, default off): NVIDIA Nemotron 3.5 ASR Streaming Multilingual 0.6B through the same package, downloaded on demand (not bundled), replaces the Deepgram socket for the session when active. The 190 MB model is bundled: `scripts/fetch-nemotron-model.sh` (pinned, checksummed) fills the gitignored `Miniti/Resources/NemotronDiarizer/` as the first build phase of both app targets
- TypeSafe Jev (`jev-1.13.0`) through the managed `/api/classify` proxy for attendee speaker naming and the sales nudge, opt-in (`jevClassifierEnabled`, default off), never generates text; GPT and the phrase heuristics remain the fallback
- OpenAI insights: Managed full and incremental `standard`, `meddpicc`, `questions`, `template`, `docs` and `investigation` requests use pinned `gpt-5.4-mini-2026-03-17`; `speaker_names`, `catchup`, `docs_topics` and `template_draft` use pinned `gpt-5-mini-2025-08-07`. `INSIGHTS_INCREMENTAL_QUALITY_MODEL=off` restores the lightweight incremental fallback. BYOK uses pinned `gpt-5-mini-2025-08-07` except investigations, which use pinned `gpt-5.4-mini-2026-03-17`.
- Vercel + Upstash Redis backend (`miniti-api`)
- Sparkle 2.9.5 for macOS auto-update; StoreKit 2 + Polar.sh for purchase rails
- Netlify Blobs for DMG hosting

## Targets

- **Miniti** — macOS app (`com.miniti.app`)
- **MinitiMobile** — iOS app (`com.miniti.mobile`)
- **MinitiLiveActivityExtension** — iOS widget extension (`com.miniti.mobile.live-activity`)
- **MinitiWatch** — watchOS companion app (`com.miniti.mobile.watchkitapp`, 3.1.0), embedded in MinitiMobile; records to AAC segments and hands them to the phone over Watch Connectivity for Deepgram prerecorded transcription
- **MinitiTests** / **MinitiMobileTests** — XCTest (same source files, different host app)

## Where to find things

| I need to… | Read |
|---|---|
| Decide what is next, dependencies or release scope | [docs/roadmap.md](docs/roadmap.md), the sole ordered priority index; bounded plans in `docs/plans/` |
| Understand the doc cleanup or find an old plan | [Archive disposition](docs/archive/README.md); archived instructions/statuses are historical, not current policy |
| Ship a version | [RELEASE.md](RELEASE.md), [fastlane/RUNBOOK.md](fastlane/RUNBOOK.md), [distribution](docs/reference/distribution.md) |
| Check 3.4.0 QA / unresolved device evidence | [Release record](docs/releases/3.4.0.md), [validation register](docs/runbooks/validation.md) |
| Understand files / cross-file conventions | [Architecture](docs/reference/architecture.md), [patterns](docs/reference/patterns.md) |
| Work on audio, automation or speaker/source identity | [Audio](docs/reference/audio.md), [recording lifecycle](docs/reference/recording-lifecycle.md) |
| Work on account access, signing or billing identity | [Accounts](docs/reference/accounts.md); [access plan](docs/plans/account-access.md), [ownership plan](docs/plans/account-ownership.md) |
| Work on UI, Settings, consent or data flows | [UI states](docs/reference/ui-states.md), [Settings](docs/reference/settings.md), [design.md](design.md) |
| Change cloud sync / account changes | [Cloud](docs/reference/cloud-sync.md), [backend contract](../miniti-api/docs/agents/08-cloud.md), [meeting ownership](docs/plans/meeting-ownership.md) |
| Change meeting Cloud/Local controls / title rules | [Selective cloud privacy](docs/plans/selective-cloud-privacy.md), distinct from private mode and calendar filters |
| Add purchase return / account integration connections | [Purchase return](docs/plans/purchase-return.md), [integration ownership](docs/plans/integration-ownership.md) |
| Fix sync, webhook, Watch/History/export/link races | [3.6.0 sync/delivery](docs/plans/sync-and-delivery-reliability.md), S1–S3/R5–R7; [remaining reliability](docs/plans/reliability.md), R4/R8; R1/narrowed R2/R3 shipped |
| Operate alerts / inspect admin diagnostics | [Operations runbook](docs/runbooks/operations.md); [logging and monitoring plan](docs/plans/logging-and-monitoring.md) owns O1–O6 |
| Understand tests / improve test quality | [Testing](docs/reference/testing.md), [test foundation](docs/plans/test-foundation.md), [T01–T17 audit disposition](docs/archive/README.md#test-audit-disposition); feature regressions stay with their owning plan |
| Work on Apple Watch / phone import | [Watch](docs/reference/watch.md), [original delivery record](docs/archive/apple-watch-plan.md) |
| Change search / Granola / saved-result handling | [Meeting history and import](docs/reference/meeting-history-and-import.md) |
| Change local models, voice prints or Jev | [Local-model contracts](docs/reference/local-models.md); linked original implementation/evaluation records retain thresholds and measured limitations |
| Evaluate local insights/transcription | [Local AI research](docs/research/local-ai-research.md), [transcription research](docs/research/local-transcription-research.md), [POC results](scripts/transcription-poc/RESULTS.md) |
| Revisit structural simplification | [Dated audit](docs/research/structural-simplification-audit-2026-08-16.md), revalidate findings before adopting |
| Understand features / plans | [Feature reference](docs/reference/features.md); private financial models stay ignored and are not public documentation |
| Regenerate marketing screenshots | [scripts/screenshots/README.md](scripts/screenshots/README.md) |
| See release history | [CHANGELOG.md](CHANGELOG.md); per-platform evidence in `docs/releases/` |
| Work on Linux | [../miniti-linux/AGENTS.md](../miniti-linux/AGENTS.md) / [PLAN.md](../miniti-linux/PLAN.md), a shipped client on its own release line |
| Evaluate Android | [Historical proposal](docs/research/android-original-plan.md), requires re-planning; shared app secret/lockstep versions below are obsolete |

[README.md](README.md) is the public repository introduction; end-user documentation lives at `https://miniti.app/docs` and the public-facing changelog at `https://miniti.app/changelog`. This file (`AGENTS.md`) is the dev-facing entry point.

## Non-negotiable conventions

- **Design tokens**: all colors route through `ColorPalette` in [Miniti/Models/ColorPalette.swift](Miniti/Models/ColorPalette.swift). Never hardcode hex literals in view code. See [design.md](design.md) for the full spec (typography, spacing, components, contrast).
- **Design system**: shared spacing, radius, control, motion, opacity, semantic control roles, navigation copy, and content-accent contracts live in `MinitiDesignSystem`; compact controls use `MinitiControlLabel`, while mutually exclusive views use the lowercase neutral `MinitiTabLabel` / `MinitiTabStripSurface` pair. Equal-width segmented strips set `fillsAvailableWidth` so every label surface and hit target occupies its full segment. Coaching metric taxonomy lives in `ColorPalette.Coaching` and must stay consistent across live, history, overview, examples, and charts without reusing CTA/status colors. The Coaching overview separates focus/trends, aggregate stats, and meeting history into lowercase `focus` / `stats` / `history` tabs; its stats include all six Coaching metrics, keep each metric plus unit on one line, show the metric explanation inline below rather than behind an info icon, and use success/error/neutral status colours for semantically good/bad/neutral changes. Historical metrics use six separate cards directly below the uninterrupted comparison table; each chart keeps its own metric scale, numeric y-axis, and adaptive meeting-sequence x-axis with plain numeric ticks under a centred `meeting` label rather than combining incompatible units or using elapsed calendar time. `CoachingLayout` owns its 720pt reading/stats-column, platform chart height, and 480pt compact-column bounds, `CoachingTypography` owns its desktop reading-size step, trend sections sit directly on the background with `MinitiFadingDivider`, grounded examples alone retain content-sized hover cards without disclosure chevrons, copy does not truncate, and grounded examples keep the label/quote together at left with a right-aligned meeting title over a date-only line. macOS back/forward swipe thresholds and the neutral edge progress cue use the shared `NavigationGesture` contract. Preserve native `Button` / `Menu` ownership of actions, focus, disabled state, shortcuts, and accessibility. Do not pass arbitrary feature colors into ordinary controls or fork shared component measurements inside feature views.
- **Typography**: Apple system font for readable prose, controls, and primary Home / Coaching / History navigation. The `miniti` lockup retains the original monospaced identity; timers/counters use monospaced digits. Transcript and insight prose share the same platform-specific size at every interface scale. Dark mode only.
- **Accessibility + adaptation**: app-authored animations must respect Reduce Motion. iPhone keeps the compact tab bar; regular-width iPad uses adaptive sidebar navigation. New visual materials are limited to functional system surfaces and must preserve contrast.
- **State**: `AppState` is the single source of truth, injected via `@EnvironmentObject`. Transient high-frequency UI signals live in `AudioLevelsState` / `TranscriptRuntimeState` to avoid invalidating the whole `AppState` on every sample.
- **Platform guards**: keep `#if os()` localized. Most branching is in `AppState.swift`; each target compiles its own `AudioCaptureService` with the same class name + public interface.
- **Model context wiring**: `appState.modelContext` must be set from `@Environment(\.modelContext)` in the first view that appears (`MainWindow.swift` on macOS, `MainTabView.swift` on iOS). Without it, `saveCurrentMeetingIfNeeded()` silently no-ops.
- **Hot-path performance**: never `.filter` `@Published` arrays in callbacks that fire on every transcript finalize (grows unboundedly). Iterate `.reversed()` and break on window expiry. See [docs/reference/patterns.md](docs/reference/patterns.md) § "Performance / hot-path rules".
- **Changelog style**: public-audience prose, no code refs. Never edit old entries unless the user explicitly requests a historical correction. Release headers are date + version only; platform availability belongs in bullets, never parenthetical header status. One flat bullet list per release with `new:` / `improvement:` / `fix:` prefixes, never sub-headers like "New features" or "Experience improvements". The product name is always lowercase (miniti). Write bullets in Ian's voice: short plain sentences, specific numbers, simple verbs, no em dashes, no "not X, it's Y", no bold, no exclamation marks. Rules and examples live in the project `changelog` skill (`.claude/skills/changelog/SKILL.md`, gitignored because the repo is public); the fuller voice guide is `../gtm/enablement/ian-tone-of-voice.md`. The changelog file itself holds entries only, no style section.
- **Managed-mode auth is device-bound** (`Miniti/Services/ClientAuth.swift`): a per-install P-256 key (Secure Enclave when available) plus an anonymous recovery key; `MinitiAPIService.send(_:)` attaches the bearer token and an ES256 `X-Request-Proof` on writes. No shared backend secret exists in the app; never reintroduce an `X-API-Key`. Existing installs migrate silently via `/api/auth/migrate` (`AppState.ensureManagedEnrollment`). An enrolled install moves to another account with `POST /api/auth/account/attach` (`ClientAuthManager.attachToAccount`, rewrites key/account/tokens in place, never signs out); Pro sponsorship arrives as `entitlement_via_account` on `/api/usage`. The Swift prompt/vector contract is shared with `../miniti-api` (`test/fixtures/client-auth-vectors.json`) and `../miniti-linux`.
- **macOS is shipped sandboxed** — `com.apple.security.app-sandbox` + audio-input + network + user-files entitlements. Don't call `codesign --force --sign` on a bundle that has entitlements without also passing `--entitlements` (that's what caused the v1.24.0 history-wipe regression — postmortem in [docs/reference/distribution.md](docs/reference/distribution.md)). Sparkle also needs `SUEnableInstallerLauncherService = true` plus `com.miniti.app-spks` / `com.miniti.app-spki` mach lookup exceptions, or sandboxed installs fail after download with `Failed copying system domain rights: -60005`. Keep Sparkle at 2.9.3+ (currently 2.9.5): older 2.9.1 collides with the `.app` suffix in Miniti's bundle ID and can trigger a first-attempt macOS security denial. The Developer ID build carries no `com.apple.application-identifier` entitlement (no provisioning profile), so `kSecUseDataProtectionKeychain` fails with -34018 on macOS; both Keychain items go through `KeychainSlot`, which falls back to the login keychain (3.2.1 postmortem in [docs/reference/distribution.md](docs/reference/distribution.md)).

**Private-mode boundary (Ian, 2026-10-26):** configured webhook and CRM exports remain allowed. Do not turn private mode into a blanket network/export ban. 3.4.0 locks the switch during starting, recording, resuming and finalizing, and adds History/Watch permission guards. The wider AI-entry-point audit remains deferred. Do not claim that a preference toggle changes an already-running transcription engine.

## Repo layout

```
AGENTS.md                          # This file — canonical entry point for agents
.cursor/rules/project.mdc          # Cursor rule that references AGENTS.md
.github/copilot-instructions.md    # GitHub Copilot shim
RELEASE.md                         # 10-step release runbook
CHANGELOG.md                       # Public-facing release history
design.md                          # Visual design spec
docs/
  roadmap.md                      # Sole priority index and recommended execution order
  plans/                          # Bounded future deliverables, one or more per release
  reference/                      # Current behavior, architecture and durable gotchas
  runbooks/                       # Operations/support and evidence reconciliation
  releases/                       # Version/platform QA, deployment evidence and waivers
  research/                       # Dated evaluations and unselected proposals
  archive/                        # Historical plans plus a complete disposition register
Miniti/                            # macOS target source
MinitiMobile/                      # iOS target source
MinitiLiveActivity/                # Widget extension source
MinitiWatch/                       # watchOS app source (recorder, store, Watch Connectivity client, views)
Shared/                            # RecordingActivityAttributes (iOS app + extension), WatchRecordingProtocol (watch + both apps)
MinitiTests/                       # XCTest sources (shared by both test targets)
fastlane/                          # Fastlane config + RUNBOOK
scripts/                           # build-dmg.sh, release-info.sh, dmg-background.png
  screenshots/                     # Marketing screenshot pipeline (build → capture → frame); README.md is the runbook
  diarization-poc/                 # Nemotron-3-Diarization vs Deepgram offline eval (Python, gitignored venv/data/out)
  transcription-poc/               # Nemotron 3.5 / Apple / Parakeet vs Deepgram offline transcription eval (Swift harness + Python scoring, gitignored data/out)
```

## When in doubt

1. Read [docs/reference/patterns.md](docs/reference/patterns.md) first — it catches most "why is this like this?" questions.
2. Search the full repo for a specific symbol before adding a new one.
3. If you change something a doc here describes, update the doc in the same PR.

## Learned user preferences (from prior Codex sessions)

- When large or Codex-authored diffs are uncommitted, the user often wants an independent second-pass review (another agent) before treating them as shippable.
- For the top-of-file changelog and App Store-style "what's new" text: keep language plain and user-facing; put technical depth elsewhere in sub-docs; order items **new → improvement → fix**; deduplicate; keep listing copy aligned with what actually shipped.
- When updating iOS release notes, double-check that bullets apply to the mobile app and are not macOS-only unless explicitly scoped.
- For UI tweaks, prefer small targeted changes over large rewrites when fixing regressions; follow explicit layout and copy instructions literally.
- The user values clear labels and keyboard hints on macOS home actions (e.g. shortcuts/settings) alongside icons when both are requested.
- Meeting utility actions such as Investigate and Catch me up use labelled neutral `MinitiControlLabel` chrome with aligned SF Symbols; do not substitute emoji or one-off button layouts.
- No em dashes anywhere in the product, not only in copy: menus, settings, errors, notifications, exports. Use commas, full stops or colons.
- Settings tabs are single words, one question per tab, grouped Setup / Meetings / Connections / Privacy / Support (Cloud sits in Setup under Account since 3.0.0; API is its own tab in Connections since 3.2.1, visible to everyone with the upgrade path when Pro or cloud is missing); model choices are "Deepgram" or "This Mac" pickers, never model names in the control. Privacy and Support are separate; Help contains support/reporting; About contains version, links and acknowledgements (3.5.0).
- Account UX contract (delivered in 3.4.0): suggest optional verified email without enabling cloud or requiring Pro; keep recovery key as backup and billing/license restore separate. B6a owns state-aware labels and full recognizable email in Account. Sending U1 should group concise data flows with one Configure action per row; consent U2 keeps actions visible outside the scroll body. B6a and U1/U2 are delivered in 3.4.0 build 141; later first-use choices remain planned.
- Do not label Jev or the Nemotron models as beta. Insight menus show names only, with a settings link at the bottom, never "Name — description".
- Normal updates should not appear as home-screen banners: macOS uses Sparkle and iOS uses the App Store. Keep `/api/version` only for the minimum-version force-update gate.

## Learned workspace facts

- Follow-up implementation (2026-10-28): logging/monitoring, selective cloud privacy and Polar purchase return are the selected scope; their `docs/plans/` files own delivery evidence. Monitoring keeps hourly checks. The 3.5.0 release record now owns deployment and user-reported UptimeRobot/QA evidence; this earlier selection note is not independent verification.
- Bot-free Mac video (2026-10-29) is a selected later product direction, outside the current release. Background window capture is required; minimising the meeting window may pause video while audio/transcription continue. Scope and feasibility gates live in [the roadmap](docs/roadmap.md#planned-later-bot-free-video-recording); the website roadmap mirrors the plan without claiming implementation or a date.

- Backend changes for managed mode may live in the sibling repo `miniti-api` (`../miniti-api` from this app repo); its `AGENTS.md` is the implementation handoff, while this repo's `docs/roadmap.md` is the sole priority index and each linked bounded plan owns its completion evidence.
- The same `MinitiTests/*.swift` sources are compiled by two bundles: `MinitiTests` (hosted by the macOS `Miniti` app, `fastlane mac test`) and `MinitiMobileTests` (hosted by `MinitiMobile`, `fastlane ios test`). Both must pass before a release. Platform-only navigation/hosting tests exist; both bundles compile the shared layer but do not have identical platform coverage. See [docs/reference/testing.md](docs/reference/testing.md).
- macOS and iOS ship independently and can sit on different versions: macOS goes live as soon as the Sparkle appcast is deployed, iOS waits on App Review. The backend's `/api/version` constants are per-platform for this reason — see `RELEASE.md` step 5.
- The release machine was replaced in July 2026 via Migration Assistant, which does not carry over signing private keys or Xcode account logins. Developer ID and Apple Distribution signing were both re-established before v2.0.0; if a future migration loses them again, see `fastlane/RUNBOOK.md` § `fastlane ios release`.
- Best manual end-to-end audio test source is the BBC World Service live stream (`https://stream.live.vc.bbcmedia.co.uk/bbc_world_service`) — continuous multi-speaker speech that exercises diarization, speaker naming, and insights. See [docs/reference/testing.md](docs/reference/testing.md) § "Manual / live testing".
- **Three clients share one backend.** `../miniti-linux` ships the same features as this app on Linux (Tauri + Rust, own version line, own `CHANGELOG.md`). Any change here to a backend contract (`/api/insights` modes or fields, headers, auth, `/api/version`), to a prompt the BYOK path copies verbatim, to the Deepgram query contract, or to a user-visible feature needs a same-day tracking issue or commit in `miniti-linux`; the auth vectors in `../miniti-api/test/fixtures/client-auth-vectors.json` are mirrored there and must stay identical. Tag changelog bullets `(macOS)`, `(iOS)`, `(macOS and iOS)`, or `(Linux)` — the website changelog splits tabs by those tags.
- **Cloud (3.0.0) lives on Neon Postgres through the Vercel Marketplace** (Frankfurt, `DATABASE_URL` injected). Minutes count per account since 3.0.0 (summed at read time, counters stay per device). Usage records are keyed by the uppercase device id the Apple apps send while auth ids are lowercase; any backend read of a `device:` record for entitlement or usage must try both spellings. The `fastlane mac release` lane does not bump the build number: set `CURRENT_PROJECT_VERSION` (pbxproj, every target) and `CFBundleVersion` (`Miniti/Info.plist`) by hand first, as RELEASE.md step 1 says, or the DMG ships with the previous build and Sparkle calls it up to date (3.1.0 had to be rebuilt for this). See [cloud reference](docs/reference/cloud-sync.md) and its linked as-built record.
- **Linux releases are separate.** `LINUX_LATEST_VERSION` / `LINUX_MIN_VERSION` on the backend are bumped from the Linux repo's release checklist (`docs/reference/distribution.md` there), not from `RELEASE.md` here; do not touch them during a Mac/iOS release.

## Delivered follow-ups and next release (2026-10-30)

Monitoring O1–O6, selective cloud privacy C1, purchase return B6d and the Settings/Help/Feedback changes shipped on macOS in 3.5.0 build 142. Backend/site are deployed; iOS build 142 is submitted, not confirmed available. [Release evidence](docs/releases/3.5.0.md) distinguishes Ian-reported QA from independently observed checks. [Contracts](docs/reference/monitoring-cloud-purchase.md) describe current behavior.

C1 UX revision (2026-10-29): no Home/pre-recording cloud checkbox. The live and saved meeting toolbars share the blue Cloud/Local control and brief confirmation; title rules still apply at creation. Add rule opens a focused editor. See the selective-cloud-privacy plan for current acceptance, including pending removal and private-mode handling.

Settings UX revision (delivered in 3.5.0): Sending is folded into Privacy; Setup, Models owns the local model inventory. Existing model choices stay in Transcription. Legacy Sending/model search links resolve to their new owners; see [Settings](docs/reference/settings.md).

Help/reporting revision (delivered in 3.5.0): expanded support details moved from Account to Help; Copy/Preview/Send share a bounded report. Default-on diagnostic inclusion exports fixed sanitized event fields (O6), never raw debug messages. Server-only recipient through Resend; see logging plan O5 and backend support contract. About acknowledgements are last and use `MinitiDisclosureStyle`.

CAM++ status must distinguish enabled voice options from a loaded model. Both voice options depend on local speaker separation; an unloaded model is not evidence the options are off. Shared status copy lives in `AppState+VoicePrints.swift`.

Release 3.5.0 build 142: Mac live, iOS submitted on 2026-10-30. Keep `IOS_LATEST_VERSION` at 3.4.0 until availability is confirmed; then update the backend and [release record](docs/releases/3.5.0.md).

Local diagnostic timeline (O6, 3.5.0): `DebugLogger.swift` owns bounded structured breadcrumbs for auth/Keychain, recording, cloud and purchase return. Help exports fixed fields rather than raw messages. Keep its code/field allowlists aligned with `../miniti-api/lib/supportReports.ts`; no new checks or repairs from logging. See the monitoring plan/reference for retention and testing limits.

Home feedback (3.5.0): bottom-right `HomeFeedbackButton` opens a minimal message/reply sheet, using Help's backend recipient without diagnostic/account data. Help and Feedback share local in-flight/cooldown and server burst/hour/day limits. `APIModeOptions` renders the two Account mode choices as separate rows on both platforms.

Review corrections (delivered 2026-10-30): private financial material at `docs/reference/monetization.md` must stay gitignored; no public links to it. Home utility buttons share `MinitiHomeActionLabel`, including lowercase `feedback`. Selective cloud actions must distinguish known/in-flight cloud copies from never-synced rows while cloud is unavailable. `RELEASE.md` makes site purchase page → additive backend → apps a hard deployment prerequisite.

3.6.0 local implementation, not released: [sync/delivery](docs/plans/sync-and-delivery-reliability.md) owns S1–S3/R5–R7 (cloud count freshness, stopped-selected upload eligibility, settled saved webhooks, immutable delivery IDs, current-data resend and saved-AI authority). Current mechanics and the held-row downgrade constraint live in [patterns](docs/reference/patterns.md#saved-ai-and-webhook-delivery-local-360-not-released) and [cloud sync](docs/reference/cloud-sync.md#local-360-implementation-not-released). The [3.6.0 checklist](docs/releases/3.6.0.md) owns test/device/release evidence. Webhooks carry the saved transcript and available summary through a small local completion marker plus the outbox; no global AI deadline or receipt archive. [Alert clarity](docs/plans/incident-alert-clarity.md) may deploy independently. Do not couple exports to optional cloud sync, infer failed upload from a stale count, or treat local implementation as shipping evidence. Linux parity is tracked in its PLAN.md, not implemented by the Swift changes.

3.6.0 review correction (2026-10-31): build 144 supersedes candidate 143. Account changes fence AI but do not cancel configured webhooks; final AI owns Update until settlement, template-only changes do not invalidate standard summaries, and deferred cloud reads must not publish successful checks. Marker-only persistence is not a cloud-content edit. See the owning plan and release record for tests and physical QA.

Hosted-test gotcha (2026-10-31): `TestRunSetup` only restores the real app defaults after normal completion. A killed test host loses its memory-only snapshot. Ian confirmed managed Pro; that mode is restored and verified, without claiming every prior preference was reconstructed. Ian subsequently waived the durable preference backup for this release validation; T01 in [test foundation](docs/plans/test-foundation.md) owns proper isolation. Never infer original settings from an older plist or print credentials.

3.6.0 device-QA fixes (2026-10-31, local/unreleased): a save debounce must not cancel an upload already running; URLSession cancellation keeps work pending without a false success/failure. Cloud removal copy names automatic retry versus settings/account gates. iOS Home opens the existing Settings sheet, never a nested Settings stack inside Home. Build 145 replaces 144 and is signed/verified locally, not published or uploaded. The final full Mac/iOS runs on `9229862` have zero failures: 1,142/1,080 executed, four/three skips respectively. Three optional WAV fixtures are absent on each platform; one Mac hardware check skipped because the tap carried audio. Ian waived the preference-backup prerequisite for this validation run. Remaining device QA and full candidate evidence belong in [release evidence](docs/releases/3.6.0.md).

Account-email CI races: wait for the actual held reconciliation response before switching accounts, then release it explicitly. A timed delay plus `accountEmailInFlight` polling is not an ordering guarantee. The 2026-10-31 test-only correction and GitHub failure evidence live in [testing](docs/reference/testing.md#account-email-ci-race-correction-2026-10-31); it does not change build-145 application binaries.

3.6.0 handoff review follow-up (2026-10-31, local/unreleased): build 145 is superseded by signed, verified local build 146. Full suites on `c570e4c`: Mac 1,154 executed/four skipped, iOS 1,092 executed/three skipped, zero failures. Nothing pushed or published. Held webhook bodies now obey the original 24-hour expiry and do not gate updates; released saved rows still do. Completion markers use a temporary SHA-256 destination fingerprint, legacy plaintext authority requires explicit retry, and cleanup follows durable release. Failed initial handoff no longer swallows History updates. See the sync/delivery plan and release record for validation and rollback evidence.
