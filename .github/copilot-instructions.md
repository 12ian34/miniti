# miniti — GitHub Copilot instructions

Start with the tracked [`AGENTS.md`](../AGENTS.md) for current contracts and [`docs/roadmap.md`](../docs/roadmap.md) for priority. [`README.md`](../README.md) is the public introduction. Private research/financial notes remain ignored; the current agent, reference and plan docs are tracked.

## Quick reference

- **Release runbook** — [`RELEASE.md`](../RELEASE.md)
- **Changelog** — [`CHANGELOG.md`](../CHANGELOG.md)
- **Visual design spec** — [`design.md`](../design.md)
- **Fastlane runbook** — [`fastlane/RUNBOOK.md`](../fastlane/RUNBOOK.md)

## Key conventions

- SwiftUI + SwiftData, Swift 6, Xcode 27.1 locally (CI currently uses 26.6), macOS 14.2+ / iOS 17+.
- Colors: route through `ColorPalette` in `Miniti/Models/ColorPalette.swift`. Never inline hex literals.
- State: `AppState` is the single source of truth, injected via `@EnvironmentObject`.
- Platform guards: keep `#if os()` localized. Most branching lives in `AppState.swift`.
- Hot-path: don't `.filter` `@Published` arrays in transcript-finalize callbacks; iterate `.reversed()` with a window break.
- Never call `codesign --force --sign` on a bundle with entitlements without passing `--entitlements`.
- Managed-mode auth is device-bound; never reintroduce a shared `X-API-Key`.
- Changelog entries are public-audience prose, flat `new:` / `improvement:` / `fix:` bullets, product name always lowercase. Never edit old entries.

Hosted XCTest uses `Testing`, with hardware opt-in. Keep current docs in sync, use no em dashes in product copy, and preserve release authorization boundaries.
