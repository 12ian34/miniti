# Miniti

macOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio, streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI.

## Architecture

- **Miniti/MinitiApp.swift** – App entry point, menu bar, global keyboard shortcuts
- **Miniti/Models/AppState.swift** – Central `@MainActor` state: recording, transcript segments, insights, audio monitoring
- **Miniti/Models/Meeting.swift** – SwiftData model for persisted meetings
- **Miniti/Services/AudioCaptureService.swift** – Mic (AVAudioEngine) + system audio (ScreenCaptureKit/SCStream) capture, publishes separate levels
- **Miniti/Services/DeepgramService.swift** – WebSocket streaming transcription (Nova-2/Nova-3)
- **Miniti/Services/InsightsService.swift** – OpenAI API for summaries, action items, MEDDPICC
- **Miniti/Views/MeetingView.swift** – Main meeting UI: ReadyStateView (home), active session, audio source panel, waveforms
- **Miniti/Views/MainWindow.swift** – Window chrome: sidebar, content area, status bar
- **Miniti/Views/TranscriptView.swift** – Live transcript with speaker colors
- **Miniti/Views/InsightsView.swift** – AI insights panel (standard + MEDDPICC modes)
- **Miniti/Views/HistoryView.swift** – Past meetings browser
- **Miniti/Views/SettingsView.swift** – API keys & preferences

## Key patterns

- `AppState` is the single source of truth, injected via `@EnvironmentObject`
- Audio levels: `microphoneLevel` and `systemAudioLevel` are published separately for per-source waveforms, plus a combined `audioLevel`
- Audio monitoring: home screen starts lightweight capture (no Deepgram) to verify sources before recording
- `@AppStorage` persists API keys, model selection, and audio source toggles (`captureMicrophone`, `captureSystemAudio`)
- Secrets.swift (gitignored) provides default API keys; Secrets.example.swift is the template

## Audio flow

1. `AudioCaptureService.startCapture(microphone:systemAudio:)` starts AVAudioEngine (mic) and/or SCStream (system)
2. Mic audio: converted to 16kHz mono PCM16 via AVAudioConverter, level via `vDSP_measqv`
3. System audio: SCStream Float32 → PCM16 via vDSP (`vDSP_vsmul` + `vDSP_vclip` + `vDSP_vfix16`), level via `vDSP_measqv`
4. **Mixing**: When both sources active, system audio PCM16 goes into a pre-allocated Int16 ring buffer (3200 samples, ~200ms, NSLock-protected, zero allocations). Mic callback drains the ring buffer and mixes via vDSP (`vDSP_vadd` after float conversion). **Gain normalization**: running EMA of RMS for each source; system audio is scaled by `micRMS / sysRMS` (clamped 0.1–5.0) before mixing, ensuring balanced levels for diarization.
5. `onAudioBuffer` callback → DeepgramService (nil during monitoring)
6. Levels flow independently: AudioCaptureService → Combine → AppState → SwiftUI views (throttled to ~20Hz, waveforms at 16Hz)

## UI states

- **Home** (`ReadyStateView`): Logo, API pills, model selector, audio source panel (mic/system toggles + waveforms), start button
- **Recording**: TerminalHeader with dual labeled waveforms (mic green, system blue), transcript, notes, live insights
- **Stopped session**: Same layout; rec button shows "cont" and resumes the current session (no new meeting created)
- **History**: Sidebar list → detail view
