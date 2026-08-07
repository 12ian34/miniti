# Miniti Android — Build Plan & Full Context

This document is the complete context and build plan for `miniti-android`, a native Android port of the Miniti meeting assistant. It is written to be self-contained: the agent working in the new repo has no access to the macOS/iOS codebase, so every relevant fact, contract, and pattern is captured here.

---

## 1. What Miniti is

Miniti is a meeting assistant that records audio, streams it to Deepgram for live transcription with speaker diarization, and generates AI insights via OpenAI. It exists today on macOS (native SwiftUI, mic + system audio) and iOS (native SwiftUI, mic only). This repo is the Android port.

**Tagline:** "multi-dimensional meetings"

**Monetization model (for context — Android v1 ships with no paid tier):**
- **BYOK** — user supplies own Deepgram + OpenAI keys, unlimited, no backend
- **Managed Free** — 500 minutes/month via Miniti backend (Deepgram grant JWTs, OpenAI proxied)
- **Managed Pro** — 5,000 minutes/month, $5/month. Subscription rail is platform-specific (Polar on macOS, StoreKit on iOS, Google Play Billing on Android when added in v1.1+)

**Android v1 scope:** BYOK + Managed Free only. No Pro tier, no Google Play Billing. Users who hit the 500-min cap either switch to BYOK or wait for monthly reset.

---

## 2. Feature parity target (matches iOS exactly)

### In scope for v1
- Mic recording with background support via foreground service
- Live Deepgram transcription (Nova-3, 11 languages)
- Live AI insights: Summary, Sales, Coaching, Questions
- Meeting history browser with full-text search
- Editable meeting titles and notes
- Terms acceptance gate, onboarding gate, force-update gate
- Managed mode (free only) and BYOK mode
- Settings: language, filler word customization, subscription/usage display, API keys (BYOK), webhooks, auto-stop, diagnostics
- Debug logger with 5-tap unlock from version text
- Dark mode terminal-style UI
- Outbound webhooks on meeting save and insights regeneration
- Resume interrupted meetings on launch
- Ongoing notification during recording (Android equivalent of iOS Live Activity — shows timer, title, current transcript line, tap to return)
- Auto-stop on silence (configurable: off/3/5/10/15 min, default 5)

### Explicitly out of scope for v1
- System audio capture (Android's `MediaProjection` path only works for apps that opt in, so Zoom/Meet/Teams/Slack wouldn't work anyway — skip entirely)
- Google Play Billing and any Pro tier (defer to v1.1+)
- Google Calendar integration (macOS only)
- Attio CRM integration (macOS only)
- Markdown auto-export to local folder (macOS only)
- Multi-speaker "You" vs "Others" mic/system separation (N/A without system audio — use Deepgram native diarization only, same as iOS)

---

## 3. Tech stack

| Concern | Choice |
|---|---|
| Language | Kotlin 2.0+ |
| UI | Jetpack Compose + Material 3 (themed dark) |
| State | ViewModel + StateFlow (manual DI, no Hilt for v1) |
| Persistence | Room (relational data) + DataStore Preferences (key-value settings) |
| Networking | Ktor client (WebSocket for Deepgram, HTTP for backend and OpenAI) |
| Serialization | kotlinx.serialization |
| Audio | `AudioRecord` API, 16kHz mono PCM16 |
| Background | Foreground service with `FOREGROUND_SERVICE_MICROPHONE` type |
| Billing | None in v1 |
| Min SDK | 26 (Android 8.0) |
| Target SDK | 34 (Android 14) |
| Package name | `com.miniti.android` |

### Version lockstep
Android version numbers stay in lockstep with macOS/iOS. Whatever is current in the Swift repo's `CFBundleShortVersionString` and `MARKETING_VERSION` is what Android ships. Bump together.

---

## 4. Architecture

Mirror the iOS layering so future cross-platform work maps 1:1.

```
app/
  src/main/kotlin/com/miniti/android/
    data/
      Meeting.kt                  Room entity — matches SwiftData `Meeting`
      TranscriptSegment.kt        Room entity
      SuggestedQuestion.kt        Embedded/JSON-blob type
      MeetingAttendee.kt          Embedded/JSON-blob type
      MeetingDao.kt
      MinitiDatabase.kt           Room database
      Preferences.kt              DataStore keys + helpers (equivalent of @AppStorage)
    services/
      AudioCaptureService.kt      Foreground service; AudioRecord + notification
      DeepgramClient.kt           Ktor WebSocket, reconnect, watchdog
      InsightsClient.kt           OpenAI HTTP (BYOK) or backend proxy (managed)
      MinitiApiClient.kt          Backend HTTP client
      WebhookClient.kt            Fire-and-forget outbound webhook
      DebugLogger.kt              1000-entry ring buffer, thread-safe, API key redaction
      DeviceIdentifier.kt         Android Keystore-backed stable UUID
      TrainingMetrics.kt          Pure computation — filler, pace, talk ratio, etc.
      InsightsMode.kt             Stable raw values: standard / meddpicc / training / questions; training displays as Coaching
      TranscriptionLanguage.kt    Enum with 11 languages + default fillers
    state/
      AppStateViewModel.kt        Singleton-scoped, equivalent of @MainActor AppState
      AudioLevelsState.kt         Separate flow for high-frequency level updates
      TranscriptRuntimeState.kt   Separate flow for transcript updates
    ui/
      MinitiApp.kt                NavHost, gate routing (force update → terms → onboarding → main)
      theme/
        Color.kt                  Port of ColorPalette.swift
        Theme.kt                  Material 3 dark theme
      screens/
        HomeScreen.kt
        RecordingScreen.kt
        HistoryScreen.kt
        HistoryDetailScreen.kt
        SettingsScreen.kt
        OnboardingScreen.kt
        TermsScreen.kt
        ForceUpdateScreen.kt
        DebugLogScreen.kt
      components/
        TranscriptView.kt
        InsightsView.kt           Mode tabs (Summary/Sales/Coaching/Questions)
        TrainingContent.kt
        QuestionsContent.kt
        SourceWaveform.kt
        UsageBanner.kt
        LimitReachedView.kt
    MainActivity.kt
  src/main/AndroidManifest.xml
  src/test/kotlin/...             JUnit tests — port of iOS MinitiTests
```

### State model

`AppStateViewModel` is the central hub, equivalent to iOS `AppState`. It holds:

- Recording state: `currentMeeting`, `liveSegments`, `isRecording`, `isPaused`, `recordingStartDate`, `recordingDuration`
- Transcript: streaming + finalized segments, interim text
- Insights: `liveSummary`, `liveActionItems`, `liveTopics`, `liveDiscussionFlow`, the eight MEDDPICC fields, `suggestedQuestions`
- Audio: `microphoneLevel` (published separately as a hot flow to avoid recomposing the whole tree)
- App mode: `AppMode.BYOK` or `AppMode.MANAGED`, stored in DataStore under key `"appMode"`
- Usage: `usageInfo` (minutes used / limit / reset date) from backend
- Gates: `hasAcceptedTerms`, `needsOnboarding`, `requiresForceUpdate`, `availableUpdate`
- Recovery: `managedSessionId` (persisted across launches for orphaned-session usage reporting), pending session-end queue
- Device state: `isDeviceDisabled` (set on 403 `device_disabled` from backend)

All high-frequency recording signals (audio levels, interim transcript) must be published via dedicated `StateFlow`s with `.distinctUntilChanged()` to avoid tearing down the whole Compose tree every 50ms.

### Gate routing

On launch, `MinitiApp` decides which screen is root in this priority order:
1. `ForceUpdateScreen` if `requiresForceUpdate` — blocks everything
2. `TermsScreen` if `acceptedTermsVersion < currentTermsVersion` (currently `1`)
3. `OnboardingScreen` if `needsOnboarding` (first launch)
4. Main app (`HomeScreen` → `RecordingScreen` → `HistoryScreen` → `SettingsScreen`)

Terms versioning: `currentTermsVersion = 1`. Migrate legacy bool users (`hasAcceptedTerms == true`) by promoting them to version 1 on first launch. To force re-acceptance after a legal update, bump the constant.

---

## 5. Backend API — complete spec

Backend repo is `miniti-api` (separate, Next.js on Vercel). Base URL: `https://api.miniti.app` (legacy alias `https://miniti-api.vercel.app` still active). Android v1 uses the same backend with a new `X-Platform: android` header value.

### Auth headers (all app routes require these)

- `X-API-Key` — shared app secret, XOR-obfuscated in `BuildConfig`, not plain text
- `X-Device-ID` — Keystore-backed UUID, stable across reinstalls
- `X-App-Version` — semver, e.g. `"1.21.0"`
- `X-Platform` — `"android"` (new value — iOS sends `"iOS"`, macOS sends `"macOS"`)
- `X-App-Mode` — `"byok"` or `"managed"` (optional but recommended)

Backend will respond with `403 {"error": "device_disabled"}` if the device has been disabled by admin. App must set `isDeviceDisabled = true` and block recording with an "account disabled" message.

### Rate limits

All errors follow `{"error": "code", "message": "..."}`. Key status codes:
- `402` — limit reached (managed mode, 500 min cap hit)
- `429` — rate limited
- `403` — device disabled

### Endpoints used by Android v1

#### `GET /api/version`
Called once at launch, fire-and-forget. Does not block on failure.

**Request:** headers only. `X-Device-ID` is optional here (unlike other endpoints) but send it anyway — backend uses it to touch the device record.

**Response:**
```json
{
  "latest_version": "1.21.0",
  "min_version": "1.0.0",
  "download_url": "https://play.google.com/store/apps/details?id=com.miniti.android",
  "release_notes": "markdown string"
}
```

**Behavior:**
- If `min_version > current`, set `requiresForceUpdate = true` and show the non-dismissable `ForceUpdateScreen` above all other gates.
- Otherwise, continue without showing an update banner. Normal Android updates should use the Play Store's update surfaces; `/api/version` is only the minimum-version force gate. Supported clients may receive their own version as `latest_version` with empty `release_notes`.
- `min_version` is per-platform on the backend (`ANDROID_MIN_VERSION` env var, defaults to `"1.0.0"`). Bumping it instantly forces all older clients to update on next launch.

#### `GET /api/usage`
Called in managed mode to check remaining minutes. 30 req/min per device.

**Response:**
```json
{
  "device_id": "uuid",
  "minutes_used": 127.3,
  "minutes_limit": 500,
  "minutes_remaining": 372.7,
  "reset_date": "2026-05-01T00:00:00Z",
  "tier": "free",
  "subscription_status": null
}
```

Note: Vercel KV returns numbers as strings sometimes. Use a lenient decoder that accepts both `Double` and `String` for numeric fields (same pattern as iOS `UsageInfo`).

Minutes display uses `.roundToInt()` (not truncation) across settings, home banner, and remaining time.

#### `POST /api/session`
Called at `startRecording()` in managed mode to get a temporary Deepgram API key. 5 req/min.

**Request body:** `{}` (no body fields required; device ID is in headers)

**Response:**
```json
{
  "session_id": "uuid",
  "deepgram_api_key": "temp_key_string",
  "expires_at": "2026-04-10T14:30:00Z"
}
```

The grant JWT has ≤1 hour TTL (`expires_at` / `expires_in`). Store `session_id` as `managedSessionId` in the Meeting entity and persist it so orphaned sessions can be reported on next launch. Refresh via `POST /api/session` before any new Deepgram connect/reconnect if the JWT is missing or within ~60s of expiry. Connect with `Authorization: Bearer <access_token>` (not `Token`).

Returns `402` if user is at limit.

#### `POST /api/session/end`
Called at `stopRecording()` in managed mode. 10 req/min. Must be durable — if it fails, queue and retry on launch, foreground, and after subsequent managed-session successes.

**Request body:**
```json
{
  "session_id": "uuid",
  "duration_seconds": 1823.5
}
```

**Response:**
```json
{
  "success": true,
  "minutes_used": 158.7,
  "minutes_remaining": 341.3
}
```

Server caps reported duration at wall-clock elapsed since session start (anti-fraud). Only clear `managedSessionId` after successful ack or durable queue persistence.

#### `POST /api/insights`
OpenAI proxy for managed mode. Replaces direct OpenAI calls. 10 req/min. Transcript capped at 100KB.

**Request body:**
```json
{
  "transcript": "Speaker 1: ...\nSpeaker 2: ...",
  "mode": "standard",
  "language": "en",
  "attendees": [
    {"email": "a@b.com", "name": "Alice", "domain": "b.com"}
  ]
}
```

- `mode`: `"standard"` | `"meddpicc"` | `"questions"` (Coaching is fully local; retain the internal `training` identifier but never call this endpoint for it)
- `language`: ISO 639-1, default `"en"`. Non-English languages instruct the model to respond in that language; JSON keys stay English.
- `attendees`: optional, used for speaker attribution context

**Response (mode=standard):**
```json
{
  "summary": "...",
  "action_items": ["..."],
  "key_decisions": ["..."],
  "topics": ["..."],
  "discussion_flow": "...",
  "suggested_title": "..."
}
```

**Response (mode=meddpicc):**
```json
{
  "metrics": "...",
  "economic_buyer": "...",
  "decision_criteria": "...",
  "decision_process": "...",
  "paper_process": "...",
  "identify_pain": "...",
  "champion": "...",
  "competition": "..."
}
```

**Response (mode=questions):**
```json
{
  "questions": [
    {
      "question": "...",
      "type": "deeper",
      "context": "why this matters"
    }
  ]
}
```

Question types: `deeper`, `challenge`, `reframe`, `clarify`, `explore`, `follow_up`.

All responses may include a `meta` object:
```json
{"meta": {"degraded": true}}
```
When `meta.degraded == true`, the response is a fallback/timeout. Client must NOT advance its incremental ack cursor (see "Client insights reliability" below).

### Session flow (managed mode)

```
Launch:
  GET /api/version       (check update gates, fire-and-forget)
  GET /api/usage         (populate usage banner)

Start recording:
  POST /api/session      (get Deepgram grant JWT)
  Connect WebSocket to wss://api.deepgram.com/... with Authorization: Bearer <access_token>
  Stream audio

Every 30s during recording (plus warmup):
  POST /api/insights mode=standard
  POST /api/insights mode=meddpicc  (staggered +15s)
  POST /api/insights mode=questions (staggered +22s)

Stop recording:
  POST /api/session/end
  POST /api/insights mode=standard  (final)
  POST /api/insights mode=meddpicc  (final)
  POST /api/insights mode=questions (final)
```

### BYOK mode

No backend calls except `GET /api/version` (which is fine — it's public-ish and helps with update checks). All Deepgram and OpenAI calls go directly to those providers using the user's keys from DataStore.

Deepgram WebSocket URL for BYOK:
```
wss://api.deepgram.com/v1/listen?model=nova-3&language={lang}&punctuate=true&diarize=true&interim_results=true&smart_format=true&encoding=linear16&sample_rate=16000&channels=1
```
Auth via `Authorization: Token {deepgram_api_key}` header for BYOK. Managed mode uses `Authorization: Bearer {access_token}` from `/api/session` (never Token for JWTs).

OpenAI for BYOK: `POST https://api.openai.com/v1/chat/completions` with `Authorization: Bearer {openai_api_key}`. Model: pinned `gpt-5-mini-2025-08-07`. System prompts must match the managed backend's prompts. Managed mode selects models server-side: incremental requests, speaker naming, catch-up, and Playbook topic extraction use pinned `gpt-5-mini-2025-08-07`; non-incremental summaries, MEDDPICC, questions, and grounded Playbook answers use pinned `gpt-5.4-mini-2026-03-17`. (Get the exact prompts and routing from the `miniti-api` repo — they live in `app/api/insights/route.ts`.)

---

## 6. Deepgram integration

### Connection

Use Ktor WebSocket client.

URL parameters (all modes):
- `model=nova-3` (hardcoded — Nova-2 removed)
- `language={ISO 639-1 code}` — from meeting language setting
- `punctuate=true`
- `diarize=true`
- `interim_results=true`
- `smart_format=true`
- `encoding=linear16`
- `sample_rate=16000`
- `channels=1`

### Audio format

Stream raw PCM16 LE mono at 16kHz as binary WebSocket messages. `AudioRecord` on Android can capture this directly — no resampling needed:

```kotlin
val record = AudioRecord(
    MediaRecorder.AudioSource.VOICE_RECOGNITION,
    16000,
    AudioFormat.CHANNEL_IN_MONO,
    AudioFormat.ENCODING_PCM_16BIT,
    bufferSize
)
```

Use `VOICE_RECOGNITION` source — it applies mild noise suppression without aggressive beam-forming, which is what you want for diarization.

### Response parsing

Deepgram sends JSON messages on the WebSocket. Relevant shape:

```json
{
  "type": "Results",
  "channel_index": [0, 1],
  "duration": 1.5,
  "start": 2.3,
  "is_final": true,
  "speech_final": false,
  "channel": {
    "alternatives": [
      {
        "transcript": "Hello there.",
        "confidence": 0.98,
        "words": [
          {
            "word": "hello",
            "start": 2.3,
            "end": 2.5,
            "confidence": 0.99,
            "speaker": 0,
            "speaker_confidence": 0.95,
            "punctuated_word": "Hello"
          }
        ]
      }
    ]
  }
}
```

Key fields:
- `is_final` — this segment won't be revised
- `speech_final` — end of a speech turn (good place to emit a finalized row)
- `words[].speaker` — Deepgram's diarization ID (0, 1, 2, ...)
- `words[].speaker_confidence` — use this to gate uncertain speaker switches

### Speaker segmentation

Port the stabilization logic from iOS (in `DeepgramService.swift`):

1. **Stricter switch confirmation.** When the speaker ID changes mid-stream, require a minimum run length (e.g. 3 words) and minimum duration (e.g. 500ms) before confirming the switch. This prevents flicker at turn boundaries.
2. **Speaker confidence gating.** If `speaker_confidence < 0.6`, treat the word as "uncertain" and don't let it trigger a new-speaker promotion.
3. **New-speaker promotion stage.** A speaker ID that has never been seen before must accumulate sustained evidence (multiple confirmed words across a short window) before being added to `detectedSpeakers`. Otherwise transient misdiarizations pollute the list.
4. **Interim gating.** Interim (not `is_final`) updates should not mutate the canonical speaker list — only finalized words can create new speakers.

Speakers are displayed as `"Speaker 1"`, `"Speaker 2"`, etc. (no "You" label — Android has no mic/system separation, same as iOS).

### Reconnect + watchdog

- **Connection errors/disconnects:** bounded reconnect with 1s → 2s → 5s backoff. Recording continues during reconnect attempts; the UI shows a subtle "reconnecting..." indicator.
- **Transcript starvation watchdog:** if audio levels remain above a speech threshold but no transcript has been received for an extended window (e.g. 20s), trigger one reconnect cycle. This catches silent WebSocket failures where the socket stays open but Deepgram stops responding.

### Language support

Eleven languages. Store defaults as a Kotlin enum with display name and default filler word list.

| Code | Display | Hard fillers (sample) |
|---|---|---|
| en | English | um, uh, like, basically, literally |
| es | Spanish | eh, este, bueno, o sea |
| fr | French | euh, bah, ben, genre |
| de | German | äh, ähm, halt, quasi |
| pt | Portuguese | né, tipo, assim |
| it | Italian | ehm, cioè, tipo |
| nl | Dutch | eh, zeg maar, gewoon |
| sv | Swedish | öh, typ, liksom |
| el | Greek | εε, εμ, ξέρεις |
| pl | Polish | yyy, eee, no |
| ru | Russian | эм, ну, типа |

(Get the exact filler lists from `InsightsService.swift` in the Swift repo when implementing — these are illustrative.)

Default language stored in DataStore under `"defaultLanguage"` (default `"en"`). Per-meeting language initialized from the default on `startNewMeeting()`.

Filler word overrides stored per-language under `"trainingFillers_{lang}"`. Migrate legacy single-language key if present.

---

## 7. OpenAI insights — prompts and modes

The exact prompts live in the `miniti-api` backend repo at `app/api/insights/route.ts`. Android v1 must pull those prompts when implementing BYOK mode so output is consistent with managed mode. In managed mode, the backend handles prompts entirely — the client just sends transcript + mode + language.

### Mode behavior summary

- **Standard:** generates `summary`, `action_items`, `key_decisions`, `topics`, `discussion_flow`, `suggested_title`
- **MEDDPICC:** generates the eight MEDDPICC fields (metrics, economic_buyer, decision_criteria, decision_process, paper_process, identify_pain, champion, competition)
- **Questions:** generates 5–10 suggested questions with type + context
- **Coaching:** 100% local — compute from transcript segments, never call OpenAI

### Decoupled background scheduling

Standard, MEDDPICC, and questions run as independent background coroutines. Each has its own in-flight flag and cadence anchor. None blocks the others.

Cadence during recording:
- Warmup: fire first request at 4 finalized segments for standard, 6 for MEDDPICC, 6 for questions
- Failed warmup cycles: at most one combined attempt every 30s
- Steady state: standard requires 60s + 4 new segments (120s max-age escape hatch), MEDDPICC 90s + 8 (180s max), questions 60s + 6 (120s max)
- Attempt gate: compare against the last attempt as well as the last success so offline failures cannot retry on every scheduler tick
- Silence gate: every mode still requires at least one new finalized segment; the max-age path prevents quiet meetings from starving on the normal segment delta

### Incremental cutover + delta window

- Send recent transcript window of 10,000 characters by default
- Track `lastFiredSegmentCount` per mode
- After 2 non-degraded responses for a mode, switch to incremental mode (send only new segments since last success)
- If delta > 35,000 chars, fall back to full recent window (recovery)
- On `meta.degraded: true`, do NOT advance the ack cursor — next request re-sends the same range

### Apply safety

`applyInsights()` must route by mode. Standard-mode responses only touch `liveSummary`, `liveActionItems`, `liveTopics`, `liveDiscussionFlow`. MEDDPICC-mode responses only touch the eight MEDDPICC fields. Questions-mode responses only touch `suggestedQuestions`. **Each field is only overwritten if the new value is non-empty** — skip empty arrays, null, or blank strings. This prevents partial or fallback responses from wiping populated data.

### Stale-final guard on stop

`generateFinalInsightsAndSave()` snapshots `meeting.id` + `segmentCount` before firing final requests. When the response arrives, only apply if:
- The meeting ID still matches
- The recording is still stopped (not resumed)
- Segment count is unchanged

Otherwise the response is stale (user resumed during the in-flight request) and must be discarded.

---

## 8. Key patterns to replicate from iOS

These are the hard-won lessons from the iOS build. Follow them.

### Debug logging

`DebugLogger` is a thread-safe 1000-entry ring buffer with automatic API key redaction. Categories: `AUDIO`, `DEEPGRAM`, `APP`. Callable from any thread (audio callbacks). Access via 5-tap on the version text in Settings → opens `DebugLogScreen` with category filters, pretty/raw view modes, copy, clear.

Key instrumentation points:
- Audio device info + format on capture start
- Audio route/device-change events
- 10s audio heartbeats
- Silent-buffer warnings
- Deepgram WebSocket/audio/transcript heartbeats
- Backend API request/response failures including HTTP status + endpoint
- App state transitions (start/stop recording)

Mirror lines to Logcat via `Log.d` for parallel debugging.

### Recording timer

Use date-based computation, not an incrementing counter:

```kotlin
val elapsed = Duration.between(recordingStartInstant, Instant.now())
```

A coroutine `delay(1.seconds)` in a loop updates the UI, but duration is always computed from the anchor. This stays accurate even if the coroutine is throttled in background.

On pause/resume, re-anchor `recordingStartInstant` from the accumulated active duration. Clear on stop and when returning to home.

### Auto-stop on silence

30-second timer fires during recording. Compares `now - lastTranscriptReceivedAt` against `autoStopMinutes * 60`. If exceeded, calls `stopRecording()` and sets `wasAutoStopped = true`. UI shows amber "auto-stopped — no speech detected" banner in the stopped state. Clear flag on `startNewMeeting()` and return-to-home.

Configurable values: 0 (off), 3, 5 (default), 10, 15 minutes. Key: `"autoStopMinutes"`.

### Periodic auto-save

30-second timer during recording calls `saveCurrentMeetingIfNeeded()`. Serialize saves through a queue — if a save is already in flight, replace any queued save with the latest snapshot. Saves do NOT set `endTime`. Only `stopRecording()` and return-to-home set `endTime`.

Meetings with `endTime == null` are identified as interrupted on next launch.

### Resume interrupted meeting

On launch (after Room is initialized), query for meetings with `endTime == null`. If found:
1. Restore `currentMeeting`
2. Reconstruct `liveSegments` from `TranscriptSegment` rows
3. Restore all insights, notes, MEDDPICC fields, `detectedSpeakers`, `suggestedQuestions`
4. Set `recordingDuration` from the last segment's timestamp
5. Restore the language

The UI automatically shows the stopped-session view because `currentMeeting != null`. User can resume or return home (which finalizes `endTime` and saves).

In managed mode, if the interrupted meeting has a `managedSessionId`, report its usage to `/api/session/end` with `duration_seconds` computed from saved segments, then clear the ID to prevent double-reporting.

Also: clean up any stale ongoing notifications on launch before showing the resume UI.

### Periodic save caveats

The save queue is async by design. Durability on abrupt termination is timing-dependent. Mitigations:
- Save on every `onPause` / `onStop` lifecycle event
- Save on `WorkManager` finished events
- Save on service destroy

### Incremental segment sync

When saving, diff `liveSegments` against the currently persisted segments (by ID) and apply:
- Delete: IDs in DB that are not in the current snapshot
- Upsert: IDs in the snapshot that are new or changed

This keeps 60+ minute sessions fast. Do the diff off the main thread. Segment IDs must persist across saves so resumed sessions update incrementally.

### Atomic list mutations

Never do `list.clear()` + `list.addAll()` on a `StateFlow<List<T>>` that backs a Compose `LazyColumn`. Compose sees intermediate states and can crash in long sessions. Build the final list locally, then assign once:

```kotlin
val updated = buildList { ... }
_liveSegments.value = updated
```

### High-frequency state isolation

Audio levels update ~20Hz. Transcript interim updates can fire ~4–10Hz. Don't put these in the main `AppStateViewModel` flow — each emission triggers recomposition of everything observing that flow. Use dedicated flows:

```kotlin
class AudioLevelsState {
    private val _micLevel = MutableStateFlow(0f)
    val micLevel: StateFlow<Float> = _micLevel.asStateFlow()
}
```

Inject these separately where needed. The waveform component observes `AudioLevelsState.micLevel` and nothing else.

### Insight apply — partial response protection

Already covered above. Emphasizing: every field must skip empty values. Test this with fallback response fixtures.

### Client insights reliability

Copy the "no-loss protocol" from iOS verbatim:
- `meta.degraded` → don't advance ack cursor
- Per-mode `request_seq` counters reject out-of-order responses
- Warmup at 4/6/6 segments for standard/MEDDPICC/questions
- Per-mode steady state: standard 60s + 4 new segments (120s max), MEDDPICC 90s + 8 (180s max), questions 60s + 6 (120s max)
- Last-attempt failure cooldown plus silence gate; maximum age still requires at least one new segment
- 2 non-degraded responses → switch to incremental
- Delta > 35k → full recovery
- Update button fires all three immediately and resets anchors
- Placeholders: "no insights yet...", "no meddpicc yet...", "no questions yet..." until first success

---

## 9. Foreground service, notification, and background audio

### Service declaration

```xml
<service
    android:name=".services.AudioCaptureService"
    android:foregroundServiceType="microphone"
    android:exported="false" />
```

Permissions:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

Runtime permission prompts needed:
- `RECORD_AUDIO` — required, block recording until granted
- `POST_NOTIFICATIONS` (API 33+) — required for the foreground service notification

### Notification

The foreground service notification is Android's equivalent of the iOS Live Activity. It must:
- Show the recording timer (auto-updating via `setWhen()` + `setUsesChronometer(true)`)
- Show the meeting title
- Show the latest transcript line (update at most once every 3 seconds, same throttle as iOS Live Activity)
- Have a "stop" action button
- Have a "return to app" click action
- Switch to a neutral color and frozen timer when paused/stopped
- Use a dedicated notification channel (`"recording"`) with `IMPORTANCE_LOW` so it doesn't make sound

When the service is stopped and the user returns home, cancel the notification.

### Audio capture

```kotlin
val bufferSize = AudioRecord.getMinBufferSize(
    16000,
    AudioFormat.CHANNEL_IN_MONO,
    AudioFormat.ENCODING_PCM_16BIT
) * 4  // Larger buffer reduces xruns

val record = AudioRecord(
    MediaRecorder.AudioSource.VOICE_RECOGNITION,
    16000,
    AudioFormat.CHANNEL_IN_MONO,
    AudioFormat.ENCODING_PCM_16BIT,
    bufferSize
)
```

Read audio on a dedicated background thread (not a coroutine dispatcher — you want a real thread here for RT audio):

```kotlin
thread(name = "miniti-audio") {
    val buf = ShortArray(1024)
    while (isCapturing) {
        val n = record.read(buf, 0, buf.size)
        if (n > 0) {
            val rms = computeRms(buf, n)
            audioLevelsState.publish(rms)
            deepgramClient.sendAudio(buf, n)
        }
    }
}
```

### Audio route changes

Register an `AudioDeviceCallback` to detect headset/bluetooth connect/disconnect mid-recording:

```kotlin
audioManager.registerAudioDeviceCallback(object : AudioDeviceCallback() {
    override fun onAudioDevicesAdded(added: Array<AudioDeviceInfo>) { /* log, maybe restart */ }
    override fun onAudioDevicesRemoved(removed: Array<AudioDeviceInfo>) { /* log, maybe restart */ }
}, handler)
```

Bluetooth SCO vs A2DP switching is the Android equivalent of the iOS Bluetooth reliability issues — log extensively and restart `AudioRecord` if the input device changes identity.

### Background behavior

With a foreground service of type `microphone`, the system keeps the process alive even when the app is backgrounded. The OS can still terminate under extreme pressure, so:
- Periodic auto-save (30s) persists transcript continuously
- Save on every lifecycle pause
- Resume interrupted meetings on next launch

---

## 10. Data model (Room)

Port the iOS `Meeting` SwiftData model to Room. Field names and types should match exactly where possible to keep webhook payloads and backend compatibility.

```kotlin
@Entity(tableName = "meetings")
data class Meeting(
    @PrimaryKey val id: String,  // UUID string
    var title: String = "untitled",
    var startTime: Long,  // epoch millis
    var endTime: Long? = null,  // null = interrupted/in-progress
    var notes: String = "",
    var language: String = "en",

    // Standard insights
    var summary: String = "",
    var actionItemsJson: String = "[]",
    var keyDecisionsJson: String = "[]",
    var topicsJson: String = "[]",
    var discussionFlow: String = "",

    // MEDDPICC
    var metrics: String = "",
    var economicBuyer: String = "",
    var decisionCriteria: String = "",
    var decisionProcess: String = "",
    var paperProcess: String = "",
    var identifyPain: String = "",
    var champion: String = "",
    var competition: String = "",

    // Questions
    var suggestedQuestionsJson: String? = null,

    // Managed-session durability
    var managedSessionId: String? = null,

    // Calendar (nullable — not used on Android v1 but keep fields for schema compat)
    var calendarEventId: String? = null,
    var attendeesJson: String? = null
)

@Entity(
    tableName = "transcript_segments",
    foreignKeys = [ForeignKey(
        entity = Meeting::class,
        parentColumns = ["id"],
        childColumns = ["meetingId"],
        onDelete = ForeignKey.CASCADE
    )],
    indices = [Index("meetingId")]
)
data class TranscriptSegment(
    @PrimaryKey val id: String,  // persists from LiveSegment
    val meetingId: String,
    val speaker: Int,  // Deepgram speaker ID
    val text: String,
    val startTime: Double,  // seconds from recording start
    val endTime: Double,
    val timestamp: Long  // epoch millis
)
```

`suggestedQuestionsJson` decodes to `List<SuggestedQuestion>` via a computed property / DAO converter.

`displayTitle` helper (on Meeting):
- Strip legacy `yyyyMMdd-HHmmss - ` prefix for old meetings
- Return `"untitled"` for timestamp-only titles
- Pass clean titles through unchanged

Use this everywhere titles are shown (history list, detail view, notification, webhook payloads).

---

## 11. Webhook payload

Fire POST to user-configured URL on meeting save and insights regeneration. 10s timeout, fire-and-forget. Log success/failure to DebugLogger.

Event types:
- `meeting.saved` — when meeting is finalized (returns home after stop)
- `meeting.updated` — when insights are regenerated for a saved meeting

Payload shape (must match iOS exactly):

```json
{
  "event": "meeting.saved",
  "meeting_id": "uuid",
  "title": "Display title",
  "start_time": "2026-04-10T14:00:00Z",
  "end_time": "2026-04-10T14:47:23Z",
  "duration_seconds": 2843,
  "language": "en",
  "summary": "...",
  "action_items": ["..."],
  "key_decisions": ["..."],
  "topics": ["..."],
  "discussion_flow": "...",
  "notes": "...",
  "meddpicc": {
    "metrics": "...",
    "economic_buyer": "...",
    "decision_criteria": "...",
    "decision_process": "...",
    "paper_process": "...",
    "identify_pain": "...",
    "champion": "...",
    "competition": "..."
  },
  "training": {
    "speakers": [
      {
        "speaker": "Speaker 1",
        "fillers_per_minute": 2.3,
        "pace_wpm": 142,
        "talk_ratio": 0.62,
        "longest_monologue_seconds": 87,
        "questions_asked": 4,
        "clarity": 14.2
      }
    ]
  },
  "suggested_questions": [
    {"question": "...", "type": "deeper", "context": "..."}
  ],
  "speaker_count": 2,
  "transcript": [
    {"speaker": "Speaker 1", "text": "...", "timestamp": 0.0},
    {"speaker": "Speaker 2", "text": "...", "timestamp": 4.2}
  ]
}
```

`calendar_event_id` and `attendees` are only included when the meeting was started from a calendar event — never set on Android v1.

---

## 12. Coaching metrics (pure computation)

Port `TrainingMetrics.compute()` from iOS. This is pure Kotlin — no network, no LLM. Runs on every new segment batch when Coaching is active, and recomputes on mode switch. Keep the internal type/storage names for compatibility; all visible labels say Coaching.

Input: `List<TranscriptSegment>`, `duration: Double` (seconds), `language: String`

Output: per-speaker struct with:
- `fillersPerMinute`
- `pacePm` (words per minute)
- `talkRatio` (fraction of total speaking time)
- `longestMonologueSeconds`
- `questionsAsked` (count of segments ending in `?` or matching question-starter patterns)
- `clarity` (average words per turn — lower is clearer)
- `fillerCounts` (map of filler word → count, sorted)

Filler detection is language-specific. Use the per-language filler list from DataStore (key `"trainingFillers_{lang}"`), falling back to the defaults in `TranscriptionLanguage`.

Helper functions to port (pure, trivially testable):
- `tokenize(text: String): List<String>` — lowercase, strip punctuation, split on whitespace
- `countPhraseOccurrences(tokens: List<String>, phrase: String): Int` — handles multi-word fillers like "you know"
- `computeLongestMonologue(segments: List<TranscriptSegment>, speaker: Int): Double`

Show Coaching metrics in `TrainingContent` with the same info-popup help text as iOS. Standardized copy: clarity helper is `"lower = clearer = better"`.

---

## 13. Settings screens

Match iOS. Sections in order:

1. **General** — startup, appearance, recording, diagnostics
2. **Language** — default language picker + link to filler detection detail (edit per-language fillers)
3. **Account** — mode toggle (BYOK/Managed), usage stats (managed), full device UUID (selectable, for support)
4. **API Keys** (BYOK only) — Deepgram key, OpenAI key, with info tooltips and masked display
5. **Audio** — permissions status, input device (read-only — Android handles device selection via system)
6. **Integrations** — webhook URL, test webhook button
7. **About** — version, privacy URL, terms URL, support URL, 5-tap debug log unlock

Hide Pro/subscription section entirely in v1 (no Google Play Billing).

No model selectors — transcription is fixed to Nova-3. BYOK insights use pinned `gpt-5-mini-2025-08-07`; managed insights show both server-selected models, pinned `gpt-5-mini-2025-08-07` and pinned `gpt-5.4-mini-2026-03-17`. Settings shows the exact models read-only for transparency.

---

## 14. Build order

Roughly 2–3 weeks of focused work without billing. Each step produces a runnable, testable build.

### Week 1 — foundation

1. Android Studio project, Gradle setup, Compose, Room, DataStore, kotlinx.serialization, Ktor, Material 3 dark theme, `BuildConfig` with XOR-obfuscated API secret
2. `ColorPalette` port from `ColorPalette.swift`
3. `DebugLogger` with ring buffer, redaction, 5-tap unlock, `DebugLogScreen`
4. `DeviceIdentifier` — Android Keystore-backed UUID, persisted to DataStore for fast read, Keystore as the anchor
5. `Preferences` — DataStore wrapper for all settings keys (mirror iOS `@AppStorage` keys)
6. `MinitiApiClient` — `GET /api/version`, `GET /api/usage`, `POST /api/session`, `POST /api/session/end`, `POST /api/insights`. All with auth headers. `X-Platform: android`.
7. Version check on launch, update banner, force update gate
8. Terms acceptance gate (versioned), `TermsScreen`
9. Onboarding gate (mode selection), `OnboardingScreen`
10. Room schema + DAOs
11. Basic navigation graph with gate routing

### Week 2 — recording pipeline

12. Runtime permission flow for `RECORD_AUDIO` and `POST_NOTIFICATIONS`
13. `AudioCaptureService` foreground service skeleton + notification channel + ongoing notification
14. `AudioRecord` capture on dedicated thread, 16kHz mono PCM16, RMS computation, audio levels flow
15. `DeepgramClient` — Ktor WebSocket, BYOK URL construction, auth header, PCM streaming
16. Managed-mode integration — fetch grant JWT via `POST /api/session`, connect with `Authorization: Bearer …`; refresh before reconnect if near expiry
17. Deepgram response parsing + speaker stabilization
18. `AppStateViewModel` recording lifecycle: start, stop, pause, resume, return home
19. Date-based recording timer
20. Auto-stop on silence
21. Reconnect + transcript starvation watchdog (managed JWT refresh on reconnect)
22. Ongoing notification live updates (title, timer, throttled transcript line)
23. Periodic auto-save (30s)
24. Resume interrupted meeting on launch
25. Orphaned managed-session reporting

### Week 3 — UI + insights + ship

26. `HomeScreen` — test mic button, waveform, usage banner, start button, update banner, animated tagline
27. `RecordingScreen` — transcript view, waveform, notes field, insights sidebar with mode tabs
28. `TranscriptView` — speaker-colored rows, merge same-speaker streaming fragments, sentence boundaries
29. `InsightsClient` — standard, MEDDPICC, questions (both BYOK direct and managed proxy paths)
30. `TrainingMetrics` pure Kotlin port
31. `InsightsView` with `TrainingContent`, `QuestionsContent`, MEDDPICC sections
32. Decoupled insights scheduling with cadence anchors, silence gate, incremental cutover, stale-final guard
33. `HistoryScreen` — list, swipe to delete, full-text search, drill-down
34. `HistoryDetailScreen` — tabs (Transcript/Insights/Sales/Coaching/Questions/Notes), generate/update insights, editable title and notes
35. `SettingsScreen` — all sections
36. `WebhookClient` + payload construction
37. Unit tests — port of iOS `MinitiTests`:
    - `MinitiApiClientTests` (JSON decoding, flexible types)
    - `TrainingMetricsTests`
    - `MeetingModelTests` (`displayTitle`, search scoring)
    - `WebhookPayloadTests`
    - `AppStateComputationTests` (`isNewer`, `parseMeetingTitle`, `buildSegmentSyncPlan`)
    - `DeepgramParsingTests`
    - `InsightsParsingTests`
    - `ColorPaletteTests`
38. Manual QA pass: long recording (60+ min), background recording, kill-and-resume, route changes, network drop mid-recording
39. Play Store listing: screenshots, description, data safety form, privacy policy URL, internal test track
40. Closed testing track → production

---

## 15. Distribution

Google Play Store. No sideloading needed.

- Internal testing track first (up to 100 testers, instant)
- Closed testing track for wider beta (staged rollout)
- Production

Versioning: lockstep with iOS/macOS. `versionName` matches Swift `CFBundleShortVersionString`. `versionCode` is a monotonically increasing integer — use `(major * 10000) + (minor * 100) + patch` so v1.21.0 = 12100.

Signing: upload key + Play App Signing (Google manages the signing key).

Play Console setup checklist:
- App name: `miniti`
- Package: `com.miniti.android`
- Category: Productivity
- Content rating: Everyone
- Privacy policy URL: (same as iOS)
- Data safety form: declares mic audio collection, transcript data transmitted to Deepgram/OpenAI (or backend), no advertising
- Target audience: 18+
- Screenshots: phone, 7" tablet, 10" tablet (reuse iOS screenshots where possible, adjusted for Android frames)

---

## 16. Required backend changes in `miniti-api`

The user will update `miniti-api` separately. Here is the exact spec for that work.

### 16.1 Accept `X-Platform: android`

Today the backend validates `X-Platform` as `iOS` or `macOS`. Add `android` as a valid value. Log it in device records so admin dashboard can distinguish.

Files to touch (in `miniti-api`):
- `lib/auth.ts` or equivalent platform validation
- Device record schema in Redis — add `android` as a possible value for the `platform` field
- Any analytics/admin queries that filter by platform

### 16.2 Add `ANDROID_MIN_VERSION` env var

Mirror `IOS_MIN_VERSION` and `MACOS_MIN_VERSION`. Default `"1.0.0"`. Used by `GET /api/version` when the incoming `X-Platform` is `android`.

Update `app/api/version/route.ts`:
- Read `ANDROID_MIN_VERSION` when platform is android
- Return it in the `min_version` field

### 16.3 Android download URL

`GET /api/version` should return a Google Play URL for Android clients:
```
https://play.google.com/store/apps/details?id=com.miniti.android
```

Add `ANDROID_DOWNLOAD_URL` env var with this value, or hardcode it in `app/api/version/route.ts` for the android platform branch.

### 16.4 Release notes per platform (optional but nice)

If feasible, support per-platform release notes so Android's update banner doesn't show "new on iOS: system audio" type messages that don't apply. Simplest approach: add `ANDROID_RELEASE_NOTES` env var alongside existing per-platform content, or filter a shared release notes string.

### 16.5 Admin dashboard

User will handle this. The dashboard needs to:
- Show `android` as a platform filter
- Display Android device records with the right platform badge
- Handle Android devices in bulk ops (disable/enable) the same as iOS/macOS

### 16.6 No changes needed for

- `POST /api/session` — works as-is, device ID is platform-agnostic
- `POST /api/session/end` — same
- `POST /api/insights` — same
- `GET /api/usage` — same
- Rate limits — same buckets
- Device disable flow — same

### 16.7 Future (v1.1+): Google Play Billing

When Pro lands on Android, add:
- `POST /api/google-play/verify` — verify a Google Play purchase token, link the entitlement to the device
- `POST /api/webhooks/google-play` — Real-Time Developer Notifications receiver for subscription lifecycle events
- Redis schema additions: `googlePlayPurchaseToken`, `googlePlayOrderId`, `googlePlaySubscriptionSource`, `google_play_sub:{purchaseToken}:devices` set for bulk ops
- Effective entitlement state logic in `/api/usage` and `/api/session` — mirror the Apple flow

**Not needed for v1.** Leaving the spec here so it's not lost.

---

## 17. Open decisions (resolved)

- **Billing in v1:** No. Ship with BYOK + Managed Free only.
- **Device identifier:** Android Keystore-backed UUID. Survives reinstalls via Keystore persistence. Does not opt into Google Auto Backup.
- **Version scheme:** Lockstep with macOS/iOS. `versionName` matches Swift `MARKETING_VERSION`. `versionCode` derived from semver.
- **Package name:** `com.miniti.android`
- **Subscription product ID (future):** `com.miniti.android.pro.monthly`
- **Repo:** separate (`miniti-android`), not a monorepo with the Swift repo

---

## 18. Changelog style

Same rules as the Swift repo:
- Human-readable, user-facing language
- No code references, function names, file paths, or implementation details
- Never modify older changelog entries — add corrections as new entries at the top
- Tag entries with `(Android)` or note "first Android release" for clarity when relevant
- User-facing docs and changelog live at `https://miniti.app/docs` and `https://miniti.app/changelog`; this repo does not ship a README

---

## 19. Out-of-the-gate sanity checks for the agent

Before writing code, the agent should:
1. Read this entire document
2. Clone and briefly inspect `miniti-api` to get the exact OpenAI prompts, request/response shapes, and any drift between this doc and reality
3. Confirm with the user that `ANDROID_MIN_VERSION` has been added to `miniti-api` env vars, or defer version gating until it is
4. Set up the Android Studio project with the stack above before touching any Miniti-specific logic
5. Get a mic-only recording + Deepgram streaming working end-to-end in BYOK mode as the first integration milestone — this validates the riskiest pieces (audio format, WebSocket, permissions, foreground service) before building UI on top

---

## 20. Non-goals — things to explicitly not do

- Do not add Hilt, Koin, or any DI framework in v1. Manual wiring in the ViewModel is fine and mirrors iOS.
- Do not try to capture system audio. It doesn't work for the apps that matter.
- Do not add a navigation library beyond Compose Navigation. No Voyager, no Decompose.
- Do not build a shared KMP module. That's a future decision; v1 is pure Android.
- Do not add analytics, Crashlytics, or any third-party SDK. Use the existing `DebugLogger` and optional diagnostics that the user can share from Settings.
- Do not add translations. The app is English-only for UI; transcription supports 11 languages but menus/settings are English.
- Do not build an iPad-equivalent tablet-optimized layout. Phone-first for v1. Room to improve later.
- Do not block on perfect parity — if a minor iOS detail is ambiguous or expensive, ship the closest Android-native equivalent and note it for follow-up.

---

That's the plan. Build mic-only, match iOS feature-for-feature, use the patterns above, update `miniti-api` with the four small backend changes in section 16, and ship to Play Store internal testing first.
