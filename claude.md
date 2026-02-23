# Miniti

macOS + iOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio (macOS) or mic-only (iOS), streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI. Two modes: managed (500 free min/month) or BYOK (own API keys, unlimited).

## Features

### macOS — native AI meeting assistant

- mic + system audio recording
- live transcription with deepgram
- live speaker identification
- live AI-generated summaries and action items
- live MEDDPICC analysis
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- meeting history browser
- native menu bar controls
- keyboard shortcuts for everything

### iOS — mobile AI meeting assistant

- mic recording with background support
- live transcription with deepgram
- live AI-generated summaries and action items
- live MEDDPICC analysis
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- meeting history browser
- Live Activity on Dynamic Island and Lock Screen (timer + live transcript)
- dark mode terminal-style UI

## Changelog

### 2026-02-23 - v1.8.1 (current)

- Fix audio cutting out when Bluetooth headphones switch modes mid-session (e.g. AirPods joining a Zoom call)
- Filler words like "um" and "uh" now appear in transcripts and get counted in training mode
- Training mode shows per-word filler frequency sorted by count for each speaker; grouped "others" shows totals only
- On iOS, each speaker's filler breakdown shown individually (no artificial grouping without a "You" speaker)
- MEDDPICC tab shows only MEDDPICC fields — no more summary, actions, or topics mixed in
- MEDDPICC fields displayed as clean separate sections with consistent styling across all views on both platforms
- MEDDPICC section labels cleaned up — lowercase with spaces instead of underscores
- MEDDPICC tab added to macOS meeting history
- Save and discard buttons on macOS stopped recordings (matching iOS)
- Discussion section added to macOS history and stopped-session insights
- Fix topics wrapping in macOS history
- Fix discussion color mismatch in iOS history

### 2026-02-23 - v1.8.0

**overall:**
- Training mode — new insights tab with real-time speech analytics: filler words (per type/speaker/minute with per-word frequency for "You"), talk ratio, pace, longest monologue, questions asked, clarity score. Purely local computation, no API keys needed. External speakers always collapsed into `others`.
- Training mode styling and layout refined to match other insights tabs (section headers, lowercase labels)
- Historical meeting insights with mode tabs (standard / MEDDPICC / training); Training stats computed locally from saved transcripts
- Meeting duration shown in history lists
- Live MEDDPICC mode is standalone (no summary/actions/topics mixed in)
- Generate/update actions hidden in Training mode to keep it local-only (no hidden AI calls)
- `miniti free` / usage status styled as indicator instead of clickable button
- Fix pause/resume time tracking so duration and managed-mode usage minutes stay accurate
- Editable meeting titles in history; new meetings default to title `new`; title separator kept as ` - ` with backward compatibility for em-dash

**macOS:**
- Entire insights tab/button area is clickable (not just text)
- `update` button in live insights panel with `⌘⇧I` shortcut; respects selected mode for completed recordings (MEDDPICC can be generated for finished meetings)
- `⌘1` / `⌘2` / `⌘3` switch insight tabs in live + history views
- Model selectors (transcription + insights) moved to Settings — home and recording views are cleaner
- Start button shows "starting..." with spinner instead of flashing recording screen
- Fix Escape not closing Settings window
- Menu bar icon toggle in Settings (default on)
- Refreshed keyboard shortcuts help overlay

**iOS:**
- All insights views (live + history) use plain desktop-style section blocks instead of card layouts
- Historical insights headers match desktop styling (no markdown headings)
- `update` button in live recording insights for Standard and MEDDPICC modes
- `discussion` section added to live Standard insights (matching macOS)
- `MEDDPICC` label casing in live mode picker (matching desktop)
- Generate/update controls for saved meeting insights (including MEDDPICC)

### 2026-02-22 - v1.7.1
- Fix mic test on iOS home screen causing layout jump — waveform area always reserves space
- Start button on iOS shows "starting..." with spinner instead of flashing the recording screen
- Fix iOS recording header and controls jumping when toggling stop/resume — all elements stay in place using opacity transitions
- Rearrange iOS controls: stop and resume share the same center position, discard on left, save on right; home and copy in the header
- Display topics in square brackets instead of hashtags

### 2026-02-21 - v1.7.0
- Move iOS recording controls to bottom of the screen for easier thumb reach
- Fix iOS buttons jumping when stop/resume changes — main action button stays centered
- Fix momentary flash of stopped-state buttons when starting a new recording
- Add discard button with confirmation when a recording is stopped
- Fix MEDDPICC insights not saving on iOS — standard mode no longer overwrites MEDDPICC data, and both standard + MEDDPICC are always generated on stop
- Generate insights for past meetings — "generate" button on history recordings that have no insights
- Show MEDDPICC data in meeting history detail view
- Collapse consecutive same-speaker segments into one block in saved meeting transcripts
- Remove sparkles badge from iOS history meeting rows
- Fix topics display on iOS — proper wrapping layout with consistent terminal-style tags
- Edit notes on saved meetings in history
- Remove Settings tab on iOS — settings accessible via gear icon on home screen
- Replace iOS insights mode picker with custom tab bar matching the section picker style (lowercase, no descriptions)
- Replace always-on mic waveform on iOS home with optional "test mic" button
- Make all iOS section picker labels lowercase (transcript/insights/notes)
- Replace native segmented picker in iOS history detail with custom dark tab bar
- Fix iOS history navigation sometimes redirecting back to active recording

### 2026-02-20 - v1.6.1
- Fix iOS update banner linking to Proton Drive DMG instead of TestFlight
- Auto-save recording every 30 seconds so transcript, insights, and notes are continuously preserved
- Resume interrupted recordings on launch — if the app was killed while recording, reopening restores your session (transcript, insights, notes) so you can continue or save
- Fix orphaned Live Activity when app was killed while recording — stale Live Activities are cleaned up on launch

### 2026-02-18 - v1.6.0
- Send platform identifier (macOS/iOS) with all backend requests for admin dashboard tracking
- Show "account disabled" message when a device has been disabled by admin
- Fix iOS transcription showing all speakers as "You" instead of using Deepgram's native speaker diarization
- Notes section now starts compact and is resizable via drag handle instead of taking half the screen
- Privacy & Terms link in Settings on both macOS and iOS
- Fix iOS mic indicator staying active after closing the app when not recording
- Cleaner Dynamic Island and Lock Screen Live Activity layout
- Fix Live Activity showing active recording after stopping — timer now freezes and everything goes gray

### 2026-02-13 - v1.5.1
- Notify users when a new version is available with a download link on the home screen

### 2026-02-13 - v1.5.0
- App version now sent with all backend requests for better diagnostics
- Fix "Generate Insights" button not working for Early Adopter users
- Fix keyboard navigation (K) in meeting history starting from the wrong end of the list
- Fix saved meetings and transcript exports showing "Speaker 1001" instead of "You" for your microphone
- Fix crash during long recordings caused by rapid transcript updates overwhelming the UI
- Reduce main thread load during recording by sending audio data without blocking the UI

### 2026-02-10 - v1.4.0
- iPhone and iPad app with live transcription, AI insights, and meeting history
- Live Activity on Dynamic Island and Lock Screen showing recording status, timer, and latest transcript
- Record meetings in the background while using other apps on iOS
- Fix recording timer drifting when the app is backgrounded
- MEDDPICC grid adapts to screen size (1 column on iPhone, 2 on iPad/Mac)

### 2026-02-07 - v1.3.0
- Unified color system across the entire app
- Fix transcript not saving correctly when resuming a paused recording
- Remove distracting focus rings from sidebar buttons

### 2026-02-06 - v1.2.0
- First-launch setup: choose Early Adopter (500 free min/month) or Bring Your Own Keys mode
- Improved audio capture with better mic/system audio separation and automatic volume balancing
- Renamed app to lowercase "miniti"
- DMG installer for easy macOS distribution

### 2026-02-05 - v1.1.0
- Live audio waveforms on the home screen to verify mic and system audio before recording
- Info tooltips explaining what each API key is used for in settings
- macOS code signing for distribution

### 2026-02-05 - v1.0.0
- Initial release: record meetings with live transcription and AI-generated summaries, action items, and topics
- API key setup on the home screen with status indicators
- Meeting history browser
- Resizable notes section during recording
- macOS app icon

## Architecture

- **Miniti/MinitiApp.swift** – App entry point, onboarding gate, menu bar, global keyboard shortcuts
- **Miniti/Models/AppState.swift** – Central `@MainActor` state: recording, transcript, insights, audio monitoring, app mode, usage tracking, Live Activity lifecycle (`#if os(iOS)` guarded)
- **Miniti/Models/Meeting.swift** – SwiftData model for persisted meetings
- **Miniti/Services/AudioCaptureService.swift** – Mic (AVAudioEngine) + system audio (Core Audio Process Tap) capture, publishes separate levels
- **Miniti/Services/DeepgramService.swift** – WebSocket streaming transcription (Nova-2/Nova-3), source-based speaker override via `sourceLookup` callback (macOS only; iOS uses Deepgram's native diarization)
- **Miniti/Services/InsightsService.swift** – OpenAI API for summaries, action items, MEDDPICC
- **Miniti/Services/DebugLogger.swift** – In-memory ring-buffer logger (1000 entries) with API key redaction. Thread-safe `log()` callable from audio threads. Categories: audio, deepgram, app. Shared between macOS and iOS.
- **Miniti/Views/DebugLogView.swift** – Terminal-style log viewer with category filters, copy, and clear. Accessed via hidden 5-tap on version text in Settings.
- **Miniti/Services/DeviceIdentifier.swift** – Keychain-based persistent device UUID (survives reinstalls)
- **Miniti/Services/MinitiAPIService.swift** – Backend communication: usage checks, temp key sessions, insights proxy, version checking. Auth via `X-API-Key` (shared app secret) + `X-Device-ID` + `X-App-Version` + `X-Platform` headers on every request; device ID never sent in body/query. `checkVersion()` is lightweight (no device ID required). Handles 403 `device_disabled` — sets `isDeviceDisabled` on AppState to block recording and show user message.
- **Miniti/Views/MeetingView.swift** – Main meeting UI: ReadyStateView (home), active session, audio source panel, waveforms
- **Miniti/Views/MainWindow.swift** – Window chrome: sidebar, content area, status bar
- **Miniti/Views/TranscriptView.swift** – Live transcript with speaker colors; mic speaker shown as "You" (green), remote speakers use blue/purple palette
- **Miniti/Views/InsightsView.swift** – AI insights panel (standard + MEDDPICC + training modes), shared `TrainingContent` view for speech analytics
- **Miniti/Views/HistoryView.swift** – Past meetings browser
- **Miniti/Views/SettingsView.swift** – Account mode toggle, API keys (BYOK only), audio, models (Deepgram + OpenAI), general preferences
- **Miniti/Views/OnboardingView.swift** – First-launch mode selection (managed vs BYOK)
- **Miniti/Views/UsageBanner.swift** – Remaining minutes display + ManagedStatusView for home screen
- **Miniti/Views/LimitReachedView.swift** – Hard block when 500 min exhausted, offers BYOK switch
- **Miniti/Models/ColorPalette.swift** – Global color palette: backgrounds, borders, text, accents, status, speaker colors, MEDDPICC colors

### iOS Target (MinitiMobile)

Separate iOS target in the same Xcode project. Mic-only recording (no system audio on iOS). Shares models, services, and several views with macOS target.

- **MinitiMobile/MinitiApp_iOS.swift** – `@main` iOS entry point, `WindowGroup` + `ModelContainer`, onboarding gate, forces `.preferredColorScheme(.dark)` app-wide
- **MinitiMobile/AudioCaptureService_iOS.swift** – Mic-only `AudioCaptureService` (same class name/interface as macOS). Uses `AVAudioSession` for iOS audio session management. Stubs system audio properties (always false/0). `dominantSource()` always returns `.mic`.
- **MinitiMobile/Views/MainTabView.swift** – `TabView` with Record / History / Settings tabs; wires `@Environment(\.modelContext)` → `appState.modelContext` on appear (critical for SwiftData saves)
- **MinitiMobile/Views/MeetingView_iOS.swift** – Mobile recording UI: terminal-style buttons (stop/resume/save/home matching macOS), custom section picker, `UIPasteboard` for copy, `SourceWaveform_iOS`
- **MinitiMobile/Views/SettingsView_iOS.swift** – `NavigationStack` + `Form`, no launch-at-login / system audio toggle / radio picker
- **MinitiMobile/Views/HistoryView_iOS.swift** – `NavigationStack` + `List` with drill-down to meeting detail
- **MinitiMobile/Info.plist** – `NSMicrophoneUsageDescription`, `UIBackgroundModes: [audio]`, `NSSupportsLiveActivities: YES`, `UILaunchScreen` (empty dict, required for iOS launch)
- **MinitiMobile/MinitiMobile.entitlements** – Empty dict (iOS is always sandboxed; macOS sandbox keys like `com.apple.security.app-sandbox` are invalid on iOS and prevent launch)

### Live Activity Extension (MinitiLiveActivityExtension)

Widget extension embedded in MinitiMobile. Shows recording status on Dynamic Island and Lock Screen.

- **Shared/RecordingActivityAttributes.swift** – `ActivityAttributes` struct shared between MinitiMobile and the extension. Static: `startTime: Date`. Dynamic `ContentState`: `meetingTitle: String`, `isRecording: Bool`, `currentTranscript: String`, `elapsedSeconds: Int?` (set when stopped to freeze the timer).
- **MinitiLiveActivity/MinitiLiveActivityBundle.swift** – `@main` widget bundle entry point
- **MinitiLiveActivity/MinitiLiveActivityLiveActivity.swift** – All Live Activity UI: Dynamic Island (compact leading: red dot, compact trailing: green timer; expanded: REC/STOPPED label + timer + title + live transcript + branding), Lock Screen banner (status + timer + title + transcript). Timer freezes when stopped via `elapsedSeconds`; all elements switch to gray. Compact DI width is system-controlled (not adjustable by apps).
- **MinitiLiveActivity/Info.plist** – `NSExtension` with `com.apple.widgetkit-extension` point identifier
- Bundle ID: `com.miniti.mobile.live-activity`, deployment target iOS 17.0

**Shared files** (macOS + iOS + extension where noted): `AppState.swift`, `Meeting.swift`, `ColorPalette.swift`, `DeepgramService.swift`, `InsightsService.swift`, `DeviceIdentifier.swift`, `MinitiAPIService.swift`, `DebugLogger.swift`, `Secrets.swift`, `TranscriptView.swift`, `InsightsView.swift`, `DebugLogView.swift`, `OnboardingView.swift`, `UsageBanner.swift`, `LimitReachedView.swift`, `Assets.xcassets`, `RecordingActivityAttributes.swift` (iOS app + extension only)

**macOS-only files**: `MinitiApp.swift`, `AudioCaptureService.swift`, `KeyboardShortcutsService.swift`, `MainWindow.swift`, `MeetingView.swift`, `SettingsView.swift`, `HistoryView.swift`

**Key design**: Minimal `#if os()` guards — only in `AppState.swift` for `import ActivityKit`, Live Activity start/update/end calls, and `#if os(macOS)` for source dominance `sourceLookup` wiring (iOS skips it to preserve Deepgram's native diarization). Each target compiles its own `AudioCaptureService` (same class name, same public interface). AppState references `AudioCaptureService` by name and works with either version. Shared views use `@Environment(\.horizontalSizeClass)` for responsive layout. MEDDPICC fields are rendered as individual sections (same heading style as summary/discussion) across all views — `LiveInsightSection` in the sidebar, `TerminalSection` in full-width/history, `InsightsPlainBlock_iOS`/`HistoricalDetailBlock_iOS` on iOS.

**Critical wiring**: `appState.modelContext` must be set from `@Environment(\.modelContext)` in the first view that appears. On macOS this happens in `MainWindow.swift`; on iOS in `MainTabView.swift`. Without it, `saveCurrentMeetingIfNeeded()` silently fails (all saves are no-ops).

## Key patterns

- **Debug logging**: `DebugLogger.shared` is an in-memory ring-buffer (1000 entries) with thread-safe `log(_ category:_ message:)`. Categories: `.audio`, `.deepgram`, `.app`. API keys are automatically redacted via patterns set by `AppState.updateLogRedaction()`. Key instrumentation points: audio device info + format on capture start, 10-second heartbeats confirming audio is flowing (buffer count + level), Deepgram WebSocket connect/disconnect/message counts, app state transitions (start/stop recording). On macOS, `AudioObjectAddPropertyListenerBlock` monitors default input/output device changes (critical for diagnosing Bluetooth headphone issues). `DebugLogView` is accessible by tapping the version text 5 times in Settings — terminal-style scrolling log with category filters, copy, and clear. Not discoverable by normal users.
- **Version check on launch**: `AppState.checkForUpdates()` calls `GET /api/version` once at startup (all modes). Compares semver — if remote is newer, sets `availableUpdate: VersionInfo?`. A blue `UpdateAvailableBanner` appears on the home screen (macOS, iOS) with version, release notes, and a download link (currently Proton Drive). The endpoint is lightweight (no device ID, no Redis) — just hardcoded JSON that gets updated each release.

## Changelog style

Changelog entries (in both `claude.md` and `README.md`) should be written as human-readable descriptions for a public audience. No code references, function names, file paths, or implementation details. Write what changed from the user's perspective — e.g. "Fix saved meetings showing wrong speaker name" not "Fix `TranscriptSegment.speakerLabel` for `micSpeakerID`". Keep both changelogs in sync.

## Color Palette

Centralized color system via `ColorPalette` struct. All colors should reference this palette instead of hardcoded hex values.

- **Backgrounds**: `ColorPalette.Background.primary/secondary/tertiary/panel/card`
- **Borders**: `ColorPalette.Border.primary/light/hover/subtle`
- **Text**: `ColorPalette.Text.primary/secondary/muted/dim/disabled/placeholder/subtle/meta`
- **Accents**: `ColorPalette.Accent.green/blue/purple/red/amber/yellow/pink/cyan/orange` (with GitHub-style variants)
- **Status**: `ColorPalette.Status.success/error/warning/info/recording/connected/disconnected/limitReached/noApiKey`
- **Speakers**: `ColorPalette.Speaker.mic` (green for "You") and `ColorPalette.Speaker.remote` array (blue/purple palette)
- **MEDDPICC**: `ColorPalette.MEDDPICC.metrics/economicBuyer/decisionCriteria/...` with helper `color(for:)` method
- **Insights**: `ColorPalette.Insights.summary/discussion/actions/topics/meddpicc`

The `Theme` struct in `MainWindow.swift` provides convenient aliases for common colors (e.g., `Theme.bg`, `Theme.text`) but all colors ultimately reference `ColorPalette`.

`Color(hex:)` extension is defined in `ColorPalette.swift` for creating colors from hex strings when needed.

- `AppState` is the single source of truth, injected via `@EnvironmentObject`
- `AppMode` enum (`.byok` / `.managed`) stored in `@AppStorage("appMode")` — purely a routing toggle
- Audio levels: `microphoneLevel` and `systemAudioLevel` are published separately for per-source waveforms, plus a combined `audioLevel`
- Audio monitoring: home screen starts lightweight capture (no Deepgram) to verify sources before recording
- **Audio engine restart on device change**: Both macOS and iOS listen for `AVAudioEngineConfigurationChange`. When the audio hardware reconfigures mid-capture (Bluetooth codec switch, device plug/unplug), the mic tap is automatically removed and reinstalled with the new format. On iOS, `AVAudioSession.routeChangeNotification` is also observed to log route changes. This prevents silent audio loss when Bluetooth headphones switch between AAC and HFP codecs (e.g. joining a Zoom call with AirPods). The observer is stored as `engineConfigObserver` and cleaned up in `stopMicrophoneCapture()`.
- `@AppStorage` persists API keys, model selection, audio source toggles, app mode, and onboarding state
- Secrets.swift (gitignored) provides default API keys; Secrets.example.swift is the template. **Only seeded in BYOK mode** — managed users never get Secrets keys written to `@AppStorage`. On switch to managed, any keys matching Secrets defaults are cleared.
- Mode-aware service routing: `startRecording()`, `updateLiveInsights()`, `generateFinalInsightsAndSave()`, `generateInsights()` all branch on `appMode`
- BYOK keys persist in `@AppStorage` regardless of active mode — switching never clears user-entered keys (only Secrets defaults are stripped in managed mode)
- **Segment persistence**: `saveCurrentMeetingIfNeeded()` syncs `liveSegments` → `meeting.segments` by comparing counts; if they differ, old persisted segments are deleted and rebuilt from current live data. This handles resumed sessions correctly (stop → cont → stop saves all segments, not just the first batch).
- **Sidebar focusability**: All sidebar buttons use `.focusable(false)` since navigation is keyboard-shortcut-driven (⌘N, J/K, etc.) — no tab focus rings needed.
- **Recording timer**: Uses date-based computation (`recordingStartDate`) instead of incrementing a counter. `Timer.scheduledTimer` fires every 1s and computes `Date().timeIntervalSince(recordingStartDate)`. This ensures accurate duration even when the app is backgrounded on iOS (timer may not fire reliably, but duration is correct when it does). Paused time is excluded by re-anchoring `recordingStartDate` from the accumulated active duration on resume; `recordingStartDate` is cleared on stop and `goHome()`.
- **Periodic auto-save**: A 30-second `periodicSaveTimer` runs during recording, calling `saveCurrentMeetingIfNeeded()`. This syncs `liveSegments`, insights, notes, and MEDDPICC to SwiftData continuously. `saveCurrentMeetingIfNeeded()` does NOT set `endTime` — only `stopRecording()` and `goHome()` set it. Meetings with `endTime == nil` are identified as interrupted/resumable on next launch.
- **Resume interrupted meetings**: On launch (when `modelContext` is set), `resumeInterruptedMeeting()` queries SwiftData for meetings with `endTime == nil`. If found, it restores the full session: `currentMeeting`, `liveSegments` (reconstructed from `TranscriptSegment`s), all insights, notes, MEDDPICC fields, `detectedSpeakers`, `recordingDuration` (from last segment timestamp), and title tracking. Title parsing accepts both the current ` - ` separator and legacy em-dash titles for backward compatibility. The UI automatically shows the stopped-session view (because `currentMeeting != nil`), where the user can resume recording or go home (which finalizes `endTime` and saves). Works on both iOS and macOS.
- **Live Activity (iOS only)**: `Activity.request()` called in `startRecording()`, `activity.update()` on stop (paused state), title changes, and transcript updates, `activity.end(.immediate)` on `goHome()`. Transcript updates are throttled to max 1 per 3 seconds (`liveActivityUpdateInterval`) to stay within ActivityKit's update budget. The widget uses `Text(timerInterval: startTime...Date.distantFuture, countsDown: false)` for an auto-updating timer when recording; when stopped, `elapsedSeconds` is set and the timer switches to a static `Text(formatDuration(_:))` so it freezes. All visual elements (dot, status, title, timer) switch to `pausedGray` when stopped, and transcript is replaced with "tap to return to miniti". `currentTranscriptLine` returns interim text if available, otherwise the last finalized segment. All ActivityKit code guarded with `#if os(iOS)` in `AppState.swift`. Note: compact Dynamic Island width is system-controlled and cannot be reduced by apps.
- **iOS background recording & kill recovery**: iOS can terminate backgrounded apps at any time (memory pressure, battery, etc.); there is no way to prevent this. Mitigations: (1) `UIBackgroundModes: [audio]` keeps the app running longer while recording. (2) Periodic auto-save (every 30s) continuously persists transcript to SwiftData. (3) `saveCurrentMeetingIfNeeded()` is also called when the app enters background (`scenePhase == .background`). (4) On launch, `cleanupOrphanedLiveActivities()` ends stale Live Activities, then `resumeInterruptedMeeting()` restores the session from SwiftData so the user lands directly in the stopped-session view with their transcript.
- **Atomic array mutations for ForEach-bound arrays**: Never do `removeAll` + `append` (or multiple mutations) on a `@Published` array that drives a SwiftUI `ForEach`. Each mutation fires a separate `objectWillChange`, and SwiftUI's AttributeGraph can see intermediate states (items removed but view nodes still referencing them), causing `EXC_BAD_ACCESS` in `AGGraphGetWeakValue`. Instead, build the final array in a local `var`, then assign it once: `liveSegments = updated`. This is especially critical for arrays that grow over long sessions (30+ minutes of recording).
- **Avoid main actor hops from audio threads**: `nonisolated func sendAudio()` on `@MainActor` services should NOT use `Task { @MainActor }` to access properties — this creates a new main-thread task per audio buffer (~4/sec), competing with SwiftUI layout passes. Instead, use `nonisolated(unsafe)` shadow properties (e.g., `_sendTask`, `_sendConnected`) written from `@MainActor` context (connect/disconnect) and read from audio threads. `URLSessionWebSocketTask.send` is thread-safe and doesn't need the main thread.
- **Discard meeting**: `discardCurrentMeeting()` deletes the current meeting from SwiftData, ends Live Activity (iOS), and clears the session without saving. Used from the "discard" button (with confirmation alert) when a recording is stopped.
- **Generate insights for history**: `generateInsightsForMeeting(_ meeting: Meeting)` generates standard + MEDDPICC insights for a saved meeting and writes directly to the `Meeting` model. Used from history detail generate/update controls.
- **MEDDPICC save safety**: `applyInsights()` only overwrites MEDDPICC fields when `insightsMode == .meddpicc`. In standard mode, the API returns nil for MEDDPICC fields — writing those nils would erase previously generated MEDDPICC data. `stopRecording()` always calls `generateFinalInsightsAndSave()` (which generates both standard + MEDDPICC) regardless of whether insights already exist.
- **Training mode**: Third `InsightsMode` (`.training`) that shows locally-computed speech analytics — no LLM calls needed for the Training UI. `TrainingMetrics.compute(from:duration:)` runs a pass over transcript segments to extract filler word counts (hard fillers like "um"/"uh" + soft fillers like "like"/"basically"), talk ratio, speaking pace (wpm), longest monologue, questions asked, and clarity (avg words/turn). Metrics are recomputed on every new segment batch when training mode is active, and on mode switch. During recording in training mode, automatic live insight refresh still computes standard insights in the background so they are ready when switching back. Manual generate/update actions are hidden (or no-op guarded) in Training mode to avoid hidden AI calls. For saved meetings, training metrics are computed on the fly from `meeting.segments` in the history views (no extra model fields needed).
- **Finished-meeting update action**: `generateInsights()` respects the selected insights mode for a completed current meeting (`standard` vs `meddpicc`). In Training mode, the action just refreshes local training metrics and does not make AI requests.
- **isStartingMeeting**: Transient flag set in `startNewMeeting()`, cleared when `startRecording()` succeeds or on failure. iOS shows a "starting..." spinner during this phase. macOS hides the session view.
- **Stop = save + stay**: `stopRecording()` saves the meeting to SwiftData and generates final insights (standard + MEDDPICC) in the background. The user stays in the stopped state with resume/save/discard controls on both iOS and macOS.

## Audio flow

1. `AudioCaptureService.startCapture(microphone:systemAudio:)` starts AVAudioEngine (mic) and/or Core Audio process tap + AVAudioEngine (system)
2. Mic audio: converted to 16kHz mono PCM16 via AVAudioConverter, level via `vDSP_measqv`
3. System audio: `AudioHardwareCreateProcessTap` → `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` → aggregate device → IO proc callback → direct vDSP conversion (mono downmix via `vDSP_vadd` + decimation via stride + `vDSP_vsmul`/`vDSP_vclip`/`vDSP_vfix16`) → 16kHz mono PCM16. The aggregate device's IO format is read from `kAudioDevicePropertyStreamFormat` (input scope) to handle cases where it differs from the tap format. Level via `vDSP_measqv`.
4. **Process Tap setup**: Creates a `CATapDescription` (global stereo, captures all processes), then an aggregate device with the tap as a sub-tap. IO proc callback runs on a custom DispatchQueue (not RT thread). Cleanup: stop IO proc → destroy aggregate device → destroy process tap.
5. **Mixing**: When both sources active, system audio PCM16 goes into a pre-allocated Int16 ring buffer (8000 samples, ~500ms at 16kHz, NSLock-protected, zero allocations). Mic callback drains the ring buffer and mixes via vDSP (`vDSP_vadd` after float conversion). **Adaptive dual AGC**: each buffer's Int16 RMS is measured in real-time, and independent gain is computed to bring mic to ~3000 and system to ~2000 Int16 RMS (mic 1.5x louder for diarization). Gains are smoothed (fast attack 0.15, slow release 0.02) to avoid pumping. A noise gate (floor=30) prevents boosting silence. Max gain capped at 25x. This handles any hardware level (process tap, ScreenCaptureKit, Bluetooth, built-in, etc.) without manual tuning. Debug log `[AudioMix]` prints every 30s, only when system audio is active.
6. **Source dominance tracking**: Each buffer's pre-AGC mic/sys RMS is logged with its stream timestamp. `dominantSource(from:to:)` returns `.mic` or `.system` for a time range. Deepgram words are tagged: mic-dominant → speaker `1000` ("You"), system-dominant → keep Deepgram's speaker ID (for multi-speaker remote diarization). Threshold: system must exceed mic × 1.5 to be tagged as system (avoids false positives from amplified mic noise). Source log bounded at 6000 entries (~10 min).
7. `onAudioBuffer` callback → DeepgramService (nil during monitoring)
8. Levels flow independently: AudioCaptureService → Combine → AppState → SwiftUI views (throttled to ~20Hz, waveforms at 16Hz)
9. **Level display**: `SourceWaveform` uses `pow(level, 0.2)` power curve (not linear) so quiet mic signals (~0.003 RMS) show visible bar movement.

### iOS audio flow (mic-only)
1. `AVAudioSession` configured with `.playAndRecord` category, `.defaultToSpeaker` + `.allowBluetoothA2DP` options
2. `AVAudioEngine` with input node tap → AVAudioConverter → 16kHz mono PCM16 (same format as macOS mic path)
3. `onAudioBuffer` callback → DeepgramService
4. No system audio, no mixing, no ring buffer, no source dominance tracking (all stubs)
5. `sourceLookup` is never set on iOS — Deepgram's native diarization handles multi-speaker separation. Speakers show as "Speaker 1", "Speaker 2", etc. (no "You" label since mic/system separation isn't possible)

### System Audio permission (macOS only)
- Uses `AudioHardwareCreateProcessTap` (Core Audio, macOS 14.2+) instead of ScreenCaptureKit. This lands the app in **"System Audio Recording Only"** permission category (like Granola) rather than "Screen Recording".
- ScreenCaptureKit was previously used but **always** triggers Screen Recording permission — even with `.audio`-only output — because `SCShareableContent.excludingDesktopWindows()` itself requires screen recording TCC access.
- Info.plist key: `NSAudioCaptureUsageDescription` (not `NSScreenCaptureUsageDescription`)
- No public API to check audio capture permission status; the system prompts on first use of `AudioHardwareCreateProcessTap`
- Minimum macOS bumped from 14.0 to 14.2 for process tap API availability

### Known limitations
- **Source tagging is energy-based, not voice-based**: when both mic and system audio are active simultaneously (overlapping speech), the dominant source wins for that time window. Works well for turn-based conversations (>95% of meeting audio).
- **Mic RMS is naturally much lower than system audio** (~0.003 vs ~0.02-0.09 depending on capture method). The adaptive dual AGC compensates automatically but amplifies noise floor when boosting quiet signals.
- **Multi-speaker remote diarization**: within system audio, Deepgram's native diarization still works. Multiple remote speakers get separate IDs. The source tagging only separates "You" (mic) from all remote speakers.

## UI states

### macOS
- **Onboarding** (first launch): Mode selection — "Early Adopter" (managed, 500 min/month) or "Bring Your Own Keys"
- **Home** (`ReadyStateView`): Mode-aware — managed shows usage status, BYOK shows API pills; audio source panel, start button; cog button (top-right) opens settings
- **Home (limit reached)**: In managed mode when 500 min used — inline "switch to BYOK" prompt, start button disabled
- **Home (device disabled)**: In managed mode when admin has disabled the device — shows "account disabled" message, start button hidden
- **Starting**: Spinner with "starting..." text while waiting for managed mode key or audio setup — stays on home screen until recording begins
- **Recording**: TerminalHeader with red dot + timer, stop button, dual labeled waveforms (mic green, system blue), transcript, notes, live insights
- **Stopped session**: Same layout; header shows discard (left), cont (center, same position as stop), save (right). Status dot hidden when not recording. Resumes the current session (no new meeting created). In managed mode, resuming requests a fresh temp Deepgram key (the previous one is cleared on stop).
- **History**: Sidebar list → detail view with tabs (transcript / insights / meddpicc / training). macOS uses split panes (transcript + notes on left, insights on right) and the insights pane has mode tabs (standard / MEDDPICC / training) with `⌘1` / `⌘2` / `⌘3`.
- **Settings**: Account tab (mode toggle + usage stats + full device UUID, selectable), API Keys (BYOK only), Models (Deepgram + OpenAI), Audio, General. Opened via cog button (`@Environment(\.openSettings)`), ⌘,, or menu bar

### iOS
- **Onboarding** (first launch): Same as macOS (shared `OnboardingView`)
- **Home** (`ReadyStateView_iOS`): Logo, mode status pill, "test mic" button (opt-in waveform), gear icon for settings, start button. Mic-only (no system audio toggle)
- **Starting**: Spinner with "starting..." text while waiting for managed mode key or audio setup
- **Recording**: Header with red dot + timer (center) + waveform, custom lowercase section picker (transcript/insights/notes), stop button at bottom center
- **Stopped session**: Same layout, no jumps — header shows gray dot + frozen timer, home + copy icons fade in (top right), waveform fades out. Bottom bar: discard (left), resume (center, same position as stop), save (right)
- **History tab**: `NavigationStack` list with swipe-to-delete, drill-down detail with custom tab bar (transcript/insights/notes/training, lowercase). Transcript collapses consecutive same-speaker segments. Insights shows standard + MEDDPICC + "generate" button for past meetings. Training shows speech analytics computed from saved segments. Notes are editable.
- **Settings**: Accessible via gear icon on home screen (no dedicated tab)
- **Tab bar**: Record / History — two-tab navigation

## Monetization

> **Note:** Strategy below is planning/aspirational; may be outdated. Current implementation is two-mode only (Free/BYOK), no Pro tier yet.

### Commercial model

| | Free | Pro | BYOK |
|---|---|---|---|
| **Price** | $0 | $14/mo or $120/yr | $0 (forever) |
| **Minutes** | 500/month | Unlimited | Unlimited |
| **Transcription** | Deepgram Nova-2 | Deepgram Nova-3 | User's own |
| **LLM** | GPT-5 Nano | GPT-5 Mini | User's own |
| **AI insights** | Summary, timeline, action items, topics | All free insights + MEDDPICC + future methodologies | All (user pays own API) |
| **History** | Full | Full | Full |

- **BYOK** is always free and unlimited — zero cost, pure evangelists
- **Free** is generous (500 min) to build habit and word-of-mouth; conversion lever is quality (Nova-3 transcription, GPT-5 Mini analysis, MEDDPICC)
- **Pro** annual plan (~29% discount vs monthly) drives commitment and reduces churn
- No team/enterprise tier yet — nail individual experience first

### Payment implementation

**iOS (App Store):**
- StoreKit 2 for subscription management (auto-renewable subscriptions)
- Apple handles billing, receipts, renewals, refunds
- Apple commission: 15% (Small Business Program, <$1M/year proceeds)
- Receipt validation server-side via App Store Server API
- Backend tracks entitlements by device ID (existing infrastructure)

**macOS (direct DMG):**
- Paddle or LemonSqueezy as Merchant of Record (handles global VAT/tax)
- LemonSqueezy fee: ~5.5% + $0.50/transaction (+1.5% international, +0.5% subscription)
- License key or account-based activation via device ID
- No Mac App Store (sandbox blocks `AudioHardwareCreateProcessTap`)

**Blended platform fee estimate:** ~12% (weighted ~60% iOS at 15% / ~40% macOS at ~7%)

### UK business structure

No company required to start — operate as sole trader:
- Apple Developer Program accepts individual enrollment
- Paddle/LemonSqueezy handle VAT collection for macOS sales as Merchant of Record
- Register for Self Assessment with HMRC for income tax
- VAT registration required only if UK taxable turnover exceeds £90K/year
- Form a Ltd company when revenue justifies it (£12 at Companies House, better liability protection)

### Financial model

#### Service pricing (as of Feb 2026, pay-as-you-go)

| Service | PAYG rate | Growth rate (~$4K+/yr spend) |
|---|---|---|
| Deepgram Nova-2 streaming | $0.0059/min | ~$0.0043/min |
| Deepgram Nova-3 streaming | $0.0077/min | ~$0.0065/min |
| GPT-5 Nano | $0.05 / $0.40 per 1M tokens (in/out) | — |
| GPT-5 Mini | $0.25 / $2.00 per 1M tokens (in/out) | — |

**LLM cost per meeting** (30 min avg, ~5 insight calls × ~8.5K input + ~2K output tokens):
- GPT-5 Nano (free): ~$0.006/meeting
- GPT-5 Mini + MEDDPICC (pro): ~$0.037/meeting

#### Unit economics per user

| User type | Avg usage | Deepgram | LLM | Total cost/mo |
|---|---|---|---|---|
| **Free (typical)** | 150 min, ~5 meetings | $0.89 (PAYG) / $0.65 (Growth) | $0.03 | **$0.92** / **$0.68** |
| **Free (at cap)** | 500 min, ~17 meetings | $2.95 / $2.15 | $0.10 | **$3.05** / **$2.25** |
| **Pro (typical)** | 1000 min, ~33 meetings | $7.70 / $6.50 | $1.22 | **$8.92** / **$7.72** |
| **Pro (heavy)** | 2000 min, ~67 meetings | $15.40 / $13.00 | $2.48 | **$17.88** / **$15.48** |
| **BYOK** | any | $0 | $0 | **$0** |

**Revenue per pro user:** $14/mo blended (mix of $14/mo monthly + $120/yr annual subscribers)
**Net revenue after platform fees:** ~$12.32/mo per pro user (at 12% blended fee)
**Net margin per pro user:** $3.40/mo (PAYG) → $4.60/mo (Growth pricing)

#### Scale scenarios

Assumptions: 75% free / 15% pro / 10% BYOK split. Free users average 150 min/mo. Pro users average 1000 min/mo. Infrastructure = Vercel Pro + Upstash Redis, scales with usage.

| | **100 users** | **1,000 users** | **5,000 users** | **25,000 users** |
|---|---|---|---|---|
| Free / Pro / BYOK | 75 / 15 / 10 | 750 / 150 / 100 | 3,750 / 750 / 500 | 18,750 / 3,750 / 2,500 |
| Deepgram pricing | PAYG | Growth | Growth | Growth+ (negotiated) |
| Free user costs | $69 | $510 | $2,550 | $12,750 |
| Pro user costs | $134 | $1,158 | $5,790 | $28,950 |
| Infrastructure | $30 | $50 | $100 | $200 |
| **Total costs/mo** | **$233** | **$1,718** | **$8,440** | **$41,900** |
| Pro revenue (gross) | $210 | $2,100 | $10,500 | $52,500 |
| Platform fees (~12%) | -$25 | -$252 | -$1,260 | -$6,300 |
| **Net revenue/mo** | **$185** | **$1,848** | **$9,240** | **$46,200** |
| **Profit (loss)/mo** | **-$48** | **+$130** | **+$800** | **+$4,300** |
| **Annualized** | **-$576** | **+$1,560** | **+$9,600** | **+$51,600** |

#### Breakeven analysis

- **PAYG pricing:** each pro user generates ~$3.40/mo margin, each free user costs ~$0.92/mo → 1 pro covers ~3.7 free users → **~21% conversion needed** to break even
- **Growth pricing:** each pro user generates ~$4.60/mo margin, each free user costs ~$0.68/mo → 1 pro covers ~6.8 free users → **~13% conversion needed** to break even
- At 15% conversion with Growth pricing, the model is profitable from ~500 users onward
- BYOK users are net neutral — they cost nothing and drive word-of-mouth

#### Key observations

- **Free tier is the main cost driver** — 500 min at Nova-2 costs $0.68-$0.92/user/mo even at typical (not max) usage. This is the price of a generous free tier.
- **Deepgram is ~90% of API costs** — LLM costs are nearly negligible (GPT-5 Nano at $0.006/meeting). Transcription is the expensive part.
- **Growth plan pricing is critical** — the ~27% Deepgram discount at $4K+/yr spend drops break-even conversion from ~21% to ~13%. Negotiate early.
- **Pro heavy users are margin-negative at PAYG** — a 2000 min/mo user costs $17.88 but only generates $12.32 net. Volume pricing and the mix of light/heavy users makes the average work.
- **Price sensitivity:** at $12/mo the model barely works (razor-thin margins). At $16/mo break-even drops to ~10% conversion. $14/mo is the sweet spot — undercuts Otter ($16.99), Fireflies ($19), Granola ($18) while staying viable.
- **Path to profitability:** reach ~1,000 users with 15% conversion → profitable. Scale to 25K users → ~$50K/yr profit. Real money comes from eventual team/enterprise tier (per-seat pricing, shared libraries, CRM integrations).

### Monetization architecture (current implementation)

Two parallel modes, to be extended with Pro tier:

- **BYOK Mode**: User's own API keys, unlimited, no backend, no tracking
- **Managed Mode**: 500 free min/month, Deepgram via temp API keys (backend issues short-lived scoped keys), OpenAI proxied through backend, hard-blocked at limit
- Mode toggle is a local routing switch only; user-entered BYOK keys persist in `@AppStorage` across mode switches (Secrets defaults are stripped in managed mode)
- Usage tracking is 100% server-side (Vercel KV, keyed by Keychain-stored device UUID); switching modes never resets the counter
- Device ID stored in macOS Keychain (`DeviceIdentifier.swift`) — persists across reinstalls, tamper-resistant
- Backend API keys (Deepgram/OpenAI) stored as Vercel encrypted env vars, never exposed to client
- At limit: user must switch to BYOK or wait for monthly reset — no paid tiers yet
- Cost: ~$3.75/user/month at full 500 min usage
- Backend is a separate repo (`miniti-api`), deployed at `https://miniti-api.vercel.app`; full spec in `BACKEND_SPEC.md`

#### Backend API (`miniti-api`)
- Repo: `12ian34/miniti-api` (private), deployed at `https://miniti-api.vercel.app`
- Stack: Next.js 14 (App Router, edge runtime), TypeScript, Vercel, Upstash Redis via `@vercel/kv`
- All routes require `X-API-Key` (shared app key) + `X-Device-ID` (UUID) headers; optional `X-App-Version` header (e.g. "1.5.0") and `X-Platform` header (`"macos"` / `"ios"`) tracked per device in Redis
- Device disable/enable via admin dashboard — disabled devices get 403 `device_disabled` on all endpoints; app shows "account disabled" message and blocks recording
- API key is XOR-obfuscated in `MinitiAPIService.swift` (not plain text in source/binary)
- **Security note**: the client `X-API-Key` is not a true secret (anything shipped in the app can be extracted). XOR obfuscation only reduces casual string scanning. Treat this as a client identifier / coarse gate, not strong authentication.
- **Safer direction**: keep quota enforcement and abuse protection server-side (`X-Device-ID`, rate limits, caps, anomaly detection), issue short-lived server tokens for sensitive flows (session creation / insights), and optionally add platform attestation later (e.g. App Attest / DeviceCheck on iOS) to raise abuse cost.
- Env vars (Vercel, encrypted): `OPENAI_API_KEY`, `DEEPGRAM_API_KEY`, `DEEPGRAM_PROJECT_ID`, `API_SECRET_KEY`, KV connection vars
- Deepgram key needs **Member** role (can create temp keys), **never expire**

**Endpoints:**
- `GET /api/version` — returns `{ latest_version, download_url, release_notes }`. No device ID required, just `X-API-Key`. Hardcoded JSON — update when publishing a new release.
- `GET /api/usage` — check device minutes used/remaining (30 req/min)
- `POST /api/session` — start session, returns temp Deepgram key (4hr TTL, `usage:write` scope); returns 402 if limit reached (5 req/min)
- `POST /api/session/end` — report duration, increment usage counter; server caps at wall-clock elapsed (10 req/min)
- `POST /api/insights` — OpenAI proxy for transcript analysis; modes: `standard` or `meddpicc`; transcript capped at 100KB (10 req/min)

**Session flow:** launch → `GET /api/version` (update check) + `GET /usage` (managed only) → `POST /session` (get temp key) → connect directly to Deepgram WebSocket with temp key → periodic `POST /insights` → stop → `POST /session/end` → final `POST /insights`

**Response types:** all snake_case JSON. Vercel KV returns numbers as strings — `UsageInfo` has a custom `init(from:)` decoder that accepts both `Double` and `String`. Minutes display uses `.rounded()` (not `Int()` truncation) across Settings, home banner, and remaining time formatter.

**Rate limiting:** sliding-window counters in KV. New device registration rate-limited per IP (5/day). All errors follow `{ "error": "code", "message": "..." }` format. Key status codes: 402 = limit reached, 429 = rate limited.

## Future: Local Mode (research notes)

Optional third `AppMode.local` — fully offline, no API keys or backend. Runs transcription and LLM inference on-device via Apple Silicon. Target audience: privacy-focused users, air-gapped environments, cost-sensitive power users.

### Transcription: whisper.cpp
- **Why whisper.cpp over WhisperKit**: more mature, battle-tested in many macOS apps (e.g. MacWhisper), C API callable from Swift via bridging header, no CoreML model conversion step — just download a GGML model file. SPM-compatible (`whisper.spm` branch).
- **Integration**: feeds directly from existing PCM16 16kHz mono buffers (same format whisper.cpp expects). Process audio in chunks (5-30s), display results as they complete.
- **Models**: `whisper-large-v3-turbo` is the sweet spot (~1.5GB VRAM, very good quality). `whisper-small` for lower-end machines.
- **Latency vs Deepgram**: whisper.cpp is **not real-time streaming**. Expect 7-13s behind on M1, 5-8s on M3 Pro with large-v3-turbo. Acceptable for most users since live transcript isn't the primary interaction during a meeting. Final transcript quality is equivalent.

### LLM for insights: Ollama (easiest) or mlx-swift (native)
- **Ollama**: exposes OpenAI-compatible API at `localhost:11434`. `InsightsService` barely changes — swap base URL and model name. Users install Ollama separately. Supports Llama 3, Mistral, Phi-3, Qwen, etc.
- **mlx-swift**: Apple's official Swift MLX bindings. Run LLMs in-process, no external dependency. More complex to integrate but fully self-contained.
- **Quality**: 8B models (Llama 3.1 8B Q4, ~5GB) are good for standard summaries. Noticeably weaker than GPT-4o for nuanced analysis (MEDDPICC). 70B models match GPT-4o quality but need ~40GB RAM.

### Diarization in local mode
- **Whisper has no diarization** — it's transcription only. All variants (whisper.cpp, WhisperKit, mlx-whisper) are the same.
- **Current approach works**: mic/system energy-based source dominance tracking already separates "You" vs "Others" without any model. Covers 90%+ of the use case (turn-based meetings).
- **Multi-speaker within system audio**: lost in local mode (Deepgram provides this in cloud mode). Acceptable tradeoff for MVP.
- **Future multi-speaker diarization**: see Roadmap. Options: sherpa-onnx (C++ library, C API, has speaker diarization built in, no Python), or CoreML-converted ECAPA-TDNN speaker embeddings + clustering. pyannote is gold standard but Python-only — ruled out to keep the app dependency-free.

### Hardware requirements
- **Minimum**: M1, 16GB RAM (Whisper Turbo + 8B LLM Q4)
- **Comfortable**: M1 Pro+, 16GB+
- **Ideal**: M2/M3/M4 Pro/Max, 32GB+ (larger/better models)

### Not pursuing
- **exo**: distributed inference across multiple Apple devices. Overkill — a single Mac handles 8B LLM + Whisper fine. Only relevant for 70B+ models.
- **Python dependencies**: no pyannote, no mlx-whisper, no whisperX. Pure Swift/C/C++ only.

## Roadmap

- [ ] **Local mode MVP** — whisper.cpp transcription + Ollama LLM insights, mic/system diarization only, new `AppMode.local`
- [ ] **Suggested follow-up questions** — new insight type: after generating summary/action items, LLM proposes 3-5 contextual follow-up questions the user could ask in the meeting (e.g. "You mentioned timeline — have you confirmed the go-live date with engineering?"). Useful for sales calls, interviews, and discovery meetings.
- [ ] **Proper multi-speaker mic diarization** — when multiple people are speaking on the same physical mic (in-room meetings), distinguish between them. Current energy-based approach can't do this. Requires speaker embedding model (ECAPA-TDNN via CoreML or sherpa-onnx) to extract voice fingerprints per audio segment, then cluster into speaker identities. Would benefit both local and cloud modes. sherpa-onnx is the leading candidate (C API, no Python, proven diarization pipeline).
- [ ] **Docs MCP for technical sales** — integrate an MCP (Model Context Protocol) server that indexes product documentation, API specs, and knowledge base articles. During a live sales call, the LLM can query this context to suggest accurate technical answers in real-time — effectively an AI sales engineer copilot. The user would configure a docs source (folder, URL, or Notion/Confluence), which gets indexed and made available as MCP resources. Insights prompts would be augmented with relevant doc snippets retrieved via semantic search. This turns Miniti from a passive recorder into an active meeting assistant for technical sales teams.
- [ ] **Multi-speaker diarization within system audio (local mode)** — match Deepgram's cloud capability
- [ ] **On-device model management UI** — download, select, and delete whisper.cpp / LLM models from Settings
- [ ] **Hybrid mode** — use local transcription but cloud LLM (or vice versa) for best quality/cost balance
- [ ] **CRM integration** — auto-update CRM fields (starting with Attio) after meetings. Map MEDDPICC insights and action items to CRM opportunity fields, push call notes and next steps automatically. Reduces manual data entry for sales reps.
- [ ] **Windows app** — native Windows client to reach non-Apple users. Likely C++/Qt or Electron with same backend services. System audio capture via WASAPI loopback.
- [ ] **Custom insight templates** — user-defined templates beyond Standard and MEDDPICC. Examples: BANT, SPIN Selling, customer success check-in, interview scorecard, standup notes. Template editor in Settings with customizable sections and prompts.

## Distribution

### macOS
Direct notarized distribution via DMG (not Mac App Store — sandbox restrictions block `AudioHardwareCreateProcessTap`).

### Release workflow

#### macOS
1. Bump version in `Miniti/Info.plist`, `MinitiMobile/Info.plist` (`CFBundleShortVersionString`) and `project.pbxproj` (`MARKETING_VERSION` — 6 places: 2 per target × 3 targets, Debug + Release). All targets share the same version number.
2. Xcode: **Product → Archive → Distribute App → Developer ID → Upload** (notarizes automatically)
3. Export the notarized `miniti.app`
4. Run `./scripts/build-dmg.sh miniti.app` → produces `miniti-<version>.dmg`
5. replace proton drive dmg

#### iOS
1. Bump version (same step as macOS — shared version across all targets)
2. Xcode: **Product → Archive → Distribute App → App Store Connect → Upload**
3. Wait for Apple to process the build (~5–15 min)
4. Go to [App Store Connect](https://appstoreconnect.apple.com) → MinitiMobile → TestFlight → External Testing
5. Add the new build to the external testers group
6. Add test instructions describing what changed and what to test
7. Submit for review — wait for Apple's TestFlight review (can take a few days). The TestFlight link stays the same; testers get the new build automatically once approved.

#### After both platforms
1. **Update backend version endpoint**: in `miniti-api`, edit `app/api/version/route.ts` — set `latest_version`, `download_url` (new Proton Drive link if changed), and `release_notes`. Without this, users on older versions won't see the update notification.

### `scripts/build-dmg.sh`
- Requires `create-dmg` (auto-installed via Homebrew if missing)
- Validates code signature and notarization before packaging
- Creates a drag-to-Applications DMG (app on left, Applications symlink on right)
- Staples the notarization ticket to the DMG
- Version extracted automatically from the app's `Info.plist`

### iOS (MinitiMobile)
- Bundle ID: `com.miniti.mobile`, deployment target iOS 17.0
- Distribution: App Store (no sandbox restrictions for mic-only recording)
- Background audio: `UIBackgroundModes: [audio]` + `AVAudioSession` category `.playAndRecord` enables recording while backgrounded
- Live Activity: `MinitiLiveActivityExtension` widget extension (bundle ID: `com.miniti.mobile.live-activity`), embedded in MinitiMobile via "Embed App Extensions" build phase. Shows recording on Dynamic Island + Lock Screen.
- No system audio capture — iOS sandbox prevents it entirely
- Export compliance: `ITSAppUsesNonExemptEncryption: NO` in Info.plist — app only uses HTTPS (OS-provided TLS), which is exempt. This key bypasses the App Store Connect encryption compliance dialog and unblocks TestFlight distribution.
- Xcode targets: `MinitiMobile` (app) + `MinitiLiveActivityExtension` (widget extension) in same project as macOS `Miniti` target
