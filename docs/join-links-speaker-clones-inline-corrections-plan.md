# Join links, one-person speaker clones, and inline dictionary corrections

Status: **v2.7.0 shipped on macOS 2026-09-10 (build 118, Sparkle live); iOS 2.7.0 build 118 submitted to App Review the same day.** Client work for A, B, and C is in the working tree on `main`, uncommitted, mixed with the version bump to 2.7.0 (build 118). Cursor implemented the first pass; Ian's field test on 2026-09-10 found the join surfaces and the correction pill broken; a second pass (Fable, 2026-09-10) reviewed the whole diff against this plan and fixed what is listed below. Do not release until Ian has run the manual matrix and approved.

Linux tracking: [#1](https://github.com/12ian34/miniti-linux/issues/1) join, [#2](https://github.com/12ian34/miniti-linux/issues/2) speaker gating, [#3](https://github.com/12ian34/miniti-linux/issues/3) corrections.

---

## Handoff, second pass (2026-09-10)

### What Ian has to do

1. **`miniti-api` is deployed** (commit `def9ef5` on `main`, pushed 2026-09-10): `lib/google.ts` extracts Meet links pasted into a description or location (`meet.google.com/xxx-xxxx-xxx`, `meet.google.com/lookup/...`), and `lib/insights.test.ts` pins the `speaker_names` prompt to the 1000+ mic-range wording. Events created with Calendar's own "Add Google Meet" button worked before through `hangoutLink`; pasted Meet URLs work after this deploy.
2. **Run the manual matrix** below on the built app, not from Xcode's debug run alone.
3. **Keychain prompt** (`com.miniti.device-auth`): choose Always Allow once per signing identity. Not a 2.7.0 bug, nothing to fix.

### Fixed in the second pass

**Root cause of "no join button" (found on Ian's second field test).** `miniti-api` serializes calendar events in camelCase (`meetLink`, `conferenceUrl`, `isAllDay`, `displayName`, `responseStatus`), which the Linux client reads correctly. The Apple client decoded snake_case for those keys, with a default for every field, so links were always nil, attendee display names were always nil (the sheet showed emails only), response statuses were always "needsAction", and speaker naming never received calendar hints. `MinitiAPIService.CalendarEvent`, `CalendarAttendee`, and `CalendarOrganizer` now decode camelCase first with a snake_case fallback for the screenshot fixture. The Meet-in-description regex on the backend was a real but secondary gap.

**A. Join**

- The browser opened even when the meeting start was refused (terms, missing key, plan limit, still finalizing), and the one-shot guard was burned before the open succeeded. `startMeetingFromEvent` now returns whether the start was accepted; `joinAndStartMeeting` opens only on success; `openMeetingLink` records the event only after a successful open, so a failed launch can be retried from any surface.
- Reminder actions carry `.foreground`: a background-delivered action on iOS could not reliably open a URL or start capture.
- A reminder tapped on a cold launch, before the first calendar refresh, is now held for that one refresh instead of being dropped.
- Join button added to the floating recording window ("join call" while a linked meeting records, "join next" on the calendar handoff prompt). The meeting header's tiny arrow became a labelled "join call" control. iOS join button colour routed through `ColorPalette`.
- Calendar refresh logs how many events carried a join link and how many carried raw link fields, so the next field report can tell an API gap from a client gap.

**B. Speakers**

- Promotion evidence is written back from finals only. Cumulative interims replay the same words on every message, so a 4-word run cleared the strict 12-word bar after four interims.
- One promoted clone could flip the environment to hybrid, which set the policy back to standard and withdrew "You": the exact case B2 and B3 protect. Hybrid now needs 20 s of speech from non-primary mic IDs (`hybridSecondaryMicSpeechSeconds`).
- Call-app and calendar context are evaluated at meeting start, so a calendar-linked call with an active call app is strict from the first response, not after the first system final.
- The persisted environment is reconstructed on resume, so live and history no longer disagree about "You" after a relaunch.
- The end-of-meeting naming pass ran before final insights and delayed the summary by one model request. It now runs concurrently, fenced by meeting ID.
- The 1:1 calendar shortcut still sent the network request afterwards; it now returns when nothing is left to name.

**C. Corrections**

- Pill and popover: the anchor rect was converted with `scrollView.convert(_, from: nil)`, which expects window coordinates, from a screen-coordinate `firstRect`, in an unflipped AppKit space. The popover presented off-view, `correctingHeardText` stayed set with nothing to dismiss it, and the pill's `== nil` condition hid it for good. The selection state no longer carries geometry; the popover anchors on the pill; the pill stays mounted while editing; a saved correction collapses the native selection so the pill does not reappear offering to correct the corrected word. The right-click item stays as a secondary path, lowercased to match.
- `snappedHeardText` enumerated words from offset 0 of the whole document on every selection change (a hot-path violation on a long transcript); it now scans a window of 80 characters either side of the selection and rejects selections that cross a paragraph.
- Regex template injection: a replacement containing `$1` or `\` corrupted the output; templates are escaped. Non-matching pairs no longer allocate.
- Re-correcting an already stored word was silently dropped (first-wins dedupe) while the UI reported success; `upsertCorrection` replaces, and reports `.invalid` / `.full` so Settings can show a message. Colons are stripped because Deepgram splits `replace=find:replacement` on the colon.
- Saved-meeting corrections take an undo snapshot like trim.

**Third pass (2026-09-11, Sasha's report "got the UX but the text did not change", corrected after the call ended).** Two real gaps: a capitals-only pair such as "lightdash" → "Lightdash" was rejected as an identity pair (`normalizedCorrections` compared case-insensitively) and every editor closed silently on a rejected save, so the most common name fix looked like a no-op. `normalizedCorrections` now rejects only an exact identity; `saveDictionaryCorrection` / `applyDictionaryCorrection` return a `DictionaryCorrectionOutcome` and the live, iOS, and saved-meeting editors show its message (rejected pair, full dictionary, or saved-but-nothing-matched) instead of closing. A retroactive rewrite made after Stop is now persisted immediately (`saveCurrentMeetingIfNeeded`), so the saved meeting and the minutes re-exported at Home carry it even if the app quits from the stopped screen. Still to confirm with Sasha's debug log: the exact word he corrected.

### Known gaps left open

- Reconnect still mints new mic IDs once two or more exist (`SpeakerIdentityState`). With first-word gating clones are rare, so this is much less visible; a voice-matched reconnect is out of scope.
- No unit test asserts `keyterm=`/`replace=` order on the built URL (the URL is built inline in `connect`); `deepgramReplaceItems` is tested.
- No test covers the interim write-back rule or the policy transition in `evaluateEnvironmentInference` end to end.
- iOS: no test for the long-press chip flow.

### Manual matrix before release

Join, after the 2.7.1 fix: press Join on a Meet reminder, let the browser join, confirm the floating surface never shows "New meeting detected" for that call, then hang up and confirm the normal ending grace appears for it.

Join: (a) event with Calendar's Add Google Meet, (b) `https://meet.google.com/...` pasted in the description only (needs the API deploy), (c) Zoom URL in the description. Each: reminder body tap, reminder action, countdown "join", upcoming sheet, header "join call", floating window "join call", handoff "join next". Confirm one tab per start and that "start now" never opens a tab.

Speakers: solo Meet call on headphones; solo Meet call on laptop speakers; BBC World Service stream; two people in a room with no call; hybrid with two in the room. Check labels, "You" placement, ordinals, and names live and after a forced reconnect; watch the DebugLogger lines "Environment inference" and "Mic speaker promotion policy".

Corrections: on a 60+ minute BBC transcript, double-click a word, click the pill, save with "fix earlier mentions", confirm earlier and later mentions change with no blank gap and no scroll jump; resize the pane; ⌘⇧D; select another word and repeat; Reduce Motion on; finish, confirm history and markdown carry the fix, start a new meeting and confirm Deepgram hears the term.

---

## For the implementing agent (original)

- Read [AGENTS.md](../AGENTS.md), then the "Performance / hot-path rules (critical)" section of [patterns.md](patterns.md), then this document in full before writing code. Section C in particular lists what must not change in the live transcript layer; that layer has had three separate "large blank gap" regressions and one multi-gigabyte layout loop, all recorded in the changelog and in patterns.md.
- Work the sections in order A, B, C as separate commits or PRs. Each section has a regression contract and a test list; do not start the next section until the previous one passes both test bundles (`fastlane mac test` and `fastlane ios test`, see [testing.md](testing.md)).
- File references are `path:line` as of 2026-09-09 on `main` at commit 96dc3e2. Re-grep before editing; the files are large and lines drift.
- Changelog for 2.7.0 is already drafted under Unreleased; do not invent a release. Update bullets only if user-facing behaviour changes.
- Update the focused docs in the same change: [patterns.md](patterns.md) for new hot-path rules, [automatic-in-room-diarization-plan.md](automatic-in-room-diarization-plan.md) for the B3 amendment, [architecture.md](architecture.md) for new files, [roadmap.md](roadmap.md) to record completion.
- The three open questions at the end are decisions for Ian. Build under the stated defaults unless he answers otherwise.

## The three problems

| # | What the user saw | Verified root cause |
| --- | --- | --- |
| A | The "meeting in 1 minute" notification does not open the Google Meet / Zoom link, so the call and miniti have to be started separately. | The backend already returns `meet_link` and `conference_url` (Meet, Zoom, Teams, Webex, from conference data, description, and location), and `MinitiAPIService.CalendarEvent` decodes both. The only consumer collapses them to a Bool for environment inference. The reminder notification has no category, no actions, and no event ID, and a body tap is ignored by both notification delegates. |
| B | One person talking into one mic became several speakers (S1, S5, S5), each needing "this is me". Nobody got a name automatically. | Mic diarization is unconditional (shipped in 2.5.0 for shared-mic rooms). `segmentBySpeaker` gates only mid-response speaker switches; the first word of every response is accepted and confirmed with no evidence, so streaming diarizer churn mints 1001, 1002. Once two mic IDs exist, reconnects mint more (1003, 1004) and the implicit "You" is withdrawn for everyone. Naming needs literal evidence tied to the exact ID (self-introduction, or a name spoken in an adjacent segment); clones split that evidence, there is no end-of-meeting naming pass, and the user's own name is not known anywhere. |
| C | Team and project words are transcribed wrong, and fixing that means going to Settings later instead of correcting from the live transcript. | The personal dictionary is a keyterm list applied only at WebSocket connect time. There is no correction (heard, correct) pair concept, no local find/replace, no selection callback or segment mapping on the macOS live pane, and no context menu. `markTranscriptEdited()` wipes every generated insight, which is far too destructive for a one-word fix. |

Ship as three independent changes in the order A, B, C. A is small and low risk. B removes the most pain. C is the largest UI change. Each has its own regression contract below and can release on its own.

Out of scope, deliberately: connecting to Google Meet itself (a bot, the Meet API, or scraping the Meet tab). Granola does not do this either. The call-lifecycle contract forbids automating meeting-app UI, and the calendar plus transcript already carry the information we need.

## A. Join the call from the reminder

### Current behaviour

- `CalendarEvent` (`Miniti/Services/MinitiAPIService.swift:528-588`) carries `meetLink` and `conferenceUrl`. `recordEnvironmentEvidence` (`Miniti/Models/AppState.swift:4427`) is the only reader.
- The 1-minute reminder (`scheduleMeetingRemindersIfEnabled`, `AppState.swift:9930`) posts a plain notification: no category, no actions, no `userInfo`. Both delegates (`Miniti/MinitiApp.swift:261`, `MinitiMobile/MinitiApp_iOS.swift:20`) ignore `UNNotificationDefaultActionIdentifier`, so a tap only raises the window on macOS.
- The auto-start countdown banner, the upcoming-events sheet, the iOS event row, and the smart calendar handoff all terminate in `startMeetingFromEvent` (`AppState.swift:8397`) or `endAndStartCalendarMeeting` (`AppState.swift:5450`). Neither touches the link.
- No join concept exists anywhere; URL opening patterns already exist at `AppState.swift:8825-8850` (cross-platform) and `docsCitationLinkURL` (`Miniti/Views/InsightsView.swift:1240`, scheme allowlist).

### Design

1. `CalendarEvent.joinURL: URL?` computed property: prefer `conferenceUrl`, then `meetLink`, trimmed, `https` only (the value is third-party data passing through the backend, so keep the allowlist). Rewrite the environment-evidence reader to `event.joinURL != nil` so its semantics do not change.
2. `AppState.openMeetingLink(for event:) -> Bool`, the existing `#if os(macOS)` NSWorkspace / `#else` UIApplication shape. One-shot per event per meeting start via an `openedJoinLinkEventIDs` set that is cleared with the other per-meeting state, so two surfaces cannot open two tabs. Logs to DebugLogger, never fails the meeting start.
3. `AppState.joinAndStartMeeting(from event:)`: call `startMeetingFromEvent(event)` first, then open the link. Starting is synchronous state setup and the transcription connect is asynchronous, so the recording is already live when the browser takes focus. Calendar context stays attached before transcription connects, as the smart-meetings contract requires.
4. Surfaces, each only on an explicit user action:
   - Reminder notification: give it a category with two actions, "join and take notes" when `joinURL` exists (otherwise "take notes") and "not now". Put `eventID` in `userInfo`. Make the default body tap behave like the primary action on both platforms; this is the exact Granola behaviour the user asked for. Register the category inside the single `setNotificationCategories` call at `AppState.swift:9652`, which clobbers anything not in the set.
   - Auto-start countdown banner (`Miniti/Views/MeetingView.swift:691`, `MinitiMobile/Views/MeetingView_iOS.swift:1686`): add a "join" button next to the existing "start now" when a link exists. "start now" is unchanged. Countdown expiry (`executeAutoStart`) never opens a link: it runs without user interaction and the floating-surface contract promises no focus stealing.
   - Upcoming events sheet and iOS event row: add "join and take notes" beside the existing "take notes" when a link exists.
   - Smart calendar handoff while recording: the in-app banner gains a "join next" variant. The notification keeps its two existing actions (the contract limits visible buttons); the floating panel stays as is in the first pass.
   - Live header for a calendar-linked recording: a small link button so the user can rejoin after a drop. Reads `selectedCalendarEvent`, no persistence needed.
5. iOS: opening from a notification action works from the background; Meet and Zoom universal links open the native apps. No `LSApplicationQueriesSchemes` needed for `https` links.
6. Optional later: persist the join URL on `Meeting` (optional String, lightweight migration) so history, webhooks, and CRM notes can carry it.

No new setting. The link opens only when the user clicks something that names joining.

**Amendment (2026-09-10):** Floating panel is **in scope** after Ian’s field test. Paste-in-description Google Meet URLs must be extracted server-side (`meet.google.com` missing from `CONFERENCE_URL_REGEXES`).

### Regression contract

- `startMeetingFromEvent`, `executeAutoStart`, and `endAndStartCalendarMeeting` keep their behaviour; the timer paths never open a browser.
- Smart meetings off leaves every existing prompt and auto-start result unchanged.
- The existing smart-meeting notification categories and action IDs stay registered.
- `calendarEventHasConferenceURL` keeps the semantics pinned by `MeetingModelTests` (a URL alone stays `.unknown`).
- One event never opens more than one tab per meeting start.
- The call that opens after Join is the meeting's own call. The lifecycle engine adopts the first recognized call that appears within 5 minutes of a join-style start (calendar event with a conference link, or a join link opened) instead of raising "New meeting detected. End the current meeting and start a new one?". Reported by Sasha on macOS 2.7.0, fixed 2026-09-11; rule and tests in `CallLifecyclePolicy.swift` / `CallLifecycleTests.swift`, contract in the call-lifecycle plan.

### Tests

- `joinURL`: prefers `conference_url`, falls back to `meet_link`, trims, rejects non-https and empty strings. Extend `makeCalendarEvent` in `MinitiTests/AppStateComputationTests.swift:2392` with both fields.
- Category registration includes the reminder category and both existing smart-meeting categories.
- Notification routing: reminder action and default tap map to `joinAndStartMeeting`; "not now" inserts into `dismissedAutoStartEventIDs`.
- One-shot guard: second call for the same event returns false without opening.
- Manual: real Meet and Zoom events, headphones and speakers, macOS and iOS, notification delivered while the app is closed on macOS.

## B. One person, one speaker, and names that appear

### Verified mechanics

- `segmentBySpeaker` (`Miniti/Services/DeepgramService.swift:924`) sets `currentSpeaker = words[0].speaker` without any gate; the promotion thresholds (6 words, 1.5 s, avg confidence 0.65) and switch thresholds (4 words, 0.85 s, 0.58) apply only to mid-response changes. `processTranscriptJSON` (`DeepgramService.swift:815-819`) then confirms every emitted speaker on a final. Result: any final whose first word carries a new diarizer ID creates and confirms a new mic speaker.
- `micPrimaryPrivileged` (`DeepgramService.swift:988-997`) exempts 1000 from confidence checks only while it is the sole mic speaker, so the first spurious clone makes later splits easier.
- `SpeakerIdentityState` (`DeepgramService.swift:229-296`) maps the first mic speaker of a new socket back to 1000 only while the meeting has seen at most one mic speaker; afterwards every reconnect mints fresh IDs. That is where S5 comes from.
- `liveImplicitSelfAllowed` (`AppState.swift:4381`) and `Meeting.implicitSelfAllowed` return false as soon as two mic IDs exist, withdrawing "You" from everyone, including the primary.
- `MeetingEnvironmentInferenceEngine` (`Miniti/Models/CallLifecyclePolicy.swift:407`) already produces `remoteLikely` from an associated call app or system speech with call context, and it is persisted on `Meeting.inferredEnvironmentRaw`. Today it is diagnostic only.
- Naming runs only from the 5 s cadence loop (`AppState.swift:3533`) after 8 then every 40 segments, at least 120 s apart. There is no pass at finalization. `speakerNameHasTranscriptEvidence` (`AppState.swift:5087`) needs a self-introduction by that ID or a name mention by a different speaker in the immediately adjacent segment. Calendar attendees are hints only, and the connected user's own display name is filtered out and never stored. The managed `speaker_names` prompt in `miniti-api` already describes the 1000+ mic range (aligned with BYOK); a regression assertion guards against regressing to "1000 is the user".

### Design

B1. Gate the first speaker of a response. Add `lastCommittedSpeakerBySource: [TranscriptSource: Int]` to `SegmentationState`. When a response starts with a speaker that is neither confirmed nor the privileged primary mic, treat it as a candidate switch away from the last committed speaker on that source: accrue `PendingSpeakerEvidence` exactly as mid-response switches do, promote only when the existing thresholds pass, otherwise fold the words into the last committed speaker. The very first response on a source (no last speaker) is accepted as today. This applies to the system channel too and removes phantom remote speakers for free. Cost: unchanged, one pass over the words.

B2. Environment-aware promotion strictness. Introduce `MicSpeakerPromotionPolicy` with two levels. `standard` is today's thresholds. `strict` requires roughly 12 words, 4 s, and average speaker confidence 0.85 (the roadmap P1.3 starting threshold) accumulated across responses before an additional mic speaker (1001+) is promoted. `AppState.evaluateEnvironmentInference` pushes `strict` to `DeepgramService` when the inferred environment becomes `remoteLikely`, and `standard` for `unknown`, `inRoomLikely`, and `hybridLikely`. Policy updates happen only on transitions, which are rare. The trade-off is explicit: on a hybrid call the second in-room person needs a few sentences before they split, and those first words attach to the primary speaker. In a room with no call context nothing changes. Pending evidence already persists across responses, so a real second voice does get promoted.

B3. Keep "You" on the primary mic speaker in remote-likely meetings. Change both implicit-self rules to: dual-source capture, and either at most one mic speaker or inferred environment `remoteLikely`. Secondary mic IDs then render "Speaker 2 (mic)" instead of removing "You" from the primary. The diarization plan's "no assumption that the first mic speaker is the user" stays in force for `unknown`, `inRoomLikely`, and `hybridLikely`; amend that document to say so. Route this through one shared resolver rather than editing the seven replicated `[micSpeakerID]` sites the plan lists; verify `TrainingMetrics`, `CoachingExampleExtractor`, the legend, and colour helpers all consume `effectiveLiveSelfSpeakerIDs` / `effectiveSelfSpeakerIDs` before shipping.

B4. One-tap consolidation. In `RenameSpeakerView` (`Miniti/Views/TranscriptView.swift:955`, plus history and iOS call sites) show "mark all mic speakers as me" when more than one mic ID exists. It marks every ID in `liveMicSpeakerIDs` (or the saved meeting's mic IDs) as self in one action. Display grouping already collapses self IDs, so no segment rewrite is needed.

B5. Naming improvements.
- End-of-meeting pass: in the finalization pipeline, if automatic naming is on and any non-self speaker with meaningful speech is still unnamed, run `updateSpeakerNamesInBackground` once with the full transcript. Isolate by meeting ID like every other late callback. One `gpt-5-mini` request per meeting at most.
- Calendar-backed evidence window: for names that match a calendar attendee, accept a mention by a different speaker within three segments of a segment by the candidate ID, not only the adjacent one. Free-form names keep the strict adjacent rule so third-party mentions do not misname anyone. Add negative tests for "did Sasha send the doc?" style mentions.
- One-to-one shortcut, local and free: when the calendar has exactly one non-self attendee with a display name and exactly one confirmed system-channel speaker with at least 5 segments, name that speaker after the attendee without a request. Never applies to mic IDs. User overrides win, as today.
- Fix the managed `speaker_names` prompt in `miniti-api` so it describes the 1000+ mic range instead of "1000 is the user". **Done** (already on `main`; regression assertion added). Backend deploy is only needed if production still runs an older prompt.
- Verify the cadence loop: earlier blocks use `continue` (`AppState.swift:3510`, `:3520`), which skips the naming block on that tick. If it can starve naming, evaluate naming before those blocks.
- Optional later: store the calendar self attendee's display name so exports can say the user's name instead of "You".

### Regression contract

- Shared-mic rooms still split: fixtures with two or three mic speakers and no call context must produce the same speakers as today under `standard` policy.
- Existing reconnect identity tests (`AppStateComputationTests.swift:697-760`) and mic echo tests keep passing.
- Explicit marks and overrides always beat inferred names and implicit defaults.
- No naming request waits on identity resolution; insights are never blocked.
- Hot path stays O(words) per response, no filtering of published arrays.

### Validation

Unit: first-word gating (new speaker folded, then promoted after evidence), strict-policy thresholds, policy transitions, implicit "You" table (topology x environment x mic count), one-tap self marking, evidence window with positive and negative cases, one-to-one shortcut, finalization pass isolation.

Manual matrix, each checked live and after a forced reconnect: solo Google Meet call with headphones; solo Meet call on laptop speakers (playback bleed); BBC World Service stream (many remote voices); two people in a room, no call; hybrid call with two in the room. Record speaker ordinals, "You" placement, and which names appear and when.

## C. Correct a word from the live transcript

### Current behaviour

- Terms live in UserDefaults `personalDictionaryTerms.v1` (`DeepgramService.swift:98-193`), merged with system and session terms, capped at 100, and sent as repeated `keyterm` query items at connect (`DeepgramService.swift:551`). Deepgram's `replace` parameter is unused.
- Nova-3 keyterms and `replace` are fixed for the life of a socket. Only Flux supports mid-stream updates. The socket connects directly to Deepgram with a backend-minted grant, so the backend never sees these parameters.
- The macOS live pane (`Miniti/Views/LiveTranscriptTextPaneMac.swift`) is one native `NSScrollView` plus one selectable TextKit 2 `NSTextView` owned by a `Coordinator`. It has no delegate, no context menu, and no selection callback. `Coordinator.finalizedLength` is the boundary between finalized and interim text. Speaker turns are merged per display speaker and segment identity is dropped in `mergeTurns` (`SelectableTextView.swift:730`); the saved-transcript path keeps a per-segment mapping (`TranscriptRenderModel`, `SelectableTextView.swift:637`), the live path deliberately does not.
- Trim is the only transcript edit and goes through `applyTranscriptTrim` (`AppState.swift:5866`) and `markTranscriptEdited` (`Meeting.swift:474`), which clears every generated insight.

### The live transcript layer: what this feature must not touch

The layer is regression-backed and has bitten before. From patterns.md, the changelog, and the 2026-08-16 audit:

- One native `NSScrollView` plus one `NSTextView`, not self-sized inside a SwiftUI scroller. The "large blank gap before the newest line" regression was fixed three times (changelog v1.23.1, v2.0.2, v2.0.4) and came from SwiftUI sizing the native text view. Do not wrap the pane in anything that measures or constrains its height, and do not add overlays that participate in its layout.
- No per-row `.textSelection(.enabled)` on the macOS live path: each row creates a SwiftUI `SelectionOverlay`, and resizing a long transcript loops in `SelectionOverlay.updateNSView`, consumes gigabytes, and hangs the main thread.
- Interim updates never rebuild finalized content. Tail appends mutate only the new suffix (`TranscriptView.rebuildSegmentCaches`, the `canAppend` branch). Everything else goes through `rebuildAllSegments`, which computes a UTF-16 common prefix and suffix snapped to whole paragraphs and applies one `SelectableTextMutation`; speaker-name, self-ID, mic-speaker, and interface-scale changes force a full replacement. Follow-to-bottom listens to `didLiveScrollNotification`, so programmatic scrolls never disable follow.
- `liveSegments` is assigned atomically, once, and holds finalized non-empty segments only. Never `filter` it on a per-final hot path.
- The audit's F10.1 finding: `TranscriptView` classifies an update as append-only from count and endpoint equality. Any change that edits interior text and appends in the same publish would render stale interior text. Corrections must never be combined with an append in one `liveSegments` assignment.
- The document builder `SelectableAttributed.transcriptDocument` is shared by the tail-append path and the full rebuild, and the tail path relies on `tailDocument.attributed.string.hasPrefix(oldTail.string)`. Changing what it emits changes both paths.

### Design

The design below adds zero new code to `LiveTranscriptTextPaneMac`'s mutation path and zero changes to the document builder. It only reads the selection and reuses the rebuild path that speaker rename already exercises.

C1. Data. `PersonalDictionaryPreferences` gains correction pairs in `personalDictionaryCorrections.v1`: `heard` (trimmed, whitespace collapsed, lowercased) and `correct` (as typed). Cap 100 pairs, dedupe by `heard`, reject pairs where `heard` equals `correct` case-insensitively or either side is empty. Saving a correction also adds `correct` to the term list if absent. Settings shows a second list, "heard, corrected to", with edit and delete, on macOS and iOS; add "correction" and "replace" to the settings search keywords for `language.dictionary`.

C2. Deepgram. At connect, append `replace=heard:correct` per pair after the keyterms, URL-encoded as one query item each (Deepgram lowercases the find term; the handshake URL stays small with 100 of each). Do not reconnect to apply a correction mid-meeting: it costs 250 ms to 3 s of dead air, resets the Deepgram word clock, and churns speaker identity. The local corrector below gives the same visible result immediately.

C3. Local corrector. A nonisolated `TranscriptCorrector` value type holding precompiled case-insensitive word-boundary `NSRegularExpression`s, sorted longest `heard` first so multi-word phrases win over their sub-words, rebuilt only when the store changes, and `nil` when the store is empty. Three call sites:
- New finals: apply to each `SpeakerSegment.text` inside `handleSpeakerSegments` before the segment reaches `liveSegments`. This keeps the append-only path append-only; the pane sees an ordinary tail append.
- Interim: apply to the interim string inside the existing 125 ms throttled publish into `TranscriptRuntimeState`. A short string and a handful of regexes.
- Retroactive, when the user saves a correction with "fix earlier mentions" on: one pass over `liveSegments` building a new array, changing only `text` on segments that match (IDs, speakers, timestamps untouched), then one `liveSegments = updated` assignment on the main actor with no other mutation in the same turn. Skip the assignment entirely if nothing matched. This must run between final batches, never inside `handleSpeakerSegments`, so it cannot combine with an append (F10.1).
When no corrections exist the corrector is `nil` and none of the three sites runs any code, so existing users pay nothing.

What the retroactive assignment does today, with no new pane code: `liveSegments.didSet` fails the `prefixStillMatches` fast path and does one signposted full cache rebuild; `TranscriptView.onChange(liveSegments)` sees equal counts, so `canAppend` is false and `rebuildAllSegments(allowsLocalizedMutation: true)` runs; `localizedReplacement` yields one paragraph-snapped mutation spanning the first to the last changed paragraph; the coordinator applies it in one `beginEditing`/`endEditing` and `LiveTranscriptSelectionPolicy` preserves the selection. For a correction scattered across a long meeting that mutation covers most of the document, which is exactly the path a speaker rename or "mark as you" takes today, and it is a one-off user action. Auto-scroll behaviour is unchanged because the mutation path already schedules the same follow.

C4. macOS selection and menu. Read-only additions to the coordinator:
- Set the coordinator as `NSTextViewDelegate` (the view currently has no delegate). Implement `textView(_:menu:for:at:)` to append a separator and "correct 'xyz'..." when `selectedRange()` is non-empty and `NSMaxRange(selectedRange) <= finalizedLength` (interim text is still changing and is excluded). The heard text is `storage.attributedSubstring(from:).string`, snapped outward to word boundaries with `NSString.rangeOfWord`-style scanning, trimmed, collapsed, and capped at 80 characters; longer selections get no menu item.
- Implement `textViewDidChangeSelection(_:)` to publish the current snapped heard text (or nil) into a small `ObservableObject` owned by `TranscriptView` (`LiveTranscriptSelectionState`), not into `AppState`, so a header button and a keyboard shortcut can enable without invalidating the app. Publish only when the value changes; capping the string keeps drag-selection cheap.
- Presenting the editor: the `SelectableTextMutation` inputs and the pane's frame are untouched. Present a SwiftUI `.popover(isPresented:attachmentAnchor: .rect(.rect(anchor)))` on the `LiveTranscriptTextPaneMac` view, mirroring the existing rename popover at `TranscriptView.swift:434`. The anchor comes from `textView.firstRect(forCharacterRange:actualRange:)` converted from screen coordinates into the scroll view's coordinate space; the coordinator exposes it alongside the heard text. A popover does not change the pane's layout or sizing.
- Editor content, built from `MinitiDesignSystem` controls like `RenameSpeakerView`: "heard" (prefilled, editable), "correct to" (focused), a toggle "fix earlier mentions in this meeting" (on), and a primary "save". Escape and outside-click dismiss without saving. Reduce Motion applies to any app-authored animation.
- Also add a menu-bar command "correct selected word..." (⌘⇧D unless it collides with an existing shortcut in `KeyboardShortcutsService`) enabled from `LiveTranscriptSelectionState`.

There is no segment-ID mapping in this design. A dictionary correction is by definition "everywhere this phrase appears", so the selected text is all the input needed. Keep `transcriptDocument`, `mergeTurns`, and `TranscriptRenderModel` exactly as they are.

**Amendment (2026-09-10):** Field test showed popover-at-text-rect + bottom pill is unreliable (click no-ops; pill appears once). Prefer a stable SwiftUI sheet/popover anchored to the pill or TranscriptView, and avoid selection clear destroying the control before the action runs. Classic macOS text submenu is not the primary UX.

C5. Saved meetings. The same editor in `TranscriptTrimView` on both platforms, triggered from its existing selection surface, again text-based. Apply rewrites matching `TranscriptSegment.text` values, then a new `Meeting.markTranscriptCorrected()` that bumps `transcriptRevision` and `transcriptEditedAt` without clearing insights, saves, re-exports markdown, and resends the webhook the way trim does. `buildSegmentSyncPlan` already upserts on text change, so the live path needs no persistence work.

C6. Insights. Live incremental insights will not re-read corrected earlier text; a word fix does not justify a re-plan. The final summary at finalization reads the corrected full transcript through the rebuilt caches. Coaching recompute is already debounced on `liveSegments` changes; it runs once after a retroactive pass.

C7. iOS. Second pass. A long-press context menu on a `TerminalTranscriptTurnRow`, "correct a word...", opens a sheet that lists the row's words as tappable chips plus a "correct to" field. Shares the store and corrector. No selection callback is needed on SwiftUI text, and the iOS lazy rows are untouched.

C8. Cross-client. The Linux client caps keyterms at 100 and has no `replace` or correction concept; file a tracking issue there.

### Regression contract

- `LiveTranscriptTextPaneMac`: `configure`, `apply`, `applyFinalizedContent`, `replace`, `replaceInterim`, `removeInterimIfNeeded`, the scroll-follow code, and the frame handling are byte-for-byte unchanged. The coordinator gains only delegate methods that read state.
- `SelectableAttributed.transcriptDocument`, `mergeTurns`, `LiveTranscriptDocumentMutation`, and `TranscriptRenderModel` are unchanged.
- The tail-append path stays append-only; a correction never lands in the same `liveSegments` assignment as new finals.
- With an empty correction store every existing code path is identical to today (corrector is `nil`).
- Existing dictionary tests (`MinitiTests/DeepgramParsingTests.swift:211-292`) pass unchanged; the keyterm cap stays 100.
- A correction never clears insights, MEDDPICC, questions, templates, or docs topics. Trim keeps its current clearing behaviour.
- The `liveSegments` invariant (finalized, non-empty, chronological, stable IDs) holds; corrections never reorder, drop, or re-time segments.
- Interim rendering, cursor blink, selection preservation, and auto-scroll behave exactly as today.

### Tests

- Store: normalization, cap, dedupe, rejection of identity pairs, term auto-add, empty save clears.
- Corrector: word boundary ("meet" does not touch "meeting"), case insensitivity, longest-phrase-first ordering, punctuation adjacency, unicode names, `nil` when empty, unchanged segment keeps its identity and timestamp.
- URL: `replace` items appear after `keyterm` items and are capped; add the missing assertion that `keyterm=` items are on the built URL.
- Retroactive pass: equal count, changed texts, one assignment; `rebuildSegmentCaches` takes the localized-mutation path; extend `testMacLiveTranscriptUsesOneTextKit2DocumentAndPreservesStableSelection` (`SelectableAttributedTests.swift:596`) with a correction applied while a selection sits after the changed paragraph and verify the selection survives.
- Selection snapping: partial word, multi-word, selection crossing into interim (no action), selection over the 80-character cap (no action).
- Meeting: `markTranscriptCorrected` bumps revision and leaves insights intact.
- Manual, on a 60+ minute BBC World Service transcript: correct a term live, watch earlier and later mentions change with no blank gap and no scroll jump, resize the pane during and after, finish the meeting, confirm history and markdown carry the fix, start a new meeting and confirm Deepgram now hears the term. Run Instruments Points of Interest and confirm one `TranscriptCacheFullRebuild` and one `TranscriptViewCacheUpdate` per correction.

## Backend and sibling repositories

- `miniti-api`: B5 prompt already fixed; **also** add `meet.google.com` to conference URL regexes before client release that depends on pasted Meet links. Ask Ian before deploying (push to `main` = prod).
- `miniti-linux`: tracking issues #1 #2 #3 filed.

## Release notes to draft when this ships (Ian's voice, all lowercase miniti)

Already under `CHANGELOG.md` → `### Unreleased - v2.7.0`. Adjust only if Fable’s fixes change user-visible behaviour.

## Open questions for Ian

1. Should "start now" in the countdown banner also open the link, or stay a separate "join" button? This plan keeps them separate so nobody already sitting in the call gets a second tab. **Default kept.**
2. Corrections stay per device (UserDefaults, like terms today). Fine until account sync exists? **Default kept.**
3. Retroactive correction applies to the current meeting only, never to past meetings in bulk. Agreed? **Default kept.**
