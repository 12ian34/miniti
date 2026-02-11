# Miniti

macOS + iOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio (macOS) or mic-only (iOS), streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI. Two modes: managed (500 free min/month) or BYOK (own API keys, unlimited).

## Features

### macOS — native AI meeting assistant

- mic + system audio recording
- live transcription with deepgram
- live speaker identification
- live AI-generated summaries and action items
- live MEDDPICC analysis
- meeting history browser
- native menu bar controls
- keyboard shortcuts for everything

### iOS — mobile AI meeting assistant

- mic recording with background support
- live transcription with deepgram
- live AI-generated summaries and action items
- live MEDDPICC analysis
- meeting history browser
- Live Activity on Dynamic Island and Lock Screen (timer + live transcript)
- dark mode terminal-style UI

## Changelog

### 2026-02-10 - v1.4.0 (current)
- iOS app (MinitiMobile): mic-only recording, live transcription, AI insights, meeting history
- Live Activity with Dynamic Island and Lock Screen: recording status, elapsed timer, live transcript line
- Background recording support on iOS
- Date-based recording timer (fixes background timer drift on iOS)
- Responsive MEDDPICC grid (1 column on iPhone, 2 on iPad/Mac)
- Shared codebase: models, services, and views between macOS and iOS targets

### 2026-02-07 - v1.3.0
- Centralized color palette (ColorPalette.swift) with Theme aliases
- Fix transcript save bug: resumed sessions ("cont") now correctly persist all segments, not just those from the first recording
- Fix sidebar focus rings: buttons use .focusable(false) since all navigation is keyboard-shortcut-driven

### 2026-02-06 - v1.2.0
- Implement onboarding flow and app mode selection (Early Adopter / BYOK)
- Refactor audio capture: Core Audio Process Tap replaces ScreenCaptureKit, adaptive dual AGC, source dominance tracking, mic/system speaker separation
- Revise README for clarity and detail
- Rename app display name to lowercase "miniti"
- Add DMG build script and distribution workflow docs

### 2026-02-05 - v1.1.0
- README: add download section, restructure with user content at top / dev at bottom
- Code signing identity for macOS distribution
- Add empty Secrets.swift for Xcode Cloud builds
- Enhance audio recording and monitoring (home screen pre-flight waveforms)
- Add info popovers for API keys in settings

### 2026-02-05 - v1.0.0
- Initial commit: core app with SwiftUI + SwiftData, Deepgram streaming transcription, OpenAI insights, meeting persistence
- Add API key inputs to home screen
- Restore Secrets.swift fallback for default API keys
- API status pills on home screen (click-to-edit)
- Fix padding syntax error
- Make notes section compact (~3 lines default, resizable)
- Add macOS app icon (all sizes/scales)

## Architecture

- **Miniti/MinitiApp.swift** – App entry point, onboarding gate, menu bar, global keyboard shortcuts
- **Miniti/Models/AppState.swift** – Central `@MainActor` state: recording, transcript, insights, audio monitoring, app mode, usage tracking, Live Activity lifecycle (`#if os(iOS)` guarded)
- **Miniti/Models/Meeting.swift** – SwiftData model for persisted meetings
- **Miniti/Services/AudioCaptureService.swift** – Mic (AVAudioEngine) + system audio (Core Audio Process Tap) capture, publishes separate levels
- **Miniti/Services/DeepgramService.swift** – WebSocket streaming transcription (Nova-2/Nova-3), source-based speaker override via `sourceLookup` callback
- **Miniti/Services/InsightsService.swift** – OpenAI API for summaries, action items, MEDDPICC
- **Miniti/Services/DeviceIdentifier.swift** – Keychain-based persistent device UUID (survives reinstalls)
- **Miniti/Services/MinitiAPIService.swift** – Backend communication: usage checks, temp key sessions, insights proxy. Auth via `X-API-Key` (shared app secret) + `X-Device-ID` headers on every request; device ID never sent in body/query.
- **Miniti/Views/MeetingView.swift** – Main meeting UI: ReadyStateView (home), active session, audio source panel, waveforms
- **Miniti/Views/MainWindow.swift** – Window chrome: sidebar, content area, status bar
- **Miniti/Views/TranscriptView.swift** – Live transcript with speaker colors; mic speaker shown as "You" (green), remote speakers use blue/purple palette
- **Miniti/Views/InsightsView.swift** – AI insights panel (standard + MEDDPICC modes)
- **Miniti/Views/HistoryView.swift** – Past meetings browser
- **Miniti/Views/SettingsView.swift** – Account mode toggle, API keys (BYOK only), audio, general preferences
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

- **Shared/RecordingActivityAttributes.swift** – `ActivityAttributes` struct shared between MinitiMobile and the extension. Static: `startTime: Date`. Dynamic `ContentState`: `meetingTitle: String`, `isRecording: Bool`, `currentTranscript: String`.
- **MinitiLiveActivity/MinitiLiveActivityBundle.swift** – `@main` widget bundle entry point
- **MinitiLiveActivity/MinitiLiveActivityLiveActivity.swift** – All Live Activity UI: Dynamic Island (compact leading: red dot, compact trailing: green timer, expanded: REC label + timer + title + live transcript line + branding), Lock Screen banner (recording status + timer + title + live transcript). Uses `Text(timerInterval:countsDown: false)` for auto-updating timer with zero ActivityKit updates.
- **MinitiLiveActivity/Info.plist** – `NSExtension` with `com.apple.widgetkit-extension` point identifier
- Bundle ID: `com.miniti.mobile.live-activity`, deployment target iOS 17.0

**Shared files** (macOS + iOS + extension where noted): `AppState.swift`, `Meeting.swift`, `ColorPalette.swift`, `DeepgramService.swift`, `InsightsService.swift`, `DeviceIdentifier.swift`, `MinitiAPIService.swift`, `Secrets.swift`, `TranscriptView.swift`, `InsightsView.swift`, `OnboardingView.swift`, `UsageBanner.swift`, `LimitReachedView.swift`, `Assets.xcassets`, `RecordingActivityAttributes.swift` (iOS app + extension only)

**macOS-only files**: `MinitiApp.swift`, `AudioCaptureService.swift`, `KeyboardShortcutsService.swift`, `MainWindow.swift`, `MeetingView.swift`, `SettingsView.swift`, `HistoryView.swift`

**Key design**: Minimal `#if os(iOS)` guards — only in `AppState.swift` for `import ActivityKit` and Live Activity start/update/end calls. Each target compiles its own `AudioCaptureService` (same class name, same public interface). AppState references `AudioCaptureService` by name and works with either version. Shared views use `@Environment(\.horizontalSizeClass)` for responsive layout (e.g. MEDDPICC grid: 1 column on compact/iPhone, 2 columns on regular/Mac).

**Critical wiring**: `appState.modelContext` must be set from `@Environment(\.modelContext)` in the first view that appears. On macOS this happens in `MainWindow.swift`; on iOS in `MainTabView.swift`. Without it, `saveCurrentMeetingIfNeeded()` silently fails (all saves are no-ops).

## Key patterns

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
- `@AppStorage` persists API keys, model selection, audio source toggles, app mode, and onboarding state
- Secrets.swift (gitignored) provides default API keys; Secrets.example.swift is the template. **Only seeded in BYOK mode** — managed users never get Secrets keys written to `@AppStorage`. On switch to managed, any keys matching Secrets defaults are cleared.
- Mode-aware service routing: `startRecording()`, `updateLiveInsights()`, `generateFinalInsightsAndSave()` all branch on `appMode`
- BYOK keys persist in `@AppStorage` regardless of active mode — switching never clears user-entered keys (only Secrets defaults are stripped in managed mode)
- **Segment persistence**: `saveCurrentMeetingIfNeeded()` syncs `liveSegments` → `meeting.segments` by comparing counts; if they differ, old persisted segments are deleted and rebuilt from current live data. This handles resumed sessions correctly (stop → cont → stop saves all segments, not just the first batch).
- **Sidebar focusability**: All sidebar buttons use `.focusable(false)` since navigation is keyboard-shortcut-driven (⌘N, J/K, etc.) — no tab focus rings needed.
- **Recording timer**: Uses date-based computation (`recordingStartDate`) instead of incrementing a counter. `Timer.scheduledTimer` fires every 1s and computes `Date().timeIntervalSince(recordingStartDate)`. This ensures accurate duration even when the app is backgrounded on iOS (timer may not fire reliably, but duration is correct when it does). The `recordingStartDate` persists across stop/resume cycles within a session, and is cleared on `goHome()`.
- **Live Activity (iOS only)**: `Activity.request()` called in `startRecording()`, `activity.update()` on stop (paused state), title changes, and transcript updates, `activity.end(.immediate)` on `goHome()`. Transcript updates are throttled to max 1 per 3 seconds (`liveActivityUpdateInterval`) to stay within ActivityKit's update budget. The widget uses `Text(timerInterval: startTime...Date.distantFuture, countsDown: false)` for an auto-updating timer. `currentTranscriptLine` returns interim text if available, otherwise the last finalized segment. All ActivityKit code guarded with `#if os(iOS)` in `AppState.swift`.

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
5. `dominantSource()` always returns `.mic` — all speakers tagged as "You" unless Deepgram's native diarization separates them

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
- **Home** (`ReadyStateView`): Mode-aware — managed shows usage status, BYOK shows API pills; model selector, audio source panel, start button; cog button (top-right) opens settings
- **Home (limit reached)**: In managed mode when 500 min used — inline "switch to BYOK" prompt, start button disabled
- **Recording**: TerminalHeader with red dot + timer, stop button, dual labeled waveforms (mic green, system blue), transcript, notes, live insights
- **Stopped session**: Same layout; rec button shows "cont" (same position as stop — model selector sits after the button, status dot hidden when not recording). Resumes the current session (no new meeting created). In managed mode, resuming requests a fresh temp Deepgram key (the previous one is cleared on stop).
- **History**: Sidebar list → detail view
- **Settings**: Account tab (mode toggle + usage stats + full device UUID, selectable), API Keys (BYOK only), Audio, General. Opened via cog button (`@Environment(\.openSettings)`), ⌘,, or menu bar

### iOS
- **Onboarding** (first launch): Same as macOS (shared `OnboardingView`)
- **Home** (`ReadyStateView_iOS`): Logo, mode status pill, mic waveform monitor, start button. Mic-only (no system audio toggle)
- **Recording**: Header with timer, mic waveform, terminal-style stop button (red), custom section picker for transcript/insights/notes
- **Stopped session**: Terminal-style buttons: home, resume (green), save (blue), copy. "save" and "home" both call `goHome()` (saves + clears)
- **History tab**: `NavigationStack` list with swipe-to-delete, drill-down detail with transcript/insights/notes segments
- **Settings tab**: `Form` with mode picker, usage (managed), API keys (BYOK), audio permissions, model selection, device ID, version
- **Tab bar**: Record / History / Settings — standard iOS tab navigation

## Monetization architecture

Two parallel modes, no conflicts:

- **BYOK Mode**: User's own API keys, unlimited, no backend, no tracking
- **Managed Mode**: 500 free min/month, Deepgram via temp API keys (backend issues short-lived scoped keys), OpenAI proxied through backend, hard-blocked at limit
- Mode toggle is a local routing switch only; user-entered BYOK keys persist in `@AppStorage` across mode switches (Secrets defaults are stripped in managed mode)
- Usage tracking is 100% server-side (Vercel KV, keyed by Keychain-stored device UUID); switching modes never resets the counter
- Device ID stored in macOS Keychain (`DeviceIdentifier.swift`) — persists across reinstalls, tamper-resistant
- Backend API keys (Deepgram/OpenAI) stored as Vercel encrypted env vars, never exposed to client
- At limit: user must switch to BYOK or wait for monthly reset — no paid tiers yet
- Cost: ~$3.75/user/month at full 500 min usage
- Backend is a separate repo (`miniti-api`), deployed at `https://miniti-api.vercel.app`; full spec in `BACKEND_SPEC.md`
### Backend API (`miniti-api`)
- Repo: `12ian34/miniti-api` (private), deployed at `https://miniti-api.vercel.app`
- Stack: Next.js 14 (App Router, edge runtime), TypeScript, Vercel, Upstash Redis via `@vercel/kv`
- All routes require `X-API-Key` (shared secret, timing-safe verified) + `X-Device-ID` (UUID) headers
- API key is XOR-obfuscated in `MinitiAPIService.swift` (not plain text in source/binary)
- Env vars (Vercel, encrypted): `OPENAI_API_KEY`, `DEEPGRAM_API_KEY`, `DEEPGRAM_PROJECT_ID`, `API_SECRET_KEY`, KV connection vars
- Deepgram key needs **Member** role (can create temp keys), **never expire**

**Endpoints:**
- `GET /api/usage` — check device minutes used/remaining (30 req/min)
- `POST /api/session` — start session, returns temp Deepgram key (4hr TTL, `usage:write` scope); returns 402 if limit reached (5 req/min)
- `POST /api/session/end` — report duration, increment usage counter; server caps at wall-clock elapsed (10 req/min)
- `POST /api/insights` — OpenAI proxy for transcript analysis; modes: `standard` or `meddpicc`; transcript capped at 100KB (10 req/min)

**Session flow:** launch → `GET /usage` → `POST /session` (get temp key) → connect directly to Deepgram WebSocket with temp key → periodic `POST /insights` → stop → `POST /session/end` → final `POST /insights`

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

## Distribution

### macOS
Direct notarized distribution via DMG (not Mac App Store — sandbox restrictions block `AudioHardwareCreateProcessTap`).

### Release workflow
1. Bump version in `Miniti/Info.plist`, `MinitiMobile/Info.plist` (`CFBundleShortVersionString`) and `project.pbxproj` (`MARKETING_VERSION` — 6 places: 2 per target × 3 targets, Debug + Release). All targets share the same version number.
2. Xcode: **Product → Archive → Distribute App → Developer ID → Upload** (notarizes automatically)
3. Export the notarized `Miniti.app`
4. Run `./scripts/build-dmg.sh /path/to/Miniti.app` → produces `Miniti-<version>.dmg`
5. Upload DMG to website / GitHub Releases

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
