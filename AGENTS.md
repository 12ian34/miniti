# Miniti

macOS + iOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio (macOS) or mic-only (iOS), streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI. Three tiers: free managed (500 min/month), pro managed ($5/month, 5000 min/month), or BYOK (own API keys, unlimited). Pro purchase rail is platform-specific: Polar.sh on macOS and StoreKit auto-renewable subscription on iOS.

This file is the canonical entry point for AI coding agents working on Miniti. It points at focused docs for each concern. Don't dump new long-form prose here — add it to the right `docs/*.md` instead.

## Tech stack

- SwiftUI + SwiftData (macOS 14.2+ / iOS 17+)
- Xcode 26.x, Swift 6 concurrency
- Deepgram Nova-3 streaming (WebSocket)
- Optional on-device speaker diarization: NVIDIA Nemotron-3-Diarization via the FluidAudio Swift package (Core ML, Apple silicon), default off, replaces Deepgram's diarizer per word when active. Optional on-device transcription (2.12.0, macOS, default off): NVIDIA Nemotron 3.5 ASR Streaming Multilingual 0.6B through the same package, downloaded on demand (not bundled), replaces the Deepgram socket for the session when active. The 190 MB model is bundled: `scripts/fetch-nemotron-model.sh` (pinned, checksummed) fills the gitignored `Miniti/Resources/NemotronDiarizer/` as the first build phase of both app targets
- TypeSafe Jev (`jev-1.13.0`) through the managed `/api/classify` proxy for attendee speaker naming and the sales nudge, opt-in (`jevClassifierEnabled`, default off), never generates text; GPT and the phrase heuristics remain the fallback
- OpenAI insights: managed incremental updates, speaker naming, catch-up, and Playbook topic extraction use pinned `gpt-5-mini-2025-08-07`; managed non-incremental summaries, MEDDPICC, questions, grounded Playbook answers, and investigations use pinned `gpt-5.4-mini-2026-03-17`; BYOK uses pinned `gpt-5-mini-2025-08-07` except investigations, which use pinned `gpt-5.4-mini-2026-03-17`
- Vercel + Upstash Redis backend (`miniti-api`)
- Sparkle 2.9.5 for macOS auto-update; StoreKit 2 + Polar.sh for purchase rails
- Netlify Blobs for DMG hosting

## Targets

- **Miniti** — macOS app (`com.miniti.app`)
- **MinitiMobile** — iOS app (`com.miniti.mobile`)
- **MinitiLiveActivityExtension** — iOS widget extension (`com.miniti.mobile.live-activity`)
- **MinitiTests** / **MinitiMobileTests** — XCTest (same source files, different host app)

## Where to find things

| I need to… | Read |
|---|---|
| Ship a new version | [RELEASE.md](RELEASE.md) (the 10-step runbook) |
| Regenerate App Store / marketing screenshots for iOS, iPad, and macOS | [scripts/screenshots/README.md](scripts/screenshots/README.md) (real-app captures via the `-MinitiScreenshotScene` launch argument, framed by `render_frames.py`) |
| Understand a specific file | [docs/architecture.md](docs/architecture.md) |
| Understand a cross-file pattern (hot paths, watchdogs, save queues, recovery) | [docs/patterns.md](docs/patterns.md) |
| Work on the audio pipeline | [docs/audio.md](docs/audio.md) |
| Work on UI (home, recording, stopped, history, settings) | [docs/ui-states.md](docs/ui-states.md) |
| Touch backend / monetization / pricing | [docs/monetization.md](docs/monetization.md) |
| Understand how we ship (Sparkle, notarization, entitlements) | [docs/distribution.md](docs/distribution.md) |
| Understand the test layout | [docs/testing.md](docs/testing.md) |
| See the single prioritized product, engineering, reliability, and platform plan | [docs/roadmap.md](docs/roadmap.md) |
| Work on the Linux desktop rewrite (separate repo) | [`../miniti-linux`](../miniti-linux) — start at `AGENTS.md` / `PLAN.md` (Tauri 2 + Rust, binary + AUR; not in this tree) |
| Plan Apple Watch meeting recording | [docs/apple-watch-plan.md](docs/apple-watch-plan.md) (planned 2026-10-18, not built: record offline using the watch microphone, transfer to the paired iPhone, generate notes afterwards) |
| Review the evidence-validated structural simplification audit | [docs/structural-simplification-audit-2026-08-16.md](docs/structural-simplification-audit-2026-08-16.md) |
| Revisit local Apple Foundation Models or MLX for insights | [docs/local-ai-research.md](docs/local-ai-research.md) |
| Change on-device transcription (Nemotron 3.5 streaming via FluidAudio), its language tiers, utterance assembly, or the local session path in `DeepgramService` | [docs/local-transcription-plan.md](docs/local-transcription-plan.md) (built 2026-10-09 for 2.12.0 behind a default-off macOS setting; status table) |
| Evaluate local transcription engines (Nemotron 3.5 streaming via FluidAudio, Apple SpeechTranscriber, WhisperKit, Gemma 4) | [docs/local-transcription-research.md](docs/local-transcription-research.md) (research and offline engine comparison 2026-10-09: Nemotron live, Parakeet finaliser, Apple for iOS later; nothing built) + [scripts/transcription-poc/RESULTS.md](scripts/transcription-poc/RESULTS.md) |
| Change the Jev classifier (attendee speaker naming, sales nudge via `/api/classify`), its thresholds, or its fallbacks | [docs/jev-system-one-plan.md](docs/jev-system-one-plan.md) (eval 2026-09-21; slice 1 built 2026-09-25 behind a default-off setting; status table, question versions, jaggedness rules) |
| Change on-device speaker separation (Nemotron-3 via FluidAudio), its Deepgram fallback, or the word-to-speaker mapping | [docs/on-device-diarization-plan.md](docs/on-device-diarization-plan.md) (built 2026-09-25 behind a default-off setting; status table) + [scripts/diarization-poc/RESULTS.md](scripts/diarization-poc/RESULTS.md) (the offline POC behind it) |
| Change call detection, Smart meetings, auto-start/stop settings, recording indicators, or macOS reopen behavior | [docs/call-lifecycle-and-recording-presence-plan.md](docs/call-lifecycle-and-recording-presence-plan.md) (shipped call-lifecycle regression contract) + [docs/smart-meetings-plan.md](docs/smart-meetings-plan.md) (original silence/calendar regression contract) |
| Change shared-microphone diarization or automatic in-room/hybrid inference | [docs/automatic-in-room-diarization-plan.md](docs/automatic-in-room-diarization-plan.md) |
| Read backend admin stats (cost, revenue, MRR, devices, usage, client errors) from a terminal or a bot without the dashboard | [docs/admin-stats-access-plan.md](docs/admin-stats-access-plan.md) (built 2026-10-15: `../miniti-api/scripts/admin-stats.mjs` plus the `admin-stats` skill; read-only `ADMIN_READ_TOKEN` deployed 2026-10-15 for Grok Bot via `scripts/admin-stats-curl.md`; no MCP by decision) |
| Change cloud sync, the sync document, Settings → Cloud, web sign-in, tokens, the REST API or the MCP server | [docs/cloud-sync-plan.md](docs/cloud-sync-plan.md) (built 2026-10-15 for 3.0.0, status table) + [`../miniti-api/docs/agents/08-cloud.md`](../miniti-api/docs/agents/08-cloud.md) (the contract) + [docs/patterns.md](docs/patterns.md) § "Cloud sync" |
| Change settings navigation, categories, or search | [docs/settings-redesign-plan.md](docs/settings-redesign-plan.md) (2.12.0 hierarchy: Setup, Meetings, Connections, Privacy, Support; Cloud joined Setup in 3.0.0; single-word tabs; `SettingsGroup`) |
| See what shipped in which version | [CHANGELOG.md](CHANGELOG.md) (+ `fastlane/metadata/en-US/release_notes.txt` per release) |
| Understand visual language / tokens | [design.md](design.md) |
| Use / debug Fastlane specifically | [fastlane/RUNBOOK.md](fastlane/RUNBOOK.md) |

There is no `README.md` in this repo — end-user documentation lives at `https://miniti.app/docs` and the public-facing changelog at `https://miniti.app/changelog`. This file (`AGENTS.md`) is the dev-facing entry point.

## Features (user-facing)

### macOS — native AI meeting assistant

- mic + system audio recording, with a microphone picker (Home mic pill and Settings → Recording) so earphones connecting do not silently move recording off a desk mic
- live transcription with deepgram, including distinct in-room speakers sharing the Mac microphone alongside remote/system speakers
- live speaker identification + automatic speaker naming (infers real names from the transcript; uses calendar attendees as hints when connected)
- optional on-device speaker separation (Settings → Transcription, Speakers: This Mac): Nemotron-3 diarization on Apple silicon replaces Deepgram's diarizer for new recordings; falls back to Deepgram whenever the model is unavailable
- private mode (Settings → Privacy, 2.12.0, Apple silicon): one switch that turns on both on-device engines and turns off every cloud AI feature (summaries, questions, Sales, templates, catch-up, speaker names, Jev, Playbook, investigations), restoring the previous choices when switched off; cloud-only languages cannot record while it is on; managed limit does not gate a private meeting
- optional on-device transcription (Settings → Transcription, Transcription: This Mac, 2.12.0): Nemotron 3.5 streaming recognition on Apple silicon replaces the Deepgram socket for new recordings in 8 of the 11 languages; a 590 or 640 MB model downloads on first enable; no minutes metered; a start with the model missing is refused unless Deepgram fallback for that meeting is allowed
- optional Jev classifier (managed only, Settings → AI, Speaker names: Jev): attendee speaker naming and the sales-conversation suggestion answered by TypeSafe Jev through `/api/classify` in under a second; GPT and the phrase list take over on any failure
- live AI-generated summaries and action items
- optional live Sales analysis using MEDDPICC (enabled from the specialist insights menu, with a local default-on suggestion when a conversation sounds commercial)
- optional Templates view — structured notes filled live from a built-in template (BANT, SPIN, interview scorecard, customer check-in, stand-up, 1:1) or your own; chosen per meeting from the insights More menu (one flat list with Sales, then Playbook; the tab remembers the pick for the meeting), refilled on a Sales-like cadence and at finalization, persisted on the meeting, and included in markdown exports and webhooks. Settings → Templates drafts a template from a one-line description (2.12.0, managed `template_draft` or BYOK OpenAI)
- questions mode — AI-generated incisive questions to ask during or after a meeting (deeper, challenge, reframe, clarify, explore, follow-up)
- optional Playbook view — docs-MCP cards with citations (configure MCP URL in Settings; automatic topic lookup for Pro/BYOK, manual metered lookup for managed-free)
- coaching mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- google calendar integration — upcoming meetings across coming days, event prep notes carried into live notes, auto-fill title and attendees, auto Attio or Twenty CRM sync; adjustable meeting filters (out of office, focus time, all-day, declined, no guests or meeting link, title prefixes) with a next-7-days preview in Settings → Calendar
- local conversation-moment detection with explicit in-app OpenAI web or codebase investigation; it never runs an investigation automatically
- saved-meeting CRM export to Attio or Twenty with a task preview, deadlines/assignment details, and per-task inclusion controls
- Granola CSV import with duplicate protection and source labels
- grouped, pinnable meeting history browser
- saved transcript trimming with insight regeneration
- native menu bar controls with an elapsed recording timer, plus a floating call/recording surface that raises for every start, recording, ending, quiet, and calendar-handoff decision and carries foreground question/coaching nudges
- keyboard shortcuts for common recording and navigation actions
- default-on Smart meetings prompts for likely-ended recordings and safe calendar handoffs (join next / end & start next / end meeting / keep recording / remind), independently switchable from existing auto-start/stop
- managed account: anonymous recovery key, up to 5 devices, Pro follows the account (a sponsored device shows "Pro comes from another device"), move this device to another account
- outbound webhooks over https only (loopback excepted), hook URLs never logged; Share Diagnostics on by default in managed mode
- cloud (3.0.0, Pro only, default off, Settings → Cloud): finished meetings synced across every device on the account through miniti's servers (Neon Postgres); optional email for web sign-in and new-device sign-in by approval link; personal access tokens for the read-only REST API and the MCP server (Claude Code, Cursor) and OAuth for Claude.ai and ChatGPT connectors; per-meeting "Keep off the cloud"; meetings recorded under private mode never sync; delete cloud copy
- in-app auto-update via Sparkle (Miniti menu → Check for Updates…)

### iOS — mobile AI meeting assistant

- mic recording with background support
- live transcription with deepgram, including multiple speakers sharing the device microphone
- automatic speaker naming (infers real names from the transcript; uses calendar attendees as hints when connected)
- optional on-device speaker separation (Settings → Transcription, Speakers: This device): Nemotron-3 diarization on the phone replaces Deepgram's diarizer for new recordings; falls back to Deepgram whenever the model is unavailable
- live AI-generated summaries and action items
- optional live Sales analysis using MEDDPICC (enabled from the specialist insights menu, with a local default-on suggestion when a conversation sounds commercial)
- optional Templates view — structured notes filled live from a built-in template (BANT, SPIN, interview scorecard, customer check-in, stand-up, 1:1) or your own; chosen per meeting from the insights More menu (flat list, remembers the pick), refilled on a Sales-like cadence and at finalization, persisted on the meeting, and included in markdown exports and webhooks. Settings → Templates drafts a template from a one-line description (2.12.0)
- questions mode — AI-generated incisive questions to ask during or after a meeting
- optional Playbook view — docs-MCP cards with citations (configure MCP URL in Settings; automatic topic lookup for Pro/BYOK, manual metered lookup for managed-free)
- coaching mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- google calendar integration — upcoming meetings across coming days, event prep notes carried into live notes, auto-start countdown, attendee context in insights; adjustable meeting filters with a next-7-days preview in Settings → Calendar
- local conversation-moment detection with explicit in-app OpenAI web research; it never runs an investigation automatically
- Granola CSV import with duplicate protection and source labels
- grouped, pinnable meeting history browser
- saved transcript trimming with insight regeneration
- Live Activity on Dynamic Island and Lock Screen (timer + optional live transcript, with tap-through to the active meeting)
- default-on Smart meetings prompts for likely-ended recordings and safe calendar handoffs (join next / end & start next / end meeting / keep recording / remind), independently switchable from existing auto-start/stop
- managed account: anonymous recovery key, up to 5 devices, Pro follows the account, move this device to another account
- outbound webhooks over https only; Share Diagnostics on by default in managed mode
- cloud (3.0.0, Pro only, default off, Settings → Cloud): the same sync, web sign-in, tokens and connected apps as macOS
- dark mode terminal-style UI

## Non-negotiable conventions

- **Design tokens**: all colors route through `ColorPalette` in [Miniti/Models/ColorPalette.swift](Miniti/Models/ColorPalette.swift). Never hardcode hex literals in view code. See [design.md](design.md) for the full spec (typography, spacing, components, contrast).
- **Design system**: shared spacing, radius, control, motion, opacity, semantic control roles, navigation copy, and content-accent contracts live in `MinitiDesignSystem`; compact controls use `MinitiControlLabel`, while mutually exclusive views use the lowercase neutral `MinitiTabLabel` / `MinitiTabStripSurface` pair. Equal-width segmented strips set `fillsAvailableWidth` so every label surface and hit target occupies its full segment. Coaching metric taxonomy lives in `ColorPalette.Coaching` and must stay consistent across live, history, overview, examples, and charts without reusing CTA/status colors. The Coaching overview separates focus/trends, aggregate stats, and meeting history into lowercase `focus` / `stats` / `history` tabs; its stats include all six Coaching metrics, keep each metric plus unit on one line, show the metric explanation inline below rather than behind an info icon, and use success/error/neutral status colours for semantically good/bad/neutral changes. Historical metrics use six separate cards directly below the uninterrupted comparison table; each chart keeps its own metric scale, numeric y-axis, and adaptive meeting-sequence x-axis with plain numeric ticks under a centred `meeting` label rather than combining incompatible units or using elapsed calendar time. `CoachingLayout` owns its 720pt reading/stats-column, platform chart height, and 480pt compact-column bounds, `CoachingTypography` owns its desktop reading-size step, trend sections sit directly on the background with `MinitiFadingDivider`, grounded examples alone retain content-sized hover cards without disclosure chevrons, copy does not truncate, and grounded examples keep the label/quote together at left with a right-aligned meeting title over a date-only line. macOS back/forward swipe thresholds and the neutral edge progress cue use the shared `NavigationGesture` contract. Preserve native `Button` / `Menu` ownership of actions, focus, disabled state, shortcuts, and accessibility. Do not pass arbitrary feature colors into ordinary controls or fork shared component measurements inside feature views.
- **Typography**: Apple system font for readable prose, controls, and primary Home / Coaching / History navigation. The `miniti` lockup retains the original monospaced identity; timers/counters use monospaced digits. Transcript and insight prose share the same platform-specific size at every interface scale. Dark mode only.
- **Accessibility + adaptation**: app-authored animations must respect Reduce Motion. iPhone keeps the compact tab bar; regular-width iPad uses adaptive sidebar navigation. New visual materials are limited to functional system surfaces and must preserve contrast.
- **State**: `AppState` is the single source of truth, injected via `@EnvironmentObject`. Transient high-frequency UI signals live in `AudioLevelsState` / `TranscriptRuntimeState` to avoid invalidating the whole `AppState` on every sample.
- **Platform guards**: keep `#if os()` localized. Most branching is in `AppState.swift`; each target compiles its own `AudioCaptureService` with the same class name + public interface.
- **Model context wiring**: `appState.modelContext` must be set from `@Environment(\.modelContext)` in the first view that appears (`MainWindow.swift` on macOS, `MainTabView.swift` on iOS). Without it, `saveCurrentMeetingIfNeeded()` silently no-ops.
- **Hot-path performance**: never `.filter` `@Published` arrays in callbacks that fire on every transcript finalize (grows unboundedly). Iterate `.reversed()` and break on window expiry. See [docs/patterns.md](docs/patterns.md) § "Performance / hot-path rules".
- **Changelog style**: public-audience prose, no code refs. Never edit old entries unless the user explicitly requests a historical correction. Release headers are date + version only; platform availability belongs in bullets, never parenthetical header status. One flat bullet list per release with `new:` / `improvement:` / `fix:` prefixes, never sub-headers like "New features" or "Experience improvements". The product name is always lowercase (miniti). Write bullets in Ian's voice: short plain sentences, specific numbers, simple verbs, no em dashes, no "not X, it's Y", no bold, no exclamation marks. Rules and examples live in the project `changelog` skill (`.claude/skills/changelog/SKILL.md`, gitignored because the repo is public); the fuller voice guide is `../gtm/enablement/ian-tone-of-voice.md`. The changelog file itself holds entries only, no style section.
- **Managed-mode auth is device-bound** (`Miniti/Services/ClientAuth.swift`): a per-install P-256 key (Secure Enclave when available) plus an anonymous recovery key; `MinitiAPIService.send(_:)` attaches the bearer token and an ES256 `X-Request-Proof` on writes. No shared backend secret exists in the app; never reintroduce an `X-API-Key`. Existing installs migrate silently via `/api/auth/migrate` (`AppState.ensureManagedEnrollment`). An enrolled install moves to another account with `POST /api/auth/account/attach` (`ClientAuthManager.attachToAccount`, rewrites key/account/tokens in place, never signs out); Pro sponsorship arrives as `entitlement_via_account` on `/api/usage`. The Swift prompt/vector contract is shared with `../miniti-api` (`test/fixtures/client-auth-vectors.json`) and `../miniti-linux`.
- **macOS is shipped sandboxed** — `com.apple.security.app-sandbox` + audio-input + network + user-files entitlements. Don't call `codesign --force --sign` on a bundle that has entitlements without also passing `--entitlements` (that's what caused the v1.24.0 history-wipe regression — postmortem in [docs/distribution.md](docs/distribution.md)). Sparkle also needs `SUEnableInstallerLauncherService = true` plus `com.miniti.app-spks` / `com.miniti.app-spki` mach lookup exceptions, or sandboxed installs fail after download with `Failed copying system domain rights: -60005`. Keep Sparkle at 2.9.3+ (currently 2.9.5): older 2.9.1 collides with the `.app` suffix in Miniti's bundle ID and can trigger a first-attempt macOS security denial.

## Repo layout

```
AGENTS.md                          # This file — canonical entry point for agents
.cursor/rules/project.mdc          # Cursor rule that references AGENTS.md
.github/copilot-instructions.md    # GitHub Copilot shim
RELEASE.md                         # 10-step release runbook
CHANGELOG.md                       # Public-facing release history
design.md                          # Visual design spec
docs/
  architecture.md                  # File-by-file map
  patterns.md                      # Cross-cutting conventions
  audio.md                         # Audio pipeline + recovery
  ui-states.md                     # Per-platform UI states
  monetization.md                  # Commercial model + backend API
  distribution.md                  # Sparkle, notarization, entitlements
  testing.md                       # XCTest layout and coverage
  roadmap.md                       # Canonical prioritized future-work plan + operational watchlist
  structural-simplification-audit-2026-08-16.md # Evidence-validated structural audit and implementation risks
  local-ai-research.md             # On-device Foundation Models, MLX, costs, compatibility, and rollout research
  local-transcription-research.md  # Local live transcription candidates, language coverage, costs, and the recommended spike (2026-10-09)
  local-transcription-plan.md      # Nemotron 3.5 on-device transcription (built 2026-10-09 for 2.12.0, default off, macOS) and its status table
  jev-system-one-plan.md           # TypeSafe Jev: eval, jaggedness rules, and slice 1 (speaker naming + sales nudge, built, default off)
  on-device-diarization-plan.md    # Nemotron-3 on-device speaker separation (built, default off) and how Jev composes with it
  automatic-in-room-diarization-plan.md # Cloud mic diarization + automatic environment inference
  cloud-sync-plan.md               # Optional cloud sync, storage, REST API and MCP server (built 2026-10-15 for 3.0.0; status table)
  admin-stats-access-plan.md       # Admin stats from the terminal (script + skill, built) and Grok Bot (read token, deployed 2026-10-15); no MCP
Miniti/                            # macOS target source
MinitiMobile/                      # iOS target source
MinitiLiveActivity/                # Widget extension source
Shared/                            # RecordingActivityAttributes (iOS app + extension)
MinitiTests/                       # XCTest sources (shared by both test targets)
fastlane/                          # Fastlane config + RUNBOOK
scripts/                           # build-dmg.sh, release-info.sh, dmg-background.png
  screenshots/                     # Marketing screenshot pipeline (build → capture → frame); README.md is the runbook
  diarization-poc/                 # Nemotron-3-Diarization vs Deepgram offline eval (Python, gitignored venv/data/out)
  transcription-poc/               # Nemotron 3.5 / Apple / Parakeet vs Deepgram offline transcription eval (Swift harness + Python scoring, gitignored data/out)
ANDROID_PLAN.md                    # Exploratory Android port plan (not started)
```

## When in doubt

1. Read [docs/patterns.md](docs/patterns.md) first — it catches most "why is this like this?" questions.
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
- Settings tabs are single words, one question per tab, grouped Setup / Meetings / Connections / Privacy / Support (Cloud sits in Setup under Account since 3.0.0); model choices are "Deepgram" or "This Mac" pickers, never model names in the control. Privacy and Support are separate; About is the support tab.
- Do not label Jev or the Nemotron models as beta. Insight menus show names only, with a settings link at the bottom, never "Name — description".
- Normal updates should not appear as home-screen banners: macOS uses Sparkle and iOS uses the App Store. Keep `/api/version` only for the minimum-version force-update gate.

## Learned workspace facts

- Backend changes for managed mode may live in the sibling repo `miniti-api` (`../miniti-api` from this app repo); its `AGENTS.md` is the implementation handoff, while this repo's `docs/roadmap.md` is the sole cross-repository plan and completion tracker.
- The same `MinitiTests/*.swift` sources are compiled by two bundles: `MinitiTests` (hosted by the macOS `Miniti` app, `fastlane mac test`) and `MinitiMobileTests` (hosted by `MinitiMobile`, `fastlane ios test`). Both must pass before a release. iOS-only source files still have no dedicated tests — the iOS bundle covers the shared layer compiled against the iOS target. See [docs/testing.md](docs/testing.md).
- macOS and iOS ship independently and can sit on different versions: macOS goes live as soon as the Sparkle appcast is deployed, iOS waits on App Review. The backend's `/api/version` constants are per-platform for this reason — see `RELEASE.md` step 5.
- The release machine was replaced in July 2026 via Migration Assistant, which does not carry over signing private keys or Xcode account logins. Developer ID and Apple Distribution signing were both re-established before v2.0.0; if a future migration loses them again, see `fastlane/RUNBOOK.md` § `fastlane ios release`.
- Best manual end-to-end audio test source is the BBC World Service live stream (`https://stream.live.vc.bbcmedia.co.uk/bbc_world_service`) — continuous multi-speaker speech that exercises diarization, speaker naming, and insights. See [docs/testing.md](docs/testing.md) § "Manual / live testing".
- **Three clients share one backend.** `../miniti-linux` ships the same features as this app on Linux (Tauri + Rust, own version line, own `CHANGELOG.md`). Any change here to a backend contract (`/api/insights` modes or fields, headers, auth, `/api/version`), to a prompt the BYOK path copies verbatim, to the Deepgram query contract, or to a user-visible feature needs a same-day tracking issue or commit in `miniti-linux`; the auth vectors in `../miniti-api/test/fixtures/client-auth-vectors.json` are mirrored there and must stay identical. Tag changelog bullets `(macOS)`, `(iOS)`, `(macOS and iOS)`, or `(Linux)` — the website changelog splits tabs by those tags.
- **Cloud (3.0.0) lives on Neon Postgres through the Vercel Marketplace** (Frankfurt, `DATABASE_URL` injected). Minutes count per account since 3.0.0 (summed at read time, counters stay per device). Usage records are keyed by the uppercase device id the Apple apps send while auth ids are lowercase; any backend read of a `device:` record for entitlement or usage must try both spellings. The `fastlane mac release` lane bumps the build number. See `docs/cloud-sync-plan.md` § "As built".
- **Linux releases are separate.** `LINUX_LATEST_VERSION` / `LINUX_MIN_VERSION` on the backend are bumped from the Linux repo's release checklist (`docs/distribution.md` there), not from `RELEASE.md` here; do not touch them during a Mac/iOS release.
