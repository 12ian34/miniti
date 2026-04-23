# Miniti — GitHub Copilot instructions

Project context and conventions live in [AGENTS.md](../AGENTS.md) at the repo root. Treat AGENTS.md as the source of truth.

## Quick reference

- **Release runbook** — [`RELEASE.md`](../RELEASE.md)
- **Architecture (file-by-file)** — [`docs/architecture.md`](../docs/architecture.md)
- **Cross-cutting patterns** — [`docs/patterns.md`](../docs/patterns.md)
- **Audio pipeline** — [`docs/audio.md`](../docs/audio.md)
- **UI states** — [`docs/ui-states.md`](../docs/ui-states.md)
- **Backend + monetization** — [`docs/monetization.md`](../docs/monetization.md)
- **Shipping / Sparkle / notarization** — [`docs/distribution.md`](../docs/distribution.md)
- **Tests** — [`docs/testing.md`](../docs/testing.md)
- **Roadmap + research notes** — [`docs/roadmap.md`](../docs/roadmap.md)
- **Changelog** — [`CHANGELOG.md`](../CHANGELOG.md)
- **Visual design spec** — [`design.md`](../design.md)
- **Fastlane runbook** — [`fastlane/RUNBOOK.md`](../fastlane/RUNBOOK.md)

## Key conventions

- SwiftUI + SwiftData, Swift 6, Xcode 26.x, macOS 14.2+ / iOS 17+.
- Colors: route through `ColorPalette` in `Miniti/Models/ColorPalette.swift`. Never inline hex literals.
- Typography: monospaced (SF Mono macOS / Menlo iOS). Dark mode only.
- State: `AppState` is the single source of truth, injected via `@EnvironmentObject`.
- Platform guards: keep `#if os()` localized. Most branching lives in `AppState.swift`.
- Hot-path: don't `.filter` `@Published` arrays in transcript-finalize callbacks; iterate `.reversed()` with a window break.
- Never call `codesign --force --sign` on a bundle with entitlements without passing `--entitlements` (v1.24.0 postmortem in `docs/distribution.md`).
- Changelog entries are public-audience prose — no code references. Never edit old entries.

If you're changing something a doc describes, update the doc in the same PR.
