# Miniti

macOS + iOS meeting assistant app built with SwiftUI + SwiftData. Records mic + system audio (macOS) or mic-only (iOS), streams to Deepgram for live transcription with speaker diarization, generates AI insights via OpenAI. Three tiers: free managed (500 min/month), pro managed ($5/month, 5000 min/month), or BYOK (own API keys, unlimited). Pro purchase rail is platform-specific: Polar.sh on macOS and StoreKit auto-renewable subscription on iOS.

## Features

### macOS — native AI meeting assistant

- mic + system audio recording
- live transcription with deepgram
- live speaker identification
- live AI-generated summaries and action items
- live MEDDPICC analysis
- questions mode — AI-generated incisive questions to ask during or after a meeting (deeper, challenge, reframe, clarify, explore, follow-up)
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- google calendar integration — upcoming meetings, auto-fill title and attendees, auto Attio sync
- meeting history browser
- native menu bar controls
- keyboard shortcuts for everything

### iOS — mobile AI meeting assistant

- mic recording with background support
- live transcription with deepgram
- live AI-generated summaries and action items
- live MEDDPICC analysis
- questions mode — AI-generated incisive questions to ask during or after a meeting
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- meeting history browser
- Live Activity on Dynamic Island and Lock Screen (timer + live transcript)
- dark mode terminal-style UI

## Changelog

### 2026-04-04 - v1.20.0

- new: (macOS and iOS) Questions mode - a new insights tab that generates smart, context-specific questions to ask during or after a meeting.
- new: (macOS and iOS) Force update support - when a minimum version is set on the server, older app versions show a blocking "update required" screen until updated

### 2026-04-03 - v1.19.0

- new: (macOS) Google Calendar integration. See upcoming meetings, auto-start/stop, attendee context, attio auto-sync, data included in webhook (Google OAuth approval in progress).
- improvement: (macOS) Cleaned up sidebar
- improvement: (macOS and iOS) Cleaned up home screen
- improvement: (macOS and iOS) Moved training to its own section

### 2026-04-01 - v1.18.0

- new: (macOS and iOS) 10 more languages supported! Record and transcribe in English, Spanish, French, German, Portuguese, Italian, Dutch, Swedish, Greek, Polish, and Russian. Set a default, or pick per meeting. Applies to transcriptions and filler word detection.
- improvement: (macOS and iOS) Nova-3 is now the only transcription model. Nova-2 removed.
- improvement: (macOS and iOS) Settings reorganised
- improvement: (macOS and iOS) Improved update available banner

### 2026-03-28 - v1.17.0

- new: (macOS and iOS) outbound webhooks to send your meeting intelligence elsewhere e.g. zapier, make, n8n, attio or other endpoints.
- new: (macOS and iOS) auto-stop recording when no speech is detected for a configurable duration (default 5 minutes)
- improvement: (macOS) home screen button style improvements.
- improvement: (macOS) reorganised settings.

### 2026-03-25 - v1.16.0

- new: auto export as markdown to local folder (macOS), optional CLAUDE.md index for AI agents. includes notes, insights, MEDDPICC, training metrics, and full transcript. works with obsidian, claude code, etc.
- new: fast full text meeting search across titles, transcripts, notes, insights, topics, action items, MEDDPICC, and discussion flow.
- fix: iPad layout now fills the full screen width.

### 2026-03-11 - v1.15.0

- new: home screen redesign
- improvement: training stats include questions asked
- improvement: training stats detail improvements
- improvement: filler words info popup links to Settings
- improvement: added deepgram keyterms for "Miniti", "Lightdash", and "Ahuja"
- improvement: iOS share button is context-aware: sharing from transcript shares the transcript only; sharing from insights shares insights, MEDDPICC, and notes.
- improvement: iOS native toolbar items

### 2026-03-10 - v1.14.0

- new: Training stats overview on the home screen (macOS + iOS) — shows fillers/min, pace, and clarity averaged across your last 5 meetings vs last meeting, with trend arrows and info buttons.
- new: iOS copy button replaced with native share sheet.
- improvement: iOS recording waveform is now a compact multi-bar visualizer inline with the timer, matching desktop.
- improvement: iOS saving a meeting shows a brief "saved" confirmation.
- improvement: iOS Settings includes a "Rate on App Store" link.
- improvement: iOS "saved" toast shown on saving a meeting.
- improvement: Training stats table uses a single header row ("avg N" / "last") above all metrics, with right-aligned numbers, left-aligned units, neutral gray trend arrows, and clarity rounded to whole number.
- improvement: iOS Settings section order: Training Insights first, then Subscription/Usage, then Mode.
- improvement: macOS home screen shortcuts and settings buttons now show labels with keyboard shortcut hints (⌘/ and ⌘,).
- fix: Last sentence before stopping is no longer lost.
- fix: Stopping a short recording in managed mode no longer briefly flashes "no openai api key".
- fix: iOS saved meeting transcripts now use monospace font with per-sentence lines, speaker headers, and timestamps (matching desktop).
- fix: iOS insights panel no longer scrolls horizontally.
- fix: iOS update banner now opens the correct App Store URL from the backend.
- fix: Topics now show hashtag prefix instead of square brackets on both platforms.
- fix: Section headings no longer use underscores ("action items" not "action_items").
- fix: "Updating..." indicator on iOS now appears next to the update button, not at the bottom.
- fix: Insights button in history always says "update" instead of switching between "generate" and "update".

### 2026-03-09 - v1.13.0

- new: Customizable training filler words (add/edit/remove/reset in Settings, applies to live and past meetings).
- improvement: Live insights more reliable - failed updates catch up; backend has higher timeouts and retries; client sends recent context + deltas instead of full transcript; 30s refresh; Update button refreshes both modes; placeholders while loading.
- improvement: Hot audio/interim published from dedicated runtime objects instead of `AppState`, reducing transcript/insights invalidation.
- improvement: Auto-save uses queued incremental segment sync with off-main diff planning, reducing 30s save spikes.
- note: Performance follow-ups in Roadmap (transcript windowing, throttling, cadence, profiling).
- known caveat: Save queue async; background/discard hardening is follow-up.
- improvement: Speaker diarization less eager at turn boundaries (stricter thresholds).
- improvement: macOS home test-waveform mounts only while audio test active.
- improvement: Home tagline animation lower refresh cadence when idle (macOS + iOS).
- fix: Pro status shows `checking plan...` while loading instead of briefly `upgrade to pro` for existing Pro users (macOS + iOS).
- fix: Transcript and debug log auto-scroll lock now respond to trackpad/wheel scroll (not just drag), scoped to the transcript pane only.
- fix: Stale final-insights no longer overwrite live insights after pause/resume.
- fix: Autosave no longer re-inserts already-tracked meetings.
- fix: Training filler edit alerts clear draft on cancel (macOS + iOS).
- fix: Keyboard typing no longer causes false "You" speaker tags during system-audio-only playback (mic energy floor + raised dominance threshold).
- improvement: Insights pane can be dragged wider (max 600px in live and history views).
- improvement: Settings Models tab now shows the insight model (GPT-5 Mini) as read-only info on macOS and iOS.

### 2026-03-08 - v1.12.4 (released)

- Fix a bug where live insights context from the previous meeting could leak into a new meeting
- Improve training metric calculations for pace, filler rates, and question detection, especially in short sessions
- Harden speaker diarization at turn boundaries to reduce false new-speaker creation during handoffs

### 2026-03-07 - v1.12.3

- Fix an iPhone bug where a recording could keep running on the Lock Screen, but the app reopened showing an older paused session
- Fix a bug where resuming after that could create two Live Activities instead of one
- Make long-recording insights more reliable so temporary OpenAI timeouts are less likely to show up as errors

### 2026-03-04 - v1.12.2

- Fix iOS Pro subscription purchase not prompting on some devices due to a stale App Store product configuration

### 2026-03-04 - v1.12.1

- Improved reliability of live meeting insights when network conditions are unstable
- Added diagnostic logging for iOS subscription purchase flow to help troubleshoot StoreKit product loading failures

### 2026-03-03 - v1.12.0

- Much more resilient audio when Bluetooth headphones switch modes mid-call: faster detection when system audio goes silent, cleaner restarts with less stale audio bleed, mic auto-retries instead of going silent for the rest of the session, and system audio automatically returns to mixed mode after mic recovery. Also fixes an edge case where recovery could restart with the wrong recording mode.
- iOS mic capture handles Bluetooth route and format changes more reliably across different devices, including automatic restarts when the audio profile shifts
- Live transcription now auto-recovers from temporary connection failures without forcing you to stop recording
- Usage tracking now retries automatically if reporting fails due to a bad connection, and fixes double-counting of minutes on retried reports
- Subtle in-session status indicator shows when audio is recovering or temporarily degraded, without flickering or causing the header to jump around
- MEDDPICC insights now update independently in the background during recording, so data is already there when you switch tabs. Switching tabs no longer triggers extra API calls or blocks standard insight updates.
- MEDDPICC insights now use a more reliable model for better results on long transcripts
- Remove the GPT model selector from Settings on both macOS and iOS — all insights now use GPT-5 Mini (the backend default) for consistent quality
- Fix insights from one mode (e.g. MEDDPICC) accidentally overwriting data in another mode (e.g. Standard) after switching
- Fix live insight updates sometimes wiping action items, topics, and discussion flow when the backend returns a partial or fallback response
- Transcript and debug-log panes now support manual scroll lock with a one-click "resume auto-scroll", and debug logs can be saved as a `.txt` file
- Copy-to-clipboard buttons now say `copy` instead of `md` to reduce confusion
- New opt-in "Share Diagnostics" toggle in Settings to help improve reliability — sends only structured event data, never transcript or audio content
- Improved internal logging to help diagnose insight generation failures
- macOS Settings now has a dedicated About tab instead of nesting About inside General

### 2026-03-02 - v1.11.0

- Add a one-time Terms & Privacy step before onboarding on both macOS and iOS
- Remember which terms version each user accepted, so people are only asked again when terms change
- Prevent starting recordings (including shortcuts and menu actions) until terms are accepted
- Simplify the terms screen to one clear line with direct Terms and Privacy links
- Update Settings links on macOS and iOS to include Website, Roadmap, and Changelog
- Change the macOS sidebar label from "new_session" to "new session"
- Add a subtle green highlight animation to the "multi-dimensional meetings" home tagline on macOS and iOS (respects Reduce Motion)
- Add native iOS StoreKit 2 subscription purchase flow for Pro (`$4.99/month`) and purchase restore flow
- Replace iOS license-key restore UX with App Store-compliant "Upgrade to Pro" + "Restore Purchases" in Settings and limit-reached state
- Add iOS deep link for managing subscriptions in Apple account settings
- Make active App Store subscribers show as Pro immediately in iOS UI and limits display
- Add iOS managed-mode display helpers for minutes/usage that show Pro allowances consistently (5,000 min/month) when App Store entitlement is active
- Keep macOS monetization unchanged (Polar checkout + portal + license-key restore)
- Redesign update-available banner on macOS and iOS with expandable release notes and cleaner layout
- Auto-recover system audio when the process tap goes silent mid-recording (e.g. after certain Bluetooth route changes)
- Fix session-end reporting failing on some backend routing configurations

### 2026-02-27 - v1.10.1

**Audio reliability:**
- Fix system audio going silent on some Bluetooth headphone configurations
- Improve reliability when switching audio devices mid-recording (e.g. connecting AirPods after recording starts) — automatic capture recovery instead of transcription silently dying
- Reduce crash risk during Bluetooth format transitions

**UI improvements:**
- Insight mode tabs look the same across live and historical views and no longer break at narrow widths
- Live recording waveforms are more responsive and match the home screen test audio behavior
- Clicking anywhere on sidebar tiles now works, not just the text
- Debug log window now has a raw text mode so you can select and copy individual lines

**Under the hood:**
- All internal logging now goes through the in-app debug log viewer instead of the hidden system console
- Richer diagnostics for audio capture, route changes, and transcription to help troubleshoot recording issues
- Managed-mode API diagnostics now log request target and non-2xx response details for session-end/reporting failures
- DMG output filename simplified to `miniti.dmg`
- Fix a potential freeze when clearing the debug log

### 2026-02-26 - v1.10.0

**Pro subscription ($5/month):**
- Upgrade to Pro for 5,000 minutes per month — 10x the free tier
- One-click upgrade on macOS opens secure checkout in your browser
- Manage or cancel your subscription anytime from Settings
- Use your subscription on multiple devices with a license key (enter it on any new Mac or iPhone to restore)
- Pro status shown across the app with a purple accent

**Other changes:**
- Limit reached screen now shows an upgrade option alongside the existing BYOK switch
- iOS shows your subscription status and supports restore, but purchasing happens on macOS or web (App Store guidelines)

### 2026-02-26 - v1.9.1

- macOS home screen no longer captures audio by default; use the "test audio" button to verify mic and system audio before recording (matching iOS behavior)
- MEDDPICC fields now display as bullet-pointed lists instead of semicolon-separated text, across all views on both platforms
- Insight mode tabs (standard/MEDDPICC/training/questions) use a single shared component with consistent pill styling across live and historical views; tabs truncate gracefully at narrow widths and show `⌘1`/`⌘2`/`⌘3`/`⌘4` shortcuts
- Live recording waveforms use the same sensitivity and noise-gate settings as the home screen test audio waveforms
- All sidebar tiles (live session, new session, history items) are fully clickable across the entire tile area
- Sidebar and insights pane collapse/expand buttons now show their keyboard shortcut hints (`⌘[` and `⌘]`)
- Fix a macOS crash when switching between historical meetings in the sidebar

### 2026-02-24 - v1.9.0

**Attio CRM integration (macOS):**
- Send saved meeting summaries to Attio: connect your account, search people/companies, and push summaries, discussion flow, action items, decisions, topics, MEDDPICC, and notes (transcript and training metrics excluded by default)
- Optionally create Attio tasks from action items
- Enable/hide in Settings → Integrations; target selection remembered per meeting
- Search shows full email/domain, scope-aware placeholder, and results collapse after selection
- Improved task sync reliability and clearer messaging when Attio returns zero tasks

**macOS layout & navigation:**
- Sidebar collapses to a compact icon/status rail (`⌘[`); history section is collapsible
- Insights pane collapses to a slim rail (`⌘]`)
- Session controls show shortcut hints (`⌘S` save / `⌘⌫` discard); both safely stop recording first if used mid-session, and save opens the meeting in history
- `⌘N` / menu-bar New Session starts a fresh session cleanly even while browsing history
- Escape closes the debug log sheet and Settings window; debug log also has an explicit close button

**Reliability & polish:**
- Resume/start shows a "starting..." spinner and blocks repeat taps while reconnecting in managed mode (macOS and iOS)
- Live MEDDPICC updates retry automatically on transient failures and throttle refresh cadence in managed mode
- Live transcript merges same-speaker streaming fragments until sentence boundaries, reducing choppy line breaks
- Markdown transcript export preserves actual speaker labels (like "You") instead of generic numbered headings

**Training mode & formatting:**
- Training UI is cleaner and easier to scan, with simplified metric rows and filler counts
- Each training metric has an info popup with plain-English guidance and coaching ranges
- Clarity helper text standardized across all views: "lower = clearer = better"
- iOS training info bubbles use a centered floating popup card with dim backdrop and tap-to-dismiss
- Labels and topic tags use human-readable spaces instead of underscores across macOS and iOS

**Bug fixes:**
- Fix a macOS crash when reactivating the app window after it sat in the background (especially after finishing a meeting)

### 2026-02-23 - v1.8.1

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
- `⌘1` / `⌘2` / `⌘3` / `⌘4` switch insight tabs in live + history views
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

- **Miniti/MinitiApp.swift** – App entry point, force update gate, onboarding gate, menu bar, global keyboard shortcuts, and custom URL callback handling (Attio OAuth return)
- **Miniti/Models/AppState.swift** – Central `@MainActor` state: recording, transcript, insights, audio monitoring, app mode, usage tracking, transport/audio recovery state, managed session-end durability queue, save queue, Live Activity lifecycle (`#if os(iOS)` guarded), and Google Calendar state (connection status, upcoming events, refresh timer, auto Attio sync). High-frequency recording signals are split into `AudioLevelsState` and `TranscriptRuntimeState` to avoid broad `AppState` invalidation. `@AppStorage("defaultLanguage")` stores the global default language; `@Published meetingLanguage` holds the per-meeting language, initialized from the default on `startNewMeeting()` and restored on `resumeInterruptedMeeting()`. `@AppStorage("googleCalendarEnabled")`, `@AppStorage("autoAttioSync")`, `@AppStorage("autoStartFromCalendar")`, and `@AppStorage("autoStopFromCalendar")` control calendar integration. `startMeetingFromEvent(_:)` pre-fills meeting title, calendar event ID, and attendees from a calendar event. Auto-start polls events every 15s and shows a countdown banner; auto-stop lowers silence threshold to 2 min after the calendar event's end time.
- **Miniti/Models/Meeting.swift** – SwiftData model for persisted meetings. Includes `managedSessionId: String?` to persist the backend session ID across app kills for orphaned-session usage reporting. `language: String` (default `"en"`) stores the meeting's transcription language. `calendarEventId: String?` links to the originating Google Calendar event. `attendeesJSON: String?` stores meeting attendees as JSON; decoded via computed `attendees: [MeetingAttendee]` property. `suggestedQuestionsJSON: String?` stores AI-generated questions as JSON; decoded via computed `suggestedQuestions: [SuggestedQuestion]` property. `hasQuestions: Bool` convenience check. `MeetingAttendee` struct (Codable, Identifiable, Sendable) holds email, displayName, domain, responseStatus, isOrganizer, isSelf. `displayTitle` computed property returns a clean title — strips legacy `yyyyMMdd-HHmmss` timestamp prefixes from old meetings, returns `"untitled"` for timestamp-only titles, and passes through clean titles unchanged. Used by all display surfaces, markdown export, webhook payloads, and Live Activity.
- **Miniti/Services/AudioCaptureService.swift** – Mic (AVAudioEngine) + system audio (Core Audio Process Tap) capture, publishes separate levels, auto-recovers system tap on silent-stall and callback-stall, and retries failed tap restarts with bounded backoff
- **Miniti/Services/DeepgramService.swift** – WebSocket streaming transcription (Nova-3 only), `TranscriptionLanguage` enum with 11 supported languages and per-language default filler lists, source-based speaker override via `sourceLookup` callback (macOS only; iOS uses Deepgram's native diarization), confidence-aware speaker-change gating/new-speaker promotion, and connection-health signals for reconnect orchestration
- **Miniti/Services/InsightsService.swift** – OpenAI API for summaries, action items, MEDDPICC, and suggested questions. Language-aware prompts: non-English meetings get an instruction to respond in the meeting language (JSON keys stay English). `InsightsMode` enum: `.standard`, `.meddpicc`, `.training`, `.questions`. `SuggestedQuestion` struct (Codable, Identifiable, Equatable): `question`, `type` (deeper/challenge/reframe/clarify/explore/follow_up), `context`. Questions mode has its own LLM prompt focused on conversational gaps, unstated assumptions, and dropped threads. `TrainingFillerPreferences` stores per-language filler lists (`trainingFillers_{lang}` keys) with migration from the legacy single-language key. `TrainingMetrics.compute` accepts a `language` parameter for filler detection.
- **Miniti/Services/WebhookService.swift** – Outbound webhook on meeting save. Fires a JSON POST to a user-configured URL when a meeting is finalized (`goHome()`) or insights are regenerated (`generateInsightsForMeeting()`). Payload includes title, start/end dates, duration, language, summary, action items, key decisions, topics, discussion flow, notes, MEDDPICC, training metrics (per-speaker fillers, pace, talk ratio, monologue, questions, clarity), suggested questions (array of `{question, type, context}`), speaker count, full transcript (array of `{speaker, text, timestamp}` entries with human-readable speaker labels), and optionally `calendar_event_id` and `attendees` (array of `{email, name, domain}`). Fire-and-forget via `Task.detached` with 10s timeout. Two payload builders: one from live AppState data, one from a persisted `Meeting` model. `trainingData(from:)` converts `TrainingMetrics` to the webhook-friendly `TrainingData` struct. Works with Zapier, Make, n8n, and custom endpoints. Shared between macOS and iOS.
- **Miniti/Services/DebugLogger.swift** – In-memory ring-buffer logger (1000 entries) with API key redaction. Thread-safe `log()` callable from audio threads. Categories: audio, deepgram, app. Also mirrors log lines to Xcode/system console output for parity while debugging. Shared between macOS and iOS.
- **Miniti/Views/DebugLogView.swift** – Terminal-style log viewer with category filters, pretty/raw modes, copy, and clear. Raw mode supports direct text selection for partial copy. Accessed via hidden 5-tap on version text in Settings.
- **Miniti/Services/KeyboardShortcutsService.swift** – Global `NSEvent.addGlobalMonitorForEvents` keyboard handler. Routes Escape (dismiss sheets → close Settings → close help → go home), shortcuts for recording (⌘⇧R, ⌘N, ⌘S, ⌘⌫), navigation (J/K/⌘H), insight mode switching (⌘1/2/3/4), sidebar collapse (⌘[), insights pane collapse (⌘]), and help overlay (⌘/). Also defines `allKeyboardShortcuts` array for the help overlay.
- **Miniti/Services/DeviceIdentifier.swift** – Keychain-based persistent device UUID (survives reinstalls)
- **Miniti/Services/MinitiAPIService.swift** – Backend communication: usage checks, temp key sessions, insights proxy, version checking, Apple subscription verification, Attio CRM export helpers, and Google Calendar integration (connect/status/events/disconnect). Auth via `X-API-Key` (shared app secret) + `X-Device-ID` + `X-App-Version` + `X-Platform` headers on every request; device ID never sent in body/query. `checkVersion()` now also sends `X-Device-ID` and `X-App-Mode` so the backend can create lightweight device records for BYOK users (parameters are optional with nil defaults for backward compatibility). Handles 403 `device_disabled` — sets `isDeviceDisabled` on AppState to block recording and show user message. Session-end decoding supports backend idempotency diagnostics. `generateInsights()` sends optional `language` field (defaults to `"en"`) and optional `attendees` array for context enrichment. Google Calendar types: `CalendarEvent`, `CalendarAttendee`, `CalendarOrganizer` with convenience properties (`startDate`, `endDate`, `externalAttendees`, `attendeeDomains`). `CalendarAttendee.toMeetingAttendee()` converts API types to persistable `MeetingAttendee`.
- **Miniti/Views/MeetingView.swift** – Main meeting UI: ReadyStateView (home) with animated `FlashingTagline`, `MeetingLanguagePicker`, active session, audio source panel, waveforms, expandable `UpdateAvailableBanner`. Recording header shows a language badge for non-English meetings.
- **Miniti/Views/MainWindow.swift** – Window chrome, history sidebar, and macOS historical meeting detail (`MeetingDetailView`, includes `send to attio` sheet with OAuth connect/search/send flow)
- **Miniti/Views/TranscriptView.swift** – Live transcript with speaker colors; mic speaker shown as "You" (green), remote speakers use blue/purple palette; merges streaming fragments into sentence-level rows for cleaner display
- **Miniti/Views/InsightsView.swift** – AI insights panel (standard + MEDDPICC + training + questions modes), shared `TrainingContent` view for speech analytics, `QuestionsContent` view for displaying suggested questions with type labels and copy-to-clipboard, and shared metric info-help UI (`TerminalSectionInfo*`; macOS popover + iOS floating popup card via `fullScreenCover`)
- **Miniti/Views/SettingsView.swift** – Settings window with tabs: General (startup, appearance, recording, diagnostics), Language (default language picker + filler word config), Account (mode toggle, subscription, usage), API Keys (BYOK only), Audio (sources, permissions), Integrations (markdown export, webhooks, Google Calendar with connect/disconnect + auto Attio sync toggle, Attio CRM), About (version, links, debug log access)
- **Miniti/Views/TermsAcceptanceView.swift** – Privacy & terms acceptance gate shown before onboarding; sets `appState.hasAcceptedTerms = true` on accept. Shared between macOS and iOS.
- **Miniti/Views/ForceUpdateView.swift** – Non-dismissable blocking screen shown when the running app version is below the server's `min_version`. Displays "update required" with a download link. Takes priority over all other gates (terms, onboarding, main app). Shared between macOS and iOS.
- **Miniti/Views/OnboardingView.swift** – First-launch mode selection (managed vs BYOK)
- **Miniti/Views/UsageBanner.swift** – Remaining minutes display + ManagedStatusView for home screen
- **Miniti/Views/LimitReachedView.swift** – Hard block when 500 min exhausted, offers BYOK switch
- **Miniti/Models/ColorPalette.swift** – Global color palette: backgrounds, borders, text, accents, status, speaker colors, MEDDPICC colors

### iOS Target (MinitiMobile)

Separate iOS target in the same Xcode project. Mic-only recording (no system audio on iOS). Shares models, services, and several views with macOS target.

- **MinitiMobile/MinitiApp_iOS.swift** – `@main` iOS entry point, `WindowGroup` + `ModelContainer`, force update gate then terms gate then onboarding gate, forces `.preferredColorScheme(.dark)` app-wide
- **MinitiMobile/AudioCaptureService_iOS.swift** – Mic-only `AudioCaptureService` (same class name/interface as macOS). Uses `AVAudioSession` for iOS audio session management with Bluetooth A2DP + HFP support, dynamic tap-format converter rebuilds, and proactive route-change mic restarts. Stubs system audio properties (always false/0). `dominantSource()` always returns `.mic`.
- **MinitiMobile/Views/MainTabView.swift** – `TabView` with Record / History tabs; wires `@Environment(\.modelContext)` → `appState.modelContext` on appear (critical for SwiftData saves)
- **MinitiMobile/Views/MeetingView_iOS.swift** – Mobile recording UI: terminal-style buttons (stop/resume/save/home matching macOS), custom section picker, `MeetingLanguagePicker_iOS`, `UIPasteboard` for copy, `SourceWaveform_iOS`
- **MinitiMobile/Views/SettingsView_iOS.swift** – `NavigationStack` + `Form`; managed-mode subscription section includes StoreKit upgrade (`$4.99/month`), restore purchases, and Apple subscription management link. Language section has default language picker + link to filler detection detail (`FillerSettingsDetail_iOS`). Models section is read-only (Nova-3, GPT-5 Mini).
- **MinitiMobile/Views/HistoryView_iOS.swift** – `NavigationStack` + `List` with drill-down to meeting detail; historical training metrics use `HistoricalDetailBlock_iOS` with local metric info popup types (`HistoricalMetricInfo*`) for iOS-only floating overlays
- **MinitiMobile/Info.plist** – `NSMicrophoneUsageDescription`, `UIBackgroundModes: [audio]`, `NSSupportsLiveActivities: YES`, `UILaunchScreen` (empty dict, required for iOS launch)
- **MinitiMobile/MinitiMobile.entitlements** – Empty dict (iOS is always sandboxed; macOS sandbox keys like `com.apple.security.app-sandbox` are invalid on iOS and prevent launch)

### Live Activity Extension (MinitiLiveActivityExtension)

Widget extension embedded in MinitiMobile. Shows recording status on Dynamic Island and Lock Screen.

- **Shared/RecordingActivityAttributes.swift** – `ActivityAttributes` struct shared between MinitiMobile and the extension. Static: `startTime: Date`. Dynamic `ContentState`: `meetingTitle: String`, `isRecording: Bool`, `currentTranscript: String`, `elapsedSeconds: Int?` (set when stopped to freeze the timer).
- **MinitiLiveActivity/MinitiLiveActivityBundle.swift** – `@main` widget bundle entry point
- **MinitiLiveActivity/MinitiLiveActivityLiveActivity.swift** – All Live Activity UI: Dynamic Island (compact leading: red dot, compact trailing: green timer; expanded: REC/STOPPED label + timer + title + live transcript + branding), Lock Screen banner (status + timer + title + transcript). Timer freezes when stopped via `elapsedSeconds`; all elements switch to gray. Compact DI width is system-controlled (not adjustable by apps).
- **MinitiLiveActivity/Info.plist** – `NSExtension` with `com.apple.widgetkit-extension` point identifier
- Bundle ID: `com.miniti.mobile.live-activity`, deployment target iOS 17.0

### Unit Tests (MinitiTests + MinitiMobileTests)

Two XCTest targets sharing the same 8 test files in `MinitiTests/`: `MinitiTests` tests the macOS `Miniti` host app (262 tests), `MinitiMobileTests` tests the iOS `MinitiMobile` host app (253 tests — 9 fewer because `sanitizeFilename` and `exportFilename` are macOS-only). Covers JSON decoding, data models, pure computation, and payload construction. No network or UI tests — purely deterministic logic.

- **MinitiTests/MinitiAPIServiceTests.swift** – UsageInfo (snake/camelCase, string/numeric), SessionResponse, EndSessionResponse, AttioSendResponse, AttioSearchRecord, ManagedInsightsResponse, AppleVerifyResponse, flexible date decoding, AttioMeetingPayload normalization
- **MinitiTests/TrainingMetricsTests.swift** – tokenize, countPhraseOccurrences, computeLongestMonologue, TrainingFillerPreferences normalization (per-language storage, defaults, save/reset), full TrainingMetrics.compute with synthetic segments (fillers, pace, talk ratio, questions, clarity), Spanish filler detection
- **MinitiTests/MeetingModelTests.swift** – TranscriptSegment speaker labels and timestamps, Meeting MEDDPICC detection, duration, hasInsights, fullTranscript, markdown export, displayTitle (old timestamp-prefixed and new clean formats), MeetingSearchResult scoring and snippet extraction (uses in-memory SwiftData container)
- **MinitiTests/WebhookPayloadTests.swift** – MEDDPICCData.isEmpty, trainingData mapping, payloadFromLiveState construction, JSON encoding roundtrip, language field in payload
- **MinitiTests/AppStateComputationTests.swift** – isNewer (semver), isTransientInsightsError, sanitizeFilename (macOS only), parseMeetingTitle, buildSegmentSyncPlan (segment diffing), exportFilename (macOS only)
- **MinitiTests/DeepgramParsingTests.swift** – DeepgramResponse decoding (nested types, missing data), findDominantSpeaker, PendingSpeakerEvidence accumulation, TranscriptionLanguage enum properties (display names, default fillers, all cases)
- **MinitiTests/InsightsParsingTests.swift** – LiveInsightsResponse (full/minimal/standard-only), InsightsResponse MEDDPICC, OpenAIResponse, OpenAIErrorResponse, InsightsMode enum
- **MinitiTests/ColorPaletteTests.swift** – Color(hex:) parsing (3/6/8-digit, hash prefix), speaker color cycling, MEDDPICC letter colors

Run macOS tests: `fastlane mac test` (or `xcodebuild test -scheme Miniti -destination 'platform=macOS' -derivedDataPath DerivedDataLocal -only-testing:MinitiTests`)
Run iOS tests: `fastlane ios test` (or `xcodebuild test -scheme MinitiMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedDataLocal -only-testing:MinitiMobileTests`)

**Cross-platform test files**: All 8 test files compile for both macOS and iOS via conditional imports (`#if IOS_TEST_TARGET` → `@testable import MinitiMobile`, else `@testable import miniti`). The `IOS_TEST_TARGET` flag is set in `MinitiMobileTests` build settings via `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. macOS-only tests (markdown export helpers) are guarded with `#if os(macOS)`. `ColorPaletteTests` uses a cross-platform `colorComponents()` helper (`NSColor` on macOS, `UIColor` on iOS).

**Coverage (macOS, as of v1.17.0)**: 18.4% overall (6,067 / 32,898 executable lines). High-value logic is well covered: ColorPalette 98%, Meeting model 92%, WebhookService 74%, MinitiAPIService decoders 47%, InsightsService parsing 45%, DeepgramService 30%, AppState 16%. Uncovered code is mostly SwiftUI views (0%, need UI tests), hardware-dependent audio (5%, not unit-testable), and network call paths (need mocking). View code (Settings, Transcript, Onboarding, etc.) accounts for ~50% of total lines and is 0% covered.

**Access control for testing**: Pure helper functions and data-only structs that need direct testing are `internal` (not `private`) so `@testable import` can reach them. These include: `AppState.isNewer`, `AppState.sanitizeFilename`, `AppState.parseMeetingTitle`, `AppState.isTransientInsightsError`, `AppState.buildSegmentSyncPlan` (+ snapshot/plan structs), `AppState.recoverySeverity`, `AppState.transcriptText`, `AppState.tailTranscriptSegments`, `DeepgramService.segmentBySpeaker` (+ `SegmentationState` struct), `DeepgramService.findDominantSpeaker`, `DeepgramService.PendingSpeakerEvidence`, `DeepgramResponse`, `InsightsService.tokenize/countPhraseOccurrences/computeLongestMonologue`, `LiveInsightsResponse`, `InsightsResponse`, `OpenAIResponse/OpenAIErrorResponse`, `MinitiAPIService.decodeFlexibleDate/timestampToDate`. Pure static functions on `@MainActor AppState` are marked `nonisolated static` so tests can call them without async context. Instance methods that previously had the same name delegate to the static versions to avoid breaking existing call sites.

**Shared files** (macOS + iOS + extension where noted): `AppState.swift`, `Meeting.swift`, `ColorPalette.swift`, `DeepgramService.swift`, `InsightsService.swift`, `DeviceIdentifier.swift`, `MinitiAPIService.swift`, `WebhookService.swift`, `DebugLogger.swift`, `Secrets.swift`, `TranscriptView.swift`, `InsightsView.swift`, `DebugLogView.swift`, `OnboardingView.swift`, `TermsAcceptanceView.swift`, `ForceUpdateView.swift`, `UsageBanner.swift`, `LimitReachedView.swift`, `Assets.xcassets`, `RecordingActivityAttributes.swift` (iOS app + extension only)

**macOS-only files**: `MinitiApp.swift`, `AudioCaptureService.swift`, `KeyboardShortcutsService.swift`, `MainWindow.swift`, `MeetingView.swift`, `SettingsView.swift`

**Key design**: Keep platform guards (`#if os()`) limited and localized. Most platform-specific branching lives in `AppState.swift` (ActivityKit + source-dominance wiring), with additional targeted guards in shared UI/service code where platform behavior differs (for example `DebugLogView`, `InsightsView`, `MinitiAPIService`, and macOS-only Attio UI in `MainWindow`). Each target compiles its own `AudioCaptureService` (same class name, same public interface). AppState references `AudioCaptureService` by name and works with either version. Shared views use `@Environment(\.horizontalSizeClass)` for responsive layout. MEDDPICC fields are rendered as individual sections (same heading style as summary/discussion) across all views — `LiveInsightSection` in the sidebar, `TerminalSection` in full-width/history, `InsightsPlainBlock_iOS`/`HistoricalDetailBlock_iOS` on iOS.

**Critical wiring**: `appState.modelContext` must be set from `@Environment(\.modelContext)` in the first view that appears. On macOS this happens in `MainWindow.swift`; on iOS in `MainTabView.swift`. Without it, `saveCurrentMeetingIfNeeded()` silently fails (all saves are no-ops).

**macOS SwiftData stability note (v1.9.0)**: `MainWindow.swift` intentionally avoids a root-level `@Query` for history and stores `selectedMeetingID` (UUID) instead of a `Meeting` object in `@State`. Meetings are fetched manually from `ModelContext` (including on app reactivation) to avoid a SwiftUI/SwiftData crash path seen when clicking the window after it had been backgrounded. `MeetingDetailView` uses `.id(meeting.id)` so SwiftUI fully tears down the old view (including `@Bindable` observation tokens and gesture recognizers) before creating a new one when switching meetings — without this, stale AttributeGraph references cause `EXC_BAD_ACCESS` in the button gesture dispatch path.

## Key patterns

- **Debug logging**: `DebugLogger.shared` is an in-memory ring-buffer (1000 entries) with thread-safe `log(_ category:_ message:)`. Categories: `.audio`, `.deepgram`, `.app`. API keys are automatically redacted via patterns set by `AppState.updateLogRedaction()`. Key instrumentation points: audio device info + format on capture start, route/device-change events, 10-second audio heartbeats, silent-buffer warnings, Deepgram WebSocket/audio/transcript heartbeats, managed-mode API request/response failures (including HTTP status + endpoint/body snippet), and app state transitions (start/stop recording). On macOS, `AudioObjectAddPropertyListenerBlock` monitors default input/output device changes (critical for diagnosing Bluetooth headphone issues). `DebugLogView` is accessible by tapping the version text 5 times in Settings — terminal-style viewer with category filters, pretty/raw view modes, copy, and clear. Raw mode enables partial text selection. Log lines are also mirrored to Xcode/system console via `print` in `DebugLogger.log`.
- **Expected CoreAudio noise during Bluetooth route handoff (macOS)**: When the default input/output device changes mid-capture (for example AirPods connect while taking/ending a phone call), CoreAudio/HAL may emit transient teardown/rebuild errors such as `!dev`, `!obj`, `who?`, `no object with given ID`, and `throwing -10877`. Treat this as expected if logs show successful restart (`Engine config changed`, `Mic restart complete`, `system audio process tap created`) and capture continues. Treat as a bug only when capture fails to recover.
- **Version check on launch**: `AppState.checkForUpdates()` calls `GET /api/version` once at startup (all modes). Now sends `X-Device-ID` and `X-App-Mode` (`"byok"` or `"managed"`) so the backend can create/touch lightweight device records for all users including BYOK. Compares semver — if remote `latest_version` is newer, sets `availableUpdate: VersionInfo?`. A blue `UpdateAvailableBanner` appears on the home screen (macOS, iOS) with version, expandable release notes ("view notes" / "hide notes"), and a download link (macOS: backend-supplied URL from `/api/version`; iOS: opens backend `download_url` directly). If the backend returns `min_version` and the running app version is below it, `requiresForceUpdate` is set and a non-dismissable `ForceUpdateView` blocks the entire app (above even terms/onboarding gates) with a download link. Bumping `min_version` on the server instantly forces all older clients to update on next launch — no app release needed. The call remains fire-and-forget (failure is silent — a failed version check never blocks the app).
- **Terms acceptance versioning**: `AppState.hasAcceptedTerms` is computed from `acceptedTermsVersion >= currentTermsVersion` (currently `1`). App init migrates old boolean-only users by promoting `hasAcceptedTerms == true` to version `1`. To force re-acceptance after a legal update, bump `currentTermsVersion`.
- **StoreKit state in AppState (iOS)**: `AppStoreSubscriptionService` lives in `AppState.swift` under `#if os(iOS)`. It loads `com.miniti.mobile.pro.monthly`, handles purchase, restore (`AppStore.sync()`), listens to `Transaction.updates`, and publishes `hasActiveSubscription`.
- **Managed Pro fast-path on iOS**: `AppState.isPro` and `isLimitReached` consider local StoreKit entitlement (`hasActiveAppStoreSubscription`) in addition to backend usage response. Display helpers (`displayMinutesLimit`, `displayMinutesRemaining`, `displayUsagePercentage`) keep iOS UI consistent at 5,000 min/month when StoreKit entitlement is active.
- **Google Calendar integration (macOS v1)**: OAuth is backend-mediated (Google redirects to `miniti-api`, backend stores token in KV keyed by device ID, backend redirects back to app custom URL scheme `miniti-google://`). macOS registers `miniti-google` in `Info.plist`; `MinitiApp.onOpenURL` routes by scheme to `.minitiGoogleOAuthCallback` or `.minitiAttioOAuthCallback`. `AppState` manages connection status, upcoming events (refreshed every 5 min), and `startMeetingFromEvent(_:)` which pre-fills title, calendar event ID, and attendees. Home screen shows "coming up" list of next 5 events when connected. Recording header shows attendee count badge. Attendees are passed to managed insights API for better speaker attribution and MEDDPICC analysis. **Auto-start**: 15-second timer checks upcoming events; when an event's start time is within [-1 min, +5 min], shows a countdown banner on the home screen with "start now" and "dismiss" buttons; auto-starts after 15s if not dismissed. Dismissed event IDs are tracked in-memory. **Calendar-aware auto-stop**: when recording from a calendar event and the event's end time passes, `calendarEventEndedWhileRecording` flag triggers a 2-minute silence threshold (shorter than the normal `autoStopMinutes`), with an amber "meeting time ended" banner in the recording header. **Auto Attio sync**: on `goHome()`, if meeting has attendees and Attio is connected and `autoAttioSync` is on, searches Attio by attendee domains and auto-sends if exactly one match found. Settings > Integrations has Google Calendar section with enable toggle, connect/disconnect, status, auto-start toggle, auto-stop toggle, and auto Attio sync toggle.
- **Attio CRM send (macOS history only)**: user-initiated from saved meeting detail (`send to attio`). OAuth is backend-mediated (Attio redirects to `miniti-api`, backend stores token in KV keyed by device ID, backend redirects back to app custom URL scheme `miniti-attio://`). macOS registers `miniti-attio` in `Info.plist`; `MinitiApp.onOpenURL` forwards the callback to the sheet via `NotificationCenter`. Frontend calls additive backend routes (`/api/attio/connect/start`, `/status`, `/search`, `/send`) and fails gracefully if backend is not deployed yet (shows a clear message instead of breaking older deployments). App payload omits full transcript by default; backend also ignores transcript if older clients still send it.
- **Decoupled live insights**: `updateLiveInsights()` runs standard insights inline (applies immediately, clears `isGeneratingInsights`), then fires MEDDPICC and questions as separate background tasks via `updateMeddpiccInBackground()` and `updateQuestionsInBackground()`, each gated by their own `isGenerating*Insights` flag. The three never block each other. `fetchLiveInsights(mode:...)` is the shared per-mode helper. `switchInsightsMode()` only updates the mode and recomputes training metrics — no re-analysis or API calls on tab switch. Managed-mode MEDDPICC requests retry once on transient timeout/network failures (e.g. 504 / gateway timeout). Questions cadence is staggered 22s after standard (vs 15s for MEDDPICC).
- **Client insights reliability (v1.13.0)**: Managed live insights use a no-loss protocol. Backend returns `meta.degraded` when a response is fallback/timeout; client decodes `ManagedInsightsMeta` and only advances ack cursor when `!degraded`. Per-mode `request_seq` counters reject stale/out-of-order responses. Scheduling: warmup fires first request at 4 segments (standard) or 6 (MEDDPICC); steady-state uses fixed 30s cadence per mode via `insightsCadenceTask`, with MEDDPICC staggered 15s after standard. Silence gate: skip tick if no new segments since last request. Incremental cutover: success-count based (2 non-degraded responses) instead of transcript length; delta > 35k chars triggers full request for recovery. Recent transcript window: 10k chars. Update button fires both modes immediately and resets cadence anchors. Warmup placeholders: "no insights yet..." and "no meddpicc yet..." until first success. State: `standardSuccessCount`, `meddpiccSuccessCount`, `standardCadenceAnchor`, `meddpiccCadenceAnchor`, `standardLastFiredSegmentCount`, `meddpiccLastFiredSegmentCount`.
- **Live transcript display merge**: streaming-finalized chunks from the same speaker are merged in the UI until a sentence terminator is reached. This keeps the live transcript readable without changing stored transcript data.
- **Markdown transcript speaker labels**: Transcript markdown export uses each segment's computed `speakerLabel` (for example `You`) instead of always rendering generic numbered labels.

## Changelog style

Changelog entries in `claude.md` should be written as human-readable descriptions for a public audience. No code references, function names, file paths, or implementation details. Write what changed from the user's perspective — e.g. "Fix saved meetings showing wrong speaker name" not "Fix `TranscriptSegment.speakerLabel` for `micSpeakerID`".
Never modify older changelog entries after they are written. Add corrections, clarifications, or reversals only as a new entry at the top.

`README.md` should not contain a changelog for this project. Keep it focused on current end-user functionality, setup, and usage guides.

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
- Audio monitoring: opt-in "test audio" button on home screen starts lightweight capture (no Deepgram) to verify sources before recording. On macOS, `AudioSourcePanel` uses local `@State isTesting`; on iOS, `isMicTesting` in `ReadyStateView_iOS`. Monitoring stops on view disappear or when the user taps stop.
- **Audio engine/device-change recovery**: Both macOS and iOS listen for `AVAudioEngineConfigurationChange`. On macOS, route changes trigger a guarded full mic restart and dynamic converter rebuild based on callback format (tap installed with nil format), with coalescing/rate-limit checks to avoid restart storms. Default output changes schedule a debounced system-tap restart and reset recovery timers so the app does not immediately re-restart. On iOS, route changes are actively inspected for input-identity changes and trigger a debounced proactive mic restart (not just logging), improving Bluetooth route/profile reliability. Observer lifecycles are cleaned up in `stopMicrophoneCapture()`.
- **Deepgram reconnect + transcript starvation watchdog**: While recording, Deepgram connection errors/disconnects trigger bounded reconnect attempts (1s/2s/5s). A transcript-health watchdog also triggers one reconnect cycle if speech-like audio levels continue but no transcript arrives for an extended window, and recording continues during transport recovery.
- **Managed session-end durability queue**: If managed `session/end` reporting fails, the app persists pending reports locally and retries on launch, foreground, and after managed-session success paths. `managedSessionId` is only cleared after successful acknowledgment or durable queue persistence.
- `@AppStorage` persists API keys, audio source toggles, app mode, onboarding state, terms acceptance state (`acceptedTermsVersion` + legacy `hasAcceptedTerms`), markdown export settings (`autoExportMarkdown`, `markdownExportFolderPath`, `generateClaudeMd` — macOS only), webhook URL (`webhookURL`), auto-stop timeout (`autoStopMinutes`, default 5, 0 = disabled), default transcription language (`defaultLanguage`, default `"en"`), Google Calendar integration (`googleCalendarEnabled`, `autoAttioSync`, `autoStartFromCalendar`, `autoStopFromCalendar`). Transcription model is hardcoded to Nova-3 (no user selection). OpenAI model is hardcoded to `gpt-5-mini` (no user selection).
- **Markdown auto-export (macOS only)**: When `autoExportMarkdown` is enabled, finalized meetings are written as `.md` files to a local folder (default `~/Documents/miniti/`). Trigger points: `goHome()` (reads live AppState data synchronously before `clearCurrentSession()` to avoid async save queue timing issues), `generateInsightsForMeeting()` (re-exports after insight updates from history), and a manual "export" button in `MeetingDetailView`. Filenames are dev-friendly with no spaces: `yyyy-MM-dd-HHmm-sanitized-title.md`. Section order: notes → insights (including MEDDPICC) → training metrics → transcript (high-value content first). Optional `CLAUDE.md` index file lists all exported meetings for AI agent discovery. All export code is guarded with `#if os(macOS)`.
- **Outbound webhooks**: When `webhookURL` is non-empty, a JSON POST is fired on meeting finalization (`goHome()` with event `meeting.saved`) and after insight regeneration for saved meetings (`generateInsightsForMeeting()` with event `meeting.updated`). Payload includes title, start date, end time, duration, language, summary, action items, key decisions, topics, discussion flow, notes, MEDDPICC, training metrics (per-speaker: fillers/min, pace, talk ratio, monologue length, questions, clarity), suggested questions (array of `{question, type, context}`), speaker count, full transcript (array of `{speaker, text, timestamp}` entries with human-readable speaker labels like "You" and "Speaker 2"), and optionally `calendar_event_id` and `attendees` (array of `{email, name, domain}`) when meeting was started from a calendar event. Training metrics are computed from transcript segments at send time. Fire-and-forget via `Task.detached`, 10s timeout, success/failure logged to `DebugLogger`. Configurable in Settings on both macOS and iOS. Works with Zapier "Webhooks by Zapier", Make, n8n, and any HTTP endpoint.
- **Terms acceptance versioning**: `AppState.hasAcceptedTerms` is computed from `acceptedTermsVersion >= currentTermsVersion` (currently `1`). App init migrates old boolean-only users by promoting `hasAcceptedTerms == true` to version `1`. To force re-acceptance after a legal update, bump `currentTermsVersion`.
- Secrets.swift (gitignored) provides default API keys; Secrets.example.swift is the template. **Only seeded in BYOK mode** — managed users never get Secrets keys written to `@AppStorage`. On switch to managed, any keys matching Secrets defaults are cleared.
- Mode-aware service routing: `startRecording()`, `updateLiveInsights()`, `generateFinalInsightsAndSave()`, `generateInsights()` all branch on `appMode`
- BYOK keys persist in `@AppStorage` regardless of active mode — switching never clears user-entered keys (only Secrets defaults are stripped in managed mode)
- **Segment persistence**: `saveCurrentMeetingIfNeeded()` snapshots current live state, enqueues a save payload, computes a segment diff plan off-main, then applies an incremental sync (`delete missing IDs`, `upsert changed/new IDs`) to `meeting.segments`. Segment IDs now persist from `LiveSegment.id`, so resumed sessions update incrementally instead of full rebuilds.
- **Save queue caveat**: The new save queue is async by design (to avoid UI stalls). This improves responsiveness, but durability on abrupt background/termination is now timing-dependent and discard races still need stricter cancellation checkpoints. Follow-ups are tracked in Roadmap.
- **Sidebar focusability**: All sidebar buttons use `.focusable(false)` since navigation is keyboard-shortcut-driven (⌘N, J/K, etc.) — no tab focus rings needed.
- **macOS focus rings / tab focus**: Prefer `.focusable(false)` for button-only controls and utility panels (including Attio send sheet controls) unless keyboard tab navigation is explicitly required. This app is shortcut-driven; avoid default tab-focus highlight rings by default.
- **Recording timer**: Uses date-based computation (`recordingStartDate`) instead of incrementing a counter. `Timer.scheduledTimer` fires every 1s and computes `Date().timeIntervalSince(recordingStartDate)`. This ensures accurate duration even when the app is backgrounded on iOS (timer may not fire reliably, but duration is correct when it does). Paused time is excluded by re-anchoring `recordingStartDate` from the accumulated active duration on resume; `recordingStartDate` is cleared on stop and `goHome()`.
- **Auto-stop on silence**: `autoStopTimer` fires every 30s during recording and compares `CFAbsoluteTimeGetCurrent() - lastTranscriptReceivedAt` against `autoStopMinutes * 60`. If the gap exceeds the threshold, calls `stopRecording()` and sets `wasAutoStopped = true`. The UI shows an amber "auto-stopped — no speech detected" banner in the stopped state on both macOS and iOS. `wasAutoStopped` is cleared on `startNewMeeting()` and `goHome()`. Timer starts in `startRecording()`, stops in `stopRecording()` and `clearCurrentSession()`. Configurable in Settings: off (0), 3, 5 (default), 10, or 15 minutes. **Calendar-aware**: when `autoStopFromCalendar` is on and a calendar event's end time passes during recording, the silence threshold drops to 2 minutes regardless of `autoStopMinutes`. `calendarEventEndedWhileRecording` flag triggers an amber banner in the recording header. The auto-stop timer also runs when `autoStopMinutes == 0` if a calendar event is active.
- **Periodic auto-save**: A 30-second `periodicSaveTimer` runs during recording, calling `saveCurrentMeetingIfNeeded()`. Saves are serialized through an internal queue (`activeMeetingSaveTask` + latest queued payload) so repeated triggers coalesce safely. `saveCurrentMeetingIfNeeded()` does NOT set `endTime` — only `stopRecording()` and `goHome()` set it. Meetings with `endTime == nil` are identified as interrupted/resumable on next launch.
- **Resume interrupted meetings**: On launch (when `modelContext` is set), `resumeInterruptedMeeting()` queries SwiftData for meetings with `endTime == nil`. If found, it restores the full session: `currentMeeting`, `liveSegments` (reconstructed from `TranscriptSegment`s), all insights, notes, MEDDPICC fields, `detectedSpeakers`, `recordingDuration` (from last segment timestamp), and title tracking. Title restore handles both old timestamp-prefixed titles (via `parseMeetingTitle`) and new clean titles for backward compatibility. The UI automatically shows the stopped-session view (because `currentMeeting != nil`), where the user can resume recording or go home (which finalizes `endTime` and saves). Works on both iOS and macOS. In managed mode, if the interrupted meeting has a `managedSessionId`, the orphaned session's usage is reported to the backend (duration computed from saved segments) and the session ID is cleared to prevent double-reporting.
- **Live Activity (iOS only)**: `Activity.request()` called in `startRecording()`, `activity.update()` on stop (paused state), title changes, and transcript updates, `activity.end(.immediate)` on `goHome()`. Transcript updates are throttled to max 1 per 3 seconds (`liveActivityUpdateInterval`) to stay within ActivityKit's update budget. The widget uses `Text(timerInterval: startTime...Date.distantFuture, countsDown: false)` for an auto-updating timer when recording; when stopped, `elapsedSeconds` is set and the timer switches to a static `Text(formatDuration(_:))` so it freezes. All visual elements (dot, status, title, timer) switch to `pausedGray` when stopped, and transcript is replaced with "tap to return to miniti". `currentTranscriptLine` returns interim text if available, otherwise the last finalized segment. All ActivityKit code guarded with `#if os(iOS)` in `AppState.swift`. Note: compact Dynamic Island width is system-controlled and cannot be reduced by apps.
- **iOS background recording & kill recovery**: iOS can terminate backgrounded apps at any time (memory pressure, battery, etc.); there is no way to prevent this. Mitigations: (1) `UIBackgroundModes: [audio]` keeps the app running longer while recording. (2) Periodic auto-save (every 30s) continuously persists transcript to SwiftData. (3) `saveCurrentMeetingIfNeeded()` is also called when the app enters background (`scenePhase == .background`). (4) On launch, `cleanupOrphanedLiveActivities()` ends stale Live Activities, then `resumeInterruptedMeeting()` restores the session from SwiftData so the user lands directly in the stopped-session view with their transcript.
- **Atomic array mutations for ForEach-bound arrays**: Never do `removeAll` + `append` (or multiple mutations) on a `@Published` array that drives a SwiftUI `ForEach`. Each mutation fires a separate `objectWillChange`, and SwiftUI's AttributeGraph can see intermediate states (items removed but view nodes still referencing them), causing `EXC_BAD_ACCESS` in `AGGraphGetWeakValue`. Instead, build the final array in a local `var`, then assign it once: `liveSegments = updated`. This is especially critical for arrays that grow over long sessions (30+ minutes of recording).
- **Avoid main actor hops from audio threads**: `nonisolated func sendAudio()` on `@MainActor` services should NOT use `Task { @MainActor }` to access properties — this creates a new main-thread task per audio buffer (~4/sec), competing with SwiftUI layout passes. Instead, use `nonisolated(unsafe)` shadow properties (e.g., `_sendTask`, `_sendConnected`) written from `@MainActor` context (connect/disconnect) and read from audio threads. `URLSessionWebSocketTask.send` is thread-safe and doesn't need the main thread.
- **Discard meeting**: `discardCurrentMeeting()` deletes the current meeting from SwiftData, ends Live Activity (iOS), and clears the session without saving. Used from the "discard" button (with confirmation alert) when a recording is stopped.
- **Generate insights for history**: `generateInsightsForMeeting(_ meeting: Meeting)` generates standard + MEDDPICC insights for a saved meeting and writes directly to the `Meeting` model. Used from history detail generate/update controls.
- **Insight apply safety**: `applyInsights(_:segmentCount:mode:)` uses an explicit `mode` parameter to route fields — standard updates only touch `liveSummary`/`liveActionItems`/`liveTopics`/`liveDiscussionFlow`; MEDDPICC updates only touch the eight MEDDPICC fields. Each field is only overwritten if the new value is non-empty (empty arrays and nil/blank strings are skipped), so partial or fallback backend responses don't wipe previously populated data. `stopRecording()` always calls `generateFinalInsightsAndSave()` (which generates both standard + MEDDPICC) regardless of whether insights already exist.
- **Pause/resume stale-final guard**: `generateFinalInsightsAndSave()` now snapshots meeting ID + final segment count and only applies final-standard/final-MEDDPICC responses if the meeting is still stopped and unchanged. If recording resumed (or segments advanced) while a final request was in flight, the stale response is ignored so older/shorter snapshots cannot overwrite live insights.
- **Training mode**: Third `InsightsMode` (`.training`) that shows locally-computed speech analytics — no LLM calls needed for the Training UI. `TrainingMetrics.compute(from:duration:language:)` runs a pass over transcript segments to extract filler word counts (language-specific: hard fillers like "um"/"uh" + soft fillers like "like"/"basically" for English, equivalent lists for other languages), talk ratio, speaking pace (wpm), longest monologue, questions asked, and clarity (avg words/turn). Filler lists are per-language with customizable overrides stored in `@AppStorage("trainingFillers_{lang}")`. Metrics are recomputed on every new segment batch when training mode is active, and on mode switch. During recording in training mode, automatic live insight refresh still computes standard insights in the background so they are ready when switching back. Manual generate/update actions are hidden (or no-op guarded) in Training mode to avoid hidden AI calls. For saved meetings, training metrics are computed on the fly from `meeting.segments` using the meeting's stored language in the history views (no extra model fields needed).
- **Training metric help UI (cross-platform)**: All major training metrics (fillers, talk ratio, pace, longest monologue, questions, clarity) expose the same plain-English guidance/ranges in live + historical views. macOS uses native popovers; iOS uses a custom centered floating popup card with dim backdrop and tap-outside-to-dismiss to avoid `.popover`/sheet full-screen presentation quirks.
- **Training clarity helper copy**: The inline clarity helper is intentionally standardized across macOS/iOS live + historical views as `lower = clearer = better` for fast scanning.
- **Questions mode**: Fourth `InsightsMode` (`.questions`) that generates AI-suggested questions to ask. Uses an independent LLM prompt focused on conversational gaps: unstated assumptions, dropped threads, tensions between statements. Six question types: `deeper` (follow a thread), `challenge` (surface a contradiction), `reframe` (question the premise), `clarify` (pin down vagueness), `explore` (open untouched territory), `follow_up` (turn understanding into action). Each question includes `question`, `type`, and `context` (why it matters). Runs as a background task like MEDDPICC with its own cadence (staggered 22s after standard, 30s steady-state). Generated on stop, on history update, and during live recording. Persisted in `Meeting.suggestedQuestionsJSON`. Included in webhook payloads and markdown exports. `⌘4` keyboard shortcut on macOS. UI shows questions as cards with type labels, context, and copy buttons.
- **Finished-meeting update action**: `generateInsights()` respects the selected insights mode for a completed current meeting (`standard` vs `meddpicc`). In Training mode, the action just refreshes local training metrics and does not make AI requests.
- **Meeting titles**: New meetings start with `title: "untitled"`. AI-suggested titles from `applyInsights()` and `generateFinalInsightsAndSave()` set `meeting.title` directly (no timestamp prefix). Calendar-started meetings use the event title. `currentTitleSuffix` tracks the last-applied title for dedup. `parseMeetingTitle()` is kept as a legacy helper for old meetings that have the `yyyyMMdd-HHmmss - Suffix` format. All display surfaces, markdown exports, webhook payloads, and Live Activity use `meeting.displayTitle` which handles both old and new title formats. Title editing in history views (`TextField`) binds directly to raw `meeting.title`.
- **isStartingMeeting**: Transient flag set in `startNewMeeting()`, cleared when `startRecording()` succeeds or on failure. iOS shows a "starting..." spinner during this phase. macOS hides the session view.
- **isResumingRecording**: Transient flag set when resuming a stopped session in managed mode (needs a fresh temp Deepgram key). Cleared when `startRecording()` succeeds, on failure, or on `clearCurrentSession()`. Shows a "starting..." spinner on the resume button and blocks repeat taps. On iOS, managed via local `@State` in `MeetingView_iOS` rather than AppState to avoid cross-view side effects.
- **pendingOpenSavedMeetingID / saveAndOpenCurrentMeeting()**: When the user saves a stopped session (⌘S), `saveAndOpenCurrentMeeting()` stores the meeting's UUID in `pendingOpenSavedMeetingID`, calls `goHome()`, and `MainWindow` picks up the pending ID to select it in the history sidebar. This makes save navigate directly to the saved meeting.
- **Escape key routing (macOS)**: Centralized in `KeyboardShortcutsService`. Order: (1) dismiss any active sheet (debug log, Attio send) via `cancelOperation` + `performClose`, (2) close Settings/Preferences window, (3) close help overlay, (4) go home. Sheet dismissal scans both key window and all visible windows as fallback. Settings detection checks window title and `toolbarStyle == .preference`.
- **J/K history navigation vs text entry (macOS)**: `KeyboardShortcutsService` ignores unmodified `j`/`k` and arrow-key history navigation when focus is in an editable text responder (`TextField`/`TextEditor` via AppKit `NSTextView`/field editor). This prevents list scrolling while typing in notes or Attio search fields.
- **Stop = save + stay**: `stopRecording()` saves the meeting to SwiftData and generates final insights (standard + MEDDPICC) in the background. The user stays in the stopped state with resume/save/discard controls on both iOS and macOS.
- **Mic restart retry**: If `handleEngineConfigurationChange` fails to restart the mic (e.g. Core Audio format mismatch during Bluetooth device bouncing), `scheduleMicRestartRetry` retries with bounded backoff (0.5s → 1.5s → 3s, max 3 attempts). On success, `restartSystemTapForMixMode()` flips the system tap back to `mixWithMic=true` if it had switched to `directCallback` mode while the mic was dead. `expectsMicAudio` tracks whether the user originally requested mic capture. `handleDefaultOutputDeviceChange` reads `isMicActive` after the settle delay (not at event time) to avoid capturing stale mic state during rapid device bouncing.
- **System tap stall recovery**: `AudioCaptureService` now handles two failure modes: (1) silent-stall (callbacks keep arriving but stay near-silent) and (2) callback-stall (callbacks stop arriving). Both paths rebuild the system tap with ring-buffer reset and bounded cooldowns, preserve the active mix mode (mic+system vs system-only), and retry failed rebuilds with bounded exponential backoff (except explicit permission-denied cases).
- **Session-end robustness**: `MinitiAPIService.endSession` still retries trailing-slash 405 routing edge cases, and now also consumes backend idempotency/session-finalization diagnostics while the app maintains a durable retry queue for failed reports.

## Audio flow

1. `AudioCaptureService.startCapture(microphone:systemAudio:)` starts AVAudioEngine (mic) and/or Core Audio process tap + AVAudioEngine (system)
2. Mic audio: converted to 16kHz mono PCM16 via AVAudioConverter, level via `vDSP_measqv`
3. System audio: `AudioHardwareCreateProcessTap` → `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` → aggregate device → IO proc callback → direct vDSP conversion (mono downmix via `vDSP_vadd` + decimation via stride + `vDSP_vsmul`/`vDSP_vclip`/`vDSP_vfix16`) → 16kHz mono PCM16. The aggregate device's IO format is read from `kAudioDevicePropertyStreamFormat` (input scope) to handle cases where it differs from the tap format. Level via `vDSP_measqv`.
4. **Process Tap setup**: Creates a `CATapDescription` (global stereo, captures all processes), then an aggregate device with the tap as a sub-tap. The aggregate's main sub-device provides the clock — always the built-in output device (shares the same hardware oscillator as the system mixer, guaranteeing zero drift). The default output device is never used as the clock because external/Bluetooth devices can run at different sample rates (e.g. AirPods HFP at 24kHz vs tap at 48kHz), causing drift compensation to fail and the tap to deliver silent buffers. Falls back to default output only if no built-in device exists. IO proc callback runs on a custom DispatchQueue (not RT thread). Cleanup: stop IO proc → destroy aggregate device → destroy process tap.
5. **Mixing**: When both sources active, system audio PCM16 goes into a pre-allocated Int16 ring buffer (8000 samples, ~500ms at 16kHz, NSLock-protected, zero allocations). Mic callback drains the ring buffer and mixes via vDSP (`vDSP_vadd` after float conversion). **Adaptive dual AGC**: each buffer's Int16 RMS is measured in real-time, and independent gain is computed to bring mic to ~3000 and system to ~2000 Int16 RMS (mic 1.5x louder for diarization). Gains are smoothed (fast attack 0.15, slow release 0.02) to avoid pumping. A noise gate (floor=30) prevents boosting silence. Max gain capped at 25x. This handles any hardware level (process tap, ScreenCaptureKit, Bluetooth, built-in, etc.) without manual tuning. Debug log `[AudioMix]` prints every 30s, only when system audio is active.
6. **Source dominance tracking**: Each buffer's pre-AGC mic/sys RMS is logged with its stream timestamp. `dominantSource(from:to:)` returns `.mic` or `.system` for a time range. Deepgram words are tagged: mic-dominant → speaker `1000` ("You"), system-dominant → keep Deepgram's speaker ID (for multi-speaker remote diarization). Threshold: system must exceed mic × 1.5 to be tagged as system (avoids false positives from amplified mic noise). Source log bounded at 6000 entries (~10 min).
7. **Diarization stabilization (both platforms)**: Final speaker segmentation now uses stricter switch confirmation (minimum run length + duration), applies `speaker_confidence` gating for uncertain boundaries, and uses a new-speaker promotion stage so brand-new speaker IDs only appear after sustained evidence. Interim updates are also gated so unconfirmed speaker guesses don't immediately pollute speaker lists.
8. `onAudioBuffer` callback → DeepgramService (nil during monitoring)
9. Levels flow independently: AudioCaptureService → Combine → AppState → SwiftUI views (throttled to ~20Hz, waveforms at 16Hz)
10. **Level display**: `SourceWaveform` uses `pow(level, 0.2)` power curve (not linear) so quiet mic signals (~0.003 RMS) show visible bar movement.

### iOS audio flow (mic-only)
1. `AVAudioSession` configured with `.playAndRecord` category, `.defaultToSpeaker` + `.allowBluetoothA2DP` + Bluetooth call-profile option (implemented with `.allowBluetooth` for toolchain compatibility)
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
- **Force update** (when server `min_version` > app version): Non-dismissable blocking screen (`ForceUpdateView`, shared with iOS). Shows "update required" message with download link. Takes priority over all other gates (terms, onboarding). Triggered by `checkForUpdates()` on launch; controlled server-side by bumping `MACOS_MIN_VERSION` / `IOS_MIN_VERSION`.
- **Terms acceptance** (first launch or existing users who haven't accepted): Privacy & terms gate — shows before onboarding. Links to privacy policy and terms. Single "i agree" button advances to onboarding or home. Backed by versioned acceptance in `@AppStorage` (`acceptedTermsVersion`, with legacy bool migration).
- **Onboarding** (first launch, after terms): Mode selection — "Early Adopter" (managed, 500 min/month) or "Bring Your Own Keys"
- **Home** (`ReadyStateView`): Mode-aware — managed shows usage status, BYOK shows API pills; animated "multi-dimensional meetings" tagline; audio source panel, start button; cog button (top-right) opens settings
- **Home (limit reached)**: In managed mode when 500 min used — inline "switch to BYOK" prompt, start button disabled
- **Home (device disabled)**: In managed mode when admin has disabled the device — shows "account disabled" message, start button hidden
- **Starting**: Spinner with "starting..." text while waiting for managed mode key or audio setup — stays on home screen until recording begins
- **Recording**: TerminalHeader with red dot + timer, stop button, dual labeled waveforms (mic green, system blue), transcript, notes, live insights
- **Stopped session**: Same layout; header shows discard (left), cont (center, same position as stop), save (right) with `⌘⌫` / `⌘S` shortcuts on macOS. Status dot hidden when not recording. Resumes the current session (no new meeting created). In managed mode, resuming requests a fresh temp Deepgram key (the previous one is cleared on stop).
- **History**: Sidebar list → detail view with tabs (transcript / insights / meddpicc / training / questions). macOS uses split panes (transcript + notes on left, insights on right) and the insights pane has mode tabs (standard / MEDDPICC / training / questions) with `⌘1` / `⌘2` / `⌘3` / `⌘4`.
- **Settings**: Tabs: General, Language, Account (mode toggle + usage stats + full device UUID, selectable), API Keys (BYOK only), Audio, Integrations (markdown export, webhooks, Google Calendar, Attio), About. Opened via cog button (`@Environment(\.openSettings)`), ⌘, or menu bar

### iOS
- **Force update**: Same as macOS (shared `ForceUpdateView`)
- **Terms acceptance** (first launch or existing users who haven't accepted): Same as macOS (shared `TermsAcceptanceView`)
- **Onboarding** (first launch, after terms): Same as macOS (shared `OnboardingView`)
- **Home** (`ReadyStateView_iOS`): Native toolbar: test mic (leading), usage status (principal), settings gear (trailing). Mic waveform appears inline below nav bar when testing. Logo with animated "multi-dimensional meetings" tagline, start button. Mic-only (no system audio toggle)
- **Home (limit reached)**: In managed mode when free cap is reached — shows in-app "Upgrade to Pro — $4.99/month", "Restore Purchases", and BYOK fallback
- **Starting**: Spinner with "starting..." text while waiting for managed mode key or audio setup
- **Recording**: Native toolbar: home (leading), red dot + timer + waveform (principal), share (trailing). Custom lowercase section picker (transcript/insights/notes), stop button at bottom center.
- **Stopped session**: Same layout — toolbar: home (leading), gray dot + frozen timer (principal), share (trailing). Bottom bar: discard (left), start/resume (center, same position as stop), save (right)
- **History tab**: `NavigationStack` list with swipe-to-delete, drill-down detail with custom tab bar (transcript/insights/notes, lowercase). Transcript collapses consecutive same-speaker segments. Insights contains standard / MEDDPICC / training modes plus generate/update for saved meetings. Training metrics are computed from saved segments. Notes are editable.
- **Settings**: Accessible via gear icon on home screen (no dedicated tab). Managed mode includes in-app Pro purchase, restore purchases, and Apple subscription management link.
- **Tab bar**: Record / History — two-tab navigation

## Monetization

> **Note:** Current implementation supports three options: Managed Free, Managed Pro, and BYOK. Some financial projections below are legacy scenario modeling and are explicitly marked.

### Commercial model

| | Free | Pro | BYOK |
|---|---|---|---|
| **Price** | $0 | $5/mo (or £5/mo) | $0 (forever) |
| **Minutes** | 500/month | 5000/month | Unlimited |
| **Transcription** | Managed backend | Managed backend | User's own |
| **LLM** | Managed backend | Managed backend | User's own |
| **AI insights** | Standard + MEDDPICC | Standard + MEDDPICC | Standard + MEDDPICC (user pays API) |
| **History** | Full | Full | Full |

- **BYOK** is always free and unlimited — zero cost, pure evangelists
- **Free** is generous (500 min) to build habit and word-of-mouth
- **Pro** expands managed usage to 5,000 min/month and keeps setup keyless
- No team/enterprise tier yet — nail individual experience first

### Payment implementation

**Current implementation: split rails by platform**
- **macOS:** Polar.sh web checkout + portal + license-key restore
- **iOS:** StoreKit 2 auto-renewable subscription (`com.miniti.mobile.pro.monthly`) with in-app purchase + in-app restore (`AppStore.sync()`)
- Subscription state and limits are still enforced server-side for managed usage; iOS also has a local StoreKit entitlement fast-path for immediate Pro UX

**macOS (direct DMG):**
- Upgrade and management flows open Polar pages in the browser
- No Mac App Store (sandbox blocks `AudioHardwareCreateProcessTap`)

**iOS:**
- In-app subscription purchase button in Settings and limit-reached state
- In-app "Restore Purchases" flow (`AppStore.sync()`)
- Manage subscription opens Apple's subscriptions page (`https://apps.apple.com/account/subscriptions`)
- iOS UI no longer relies on license-key restore flow

### UK business structure

No company required to start — operate as sole trader:
- Apple Developer Program accepts individual enrollment
- Polar.sh can operate as Merchant of Record for subscription sales and VAT handling
- Register for Self Assessment with HMRC for income tax
- VAT registration required only if UK taxable turnover exceeds £90K/year
- Form a Ltd company when revenue justifies it (£12 at Companies House, better liability protection)

### Financial model (legacy scenario model)

> Assumes an older `$14/mo + unlimited` Pro concept. Keep as historical/reference math only until recalculated for the current `$5/mo, 5,000 min/month` model.

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

Three parallel modes:

- **BYOK Mode**: User's own API keys, unlimited, no backend, no tracking
- **Managed Free**: 500 min/month, Deepgram via temp API keys (backend issues short-lived scoped keys), OpenAI proxied through backend, hard-blocked at limit
- **Managed Pro**: 5,000 min/month for $5/month (or £5/month GBP). Subscription rail is platform-specific: Polar.sh on macOS and StoreKit on iOS. Same backend routing as free, just higher limit.
- Mode toggle is a local routing switch only; user-entered BYOK keys persist in `@AppStorage` across mode switches (Secrets defaults are stripped in managed mode). Pro is a tier within managed mode, not a separate AppMode.
- Usage tracking is server-side (Vercel KV, keyed by Keychain-stored device UUID); switching modes never resets the counter. Free users reset on the 1st of each month UTC. Polar-backed Pro resets align to Polar billing cycle (`current_period_end`). Apple-backed Pro resets align to Apple subscription periods via `/api/apple/verify` + `/api/webhooks/apple`. iOS also keeps a local StoreKit entitlement fast-path in-app for immediate Pro UX.
- Device ID stored in macOS Keychain (`DeviceIdentifier.swift`) — persists across reinstalls, tamper-resistant
- Backend API keys (Deepgram/OpenAI) stored as Vercel encrypted env vars, never exposed to client
- At limit: free users can upgrade to Pro, switch to BYOK, or wait for monthly reset
- Backend is a separate repo (`miniti-api`), deployed at `https://miniti-api.vercel.app`; full spec in `BACKEND_SPEC.md`

#### Subscription integration (current split)
- **Checkout flow (macOS only)**: App calls `GET /api/subscribe` → backend creates Polar checkout session with `customerExternalId=deviceId` → returns checkout URL → app opens in system browser → user pays → Polar webhook fires → backend upgrades device tier in Redis
- **Webhook handling**: `POST /api/webhooks/polar` verifies HMAC-SHA256 signature (Standard Webhooks spec, zero npm dependencies — uses Web Crypto API). Handles `subscription.active`, `subscription.canceled`, `subscription.revoked`, `subscription.updated`. On activation/renewal, extracts `current_period_start`/`current_period_end` from the subscription payload to align the device's usage reset date with the billing cycle. If the billing period rolled over (new `current_period_start`), minutes are reset to 0. Cancellation downgrades ALL devices linked to that subscription via `polar_sub:{subId}:devices` Redis SET and reverts reset dates to 1st-of-month.
- **License key restore**: Polar auto-generates a license key on subscription. User enters it on any new device via `POST /api/restore` → backend calls Polar's public activation API → verifies active subscription → links device. License keys are auto-revoked on cancellation.
- **Customer portal**: `GET /api/portal` creates a Polar customer portal session for managing subscription (cancel, update payment, view invoices). Opens in browser.
- **StoreKit flow (iOS):** iOS app loads `com.miniti.mobile.pro.monthly`, presents native purchase sheet, supports in-app restore via `AppStore.sync()`, and opens Apple subscription management URL for cancellations/changes.
- **iOS App Store compliance:** iOS purchase and restore are now in-app (no external web checkout button in iOS purchase UX).
- **Cross-platform policy:** subscriptions are intentionally separate by platform (Apple IAP does not unlock macOS Polar Pro, and Polar does not auto-unlock Apple IAP).
- **Security**: Polar access token is server-side only (`POLAR_ACCESS_TOKEN` env var). Subscription state enforced in Redis — app cannot fake pro status. Webhook signatures verified cryptographically. Restore rate-limited (5/min).
- **Env vars**: `POLAR_ACCESS_TOKEN`, `POLAR_WEBHOOK_SECRET`, `POLAR_PRODUCT_ID`, `POLAR_ORGANIZATION_ID`
- **Redis per-device additions**: `polarCustomerId`, `polarSubscriptionId`, `subscriptionStatus` (active/canceled/null), `currentPeriodStart` (ISO 8601, from Polar webhook). `polar_sub:{subId}:devices` SET tracks all devices linked to a subscription for bulk downgrade on cancel.

#### Apple backend implementation (current, in `miniti-api`)

Apple server-side entitlement is now implemented and live for managed mode:

- **Separate rails remain intentional**: macOS Pro is Polar; iOS Pro is Apple IAP. Apple purchase does not unlock macOS Polar Pro.
- **Data model is merged entitlement-aware**: `subscriptionSource`, Apple transaction/status/period fields, `apple_sub:{originalTransactionId}:devices` linkage set, canonical `apple_sub_state:{originalTransactionId}` hash, and `apple_event:{notificationUUID}` webhook idempotency keys.
- **`POST /api/apple/verify` is active**: authenticated with `X-API-Key` + `X-Device-ID`, accepts StoreKit signed transaction JWS, verifies signature/cert chain, enforces configured bundle/product IDs, links device to Apple entitlement, then returns updated usage/tier payload.
- **`POST /api/webhooks/apple` is active**: verifies App Store Server Notifications v2 JWS, dedupes by `notificationUUID`, and propagates entitlement updates across all linked iOS devices for that `originalTransactionId`.
- **Status handling is explicit**: active/grace/billing-retry keep Pro entitlement; expired/revoked downgrade; renewal-preference changes are tracked separately.
- **Usage gating now uses effective entitlement state** for `GET /api/usage` and `POST /api/session`, so Apple-managed Pro limits and reset windows are applied server-side.
- **Rate limits are in place**: `apple_verify` and `webhook_apple` buckets are enforced.
- **Required Apple env vars**: `APPLE_BUNDLE_ID`, `APPLE_IAP_PRODUCT_ID`; optional pinning with `APPLE_ROOT_CA_PEM`.
- **Admin/reporting**: Apple subscriber emails are not available; admin surfaces Apple transaction/state diagnostics without customer email enrichment.

#### Backend API (`miniti-api`)
- Repo: `12ian34/miniti-api` (private), deployed at `https://miniti-api.vercel.app`
- Stack: Next.js 14 (App Router), TypeScript, Vercel, Upstash Redis via `@vercel/kv` (Node.js runtime on endpoints that need Node crypto/TLS cert APIs)
- Most app routes require `X-API-Key` + `X-Device-ID` (UUID). Exceptions: `GET /api/version` does not require `X-Device-ID`; Apple webhook does not use app auth headers.
- Device disable/enable via admin dashboard — disabled devices get 403 `device_disabled` on all endpoints; app shows "account disabled" message and blocks recording
- API key is XOR-obfuscated in `MinitiAPIService.swift` (not plain text in source/binary)
- **Security note**: the client `X-API-Key` is not a true secret (anything shipped in the app can be extracted). XOR obfuscation only reduces casual string scanning. Treat this as a client identifier / coarse gate, not strong authentication.
- **Safer direction**: keep quota enforcement and abuse protection server-side (`X-Device-ID`, rate limits, caps, anomaly detection), issue short-lived server tokens for sensitive flows (session creation / insights), and optionally add platform attestation later (e.g. App Attest / DeviceCheck on iOS) to raise abuse cost.
- Env vars (Vercel, encrypted): `OPENAI_API_KEY`, `DEEPGRAM_API_KEY`, `DEEPGRAM_PROJECT_ID`, `API_SECRET_KEY`, KV connection vars, `POLAR_ACCESS_TOKEN`, `POLAR_WEBHOOK_SECRET`, `POLAR_PRODUCT_ID`, `POLAR_ORGANIZATION_ID`, `APPLE_BUNDLE_ID`, `APPLE_IAP_PRODUCT_ID`, optional `APPLE_ROOT_CA_PEM`, optional `DOWNLOAD_LATEST_SECRET`
- Optional Attio env vars for CRM export (backend repo): `ATTIO_CLIENT_ID`, `ATTIO_CLIENT_SECRET`, `ATTIO_OAUTH_REDIRECT_URI`, `ATTIO_OAUTH_SCOPES`
- Optional Google Calendar env vars (backend repo): `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_OAUTH_REDIRECT_URI`
- Deepgram key needs **Member** role (can create temp keys), **never expire**

**Endpoints:**
- `GET /api/version` — returns `{ latest_version, min_version, download_url, release_notes }`. Requires `X-API-Key`. Optionally accepts `X-Device-ID`, `X-App-Version`, `X-Platform`, and `X-App-Mode` — when device ID is present, the backend creates or touches a lightweight device record (no usage/entitlement side effects). `latest_version` > app version = soft update banner; `min_version` > app version = hard block (must update). `min_version` is per-platform (`IOS_MIN_VERSION`, `MACOS_MIN_VERSION`) and defaults to `"1.0.0"`. Version/notes are release constants; macOS `download_url` is generated as a short-lived signed `download-latest-dmg` link when `DOWNLOAD_LATEST_SECRET` is configured, otherwise falls back to the configured desktop URL.
- `GET /api/usage` — check device minutes used/remaining; returns `tier`, `subscription_status`, tier-aware `minutes_limit` (30 req/min)
- `POST /api/session` — start session, returns temp Deepgram key (4hr TTL, `usage:write` scope); returns 402 if limit reached; limit is tier-aware (5 req/min)
- `POST /api/session/end` — report duration, increment usage counter; server caps at wall-clock elapsed (10 req/min)
- `POST /api/insights` — OpenAI proxy for transcript analysis; modes: `standard`, `meddpicc`, or `questions`; optional `language` field (ISO 639-1, default `"en"`) for language-aware prompts; transcript capped at 100KB (10 req/min)
- `GET /api/subscribe` — create Polar checkout session with `customerExternalId=deviceId`; returns `{ checkout_url }` (5 req/min)
- `POST /api/webhooks/polar` — Polar webhook receiver; HMAC signature verification (no X-API-Key); handles subscription lifecycle
- `POST /api/restore` — activate Polar license key on device; verifies active subscription; links device to subscription (5 req/min, macOS/web restore path)
- `GET /api/portal` — create Polar customer portal session; returns `{ portal_url }`; requires device to have `polarCustomerId` (5 req/min)
- `POST /api/apple/verify` — verify StoreKit signed transaction JWS, link Apple entitlement to device, return updated managed usage/tier payload (10 req/min)
- `POST /api/webhooks/apple` — App Store Server Notifications v2 receiver with signature verification + idempotency for Apple entitlement lifecycle updates (IP rate-limited)
- `POST /api/attio/connect/start`, `GET /api/attio/status`, `POST /api/attio/search`, `POST /api/attio/send` — additive Attio CRM export routes (backend stores OAuth token; older app versions unaffected)
- `POST /api/google/connect/start` — initiate Google OAuth flow, returns `{ auth_url, callback_scheme }` (5 req/min)
- `GET /api/google/connect/callback` — Google OAuth callback (no X-API-Key), exchanges code for tokens, redirects to `miniti-google://oauth-callback?status=success`
- `GET /api/google/status` — check Google Calendar connection status, returns `{ connected, email }` (10 req/min)
- `GET /api/google/events` — fetch upcoming calendar events with attendees, returns `{ events: CalendarEvent[] }` (30 req/min). Filters out all-day, cancelled, and self-declined events.
- `POST /api/google/disconnect` — revoke Google token and delete from KV, returns `{ disconnected: true }` (5 req/min)

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
- [ ] **Move Deepgram parse + speaker segmentation off the main queue** — current WebSocket delegate/parse path is main-queue-bound; shift JSON decode + segmentation to a background queue and publish only final UI state back on main.
- [ ] **Reduce audio callback allocation churn + meter publish frequency** — reuse temporary buffers in hot DSP paths and lower UI level-update cadence where possible to reduce callback CPU overhead.
- [ ] **Retune live-insights cadence for power efficiency** — increase segment/time thresholds for periodic live insight requests to cut long-session network/JSON processing cost.
- [ ] **Live transcript windowing while recording** — render only the most recent N transcript rows during active sessions (with optional “load older”) to cap layout/diff cost as sessions grow.
- [ ] **Throttle interim transcript + auto-scroll cadence** — reduce scroll churn by batching interim updates/scroll-to-bottom events instead of reacting to every fragment.
- [ ] **Adaptive waveform cadence** — lower waveform refresh rate (especially when idle/quiet) to cut sustained UI timer overhead.
- [ ] **Eliminate repeated hot-path full-array scans** — replace repeated `filter/count/last(where:)` passes in recording loops with incremental counters/cursors.
- [ ] **Profile instrumentation pass** — add signposts around transcript-cache rebuilds and save-plan/apply phases, then validate with Instruments on 60+ minute sessions.
- [ ] **Harden async save durability + discard semantics** — add explicit flush checkpoints for background/stop paths and cancellation guards so in-flight saves cannot resurrect discarded meetings.
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
1. Confirm local signing state once in Xcode:
   - Xcode → Settings → Accounts: signed into the Apple account that owns team `9AUR5U5KTF`
   - target `Miniti`: automatic signing on, team `9AUR5U5KTF`, bundle ID `com.miniti.app`
   - Developer ID distribution must already work on this Mac
2. Confirm the repo root `.env` contains App Store Connect credentials:
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY`
   - these are reused for notarization via `notarytool`
3. Bump version in `Miniti/Info.plist`, `MinitiMobile/Info.plist` (`CFBundleShortVersionString`) and `project.pbxproj` (`MARKETING_VERSION` — 6 places: 2 per target × 3 targets, Debug + Release). All targets share the same version number.
4. Run unit tests: `fastlane mac test` — verify all MinitiTests pass before building a release.
5. Sanity-check the local macOS export flow:
   - `fastlane mac build`
   - this builds `Miniti` with configuration `Release`, forces Developer ID signing during archive/export, writes `build/macos/miniti.app`, and stores the archive in `build/macos/miniti.xcarchive`
6. Notarize the macOS app:
   - `fastlane mac notarize_app`
   - submits `build/macos/miniti.app` to Apple notarization, staples the notarization ticket, and also copies the notarized app to repo root as `miniti.app`
7. Build the DMG:
   - `fastlane mac dmg`
   - runs `./scripts/build-dmg.sh build/macos/miniti.app` and creates `miniti.dmg` in the repo root
8. One-command path if the above is already trusted:
   - `fastlane mac release`
   - runs build, notarize, and DMG packaging in sequence
9. Publish/replace the desktop DMG artifact used by `miniti.app` download flow (currently Netlify Blobs key `downloads/miniti.dmg` served via `/.netlify/functions/download-latest-dmg`).
10. Xcode fallback if Fastlane is blocked for any reason: **Product → Archive → Distribute App → Developer ID → Upload** (notarizes), then export the notarized `miniti.app` and run `./scripts/build-dmg.sh miniti.app`

#### iOS
1. Confirm local signing state once in Xcode:
   - Xcode → Settings → Accounts: signed into the Apple account that owns team `9AUR5U5KTF`
   - target `MinitiMobile`: automatic signing on, team `9AUR5U5KTF`, bundle ID `com.miniti.mobile`
   - target `MinitiLiveActivityExtension`: automatic signing on, team `9AUR5U5KTF`, bundle ID `com.miniti.mobile.live-activity`
   - if Xcode shows **Fix Issue**, click it before using Fastlane
2. Confirm the repo root `.env` contains App Store Connect credentials:
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY`
   - Fastlane loads the root `.env` directly; no separate `fastlane/.env` or `.p8` file is required
3. Bump version (same step as macOS — shared version across all targets) if doing a new release version
4. Sanity-check the local archive flow:
   - `fastlane ios build`
   - this builds `MinitiMobile` with scheme `MinitiMobile`, configuration `Release`, automatic signing via `-allowProvisioningUpdates`, derived data in `DerivedDataLocal/`, and outputs `build/ios/MinitiMobile.ipa`
5. For a TestFlight build:
   - `fastlane ios beta version:1.13.0 changelog:"release notes here"`
   - auto-increments build number unless `build:` is provided explicitly
   - uploads to TestFlight, but does not add testers/groups or submit external review automatically
6. For an App Store upload:
   - `fastlane ios release version:1.13.0`
   - auto-increments build number unless `build:` is provided explicitly
   - the lane excludes precheck IAP validation (`precheck_include_in_app_purchases: false`) because App Store Connect API key auth cannot run IAP precheck
   - uploads the binary to App Store Connect, uploads metadata from `fastlane/metadata`, uploads/replaces screenshots from `fastlane/screenshots`, and includes app review notes from `fastlane/metadata/app_review_notes.txt` when present
   - does not submit for review automatically
7. Confirm App Store Connect auto-renewable subscription exists: `com.miniti.mobile.pro.monthly` (USD `$4.99`), with localized display name/description
8. Confirm app metadata includes privacy URL + terms URL and that subscription metadata is complete
9. Wait for Apple to process the build (~5–15 min)
10. If doing TestFlight first: add build to external testing group and submit for TestFlight review
11. For same-day App Store submission: create/select the app version in App Store Connect, attach the uploaded build, complete screenshots/review notes, and submit for App Review
12. Xcode fallback if Fastlane is blocked for any reason: **Product → Archive → Distribute App → App Store Connect → Upload**
13. `fastlane/RUNBOOK.md` is the practical runbook for the exact lane behavior and parameters in this repo. `fastlane/README.md` is auto-generated by Fastlane and may be rewritten.
14. Optional repo-managed App Store assets now have tracked placeholders so folders exist in git:
   - screenshots: `fastlane/screenshots/`
   - metadata: `fastlane/metadata/`
15. "What's New in This Version" is sourced from locale-specific metadata files, e.g. `fastlane/metadata/en-US/release_notes.txt`.
16. Before every release, update `fastlane/metadata/en-US/release_notes.txt` from the latest `claude.md` changelog entry before running `fastlane ios release`.
17. Keep versioned Fastlane docs/examples aligned with the release version: update `fastlane/RUNBOOK.md` example commands (`fastlane ios beta version:X.Y.Z`, `fastlane ios release version:X.Y.Z`) when the app version changes.
18. If the listing description includes a literal version footer (for example `v1.13.0`), bump it in `fastlane/metadata/en-US/description.txt` and mirrored locale descriptions (currently `fastlane/metadata/en-GB/description.txt`).
19. Repo-managed listing metadata currently includes `fastlane/metadata/en-US/name.txt`, `subtitle.txt`, `promotional_text.txt`, `description.txt`, `keywords.txt`, `privacy_url.txt`, `support_url.txt`, `marketing_url.txt`, and root `fastlane/metadata/copyright.txt`.
20. App Review notes for Fastlane uploads live in `fastlane/metadata/app_review_notes.txt` and are attached by `fastlane ios release` when present.
21. Keep `fastlane/metadata/copyright.txt` updated with the current year before running `fastlane ios release` (ASC rejects missing/outdated copyright year values).
22. If App Store Connect default locale is not `en-US`, mirror all localized metadata files into that locale folder as well (example: `fastlane/metadata/en-GB/{name,subtitle,promotional_text,description,keywords,privacy_url,support_url,marketing_url,release_notes}.txt`) so listing text updates consistently in that locale.

#### After both platforms
1. **Update backend version endpoint**: in `miniti-api`, edit `app/api/version/route.ts` — set `latest_version` + `release_notes` (and iOS App Store URL if changed). macOS `download_url` is signed at request time when `DOWNLOAD_LATEST_SECRET` is set, so no per-release DMG URL paste is needed there.

### `scripts/build-dmg.sh`
- Tracked in git (not gitignored) — safe because `scripts/` is not referenced in `project.pbxproj`, so Xcode Cloud ignores it entirely
- Requires `create-dmg` (auto-installed via Homebrew if missing)
- Validates code signature and notarization before packaging
- Creates a drag-to-Applications DMG with README (app center, Applications symlink right, README left)
- Staples the notarization ticket to the DMG
- Version extracted from the app's `Info.plist` (for display only — output filename is always `miniti.dmg`)
- Background image: `scripts/dmg-background.png`; volume icon pulled from app's `AppIcon.icns`

### iOS (MinitiMobile)
- Bundle ID: `com.miniti.mobile`, deployment target iOS 17.0
- Distribution: App Store (no sandbox restrictions for mic-only recording)
- In-app purchase: StoreKit 2 auto-renewable subscription product `com.miniti.mobile.pro.monthly` (`$4.99/month`)
- Background audio: `UIBackgroundModes: [audio]` + `AVAudioSession` category `.playAndRecord` enables recording while backgrounded
- Live Activity: `MinitiLiveActivityExtension` widget extension (bundle ID: `com.miniti.mobile.live-activity`), embedded in MinitiMobile via "Embed App Extensions" build phase. Shows recording on Dynamic Island + Lock Screen.
- No system audio capture — iOS sandbox prevents it entirely
- Export compliance: `ITSAppUsesNonExemptEncryption: NO` in Info.plist — app only uses HTTPS (OS-provided TLS), which is exempt. This key bypasses the App Store Connect encryption compliance dialog and unblocks TestFlight distribution.
- Xcode targets: `Miniti` (macOS app) + `MinitiMobile` (iOS app) + `MinitiLiveActivityExtension` (widget extension) + `MinitiTests` (XCTest, macOS host) + `MinitiMobileTests` (XCTest, iOS host)
