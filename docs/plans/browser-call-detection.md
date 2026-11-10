# Browser call detection and calendar start reliability, 3.8.0

Status, 2026-11-09: Mac 3.8.0 build 164 was released on 2026-11-09; iOS build 164 was confirmed live on the App Store on 2026-11-10. Final automated validation and signed-package verification pass. Specialist physical evidence remains unitemised; publication does not turn it into a pass. CD1/CD2 have synthetic regression coverage; the exact Arc incident and physical browser matrix have no itemised verification. See the [release record](../releases/3.8.0.md).

Research findings and proposed implementation sequence: [2026-11-04 investigation](../research/browser-call-detection-2026-11-04.md).

## Evidence and limits

A customer reports repeated Google Meet detection failures in Arc, confirmed by Ian after an initial tentative Dia report. An initial muted join and later speech are reported tentatively; mute details and exact Arc version remain unconfirmed. A supplied screenshot shows the calendar no-show prompt after ten minutes. Ian also reports possible intermittent failures on his own setup; do not assume the same cause.

Original 3.7.0 source evidence, before the local corrections below:
- `Miniti/Services/CallActivityMonitor.swift` reads Core Audio active input processes once per second. Processes without a recognised bundle ID are omitted. Only process-list query failure marks the snapshot unreliable; failures reading individual process properties can disappear as no activity.
- `Miniti/Models/CallLifecyclePolicy.swift`, `CallApplicationDirectory`, lists Chrome, Safari/Technology Preview, Edge, Arc, Brave and Firefox. Arc is explicitly mapped as `company.thebrowser.Browser`. The earlier missing-Dia hypothesis does not explain this incident. Helpers use exact aliases or a known bundle-ID prefix. Browser microphone activity identifies a browser, not Google Meet or participant presence.
- `Miniti/Models/AppState.swift`, `autoStartCallDetectionAvailable`, treats Smart meetings plus a reliable snapshot as detection availability. It does not establish coverage of the browser actually hosting the call, or check snapshot age there.
- `autoStartDecision` waits from T-5 through T+10 for calendar events with conference links. After T+10 it prompts even if activity subsequently appears. The existing tests explicitly pin this late-join behaviour.
- `presentAutoStartNoShowPrompt` claims the meeting has not started and nobody has joined. Neither claim follows from the local sensor.

Read-only production diagnostics were inspected on 2026-11-04. They support successful capture after start on the reported current build, but expose neither browser identity nor calendar decision reasons. They do not establish the root cause or prove detection works. Customer identifiers, meeting titles, raw event data and screenshots remain outside repository documentation. No notification-producing health refresh was run.

## Browser coverage requirement

Ian explicitly requested broad support for mainstream Mac browsers on 2026-11-04. CD1 must cover browser detection generally, not only patch the reported Arc case. The initial acceptance inventory is Safari, Chrome, Edge, Firefox, Arc, Brave, Dia, Opera, Vivaldi and Zen. Verify current Mac builds and actual process identities during implementation; this list is a validation target, not a claim of shipped support. Record any additional mainstream browsers found during that inventory. Stable releases are the baseline; alternate channels and installed web apps need explicit coverage notes rather than assumed prefix compatibility.

Prefer verified owning-application resolution and reusable browser-family handling where public OS evidence supports it, backed by explicit identities and regression fixtures. Do not assume all Chromium, Firefox-derived or WebKit browsers expose identical helpers. Never classify every microphone user as a call. Each browser needs real join, mute/unmute, background, reconnect and leave evidence, with both calendar-linked and non-calendar starts. Start and end detection must be assessed separately.

For every targeted browser, record tested version/OS, observed process ownership, start/end results and remaining limitations. Missing or ambiguous sensor evidence must produce an immediate usable manual path and truthful status, not a silent ten-minute wait or a claim nobody joined. A limitation blocks an unqualified support claim and needs an explicit release disposition; do not silently drop a browser from the selected scope. Browser support applies across tiers. Broad automatic detection remains macOS-specific; iOS must retain accurate platform wording.

## Proposed correction

1. Reproduce Google Meet with Arc on the reported OS/build, then supported browser controls. Verify actual owning/helper bundle identities from local process evidence before adding mappings. Never guess a bundle ID or attribute every unknown mic process to a browser.
2. Distinguish positive recognised activity, no observed activity, unknown/unsupported process identity, stale snapshot and failed/partial sensor reads. A successful enumeration is not proof of browser coverage. Preserve these distinctions through calendar policy and UI.
3. Replace unsupported participant/meeting-status assertions with truthful detection copy, such as “miniti could not detect your call. Record anyway?” The main-window banner already offers Start now and dismissal while waiting. Verify equivalent reachable actions in the floating panel/menu bar, not only the later no-show prompt. Do not silently reinterpret unknown activity as permission to record.
4. Design the calendar fallback explicitly: retain the user's auto-start choice, show an early actionable fallback when evidence is inconclusive, and define late activity after T+10, skipped events, expired events and clock-fallback transitions. Confirm whether an opt-in calendar-time start mode is wanted for callers whose browser cannot be detected. Do not turn it on globally as a hidden workaround.
5. Keep call-end evidence conservative when broadening start coverage. Mute, helper restart, mic-device change and transient missing readings must not trigger an incorrect automatic end. Browser input alone must not claim that the specific calendar meeting is active.
6. Add bounded local diagnostic reason codes for sensor coverage and start decisions. Reuse existing diagnostic consent and allowlists if exported; no URLs, tab titles, calendar titles, arbitrary process inventory or customer content. Do not add continuous network telemetry to the polling loop.

## Delivery and acceptance

CD1 is a release-required macOS reliability package, integrated with MC1 and the existing recording/metering owner. No new recording coordinator or duplicated start/save path. No billing-tier dependency is expected in the detector; Pro status does not establish coverage.

Automated: test actual monitor interpretation with injectable process reads, verified helper identities, unknown processes, input-read failures, stale snapshots, browser mute/unmute, process restart, self-exclusion and unrelated dictation. Exercise real calendar coordinator transitions, early/on-time/late join, detection failure after the two-minute clock grace, Skip suppression, back-to-back meetings, simultaneous manual/automatic start and Stop. Pin save/charge once. Update existing T+10 tests only after the new policy is explicit.

Physical release evidence: Google Meet across the browser coverage inventory above, beginning with Arc reproduction; join muted, speak after joining, never speak, switch audio device, background the browser, lose/rejoin the call, and leave it. Include unrelated browser microphone use and an unattended calendar event as negative controls. Record app/browser/OS versions and observed owning process identities privately. Demonstrate the reported missed start is fixed before calling CD1 complete; synthetic tests alone do not prove OS/browser coverage.

Performance: keep one off-main polling owner with bounded per-process work, no audio-content analysis added to the poll, no per-tick remote requests and no repeated prompt storms. Compare polling cost and start latency on the same hardware with 3.7.0. Measurements pending.

Security and compatibility: preserve existing user choices, capture permissions, account/start generation fences and private-mode export rules. Detection stays local. New diagnostic fields require compatible backend allowlists before new producers; app-only detection changes need no server deployment. Unknown sensors must not weaken automatic stop policy. Rollback disables added automatic transitions without losing saved meetings or altering preferences.

## Surface register

| Surface | Action / owner / timing |
|---|---|
| `Miniti/Models/CallLifecyclePolicy.swift`, `Miniti/Services/CallActivityMonitor.swift`, `Miniti/Models/AppState.swift` | CD1 implementation and regression ownership after policy design |
| `Miniti/Views/RecordingIndicatorPanel.swift`, automation Settings and notification prompts | CD1 truthful coverage/waiting copy; native actions, keyboard, VoiceOver, Reduce Motion and long text verification |
| `docs/reference/recording-lifecycle.md`, `docs/reference/settings.md` | CD1 update actual browser/fallback contract after implementation |
| `docs/releases/3.8.0.md`, `docs/releases/3.8.0-planning-audit.md`, `docs/roadmap.md`, `AGENTS.md` | CD1 scope now; measured/runtime evidence later |
| Public Smart meetings/calendar docs, website duplicates and roadmap | CD1 inventory exact page paths in expanded audit; publish supported browser claims only after physical verification |
| Changelog/store notes/screenshots | CD1 Mac-scoped release bullet after implementation; capture truthful waiting/unsupported states with synthetic data; iOS copy must not claim this Mac fix |
| Linux `PLAN.md` | Track parity implications before shared contract or user-visible implementation; Linux release independent |

Remaining gates: exact Arc version/process attribution and physical reproduction, the browser matrix and signed-build measurements. The local implementation below settles fallback: keep explicit clock mode unchanged, offer manual Start now when detection is inconclusive, and never silently switch a detection-enabled event to clock start. Diagnostics remain bounded local sensor-health reasons without a new upload schema; the planning audit owns the public surface inventory. Planning link checks alone do not validate detection. Granola comparison is qualified in the research note: current help docs describe microphone-based prompts; customer-reported success does not establish which signal/path handled this call.

## Manual-start association and duplicate prompts (CD2)

Selected for 3.8.0 planning on 2026-11-04. Two customer reports: starting a meeting manually before joining a call can still produce a start-call notification; another user sees End and start next while already recording the intended meeting. Reported wording is approximate. Neither exact trigger is reproduced. CD2 is separate from browser recognition: correct detection must associate with an existing recording rather than propose another one.

Source leads: `CallLifecyclePolicy.noteRecordingStarted` allows an unassociated plain manual start to adopt a detected call for 120 seconds; explicit expected calls have a 300-second window. After expiry, matured activity can become an offerTransition. `checkSmartCalendarTransition` excludes the current calendarEventId but a plain manual recording may have no calendar link, so its own upcoming event can be offered as next. `handleCallLifecycleEvent(.offerStartPrompt)` already rejects prompts with a current meeting; therefore the duplicate-start report also needs stale visible/delivered notifications, start-in-flight ordering, calendar reminders and action routing investigated. These are plausible paths, not confirmed incident diagnoses.

Required contract:

- A manual start establishes the active recording as authoritative immediately, including preparation/start-in-flight. Clear or update obsolete start reminders on every surface and invalidate their delayed actions by meeting/generation identity. A stale notification click cannot create another recording or split the current one.
- When the intended call becomes detectable later, associate it with the existing recording where evidence is unambiguous. Do not create, stop or split a meeting merely because detection was late, an arbitrary adoption timer expired, the microphone was unmuted or a helper restarted.
- Reconcile explicit Join/calendar intent with a manual recording using stable event identity and the existing start owner. Nearby time, matching title or same browser alone cannot prove identity. With multiple possible events/calls, offer a non-destructive association choice and continue recording; do not label the user's current call as a new one by assumption.
- A handoff prompt requires evidence of a genuinely distinct meeting. Preserve real next-meeting reminders and explicit user handoff. Do not suppress all automation for the rest of a manual session or extend blind first-call adoption indefinitely.
- Linking metadata must preserve recording UUID, captured audio/transcript, manual title/notes, usage, exports and Cloud/Local choice. Audit any metadata-triggered sync/export side effects. End/start actions revalidate current recording and event before executing. Keep live, floating, menu-bar and system-notification state consistent.

Acceptance: use the real coordinator and notification action routes with injected time. Manual start then call arrival at 30 seconds, 119/121 seconds, 299/301 seconds and ten minutes; muted join then unmute; delayed start/grant callbacks; pending reminders before manual start; notifications delivered/clicked after start; manual start near the intended calendar event with no event ID; overlapping events; browser helper/route changes; reconnect; actual back-to-back calls in one browser; Stop/new meeting while old actions remain queued. Assert one recording ID, no same-meeting handoff, no duplicate save/usage/export, and preserved genuine next-meeting actions. Physically verify both reported journeys in the signed Mac app with floating/system notifications and Arc/Meet; do not infer a pass from pure policy tests.

CD2 integrates with CD1 before MC1 completion changes. Uses existing AppState/call lifecycle/calendar/notification owners. No new API is assumed; any changed contract requires normal cross-client review. Bounded local decision diagnostics must omit meeting titles and customer content. Validate snapshot processing and notification churn remain bounded. Update recording-lifecycle/settings documentation and actual affected screenshots after implementation. The implementation contract below now defines the association rules; the release audit inventories public assets. Physical reproduction and the browser matrix remain release gates.


## Local implementation and deliberate limits (2026-11-04)

The monitor reads input/output separately, resolves the PID's owning application including embedded helper bundles, and does not map generic WebKit processes to Safari. Dia, Opera, Vivaldi and Zen bundle IDs are verified against their primary Homebrew cask sources; this is identity evidence, not a call-detection pass. The Xcode SDK Core Audio header confirms that the device-list property selects input/output via scope. Enumeration is capped at 2,048 process objects, owner traversal at 16 path components, one utility-priority poll per second, no PID cache or network telemetry. Cancelled polling generations cannot publish after restart.

Snapshots distinguish complete, partial, unavailable and unidentified-input readings; AppState rejects snapshots older than five seconds. Positive reliable input can start a single eligible calendar event until its actual end, including after T+10. Missing detection never silently switches a detection-enabled event to a clock start. Existing explicit clock mode remains unchanged. Early manual fallback is reachable from Home, the floating panel and menu bar. Skip, event cancellation/expiry and simultaneous start guards remain authoritative.

A single late call within the existing adoption window joins the recording. After that window, an unassociated recording gets a non-destructive association choice. Linking an unlinked calendar event preserves its title, notes, attendees, Cloud/Local setting and recording ID. Already-associated calls retain explicit next-meeting handoff. Notification scheduling and actions carry recording/prompt generations, including reminder and ending-grace cancellation races.

Browser output can support an already associated muted call but cannot start a recording. Losing browser input and output asks whether to finish; it does not prove the tab left its call. Browser microphone use cannot identify a website, participant or calendar event. A fully muted/no-audio join may require Start now. Native confirmed-call ending retains its existing grace/Keep recording path. No continuous diagnostic upload or new consent field was introduced; fixed sensor-health reasons stay in the existing local debug log.

Synthetic evidence covers owner attribution, unknown/partial reads, stale snapshots, mute/output, 120/300-second boundaries, late positives, expired events, explicit clock mode, manual/calendar association and stale notifications. Physical Arc/Meet reproduction, the ten-browser matrix, signed-build process ownership and comparative polling measurements remain pending user QA; do not advertise that matrix as verified support.

## Shared WebKit follow-up, 2026-11-05

When owner attribution fails for a microphone process inside the shared WebKit framework, retain generic WebKit browser input evidence. Do not assert Safari identity or inspect browser content. This supports weak browser start evidence and conservative end handling; playback alone is insufficient. The real Safari muted-join/talking/end scenario remains an uncompleted release gate. See the second-review release disposition.

## Continuing-call decision, confirmed 2026-11-06

A new calendar event does not automatically split the active recording, even with both calendar automation switches enabled and quiet audio. The next-meeting prompt stays actionable but has no automatic handoff countdown. Explicit End and start next and independently detected call completion retain their existing owners. This removes the quiet-calendar countdown path; it does not change existing silence preferences or claim a muted browser can always be detected. The actual coordinator regression covers an expired previous event, imminent next event and no recent activity.
