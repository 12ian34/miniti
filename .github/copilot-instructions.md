# miniti — GitHub Copilot instructions

Start with [`README.md`](../README.md). Maintainers keep an `AGENTS.md` and a `docs/` folder with internal plans; both are gitignored and may be absent.

## Quick reference

- **Release runbook** — [`RELEASE.md`](../RELEASE.md)
- **Changelog** — [`CHANGELOG.md`](../CHANGELOG.md)
- **Visual design spec** — [`design.md`](../design.md)
- **Fastlane runbook** — [`fastlane/RUNBOOK.md`](../fastlane/RUNBOOK.md)

## Key conventions

- SwiftUI + SwiftData, Swift 6, Xcode 26.x, macOS 14.2+ / iOS 17+.
- Colors: route through `ColorPalette` in `Miniti/Models/ColorPalette.swift`. Never inline hex literals.
- State: `AppState` is the single source of truth, injected via `@EnvironmentObject`.
- Platform guards: keep `#if os()` localized. Most branching lives in `AppState.swift`.
- Hot-path: don't `.filter` `@Published` arrays in transcript-finalize callbacks; iterate `.reversed()` with a window break.
- Never call `codesign --force --sign` on a bundle with entitlements without passing `--entitlements`.
- Managed-mode auth is device-bound; never reintroduce a shared `X-API-Key`.
- Changelog entries are public-audience prose, flat `new:` / `improvement:` / `fix:` bullets, product name always lowercase. Never edit old entries.
