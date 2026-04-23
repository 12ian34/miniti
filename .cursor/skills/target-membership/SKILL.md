---
name: target-membership
description: >-
  Add new Swift files to the correct Xcode targets. Use when creating new Swift
  files, moving files between targets, or deciding which target a file belongs to.
---

# Target Membership

Three Xcode targets in `Miniti.xcodeproj`:

| Target | Platform | Bundle ID |
|---|---|---|
| `Miniti` | macOS | `com.miniti.app` |
| `MinitiMobile` | iOS | `com.miniti.mobile` |
| `MinitiLiveActivityExtension` | iOS | `com.miniti.mobile.live-activity` |

Plus two XCTest targets (`MinitiTests`, `MinitiMobileTests`) — see the `testing` section in [`docs/testing.md`](../../../docs/testing.md).

## File placement rules

### Shared files (macOS + iOS)

Directory: `Miniti/` (models, services, shared views).
Targets: **Miniti + MinitiMobile**.

Current shared files:

- `AppState.swift`, `Meeting.swift`, `ColorPalette.swift`
- `DeepgramService.swift`, `InsightsService.swift`, `DeviceIdentifier.swift`, `MinitiAPIService.swift`, `DebugLogger.swift`, `Secrets.swift`, `WebhookService.swift`
- `TranscriptView.swift`, `InsightsView.swift`, `DebugLogView.swift`, `OnboardingView.swift`, `TermsAcceptanceView.swift`, `ForceUpdateView.swift`, `UsageBanner.swift`, `LimitReachedView.swift`
- `Assets.xcassets`

### macOS-only files

Directory: `Miniti/`.
Target: **Miniti only**.

- `MinitiApp.swift`, `AudioCaptureService.swift`, `KeyboardShortcutsService.swift`
- `MainWindow.swift`, `MeetingView.swift`, `SettingsView.swift`
- **`UpdateService.swift`** — Sparkle wrapper, guarded by `#if os(macOS) && canImport(Sparkle)`. Must be added to the Miniti target only — adding it to MinitiMobile breaks the iOS build because Sparkle isn't iOS-compatible. When creating this file (or any new macOS-only Swift file) via the CLI, remember to add it to the Xcode target membership in the GUI: right-click `Miniti/Services` in the Project Navigator → Add Files to "miniti"… → Copy items OFF, Add to targets: Miniti ON, all others OFF.

### iOS-only files

Directory: `MinitiMobile/`.
Target: **MinitiMobile only**.

- `MinitiApp_iOS.swift`, `AudioCaptureService_iOS.swift`
- `MainTabView.swift`, `MeetingView_iOS.swift`, `SettingsView_iOS.swift`, `HistoryView_iOS.swift`
- `Info.plist`, `MinitiMobile.entitlements`

### Live Activity extension

Directory: `MinitiLiveActivity/` and `Shared/`.
Target: **MinitiLiveActivityExtension only** (plus shared attributes).

- `MinitiLiveActivityBundle.swift`, `MinitiLiveActivityLiveActivity.swift`, `Info.plist`
- `RecordingActivityAttributes.swift` — shared between **MinitiMobile + MinitiLiveActivityExtension** (not macOS)

## When creating a new file

1. **Decide the scope**: does it apply to macOS only, iOS only, or both?
2. **Place in the right directory**:
   - Shared → `Miniti/Models/`, `Miniti/Services/`, or `Miniti/Views/`
   - iOS-only → `MinitiMobile/` or `MinitiMobile/Views/`
   - macOS-only → `Miniti/` (alongside existing macOS-only files)
3. **Add to `project.pbxproj`**: the file must appear in the correct target's "Compile Sources" build phase. The safest path is Xcode GUI (Add Files to "miniti"…). Editing pbxproj by hand is possible but error-prone.
4. **Platform guards**: if a shared file needs platform-specific behaviour, use `#if os(iOS)` / `#if os(macOS)` sparingly. Keep guards localized.
5. **SPM dependencies**: if the file imports a package that's macOS-only (e.g. `Sparkle`), guard with `#if canImport(PackageName)` so the iOS build still succeeds even if the dep is ever removed or restricted.

## Key design rules

- Each platform has its own `AudioCaptureService` with the same class name and public interface. AppState references it by name — no `#if os()` needed for the type.
- Shared views use `@Environment(\.horizontalSizeClass)` for responsive layout, not `#if os()`.
- `appState.modelContext` must be set from `@Environment(\.modelContext)` in the first view: `MainWindow.swift` (macOS) or `MainTabView.swift` (iOS).
- For the full architecture reference (every file's purpose + target membership), see [`docs/architecture.md`](../../../docs/architecture.md).

## "Cannot find 'X' in scope" when building

A common symptom: you created a file on disk (via CLI/editor), it compiles fine on its own, but a view or other file in the same target shows "Cannot find 'X' in scope". Cause: the file wasn't added to the Xcode target's "Compile Sources" build phase. Fix: add it via the Xcode GUI as described above.
