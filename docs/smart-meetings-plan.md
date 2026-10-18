# Smart meetings and reliable macOS reopening

> **Shipped regression contract:** This document records the implemented silence/calendar Smart meetings and macOS reopening behaviour. The shipped successor for call-app lifecycle detection, reversible automatic ending, recording presence UI, and settings simplification is [call-lifecycle-and-recording-presence-plan.md](call-lifecycle-and-recording-presence-plan.md). Where the two differ about end detection or settings, the newer call-lifecycle contract controls; the durable transition, reopening, notification, and fallback constraints here remain required.

## Goal

Miniti should remain reachable after its main macOS window is closed, and it should help people separate adjacent meetings without silently putting the second meeting into the first. The meeting assistance is optional, conservative, and controlled by one new default-on `Smart meetings` setting.

This document is the implementation and regression plan. It is intentionally kept in the repository so future changes preserve the product decisions and safety boundaries.

## Scope

### 1. Reliable macOS reopening

- Give the primary `WindowGroup` a stable `main` scene ID.
- Tag the actual primary `NSWindow` with a stable identifier once SwiftUI creates it.
- Route Dock reopen and the menu bar `Open Miniti` action through one helper that:
  - deminiaturizes and fronts the identified main window when it exists;
  - asks SwiftUI to open the `main` scene when no main window exists;
  - never mistakes Settings, an alert, or a transient panel for the main window.
- Preserve the existing OAuth duplicate-window cleanup, but make it operate on the stable main-window identifier.
- Add privacy-safe unified lifecycle logs for close, reopen, fallback creation, and duplicate cleanup. Do not log transcript, title, attendee, or calendar content.
- Keep the app as a `WindowGroup`, rather than converting it to a singleton `Window`, so disabling the menu bar item does not leave the user without a supported way to recreate the main window.

### 2. Smart meetings preference

Add `Smart meetings` to Settings -> Calendar (then "Calendar & Meetings") -> Calendar & Meeting Automation, beside the existing calendar controls. Keep it visible and usable when Google Calendar is disabled or disconnected because quiet-ended assistance does not require a calendar. It defaults on.

Copy:

> Notices when a meeting may have ended or another meeting is approaching, then helps you finish, save, and start the right recording.

The row includes `Learn more about Smart meetings` and opens `https://miniti.app/docs/features/smart-meetings`.

The switch controls only the new inferred assistance:

- likely-ended prompts based on quiet;
- common-boundary detection at `:00` and `:30`;
- calendar transition prompts;
- conservative automatic handoff countdowns;
- smart meeting notifications and menu bar status;
- five-minute `keep recording` suppression.

Turning it off does not change existing explicit behaviour:

- configured silence auto-stop;
- calendar auto-start;
- calendar-aware auto-stop;
- existing one-minute calendar reminders;
- manual start, stop, resume, and `End & Start New Meeting`;
- audio/transcription recovery or the macOS window fix.

This gives three useful configurations without adding interdependent switches:

1. Smart meetings on, with existing automatic start/stop choices independently configured.
2. Smart meetings off, while existing automatic start/stop continues exactly as configured.
3. Smart meetings off and existing automatic start/stop off, for fully manual operation.

### 3. Non-calendar likely-ended flow

Only evaluate a likely-ended prompt while a meeting is recording, Smart meetings is on, and at least one meaningful finalized transcript segment exists. Require both transcript quiet and no speech-like audio activity. "Speech-like audio" is Deepgram's own `SpeechStarted` detection (`vad_events=true`, already requested) while transcription is healthy (`audioRecoveryState == .healthy`), and the raw capture level only while the pipeline is reconnecting or degraded (`AppState.smartMeetingSpeechGap`). The raw level counted fans, keyboards and traffic as activity and kept the prompt from ever appearing in an ordinary room (2026-09-25). The hard silence auto-stop and the automatic calendar handoff keep the raw-level gate. Once the meeting's calendar event has ended, the quiet threshold drops to 2 minutes regardless of the calendar auto-stop setting (an ask, never a stop).

Use these prompt thresholds:

| Existing silence auto-stop | Smart prompt after quiet |
|---|---:|
| Off | 5 minutes |
| 3 minutes | 2 minutes |
| 5 minutes | 3 minutes |
| 10 minutes | 5 minutes |
| 15 minutes | 5 minutes |

The prompt can occur earlier at a common meeting boundary only when the recording has lasted at least 15 minutes, the quiet period spans `:00` or `:30`, and quiet has lasted at least 2 minutes. This avoids prompting during ordinary short pauses.

Prompt copy:

> No speech for 3 minutes. Has this meeting ended?

Actions:

- `End meeting` stops, durably saves, completes required finalization bookkeeping, and returns Home so the next Start creates a new meeting.
- `Keep recording 5 min` dismisses the prompt and suppresses the inferred prompt and silence auto-stop for five minutes.

Show at most one prompt per uninterrupted quiet episode. Meaningful speech clears the prompt episode and any suppression: while transcription is healthy that means interim or final words, not a capture-level burst, so a noise burst neither dismisses the quiet or call-ended ask nor forgets a "Keep recording" answer (`noteSmartMeetingActivity(source:)`); a level burst still cancels an automatic calendar handoff countdown, and with the pipeline down the level is all there is. Ignoring the prompt does not alter the existing auto-stop result: configured auto-stop still fires at its original threshold, while Auto-stop Off continues recording.

### 4. Calendar transition flow

When a different calendar event is approaching and the current meeting has not ended, show a transition prompt about one minute before the next event:

> Next: Design review starts at 10:30. Is the current meeting over?

In-app actions:

- `Join next` (when the next event has a conference link)
- `End & start next`
- `End meeting` (end the current meeting without starting the next one; added 2026-09-11 after Josh reported having only "end and start next" or "keep recording" when the next event was not his to record)
- `Keep recording`
- `Remind in 2 min`

System notifications expose three actions:

- `End & start next`
- `End meeting`
- `Keep recording`

Out-of-office, focus-time, working-location, and birthday events (Google `eventType`), all-day events, events the person declined, titles that start with a time-block label (OOO, PTO, holiday, focus time), and timed events with no conference link, no guest other than the person, and no outside organizer (a personal block such as "kids pickup", 2026-09-25) are not meetings, so they never reach reminders, auto-start, or this prompt (2026-09-11). The rules are the person's: `CalendarMeetingFilterPreferences` (UserDefaults `calendarMeetingFilters.v1`, edited in Settings → Calendar → Meeting filters, shared `CalendarMeetingFiltersSection`) holds a toggle per rule and an editable list of title prefixes. The client fetches `/api/google/events?include_filtered=true`, keeps every non-cancelled event in `AppState.fetchedCalendarEvents`, and derives `upcomingEvents` through `CalendarEvent.skipReason(under:)`, so a settings change re-applies without a refetch. "Preview next 7 days" (`AppState.previewCalendarMeetingFilters`) lists the coming week with each event's skip reason. The backend applies the same defaults for older clients.

Do not silently split meetings just because the clock reaches an event boundary. Automatic handoff is allowed only when all of these are true:

- Smart meetings is on;
- the current recording is associated with a calendar event;
- the current event has ended;
- the next non-overlapping event starts within 15 minutes;
- existing calendar auto-start and calendar-aware auto-stop are both enabled;
- transcript and speech-like audio have both been quiet for at least 2 minutes.

When eligible, show a cancellable 15-second countdown before ending and starting the next event. Cancel the countdown immediately when meaningful speech resumes. Calendar overlap, missing event association, active speech, or either existing automatic setting being off always leaves the decision to the user.

Calendar context must be attached to the new `Meeting` before transcription connects so the first request has the right title, attendees, keyterms, and speaker hints.

### 5. Safe meeting transition transaction

All calendar, notification, menu bar, keyboard, and in-app transition actions use one AppState-owned transition path.

The transition path:

1. Validate that a fresh meeting is allowed before stopping the current one.
2. Stop capture and disconnect transcription gracefully.
3. Preserve interim transcript text.
4. wait for the existing durable save fence;
5. snapshot the old meeting for background insight generation;
6. clear the active session;
7. create the new meeting, applying calendar context before connection when applicable;
8. start capture only after the new meeting is the active AppState meeting.

Background finalization of the old meeting remains meeting-ID and revision scoped. A late callback must not mutate the new meeting. If validation fails, the current meeting keeps recording and the user sees the existing actionable error.

Manual behaviour is clarified at the same time:

- `New Meeting` starts a fresh meeting from Home.
- During an active or stopped session, the action is `End & Start New Meeting`.
- The menu bar distinguishes `Resume Meeting` from `Start New Meeting` for a stopped session.

### 6. Presentation and notification routing

- Keep AppState's pending prompt as the authoritative state, with every action routed through the same transition method.
- On macOS, show every start, ending, quiet, and calendar-handoff prompt in the non-activating floating recording surface when it is enabled. A new decision auto-expands and explicitly reorders that surface front without activating Miniti or stealing focus.
- Mirror a prompt to a local system notification when notification permission is already granted and either another app is active or the floating recording surface is disabled. The AppDelegate opts intentional foreground fallback requests into banner/list/sound presentation. Smart meetings must remain fully usable without notification permission.
- On iOS, retain the background-only notification rule and the in-app prompt as the foreground presentation.
- Register notification categories and actions during application launch.
- Route notification actions back through the same AppState transition methods.
- On macOS, a notification tap also restores or opens the identified main window.
- Surface the same pending prompt and countdown in the macOS menu bar so closing the window does not hide the decision.
- Respect Reduce Motion for the countdown and prompt transitions.

### 7. Regression constraints

- Do not alter Deepgram retry, watchdog, audio capture, save queue, insight revision fencing, managed-minute accounting, Live Activity, CRM sync, auto-export, or webhook contracts.
- Do not add a backend migration, entitlement, schema migration, or new account permission.
- Do not request calendar access from Smart meetings itself. Calendar-specific behaviour activates only when calendar data is already available.
- Do not repeatedly scan growing published transcript arrays from per-segment callbacks. Smart evaluation runs on bounded timers and resets from existing activity timestamps.
- Preserve macOS menu bar disabled mode, OAuth callback behaviour, minimized-window Dock reopening, and Settings-window independence.
- Preserve iOS background recording and Live Activity state during prompts.
- Make the preference durable through `AppStorage` and default it on for both new and existing installations.

### 8. Tests

Add deterministic tests for pure policy and transition decisions:

- the threshold table for every auto-stop setting;
- no prompt without meaningful transcript;
- both transcript and audio quiet are required;
- one prompt per quiet episode;
- five-minute suppression and speech reset;
- common-boundary rules, minimum meeting duration, and minimum quiet duration;
- next-event selection and overlap rejection;
- automatic calendar handoff requires every opt-in and inactivity condition;
- calendar context exists before meeting startup;
- manual and calendar handoffs save the old meeting and isolate late insight callbacks;
- Smart meetings off leaves all existing auto-start/auto-stop policy results unchanged;
- reopening chooses only the stable main window identifier and falls back to scene creation.

Run both shared test bundles because `MinitiTests/*.swift` compiles against both app targets:

- macOS unit tests;
- iOS simulator unit tests;
- macOS Debug build;
- iOS simulator Debug build.

Manual smoke matrix:

- close main window, reopen from Dock, reopen from menu bar, and repeat while Settings is open;
- minimize then Dock-click;
- OAuth callback with no main window and with one main window;
- Smart meetings on/off crossed with silence auto-stop off/on;
- calendar disconnected, connected with back-to-back events, overlapping events, and a gap over 15 minutes;
- active speech during the final countdown;
- stopped session Resume versus Start New;
- notifications allowed/denied and app foreground/background;
- iOS lock/background recording and Live Activity remain intact.

### 9. Documentation and release notes

- Add the public `features/smart-meetings` page and navigation entry in `../miniti-docs`.
- Cross-link the existing auto-start/stop and Google Calendar pages so the master setting boundary is clear.
- Update `docs/patterns.md`, `docs/ui-states.md`, `docs/testing.md`, and `AGENTS.md` in this repository.
- Add a plain user-facing bullet only to the current unreleased platform section that will actually ship the change. Do not edit historical changelog entries.

## Rollout and observability

The feature is local and default on, but its decisions are deliberately prompt-first. There is no silent calendar split outside the narrow double-opt-in inactivity case. Privacy-safe unified logs record only lifecycle route, policy reason codes, and success/failure state. They do not include meeting content.

If field feedback shows excessive prompts, the first tuning lever is the pure policy threshold, not additional settings. If the macOS disappearance recurs, lifecycle logs should distinguish a hidden/minimized main window, a missing scene, a notification route, and a duplicate-window cleanup without exposing customer data.
