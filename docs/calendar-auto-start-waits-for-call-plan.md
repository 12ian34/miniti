# Calendar auto-start waits for the call (2.11.0)

Field report, 2026-10-05 (Sasha): "miniti still starts recording before the meeting has started. It just starts at the time of the meeting. I thought we fixed this in the latest update."

## What happens today

`checkAutoStart` (`AppState.swift`) runs every 5 s while Google Calendar is connected and **auto-start** is on. 16 s before an eligible event it shows the countdown; at the event's start time `executeAutoStart` records, whether or not anyone has joined the call. An event found already in progress (up to 2 min late, e.g. after launch) starts immediately. Nothing in 2.10.0 changed this; 2.8.0 and 2.10.0 only changed *which* events count as meetings (filters). So the report is accurate and the expectation was never shipped.

Smart meetings already knows when a call is actually live on macOS: `CallActivityMonitor` sees a supported call app (Zoom, Teams, Meet in a browser, Slack, FaceTime, Webex…) holding the microphone, and `CallLifecycleEngine` offers "Meeting detected, take notes" when there is no recording. Auto-start simply does not consult it.

Workaround today, macOS: turn **auto-start** off and keep Smart meetings on. Recording is then offered when the call starts, and the nearby calendar event is linked to it. The downside is one click per meeting, which is exactly what auto-start was meant to remove.

## Design

Auto-start keeps the calendar as the trigger but adds a gate on macOS: **record when the call is live, not when the clock says so.**

### Rule (`AutoStartPolicy.decision`)

Inputs: event start time, whether the event has a conference link, Smart meetings call detection available (macOS only) and the latest call snapshot, now.

- **Event has a link and call detection is available:** arm a *waiting* state from T−5 min to T+10 min. The moment a recognized call app becomes active in that window, start the meeting from the event (same `startMeetingFromEvent`, so title, attendees, prep notes and the join adoption all behave as now). Early joiners therefore record from when they actually join, and a call that starts 7 minutes late records from minute 7, not from minute 0.
- **No call by T+10 min:** do not record. Show one quiet nudge on the floating surface and in-app: "*Weekly sync* hasn't started. Record anyway?" with **Record** and **Skip**. The nudge dismisses itself at the event's end time.
- **Event has no link (in-room or phone):** today's behaviour, countdown and start at T, because there is no call to observe. The countdown banner says so: "starts at 10:00".
- **Call detection unavailable** (browser-only call that macOS cannot distinguish, call monitoring off, or iOS): today's behaviour.
- The 16 s countdown stays for the no-link case only. In the waiting case the banner reads "waiting for your *Weekly sync* call" with **Start now** and **Dismiss**, so a person who wants the old behaviour has it one click away.

### Edge cases

- Call already active at T−5 min (back-to-back in the same app): start immediately when the waiting state arms, the engine already associates the recording with that call.
- User presses **Join** from the reminder or the upcoming list: unchanged, that path starts notes and opens the link at once.
- Two eligible events overlapping: the existing selection order applies; the waiting state is per event and the second cannot arm while a recording runs.
- Smart meetings off but auto-start on: no call detection, so clock-based start, as today. Settings copy explains the dependency.
- iOS: no call detection, so unchanged. The 60 s reminder notification remains the way in.

### Settings and copy

Settings → Calendar → Auto-start gains one line under the toggle on macOS: "Starts when your call connects, not at the scheduled time. Meetings without a link start at their scheduled time." No new toggle: there is no case where someone wants an empty recording of a call that has not started.

Changelog: "auto-start now waits for the call. A calendar meeting with a Zoom, Meet, Teams or Slack link starts recording when the call actually connects, up to 5 minutes early or 10 minutes late, instead of at the scheduled minute. If nobody joins, miniti asks once instead of recording an empty room. Meetings without a link still start on time."

## Tests

- `AutoStartPolicyTests`: pure decisions for every branch above with injected now, snapshot and availability; the T−5/T+10 window edges; link vs no link; detection unavailable; call already active at arm time.
- `CallLifecycleTests`: a waiting-state start adopts the detected call as its association (no "new meeting detected" prompt afterwards).
- Manual: a real Zoom event, join 3 minutes late, confirm recording begins at join and the title is the event's; let one event pass with no call, confirm the single nudge and no recording.

## Status

| Item | Status |
|---|---|
| Plan written | 2026-10-05 |
| `AutoStartPolicy` + tests | done 2026-10-05 (`AppState.autoStartDecision`, `AutoStartPolicyTests`) |
| Waiting state in `checkAutoStart`, banner copy, floating surface | done 2026-10-05 |
| T+10 nudge (Record / Skip) | done 2026-10-05 (`SmartMeetingPrompt.Kind.calendarNoShow`, notification category, menu bar, floating surface) |
| Settings copy, docs (`auto-start-stop.mdx`), changelog, Linux parity issue | done 2026-10-05 (Linux issue miniti-linux#24) |
| Manual check (late join, no-show) | not started |
