# Miniti

macOS + iOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio (macOS) or mic-only (iOS), streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI. Three tiers: free managed (500 min/month), pro managed ($5/month, 5000 min/month), or BYOK (own API keys, unlimited). Pro purchase rail is platform-specific: Polar.sh on macOS and StoreKit auto-renewable subscription on iOS.

This file is the canonical entry point for AI coding agents working on Miniti. It points at focused docs for each concern. Don't dump new long-form prose here — add it to the right `docs/*.md` instead.

## Tech stack

- SwiftUI + SwiftData (macOS 14.2+ / iOS 17+)
- Xcode 26.x, Swift 6 concurrency
- Deepgram Nova-3 streaming (WebSocket)
- OpenAI `gpt-5-mini` for insights (MEDDPICC / questions / summaries)
- Vercel + Upstash Redis backend (`miniti-api`)
- Sparkle 2 for macOS auto-update; StoreKit 2 + Polar.sh for purchase rails
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
| Understand a specific file | [docs/architecture.md](docs/architecture.md) |
| Understand a cross-file pattern (hot paths, watchdogs, save queues, recovery) | [docs/patterns.md](docs/patterns.md) |
| Work on the audio pipeline | [docs/audio.md](docs/audio.md) |
| Work on UI (home, recording, stopped, history, settings) | [docs/ui-states.md](docs/ui-states.md) |
| Touch backend / monetization / pricing | [docs/monetization.md](docs/monetization.md) |
| Understand how we ship (Sparkle, notarization, entitlements) | [docs/distribution.md](docs/distribution.md) |
| Understand the test layout | [docs/testing.md](docs/testing.md) |
| Check upcoming work / research notes | [docs/roadmap.md](docs/roadmap.md) |
| See what shipped in which version | [CHANGELOG.md](CHANGELOG.md) (+ `fastlane/metadata/en-US/release_notes.txt` per release) |
| Understand visual language / tokens | [design.md](design.md) |
| Use / debug Fastlane specifically | [fastlane/RUNBOOK.md](fastlane/RUNBOOK.md) |

There is no `README.md` in this repo — end-user documentation lives at `https://miniti.app/docs` and the public-facing changelog at `https://miniti.app/changelog`. This file (`AGENTS.md`) is the dev-facing entry point.

## Features (user-facing)

### macOS — native AI meeting assistant

- mic + system audio recording
- live transcription with deepgram
- live speaker identification + automatic speaker naming (infers real names from the transcript; uses calendar attendees as hints when connected)
- live AI-generated summaries and action items
- live MEDDPICC analysis
- questions mode — AI-generated incisive questions to ask during or after a meeting (deeper, challenge, reframe, clarify, explore, follow-up)
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- google calendar integration — upcoming meetings, auto-fill title and attendees, auto Attio sync
- meeting history browser
- native menu bar controls
- keyboard shortcuts for everything
- in-app auto-update via Sparkle (Miniti menu → Check for Updates…)

### iOS — mobile AI meeting assistant

- mic recording with background support
- live transcription with deepgram
- automatic speaker naming (infers real names from the transcript; uses calendar attendees as hints when connected)
- live AI-generated summaries and action items
- live MEDDPICC analysis
- questions mode — AI-generated incisive questions to ask during or after a meeting
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- google calendar integration — upcoming meetings on home, auto-start countdown, attendee context in insights
- meeting history browser
- Live Activity on Dynamic Island and Lock Screen (timer + live transcript)
- dark mode terminal-style UI

## Non-negotiable conventions

- **Design tokens**: all colors route through `ColorPalette` in [Miniti/Models/ColorPalette.swift](Miniti/Models/ColorPalette.swift). Never hardcode hex literals in view code. See [design.md](design.md) for the full spec (typography, spacing, components, contrast).
- **Typography**: monospaced throughout (SF Mono on macOS, Menlo on iOS). Dark mode only.
- **State**: `AppState` is the single source of truth, injected via `@EnvironmentObject`. Transient high-frequency UI signals live in `AudioLevelsState` / `TranscriptRuntimeState` to avoid invalidating the whole `AppState` on every sample.
- **Platform guards**: keep `#if os()` localized. Most branching is in `AppState.swift`; each target compiles its own `AudioCaptureService` with the same class name + public interface.
- **Model context wiring**: `appState.modelContext` must be set from `@Environment(\.modelContext)` in the first view that appears (`MainWindow.swift` on macOS, `MainTabView.swift` on iOS). Without it, `saveCurrentMeetingIfNeeded()` silently no-ops.
- **Hot-path performance**: never `.filter` `@Published` arrays in callbacks that fire on every transcript finalize (grows unboundedly). Iterate `.reversed()` and break on window expiry. See [docs/patterns.md](docs/patterns.md) § "Performance / hot-path rules".
- **Changelog style**: public-audience prose, no code refs. Never edit old entries. See [CHANGELOG.md](CHANGELOG.md) for the format.
- **macOS is shipped sandboxed** — `com.apple.security.app-sandbox` + audio-input + network + user-files entitlements. Don't call `codesign --force --sign` on a bundle that has entitlements without also passing `--entitlements` (that's what caused the v1.24.0 history-wipe regression — postmortem in [docs/distribution.md](docs/distribution.md)).

## Repo layout

```
AGENTS.md                          # This file — canonical entry point for agents
CLAUDE.md                          # Same content for Claude Code compatibility
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
  roadmap.md                       # Forward-looking work
Miniti/                            # macOS target source
MinitiMobile/                      # iOS target source
MinitiLiveActivity/                # Widget extension source
MinitiTests/                       # XCTest sources (shared by both test targets)
fastlane/                          # Fastlane config + RUNBOOK
scripts/                           # build-dmg.sh, release-info.sh, dmg-background.png
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
- For the update-available banner (and similar surfaces): make expand/collapse obvious, keep type large enough to read, and style download/update as a clear primary button — not tiny body text or ambiguous links.

## Learned workspace facts

- Backend changes for managed mode may live in the sibling repo `miniti-api` (`../miniti-api` from this app repo); its CLAUDE.md is the handoff when the user says the API was updated.
- The `MinitiTests` XCTest bundle is hosted by the macOS `Miniti` app; `fastlane mac test` runs it. Shared Swift is exercised there, but iOS-only code is not covered by a separate unit test target unless one is added.
