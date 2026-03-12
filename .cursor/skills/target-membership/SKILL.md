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

## File placement rules

### Shared files (macOS + iOS)

Directory: `Miniti/` (models, services, shared views).
Targets: **Miniti + MinitiMobile**.

Current shared files:
- `AppState.swift`, `Meeting.swift`, `ColorPalette.swift`
- `DeepgramService.swift`, `InsightsService.swift`, `DeviceIdentifier.swift`, `MinitiAPIService.swift`, `DebugLogger.swift`, `Secrets.swift`
- `TranscriptView.swift`, `InsightsView.swift`, `DebugLogView.swift`, `OnboardingView.swift`, `TermsAcceptanceView.swift`, `UsageBanner.swift`, `LimitReachedView.swift`
- `Assets.xcassets`

### macOS-only files

Directory: `Miniti/`.
Target: **Miniti only**.

- `MinitiApp.swift`, `AudioCaptureService.swift`, `KeyboardShortcutsService.swift`
- `MainWindow.swift`, `MeetingView.swift`, `SettingsView.swift`

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
3. **Add to `project.pbxproj`**: the file must appear in the correct target's "Compile Sources" build phase. Use the xcode skill for the mechanics.
4. **Platform guards**: if a shared file needs platform-specific behaviour, use `#if os(iOS)` / `#if os(macOS)` sparingly. Keep guards localized.

## Key design rules

- Each platform has its own `AudioCaptureService` with the same class name and public interface. AppState references it by name — no `#if os()` needed for the type.
- Shared views use `@Environment(\.horizontalSizeClass)` for responsive layout, not `#if os()`.
- `appState.modelContext` must be set from `@Environment(\.modelContext)` in the first view: `MainWindow.swift` (macOS) or `MainTabView.swift` (iOS).
