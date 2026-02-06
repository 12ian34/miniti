# Miniti

macOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio, streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI. Two modes: managed (500 free min/month) or BYOK (own API keys, unlimited).

## Architecture

- **Miniti/MinitiApp.swift** – App entry point, onboarding gate, menu bar, global keyboard shortcuts
- **Miniti/Models/AppState.swift** – Central `@MainActor` state: recording, transcript, insights, audio monitoring, app mode, usage tracking
- **Miniti/Models/Meeting.swift** – SwiftData model for persisted meetings
- **Miniti/Services/AudioCaptureService.swift** – Mic (AVAudioEngine) + system audio (ScreenCaptureKit/SCStream) capture, publishes separate levels
- **Miniti/Services/DeepgramService.swift** – WebSocket streaming transcription (Nova-2/Nova-3)
- **Miniti/Services/InsightsService.swift** – OpenAI API for summaries, action items, MEDDPICC
- **Miniti/Services/DeviceIdentifier.swift** – Keychain-based persistent device UUID (survives reinstalls)
- **Miniti/Services/MinitiAPIService.swift** – Backend communication: usage checks, temp key sessions, insights proxy. Auth via `X-API-Key` (shared app secret) + `X-Device-ID` headers on every request; device ID never sent in body/query.
- **Miniti/Views/MeetingView.swift** – Main meeting UI: ReadyStateView (home), active session, audio source panel, waveforms
- **Miniti/Views/MainWindow.swift** – Window chrome: sidebar, content area, status bar
- **Miniti/Views/TranscriptView.swift** – Live transcript with speaker colors
- **Miniti/Views/InsightsView.swift** – AI insights panel (standard + MEDDPICC modes)
- **Miniti/Views/HistoryView.swift** – Past meetings browser
- **Miniti/Views/SettingsView.swift** – Account mode toggle, API keys, audio, general preferences
- **Miniti/Views/OnboardingView.swift** – First-launch mode selection (managed vs BYOK)
- **Miniti/Views/UsageBanner.swift** – Remaining minutes display + ManagedStatusView for home screen
- **Miniti/Views/LimitReachedView.swift** – Hard block when 500 min exhausted, offers BYOK switch

## Key patterns

- `AppState` is the single source of truth, injected via `@EnvironmentObject`
- `AppMode` enum (`.byok` / `.managed`) stored in `@AppStorage("appMode")` — purely a routing toggle
- Audio levels: `microphoneLevel` and `systemAudioLevel` are published separately for per-source waveforms, plus a combined `audioLevel`
- Audio monitoring: home screen starts lightweight capture (no Deepgram) to verify sources before recording
- `@AppStorage` persists API keys, model selection, audio source toggles, app mode, and onboarding state
- Secrets.swift (gitignored) provides default API keys; Secrets.example.swift is the template
- Mode-aware service routing: `startRecording()`, `updateLiveInsights()`, `generateFinalInsightsAndSave()` all branch on `appMode`
- BYOK keys persist in `@AppStorage` regardless of active mode — switching never clears them

## Audio flow

1. `AudioCaptureService.startCapture(microphone:systemAudio:)` starts AVAudioEngine (mic) and/or SCStream (system)
2. Mic audio: converted to 16kHz mono PCM16 via AVAudioConverter, level via `vDSP_measqv`
3. System audio: SCStream Float32 → PCM16 via vDSP (`vDSP_vsmul` + `vDSP_vclip` + `vDSP_vfix16`), level via `vDSP_measqv`
4. **Mono downmix**: System audio conversion always extracts first channel via `vDSP_Stride(channelCount)` — handles stereo even though SCStream currently delivers mono at 16kHz. Same stride approach used for level metering.
5. **Mixing**: When both sources active, system audio PCM16 goes into a pre-allocated Int16 ring buffer (8000 samples, ~500ms at 16kHz, NSLock-protected, zero allocations). Mic callback drains the ring buffer and mixes via vDSP (`vDSP_vadd` after float conversion). **Soft AGC**: mic is boosted to target 0.06 RMS (up to 15x, since raw mic RMS is typically ~0.003 vs system ~0.09), system audio scaled to 25%. This keeps mic ~2x louder than system in the mix. Debug log `[AudioMix]` prints every 5s with drain count, boost, gain, and both RMS values.
6. `onAudioBuffer` callback → DeepgramService (nil during monitoring)
7. Levels flow independently: AudioCaptureService → Combine → AppState → SwiftUI views (throttled to ~20Hz, waveforms at 16Hz)
8. **Level display**: `SourceWaveform` uses `pow(level, 0.2)` power curve (not linear) so quiet mic signals (~0.003 RMS) show visible bar movement.
9. **SCStream requires `.screen` output** registered even though we only use audio — without it, errors spam the console. Frame size set to 32x32 (minimal) to avoid "Invalid view geometry" warnings.

### Known limitations
- **Diarization in mono mix is imperfect**: when mic and system audio are close in volume (after AGC), Deepgram may assign both to the same speaker. Reducing mic boost improves diarization but risks mic being inaudible. Current tuning (micBoost up to 15x, sysGain 0.25) prioritises both sources being transcribed over accurate speaker labels.
- **Mic RMS is naturally ~30x lower than system audio** (~0.003 vs ~0.09) because mic is analog at distance while system audio is direct digital. The soft AGC compensates but amplifies noise floor too.

## UI states

- **Onboarding** (first launch): Mode selection — "Early Adopter" (managed, 500 min/month) or "Bring Your Own Keys"
- **Home** (`ReadyStateView`): Mode-aware — managed shows usage status, BYOK shows API pills; model selector, audio source panel, start button; cog button (top-right) opens settings
- **Home (limit reached)**: In managed mode when 500 min used — inline "switch to BYOK" prompt, start button disabled
- **Recording**: TerminalHeader with red dot + timer, stop button, dual labeled waveforms (mic green, system blue), transcript, notes, live insights
- **Stopped session**: Same layout; rec button shows "cont" (same position as stop — model selector sits after the button, status dot hidden when not recording). Resumes the current session (no new meeting created)
- **History**: Sidebar list → detail view
- **Settings**: Account tab (mode toggle + usage stats + full device UUID, selectable), API Keys, Audio, General. Opened via cog button, ⌘, or menu bar

## Monetization architecture

Two parallel modes, no conflicts:

- **BYOK Mode**: User's own API keys, unlimited, no backend, no tracking
- **Managed Mode**: 500 free min/month, Deepgram via temp API keys (backend issues short-lived scoped keys), OpenAI proxied through backend, hard-blocked at limit
- Mode toggle is a local routing switch only; BYOK keys persist in `@AppStorage` regardless of active mode
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
