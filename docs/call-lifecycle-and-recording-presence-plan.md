# macOS call lifecycle, automatic meeting boundaries, and recording presence

## Status and decision

> **Shipped regression contract (v2.4.0–v2.5.0):** The call-app lifecycle, reversible automatic ending, recording-presence UI, settings simplification, and subsequent floating-surface nudge refinements described here are implemented. This document is retained as the decision record, regression contract, and operational validation reference.

This programme superseded the silence-first end-detection direction in [smart-meetings-plan.md](smart-meetings-plan.md), while preserving that document as the regression contract for window reopening, durable handoff, notification routing, and quiet/calendar fallback behaviour.

The product decision is:

> On macOS, the lifecycle of the call application becomes the primary signal for virtual-meeting start and end. Calendar context and transcript/audio activity strengthen or recover the decision. Prolonged silence remains only a fallback for in-person meetings, unsupported call applications, and failed lifecycle detection.

Miniti must not use the camera, inspect screen contents, automate meeting-app UI, or require Accessibility merely to determine whether a call is active. Strong call-end detection should automatically finish a recording after a short, visible, reversible grace period. Start detection remains consent-preserving: it offers to start notes and does not silently capture unless the user separately enabled calendar auto-start.

This programme is macOS-first. iOS cannot inspect other applications' audio-input use and retains the current calendar, silence, background recording, and Live Activity contracts.

## User problem before v2.4.0

Before v2.4.0, Miniti inferred that a meeting may have ended from transcript quiet, audio-level quiet, calendar boundaries, and upcoming events. This was necessarily slow and ambiguous:

- an ended Zoom, Meet, Teams, or Slack call is indistinguishable from a long pause without an application-lifecycle signal;
- music, media, room noise, or a sensitive amplitude threshold can keep the audio-activity timestamp fresh after the call is over;
- transcript failure must be distinguished from genuine quiet, which makes transcript-only stopping unsafe;
- the normal quiet prompt waits two to five minutes and is checked on a 30-second timer;
- the non-calendar quiet prompt deliberately excludes calendar-linked recordings, whose behaviour follows separate calendar paths;
- back-to-back meetings can remain in one recording if the user misses or ignores a transition prompt;
- closing or covering the main window makes recording state and pending decisions too easy to miss.

The result is a product-level adoption problem, not merely a threshold-tuning problem. Lower silence thresholds would increase false stops without proving that a call ended.

## Granola research findings

Research was performed on 20 August 2026 using Granola's current public documentation, Apple documentation and SDK headers, and a read-only inspection of the current public Granola 7.498.1 macOS bundle.

### Confirmed product behaviour

Granola documents the following behaviour:

- ad-hoc call prompts are triggered when a supported application begins using the microphone;
- the prompt names the application and asks the user to take notes;
- Granola does not silently start every detected call: transcription starts after the user opens/clicks a note or notification, or when a pre-opened scheduled note reaches its start time;
- auto-end combines whether the call application is still using the microphone, transcript length/activity, scheduled calendar end time, a 15-minute no-audio fallback, and computer sleep;
- if one call application keeps its microphone active between two calls, Granola may merge the meetings and recommends a manual stop;
- its live meeting indicator floats at the right side of the screen, is draggable, and opens the active meeting when clicked.

Sources:

- [Granola: How transcription works](https://docs.granola.ai/help-center/taking-notes/transcription)
- [Granola: Notifications and ad-hoc call detection](https://docs.granola.ai/help-center/taking-notes/notifications)
- [Granola: Setup and macOS audio permissions](https://docs.granola.ai/help-center/getting-started/setting-up-granola-for-the-first-time)

### Confirmed implementation shape

The inspected bundle contains a native `macos_mic_apps_with_devices` component that polls active Core Audio input processes once per second. It maps helper processes to known applications including Chrome, Zoom, Slack, Teams, Safari, FaceTime, Webex and other call-capable apps. This is separate from Granola's virtual-camera system extension.

Granola's camera declaration says the camera is used to show a watermark in meetings. Its camera/system-extension footprint supports an optional consent-presence feature, not basic call start/end detection. Miniti must not copy that unrelated permission footprint.

Granola's documentation says macOS auto-end requires admin rights, but does not document the technical reason. Its current bundle supports older macOS releases and contains compatibility/fallback mechanisms that Miniti does not need. Miniti must validate its own signed sandbox path rather than treating Granola's admin requirement as inherent to call detection.

## Apple API and permission conclusion

macOS exposes public Core Audio process objects:

- `kAudioHardwarePropertyProcessObjectList` returns processes connected to the audio system;
- `kAudioProcessPropertyPID` and `kAudioProcessPropertyBundleID` identify the process;
- `kAudioProcessPropertyDevices` identifies its audio devices;
- `kAudioProcessPropertyIsRunningInput` reports whether it is running IO with an active input stream.

Apple references:

- [kAudioHardwarePropertyProcessObjectList](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyprocessobjectlist)
- [kAudioProcessPropertyIsRunningInput](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunninginput)
- [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)

Miniti already requires macOS 14.2, uses the Core Audio process-tap family, ships sandboxed with the audio-input entitlement, and declares microphone and system-audio usage descriptions. The intended lifecycle detector therefore requires:

| Requirement | Decision |
|---|---|
| Camera permission | No |
| Accessibility permission | No |
| Screen-content capture | No |
| System extension | No |
| Privileged/admin helper | No |
| Private API | No |
| New entitlement | No expected change |
| New TCC prompt | No expected change |
| Higher macOS minimum | No |
| Existing microphone/system-audio permissions | Reused |

These conclusions are implementation gates, not assumptions to skip testing. Phase 0 must prove them in a signed, sandboxed Miniti build on every supported macOS generation before product behaviour changes.

## Product model and settings simplification

The stronger signal permits a simpler, user-comprehensible settings model.

### Primary settings

#### Smart meetings — default on

Copy:

> Detects calls, keeps recordings separated, and finishes when a call ends.

On macOS this one setting controls inferred assistance:

- supported call-app detection and the start-notes prompt;
- associating a detected call with a nearby calendar event;
- strong call-end detection and its reversible ending grace period;
- calendar transition assistance for back-to-back meetings;
- weak quiet/calendar fallback prompts;
- Smart meeting status in the menu bar and floating recording indicator.

Turning Smart meetings off disables inferred call start/end and transition assistance. It does not disable manual recording, recovery, the recording indicator, or explicit calendar auto-start until the existing auto-start setting is changed.

#### Automatically start scheduled meetings — default off

Keep this as the sole prominent automation switch because it changes the consent boundary: Miniti starts capturing at the calendar time without a click. It remains independent of Smart meetings.

### Advanced fallback

Replace the visible 3/5/10/15-minute silence picker with:

#### Stop after prolonged inactivity

- Off
- After 15 minutes

This is a safety fallback for in-person meetings, unsupported call applications and lifecycle-monitor failure. It is not presented as normal virtual-call end detection. Calendar end time can strengthen a fallback decision but does not need a separate user-facing auto-stop switch.

### Settings to retire

- **Auto-stop after calendar event ends:** redundant once calendar time is supporting evidence and call-app lifecycle is authoritative.
- **Multiple short silence durations:** these imply precision the signal cannot supply and can stop real meetings during pauses.
- **Separate inferred transition controls:** call detection, call ending and calendar handoff are one Smart meetings capability.
- **Upcoming meeting reminders inside automation:** keep notification preferences under Notifications rather than making them appear to control capture.

### Recording indicator setting

Add an independent default-on `Show recording indicator` setting under Appearance. A person may want lifecycle automation without the floating strip, or the strip while using manual recording. Disabling the indicator must not disable Smart meetings or the menu bar item.

### Staged settings migration

Do not delete persisted settings in the first lifecycle release.

1. Ship call lifecycle detection while retaining existing settings storage and showing old auto-stop controls as advanced fallbacks.
2. Preserve `autoStartFromCalendar` exactly.
3. Preserve `smartMeetingsEnabled`; off remains off.
4. During beta, record only privacy-safe reason codes and user decisions to validate strong-signal coverage.
5. In the next release, retire the calendar-auto-stop row and migrate the silence picker to Off/15 minutes. Keep tolerant reads of legacy values long enough for direct upgrades from older app versions. Three migration decisions are fixed now rather than left to the migration release:
   - **Value mapping:** legacy `autoStopMinutes` of 0 maps to Off; any non-zero legacy value (3/5/10/15) maps to 15 minutes. Shortening is never inferred — a person who relied on a 5-minute silence stop gets the safer longer fallback plus the new prompts, and the What's New copy says so explicitly.
   - **Quiet-prompt thresholds:** the smart quiet prompt currently derives its timing from the `autoStopMinutes` table, which collapses once the picker is Off/15. The fallback quiet prompt gets its own fixed policy constants (5 minutes, or 2 minutes across a `:00`/`:30` boundary for meetings over 15 minutes) that no longer read the picker.
   - **Handoff consent gate:** automatic calendar handoff currently requires calendar auto-start *and* calendar auto-stop both enabled. Retiring the auto-stop switch removes half of that double opt-in. The replacement gate is **Smart meetings on and explicit calendar auto-start on**, preserving a deliberate two-switch consent boundary where one of the switches is the same silent-capture opt-in that already governs unattended starts. Calendar auto-stop being retired must not silently loosen this.
6. Update public documentation before changing the meaning of Smart meetings for existing users. The What's New copy must state that supported calls can finish automatically after a cancellable countdown.

## Technical architecture

### 1. `CallActivityMonitor` service

Add a macOS-only service with a narrow public interface. It owns Core Audio process enumeration and emits immutable snapshots; it does not own product policy or mutate `AppState` directly.

Suggested output:

```swift
struct CallActivitySnapshot: Sendable, Equatable {
    let capturedAt: Date
    let activeCalls: [ActiveCallApplication]
}

struct ActiveCallApplication: Sendable, Equatable, Identifiable {
    let bundleID: String
    let displayName: String
    let deviceUIDs: Set<String>
    let confidence: CallApplicationConfidence
}
```

Implementation rules:

- use only public Core Audio properties;
- poll once per second initially, matching proven competitor behaviour; optimize only after measuring;
- poll off the main actor and deliver snapshots to the main actor; the monitor's Mach calls must never add jitter to UI or audio work;
- give the monitor a real start/stop lifecycle tied to Smart meetings being enabled — do not copy `AudioCaptureService`'s register-in-init-never-remove listener pattern — and pause polling while the machine is asleep;
- exclude Miniti, its helpers, aggregate devices and known loopback/tap identifiers;
- normalize known helper bundle IDs to a stable owning call application using a local table;
- cover non-default microphone devices rather than watching only the default input;
- debounce disappearance in policy, not by hiding raw monitor transitions;
- do not use `responsibility_get_pid_responsible_for_pid`, unified-log scraping, `lsof`, Accessibility, camera state or screen OCR;
- treat unknown microphone apps as low confidence and do not auto-start or auto-end from them;
- keep bundle IDs local. Diagnostics may report only a bounded known-app category when the user has opted into Share Diagnostics.

Initial known-app coverage should include Zoom, Microsoft Teams, Google Meet in Chrome/Safari/Edge/Arc/Brave, Slack, FaceTime, Cisco Webex, Discord, WhatsApp, Tuple, Dialpad and Gather. The normalization table must be unit tested and easy to extend without changing policy.

**Browser detection is app-level, not site-level.** Core Audio identifies only the browser's bundle ID. A Chrome helper running input is equally a Meet call, a Loom recording, voice dictation, voice search, or any WebRTC site; no product name can be inferred. Therefore browsers:

- carry a distinct `browser` confidence tier below native call apps;
- use the neutral `Meeting detected` prompt and never claim a site or product such as Google Meet;
- must expect false start candidates from short microphone uses, which the start debounce and prompt-only behaviour absorb;
- have weaker end evidence, because a second microphone-using tab in the same browser masks the call's end. Browser end candidates therefore lean harder on the quiet and calendar supporting signals below.

### 2. AppState-owned lifecycle policy

`AppState` remains the single source of truth. Add pure decision functions and small state rather than scattering timer callbacks through views.

Suggested lifecycle states:

- `idle`
- `startCandidate(app, firstSeenAt)`
- `callActive(app, associatedMeetingID)`
- `endCandidate(app, firstMissingAt)`
- `endingGrace(app, deadline, reason)`

The state machine consumes:

- raw call-activity snapshots;
- recording/current-meeting state;
- whether the meeting has meaningful transcript content;
- transcript and speech-like activity timestamps;
- selected/nearby calendar events;
- sleep/wake lifecycle;
- explicit user actions.

Keep all end/start/calendar actions routed through the existing AppState-owned durable meeting transition path. A late capture, transcript, save or insight callback from the old meeting must never mutate the next one.

### 3. Confidence policy

#### Call association

Every end decision hinges on which call the recording belongs to, so association formation is an explicit, unit-tested pure rule rather than an implicit side effect:

- a recording started from the start-notes prompt is associated with the detected application;
- a calendar auto-start that begins while exactly one recognized call application is active associates with that application;
- a manual recording started while exactly one recognized call application is already active associates with it;
- a call application that becomes active mid-recording is **never** retroactively associated. It is at most a transition candidate. This protects an in-person or unrelated recording from being ended because someone answered and then finished a FaceTime call during it;
- the one bounded exception is a start that expects its call: a calendar meeting with a conference link, or a join link the user opened (Join on a reminder or upcoming meeting). Notes start before the browser or app joins, so the first recognized call to appear within 5 minutes of that start (after the normal start debounce) is adopted as the recording's own call instead of being offered as "New meeting detected". A call already associated at start, or a call that appears after the window, follows the normal rules. Regression: Sasha pressed Join on a Meet and was immediately asked to end the meeting he had just started (2026-09-11);
- the second bounded exception (2026-09-25) is a plain start with no call active and no join link: the first recognized call to appear within 2 minutes (after the start debounce) is adopted as an *inferred* association. "Press Record, then join the Zoom" is the common ad-hoc flow, and without this the call's end was never noticed. An inferred association only ever asks at the end (`askOnly`), never enters the automatic ending grace, and is excluded from in-room/hybrid environment evidence. A call that appears after the window remains a transition candidate, which keeps the in-person-plus-FaceTime protection above;
- with two or more recognized call applications active at recording start, no association is formed, no adoption window is armed, and end detection stays in fallback mode until the ambiguity resolves.

#### Strong start signal

A recognized call application has an active input stream continuously for approximately two seconds.

Behaviour:

- when no recording exists, show the neutral `Meeting detected` title with the branded `take notes with miniti` invitation, plus `Take notes` and `Not now`;
- associate a calendar event within the existing bounded time window when unambiguous;
- clicking Take notes applies calendar title/attendees/context before transcription connects;
- never start silently unless calendar auto-start is already enabled and eligible;
- suppress repeated prompts for the same uninterrupted call after dismissal.

#### Strong end signal

The recognized call application associated with the recording had an active input stream and then has none for approximately four continuous seconds.

Additional guardrails:

- Miniti must have observed the call as active, rather than inferring an end from an app that was never seen;
- **the recording's own transcript must agree that the call is over.** Entering grace additionally requires that no transcript (interim or final) arrived within the last several seconds. Microphone-stream release proves only that the application let go of the microphone — push-to-talk, listen-only attendance, and applications that release input on mute all look identical to a call end from the process list alone. Miniti captures and transcribes the call's system audio, so live call speech expresses itself as fresh transcript and vetoes the end. The veto is deliberately transcript-based rather than audio-level-based: post-call music keeps system audio levels hot and an amplitude veto would block ending forever, which is one of the original silence-model failures. This reuses the existing `lastTranscriptReceivedAt` timestamp and is the primary defence of the sub-1% false-end acceptance bar;
- the recording must have minimum meaningful content or duration before automatic ending; very short/empty sessions receive an ask-only prompt, and so does any recording whose association was inferred rather than announced;
- a device switch by the same application must not look like an end;
- another recognized call app becoming active is a transition candidate, not proof that both meetings should be merged;
- reactivation during debounce or grace cancels the end automatically.

#### Supporting signals

- associated calendar event has ended;
- another non-overlapping event starts soon;
- meaningful transcript exists;
- transcript and speech-like audio are quiet;
- Mac is sleeping or the associated call application terminates.

Supporting signals may shorten a prompt or strengthen a handoff, but they must not override a currently active associated call app.

#### Weak fallback signals

- prolonged transcript quiet;
- amplitude-derived audio quiet;
- `:00` or `:30` common boundaries;
- calendar end without a previously observed call app.

Weak signals ask rather than silently stop, except the explicit 15-minute advanced inactivity fallback. Apply weak fallback to calendar-linked and non-calendar meetings consistently when there is no stronger transition in progress.

### 4. Ending grace as a deferred stop

The grace period is a **deferred stop, not a reversible stop**. `stopRecording()` is irreversible from its first lines — it sets `endTime`, reports the managed session end and clears the managed Deepgram credential, tears down capture, and closes the socket — and `startRecording()` is blocked while `isFinalizingMeeting` is set. No part of the existing stop path runs until grace expires; grace only defers the single eventual call to the existing durable finish transaction.

Mechanics:

1. After the four-second end debounce (with the quiet-audio guardrail above satisfied), enter `endingGrace`: **suspend sending audio without tearing down capture or the socket.**
   - Suspension is an explicit send gate, not `onAudioBuffer = nil`: the system-tap IO proc captures its callback by value at start, so a nil assignment does not silence the system-only path. The gate is checked inside the mic and system buffer paths before any bytes reach `DeepgramService`.
   - The Deepgram socket **stays open** for the whole grace period. The existing 5-second unbilled `KeepAlive` holds an idle socket indefinitely; a deliberate disconnect would both trigger the recording-time reconnect ladder and, on resume, reset multichannel speaker identity and re-run speaker naming. `Keep recording` therefore reopens the send gate on the **same socket** — no reconnect.
   - Suspended audio is dropped before it leaves the machine, which preserves the privacy goal: no post-call speech is transcribed or transmitted.
2. Suppress Miniti's own recovery and inference machinery for the duration of grace, or it will fight the suspension: the system-tap callback-stall watchdog, the silent-stall detector (real post-call silence is exactly its trigger condition), the post-recovery full-capture-restart escalation, the transcript-health reconnect, silence auto-stop, and the smart quiet prompt.
3. Do not generate final insights, clear `currentMeeting`, report managed session completion, fire webhooks/CRM, set `endTime`, or mark the meeting complete yet.
4. Show `Call ended · finishing in 10s` everywhere recording state is represented. **Visibility rule:** if no surface can show the countdown — menu bar item disabled, recording indicator disabled, main window closed — mirror it to a system notification; if notification permission is also missing, degrade the automatic end to an ask-first prompt rather than ending invisibly.
5. Offer `Keep recording` and `End now`.
6. Automatically cancel grace and resume the same meeting on the same socket if the associated call app becomes active again. (No transcript can arrive during grace — sending is suspended — so reactivation is the in-grace cancel signal; the transcript veto guards entry.)
7. At expiry, run the existing durable finish/save/finalization transaction exactly once by calling the normal stop path.
8. **Sleep:** the Mac sleeping during grace ends the deliberation — on wake, an expired grace deadline finalizes immediately without a reactivation window. Add explicit `NSWorkspace` sleep/wake observers (none exist today); a wake also reproduces the exact callback-gap signature the stall watchdog repairs, so the suspension flag must be consulted there too.

If reversible suspension cannot be made safe without disturbing managed-session accounting or transcript ordering, Phase 2 must stop and redesign this boundary rather than continuing to capture throughout a cosmetic countdown.

### 5. Back-to-back calls

Core Audio cannot prove that one Zoom meeting ended and another began if Zoom holds the same microphone stream continuously. This limitation must be explicit.

Use existing calendar context to cover the common case:

- a different event approaching produces a visible handoff decision;
- a strong old-app end followed by a new-app start offers `End & start next`;
- a same-app continuous stream plus an unambiguous non-overlapping calendar boundary remains a cancellable handoff, not a silent split;
- overlapping events or ambiguous calendar matches always ask;
- no browser extension, Zoom integration, Accessibility permission or window-title scraping is included in this programme.

If field evidence later shows same-app continuous calls remain a major failure source, evaluate an optional browser extension as a separate product decision with its own permission and distribution review.

## Recording presence design

The recording state must be obvious even when the main window is closed, covered or on another Space. The menu bar and floating indicator share one AppState-derived presentation model so their wording, countdowns and actions cannot diverge.

### Menu-bar label

While recording:

- use `ColorPalette`'s recording token, never hardcoded `.red`;
- show a compact fixed-width red surface such as `● REC 12:34`;
- use monospaced digits without horizontal jitter;
- keep motion subtle and respect Reduce Motion;
- distinguish normal recording, recovery and ending grace without relying only on colour.

When not recording, preserve the current Miniti identity and useful next-event context without allowing long event names to expand the menu bar excessively.

### Expanded menu-bar content

Use a wider, information-led surface containing:

- current meeting title and timer;
- `Zoom call active`, `call ended`, `in-person/unsupported call`, or equivalent bounded lifecycle status;
- microphone and system-audio health;
- transcription state: live, reconnecting or degraded;
- pending start/end/handoff decision and countdown;
- next calendar event when relevant;
- `Open active meeting` as the primary navigation action;
- native actions for Pause/Resume, End meeting, End & start new, and Keep recording during grace.

Do not show transcript text by default in the menu bar. Do not repeatedly filter the growing `liveSegments` array to derive counts; use its finalized-by-contract count or a cached bounded presentation value.

### Floating recording indicator

Add one macOS non-activating `NSPanel` owned by a small coordinator rather than the main SwiftUI window hierarchy.

Collapsed state:

- recording dot/state icon;
- elapsed timer;
- recognized call-app icon/name when available;
- compact enough not to cover meeting controls.

Expanded state:

- meeting title;
- recording/transcription/audio health;
- supported-call start, end, and handoff questions with the same actions as the main app;
- pending end or handoff countdown;
- Open meeting, Keep recording, End now/End meeting. Pause is omitted until recording has a real pause primitive; the panel must not simulate it with stop/start.

Behaviour and adaptation:

- do not steal keyboard focus from Zoom, Meet, Teams or the user's notes;
- appear auto-expanded and explicitly reorder front when any supported-call, quiet, or calendar prompt arrives, recording starts, or ending grace begins;
- respect a manual collapse until the next meaningful lifecycle transition, rather than reopening on timer ticks;
- make the whole header a clearly indicated expand/collapse target, not only the chevron glyph;
- render actions with the same shared control chrome as Miniti's start/stop/resume controls;
- Open meeting explicitly activates Miniti and recreates the main scene when the previous window was X-closed;
- drag the panel and remember position;
- anchor expansion to the nearest horizontal edge, grow downward, and clamp the whole panel into the visible frame after every resize or display change;
- work on multiple displays and full-screen Spaces;
- hide while idle, after finalization, and when the user disables `Show recording indicator`;
- show for manual recordings as well as detected calls;
- expose complete VoiceOver labels/actions and keyboard reachability where a non-activating panel permits it;
- respect Reduce Motion;
- show no transcript content by default;
- show opt-in incisive-question, monologue, and filler guidance as a short-lived foreground nudge, while using Notification Center when another app is active or the panel is disabled;
- use system surfaces and Miniti design tokens without shadow-heavy floating-card styling.

The panel must not become a second source of action logic. Every button calls the same AppState methods used by the main window, menu bar and notifications.

## Delivery plan

### Phase 0 — signed sandbox feasibility spike, 2–3 engineering days

Build the smallest read-only monitor and test it inside a signed, sandboxed Miniti Debug build.

Matrix:

- macOS 14.2, current macOS 15, and current macOS 26;
- Zoom, Teams, Slack, FaceTime, Webex;
- Google Meet in Chrome, Safari, Edge, Arc and Brave where available;
- built-in mic, AirPods, USB microphone and device switching;
- application mute, hardware mute, waiting room, joining/leaving, app termination;
- Miniti recording and not recording;
- microphone and system-audio permission granted, denied and later restored;
- admin and standard-user accounts on an unmanaged Mac where practical;
- signed notarization-style sandbox entitlements, not an unsandboxed command-line proof.

Measure snapshot accuracy, transition latency, idle CPU, wakeups and error behaviour. Confirm that no new TCC prompt, entitlement, system extension or admin flow appears.

Exit criteria:

- active supported call apps are identified on non-default devices;
- their end transition is observed reliably;
- Miniti/self audio is excluded;
- idle CPU averages below 0.5% on an Apple Silicon test Mac;
- no permission/distribution conclusion in this plan is disproved.

If the public process-object path fails under Miniti's sandbox, stop. Do not fall back to private API, log scraping, camera, Accessibility or a privileged helper without a new explicit product/security decision.

### Phase 1 — lifecycle monitor and pure policy, 4–5 engineering days

- add `CallActivityMonitor` and its target membership;
- add the known-app/helper normalization table;
- add AppState lifecycle state and pure decision functions;
- add start/end debounce, short-session guardrails and reactivation cancellation;
- associate an unambiguous nearby calendar event before recording begins;
- retain existing unsupported/in-person fallback;
- add privacy-safe local reason-code logs and optional allowlisted diagnostics events;
- do not alter finalization yet: surface end candidates in internal/debug UI until the policy is validated.

### Phase 2 — deferred-stop ending grace and durable integration, 3–5 engineering days

- add the send-gate capture suspension without final insight generation;
- suppress the tap watchdogs, transcript-health reconnect, auto-stop and quiet prompt during grace;
- preserve interim transcript and reconnect ordering;
- integrate Keep, End now, timeout and automatic reactivation on the same socket;
- route completion through the existing durable save fence and meeting-scoped finalization;
- **fix the pre-existing exactly-once gaps this path will sit on**: the no-content branch of `stopRecording()` never sets `isFinalizingMeeting`, so a double stop re-runs the whole body including a second managed session-end report; `stopRecording()` has no `guard isRecording`; and markdown auto-export can fire twice (`goHome()` plus the un-scoped call in `generateFinalInsightsAndSave`). An automated end path calls `stopRecording()` programmatically and multiplies exposure to all three;
- verify managed-minute reporting occurs once;
- preserve CRM, webhook, auto-export and deleted-meeting guards;
- ensure stopping or transitioning one meeting cannot write into the next.

### Phase 3 — menu bar and floating recording indicator, 4–5 engineering days

- create the shared recording-presence presentation model;
- upgrade the menu-bar label and expanded content;
- add the non-activating floating panel and coordinator;
- add the independent default-on indicator preference;
- cover multi-display, full-screen Space, display removal, Dock/menu reopening, Settings-window independence, VoiceOver and Reduce Motion;
- route all actions through AppState.

### Phase 4 — settings migration, documentation and beta, approximately one week

- relabel legacy auto-stop controls as advanced fallback in the first lifecycle build;
- dogfood supported calls and back-to-back calendar scenarios for several days;
- review false candidates, automatic cancellations, Keep decisions and orphaned recordings using reason codes only;
- publish updated Smart meetings documentation before default behaviour changes;
- run a staged beta before general release;
- retire calendar auto-stop and simplify inactivity values in the following release only after the detector meets the acceptance bar.

A realistic delivery estimate is approximately three engineering weeks plus one week of beta observation. Do not combine this programme with unrelated audio transcription, insight, CRM or backend refactors.

## Testing contract

### Unit tests

- known helper-to-app bundle normalization;
- self, Miniti tap and loopback exclusion;
- active app survives device UID changes;
- start requires continuous supported-app activity;
- dismissal suppresses repeated start prompts for one uninterrupted call;
- end requires a previously observed associated call;
- end debounce and reactivation cancellation;
- short/empty recording asks rather than automatically ends;
- another call app creates a transition candidate;
- a join-style start adopts the call that appears within the expected-call window, and the window expires back to transition candidates;
- strong active-call state overrides weak quiet/calendar evidence;
- weak fallbacks work for calendar-linked and non-calendar meetings;
- Smart meetings off leaves lifecycle snapshots inert;
- explicit calendar auto-start remains independent;
- legacy inactivity values migrate tolerantly;
- ending grace timeout executes finalization exactly once;
- Keep resumes the same meeting without an insight/save race;
- late callbacks remain meeting-ID/revision scoped.

### Integration and manual tests

- supported app join, mute, unmute, device switch, leave and rejoin;
- browser helper processes and multiple open browser profiles;
- two supported call apps active simultaneously;
- same-app back-to-back calls with and without a calendar transition;
- different-app back-to-back calls;
- unsupported/in-person recording;
- media or music after a call ends;
- Deepgram connected, stalled and disconnected at call end;
- sleep/wake during recording and during ending grace;
- main window visible, closed, minimized and on another Space;
- Settings open while the floating panel or menu action opens the main window;
- multiple displays, display disconnect and full-screen meeting apps;
- menu bar disabled while floating indicator is enabled, and vice versa;
- indicator hidden while lifecycle automation remains enabled;
- microphone/system-audio permissions denied and later restored;
- both shared XCTest bundles, macOS Debug build and iOS simulator Debug build.

## Observability and privacy

Local unified/debug logs may contain only bounded lifecycle state and reason codes, for example:

- `supported_call_started`
- `start_prompt_dismissed`
- `associated_call_missing`
- `end_candidate_cancelled_reactivated`
- `ending_grace_started`
- `ending_grace_kept`
- `ending_grace_completed`
- `fallback_quiet_prompted`

Do not log meeting title, attendees, transcript, raw audio, browser URL, window title, device UID, unknown bundle ID, or screen contents. If Share Diagnostics is enabled, upload only an allowlisted known-app category, OS/app version, elapsed buckets, result and failure code. Unknown bundle IDs remain local and should be hashed or omitted even from local routine logs unless an explicit debug build requires them.

## Acceptance bar

The programme is complete only when:

- supported call starts are recognized within three seconds;
- supported call ends enter grace within five seconds of the app releasing its input stream;
- no camera, Accessibility, screen-content, system-extension, admin-helper or new TCC prompt is introduced;
- normal manual recording and transcription remain unchanged when Smart meetings is off;
- device switching and ordinary mute/unmute do not end meetings;
- call reactivation cancels ending automatically;
- false automatic ends remain below 1% during beta and every automatic end had a previously observed supported call;
- supported different-app and calendar-backed back-to-back meetings separate correctly;
- same-app continuous-microphone limitations are documented and never silently guessed without calendar evidence;
- idle detector CPU remains below the Phase 0 budget;
- recording and ending state are obvious from the menu bar and floating indicator even with the main window closed;
- the floating panel never steals focus unexpectedly or exposes transcript content;
- finalization, managed usage, saves, insights, CRM and webhooks run exactly once;
- the visible settings model is reduced to Smart meetings, explicit calendar auto-start, a default-on recording indicator, and one advanced prolonged-inactivity fallback.

## Non-goals

- camera-on/off detection;
- recording video or inspecting screen pixels;
- Accessibility/UI scripting of Zoom, Teams, Meet or Slack;
- automatic consent chat messages or virtual-camera watermarks;
- a required browser extension;
- perfectly separating same-app calls when the application never releases its microphone and no unambiguous calendar boundary exists;
- changing iOS background recording or Live Activity behaviour;
- changing Deepgram, insight cadence, managed billing, CRM or webhook contracts except for preserving their existing boundaries during the new reversible end state.
