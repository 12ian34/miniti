# Miniti

macOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio, streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI. Two modes: managed (500 free min/month) or BYOK (own API keys, unlimited).

## Architecture

- **Miniti/MinitiApp.swift** – App entry point, onboarding gate, menu bar, global keyboard shortcuts
- **Miniti/Models/AppState.swift** – Central `@MainActor` state: recording, transcript, insights, audio monitoring, app mode, usage tracking
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

## Key patterns

- `AppState` is the single source of truth, injected via `@EnvironmentObject`
- `AppMode` enum (`.byok` / `.managed`) stored in `@AppStorage("appMode")` — purely a routing toggle
- Audio levels: `microphoneLevel` and `systemAudioLevel` are published separately for per-source waveforms, plus a combined `audioLevel`
- Audio monitoring: home screen starts lightweight capture (no Deepgram) to verify sources before recording
- `@AppStorage` persists API keys, model selection, audio source toggles, app mode, and onboarding state
- Secrets.swift (gitignored) provides default API keys; Secrets.example.swift is the template. **Only seeded in BYOK mode** — managed users never get Secrets keys written to `@AppStorage`. On switch to managed, any keys matching Secrets defaults are cleared.
- Mode-aware service routing: `startRecording()`, `updateLiveInsights()`, `generateFinalInsightsAndSave()` all branch on `appMode`
- BYOK keys persist in `@AppStorage` regardless of active mode — switching never clears user-entered keys (only Secrets defaults are stripped in managed mode)

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

### System Audio permission
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

- **Onboarding** (first launch): Mode selection — "Early Adopter" (managed, 500 min/month) or "Bring Your Own Keys"
- **Home** (`ReadyStateView`): Mode-aware — managed shows usage status, BYOK shows API pills; model selector, audio source panel, start button; cog button (top-right) opens settings
- **Home (limit reached)**: In managed mode when 500 min used — inline "switch to BYOK" prompt, start button disabled
- **Recording**: TerminalHeader with red dot + timer, stop button, dual labeled waveforms (mic green, system blue), transcript, notes, live insights
- **Stopped session**: Same layout; rec button shows "cont" (same position as stop — model selector sits after the button, status dot hidden when not recording). Resumes the current session (no new meeting created). In managed mode, resuming requests a fresh temp Deepgram key (the previous one is cleared on stop).
- **History**: Sidebar list → detail view
- **Settings**: Account tab (mode toggle + usage stats + full device UUID, selectable), API Keys (BYOK only), Audio, General. Opened via cog button (`@Environment(\.openSettings)`), ⌘,, or menu bar

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

## Distribution

Direct notarized distribution via DMG (not Mac App Store — sandbox restrictions block `AudioHardwareCreateProcessTap`).

### Release workflow
1. Bump version in `Info.plist` (`CFBundleShortVersionString`) and `project.pbxproj` (`MARKETING_VERSION`)
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
