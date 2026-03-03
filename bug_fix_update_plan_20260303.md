# Audio Reliability Hardening plan for 1.12

## Summary
This plan merges both proposals into one robust, low-regression reliability pass for macOS + iOS + managed backend session durability, without removing features or changing core UX flows.

Scope defaults:
1. Full single pass.
2. Auto-heal first, with subtle non-blocking in-app recovery status.
3. Conservative threshold tuning first (instrumentation before aggressive timing changes).

## Implementation Scope

### 1) macOS system-audio resilience (`Miniti/Services/AudioCaptureService.swift`)
1. Reset ring buffer before system tap restart paths:
- `handleDefaultOutputDeviceChange`
- `recoverSystemTapAfterSilentStall`

2. Reset silence/recovery timing state after successful restart:
- set `lastSystemNonSilentAt = now`
- set/update `lastSystemAutoRestartAt` to prevent immediate redundant restart

3. Add callback-stall detection in mic callback path:
- detect “no system callbacks arriving” separately from “callbacks are silent”
- watchdog cadence: every 2s
- recovery trigger: callback gap > 6s (with startup grace window)
- cooldown to avoid storms

4. Keep existing silent-stall recovery but make it coexist with callback-stall recovery.

5. Add bounded automatic retry for failed system tap recovery:
- exponential backoff: 1s, 2s, 4s, 8s
- max 4 attempts
- no retries for explicit permission-denied failures

6. Make system tap start cleanup-safe on partial failure:
- ensure aggregate/tap/proc resources are always torn down if setup aborts mid-path.

### 2) iOS route-change hardening (`MinitiMobile/AudioCaptureService_iOS.swift`)
1. Use dynamic tap format:
- install tap with `format: nil`
- rebuild converter in callback when `buffer.format` changes

2. Add proactive route-change restart:
- track active input identity (UID/port)
- on route change, if input identity changed and capture is active, trigger debounced restart
- coalesce with existing engine configuration restart path

3. Update audio session options:
- keep `.allowBluetoothA2DP`
- add `.allowBluetooth` for HFP call-profile compatibility

### 3) Deepgram transport resilience (`Miniti/Services/DeepgramService.swift`, `Miniti/Models/AppState.swift`)
1. Add reconnect orchestration when recording is active and connection enters error state.
2. Retry policy:
- reconnect attempts: 3
- backoff: 1s, 2s, 5s
3. Add transcript starvation watchdog:
- if audio packets/levels indicate ongoing speech but no transcript for threshold window, trigger one reconnect cycle.
4. Keep capture running while transport reconnects.

### 4) Managed session durability in app (`Miniti/Models/AppState.swift`, model/persistence layer)
1. Persist pending `/session/end` reports if stop-report call fails.
2. Retry pending reports:
- on app launch
- on foreground transition
- after successful network-managed calls
3. Clear `managedSessionId` only after:
- successful backend acknowledgment, or
- durable queue persistence is confirmed.

### 5) Backend idempotency and retry safety (`../miniti-api/app/api/session/end/route.ts`, `../miniti-api/lib/deepgram.ts`)
1. Make `/api/session/end` idempotent by `(deviceId, sessionId)`:
- first success stores canonical result in KV
- duplicate calls return stored result without incrementing usage again
2. Keep “missing session record still accepted” behavior, but still idempotent.
3. Add transient retry around temp Deepgram key creation:
- 3 attempts with jitter on network/5xx failures.

### 6) Documentation and release notes (`README.md`, `claude.md`)
1. README Bluetooth troubleshooting update:
- app auto-recovers system audio when possible
- expected recovery latency window
- fallback actions if still degraded
2. Add changelog entry for v1.11.1 reliability hardening using user-facing language.

## Public API / Interface / Type Changes
1. Backend `POST /api/session/end` response adds:
- `session_finalized: boolean`
- `idempotent_replay: boolean` (optional diagnostic)

2. App state additions:
- `audioRecoveryState` enum for UI/status (`healthy`, `recovering`, `degraded`)
- optional counters/timestamps for recovery diagnostics

3. New persisted client record:
- `PendingSessionEndReport` with `sessionId`, `deviceId`, `durationMinutes`, `createdAt`, `retryCount`.

## Test Cases and Scenarios

### macOS capture + Bluetooth
1. Start recording on built-in output, switch to AirPods, then join/leave call profile.
2. Validate callback-stall recovery and silent-stall recovery both heal without manual restart.
3. Validate ring buffer reset prevents stale audio bleed after restart.
4. Validate no restart storm during rapid output-device toggles.

### iOS capture
1. Start with built-in mic, switch to Bluetooth input/output, verify continuous capture.
2. Force route change where engine config notification is delayed; verify proactive restart path.
3. Validate HFP/A2DP transitions with `.allowBluetooth` + `.allowBluetoothA2DP`.

### Deepgram transport
1. Drop websocket mid-recording, verify automatic reconnect and resumed transcription.
2. Simulate transcript starvation with continuing audio flow, verify watchdog-triggered reconnect.

### Managed session accounting
1. Force `/session/end` failure, verify pending report persistence and later retry.
2. Replay identical `/session/end` request; verify backend idempotent result and no double usage increment.

### Regression checks
1. Mic-only mode unchanged.
2. System-only mode unchanged.
3. BYOK and managed user flows unchanged.
4. Existing onboarding/terms, history, insights, and save/discard behavior unchanged.

## Rollout and Monitoring
1. Ship with feature flags:
- `audio_callback_stall_watchdog`
- `deepgram_auto_reconnect`
- `session_end_idempotency`
2. Monitor:
- recovery attempt counts and success rate
- callback-stall incidence
- transcript starvation incidence
- duplicate `/session/end` replay count
- user-reported “other person dropped out” rate
3. If stable for one release cycle, remove flags and keep diagnostics.

## Acceptance Criteria
1. Bluetooth/device-switch scenarios no longer require manual stop/resume in normal cases.
2. No silent transcription drop lasting beyond retry windows without user-visible degraded status.
3. Managed usage reporting remains accurate under retries/network failures.
4. No feature removals and no behavior regressions in core recording workflow.

## Repo and Documentation Context

### Codebase layout
- **App repo**: `/Users/ian/dev/miniti` — macOS + iOS Swift app (this repo)
- **Backend repo**: `../miniti-api` — Next.js backend, also open for changes in this plan
- Both repos have a `CLAUDE.md` at their root and a `README.md`

### Documentation requirements
- **`CLAUDE.md` (app repo)**: Must be kept up to date with architecture, key patterns, and a changelog at the top. The changelog must use human-readable, user-facing language — no code references, function names, file paths, or implementation details. Write what changed from the user's perspective.
- **`CLAUDE.md` (backend repo at `../miniti-api`)**: Must be kept up to date if any backend changes are made (endpoint contracts, data model, behavior).
- **`README.md` (both repos)**: Must be kept current with any user-facing changes (troubleshooting, features, etc.).
- Never modify older changelog entries — only add new entries at the top.

### Version bump to 1.12.0
- Bump version from `1.11.1` to `1.12.0` in:
  - `Miniti/Info.plist` (`CFBundleShortVersionString`)
  - `MinitiMobile/Info.plist` (`CFBundleShortVersionString`)
  - `project.pbxproj` (`MARKETING_VERSION` — 6 places: 2 per target × 3 targets, Debug + Release)
- in the `### 2026-03-03 - v1.12.0 (unreleased)` changelog section at the top of `CLAUDE.md`, add human-idiot readable entries for all changes in this plan
- Update `../miniti-api/app/api/version/route.ts` with the new `latest_version` and `release_notes` after all changes are complete

## Assumptions and Defaults
1. Conservative timing values ship first; threshold tightening only after telemetry confirms need.
2. UI surface for recovery remains subtle and non-blocking.
3. Backward compatibility is maintained for existing clients and backend deployments.
4. Plan is implementation-ready for direct execution in one pass.
