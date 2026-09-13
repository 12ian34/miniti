# Changelog

Public-facing changelog. End-user documentation lives at `https://miniti.app/docs`; the hosted changelog lives at `https://miniti.app/changelog`.

## Style

- Write entries as human-readable descriptions for a public audience. No code references, function names, file paths, or implementation details. Write what changed from the user's perspective — e.g. "Fix saved meetings showing wrong speaker name" not "Fix `TranscriptSegment.speakerLabel` for `micSpeakerID`".
- Never modify older changelog entries after they are written unless the user explicitly requests a historical correction. Add other corrections, clarifications, or reversals only as a new entry at the top.
- The entry at the top of this file is the source of truth; `fastlane/metadata/en-US/release_notes.txt` and `en-GB/release_notes.txt` are mirrored from it at release time.
- While a release is still being prepared, its top entry may use `### Unreleased - vX.Y.Z`. Replace `Unreleased` with the ship date only when the release is actually going out.
- Release headers contain only the date and version. Put platform availability in the relevant bullets, never in a parenthetical status suffix.
- One flat bullet list per release, prefixed `new:`, `improvement:`, or `fix:`. No sub-headers such as "New features" or "Experience improvements"; the prefixes already say that.
- The product name is always lowercase: miniti, never Miniti, including at the start of a sentence.
- Voice (Ian's, see `../gtm/enablement/ian-tone-of-voice.md`): short plain sentences that assume an intelligent reader. Lead each bullet with the thing itself, then one line on what it does for you. Specific numbers over "several" or "many". Simple verbs (is, has, does) over "enables", "enhances", "leverages". No em dashes, no "not X, it's Y" framing, no bold, no exclamation marks, no filler ("we're excited to"). Full stops between sentences inside a bullet; no full stop at the end of a bullet.

## Releases

### 2026-09-13 - v2.9.0

- new: (macOS and iOS) make your own templates. Settings, Templates: name it, add up to 8 sections with a line on what goes in each, preview it against a past meeting, then pick it from the More menu like BANT or SPIN. Duplicate a built-in to start, and export or import a template as a file
- new: (macOS) template sections are included when you send a meeting to Attio or Twenty
- new: (macOS and iOS) if miniti can't open your meetings it shows a recovery screen instead of crashing. Your data is never touched, and you can still export what it can read
- fix: (macOS and iOS) when something doesn't save, such as a pin, a rename, or a delete, miniti tells you and offers a retry
- fix: (macOS and iOS) if your history can't be read, miniti says so instead of showing an empty list
- fix: (macOS and iOS) a correction that can't be saved keeps the editor open and tells you why
- improvement: security work on miniti's servers behind the scenes. Nothing changes for you

### 2026-09-11 - v2.8.0

This release is available on macOS and iOS.

- new: (macOS and iOS) Pro follows your account. Buy Pro on one device and every device on the same account gets it
- new: (macOS and iOS) move a device to another account from Settings → Account & Plan with that account's recovery key. It keeps its meetings, usage, and connections
- new: (macOS and iOS) the next-meeting prompt has an End meeting button, so you can end the current meeting without starting the next one
- improvement: (macOS and iOS) live summary and question updates arrive about 3 times faster
- improvement: (macOS and iOS) Share Diagnostics is on by default in managed mode. It sends error and health events only, never transcript or audio. Turn it off in Settings → Privacy
- improvement: (macOS and iOS) webhooks only send over https, and webhook addresses never appear in diagnostics logs
- improvement: (macOS and iOS) the correct-word editor tells you when a correction was not saved or matched nothing, instead of closing quietly
- fix: (macOS) pressing Join no longer asks you to end the meeting you just started
- fix: (macOS and iOS) correcting only the capitals of a word, such as lightdash to Lightdash, now works
- fix: (macOS and iOS) a correction made after the meeting has stopped is saved to the meeting straight away
- fix: (macOS and iOS) filler counts no longer double count. An "uh huh" counts once, and Coaching calls them detected fillers
- fix: (macOS) task cards in the CRM send preview line up. Short tasks no longer sit with a gap on the left
- new: (macOS and iOS) out of office, focus time, all-day, and declined events no longer count as meetings, so they never trigger reminders, auto-start, or the next-meeting prompt. Settings → Calendar → Meeting filters lets you change the rules, add your own title words, and preview which of next week's events would be skipped

### 2026-09-10 - v2.7.0

This release shipped on macOS. On iOS it was never released: 2.8.0 replaced it in App Review, so iPhone and iPad went from 2.6.0 straight to 2.8.0.

- new: (macOS and iOS) join button on meeting reminders and upcoming meetings. One click opens the Meet or Zoom link and starts miniti
- new: (macOS) select a word in the live transcript to correct it. miniti fixes earlier mentions, keeps fixing it for the rest of the meeting, and remembers it next time
- new: (iOS) long-press a transcript line to correct a misheard word
- new: (macOS and iOS) Settings, Personal Dictionary lists your corrections so you can remove them
- improvement: (macOS and iOS) speaker names appear more often, with a final check when the meeting ends and names from the invite on 1:1 calls
- fix: (macOS) one person on the Mac mic no longer splits into several speakers during a call, and you stay labelled You
- fix: (macOS and iOS) meeting links and attendee names from Google Calendar were being dropped. Join buttons and attendee names now show

### 2026-09-06 - v2.6.0

- new: (Linux) miniti for Linux. Mic and system audio through PipeWire, live transcription with speakers, the same live insights, calendar, CRMs, webhooks, and Pro. Download the tarball from the GitHub release
- new: (macOS and iOS) Templates. Pick BANT, SPIN, an interview scorecard, a customer check-in, a stand-up, or a 1:1 from the More menu and miniti fills it in as the meeting goes. Saved with the meeting, included in exports and webhooks
- new: (macOS and iOS) your account is a recovery key. No email, no password, nothing to sign up for. Existing installs get one on first launch and keep their plan, usage, and history
- new: (macOS and iOS) up to 5 devices on one account. Restore with recovery key during setup or in Settings → Account & Plan. The same section lists your devices and lets you reveal or rotate the key, sign out, or delete the account
- improvement: (macOS and iOS) pick a specialist view mid-meeting and it fills in straight away
- improvement: (macOS and iOS) one card on Home asks you to save your recovery key. Confirm once and it goes away
- improvement: App Store screenshots and the screens page on miniti.app are captured from the real app on every release
- improvement: (macOS and iOS) every request to miniti's servers is signed by your device

### 2026-08-23 - v2.5.0

Available now on Mac. The iPhone and iPad update has been submitted to Apple and will release automatically after approval.

- new: (macOS) Several people sharing one microphone are now transcribed as distinct speakers — in-person and hybrid meetings keep per-person attribution on the Mac's mic alongside the existing remote-speaker separation, with automatic speaker naming, renaming, and "mark as you" working for everyone in the room
- new: When more than one person is detected on the microphone, miniti stops assuming any of them is you — speakers get neutral labels until names are inferred or you mark yourself, so coaching and talk-ratio stats are never silently attributed to the wrong person
- new: miniti offers to enable Sales (MEDDPICC) analysis when a live meeting sounds like a sales conversation — detected locally from commercial vocabulary, suggested at most once per meeting, and switchable off in Settings → Notifications
- improvement: Reconnections mid-meeting no longer discard inferred speaker names or your "mark as you" choices
- improvement: Shared-microphone meetings get cleaner turn boundaries — once a second voice is confirmed on the mic, borderline words no longer preferentially stick to the first speaker
- improvement: (macOS) The floating recording surface now wraps long nudges and questions instead of stretching across the screen, and every nudge has dismiss and "don't remind me" buttons — the latter flips the matching toggle in Settings → Notifications, where it can be re-enabled any time
- improvement: (macOS) Every meeting-ending decision now raises and expands the floating recording surface, including prolonged-quiet and calendar handoff prompts, so the choice cannot remain hidden behind the main window
- improvement: (macOS) Optional question, monologue, and filler-word nudges now appear in the floating recording surface while you are using miniti, with system notifications used when your attention is in another app or the recording indicator is turned off
- fix: (macOS) "Open meeting" on the floating recording surface now reliably brings the main window to you when another app is in focus — including pulling the window over to your current Space instead of raising it somewhere out of sight

### 2026-08-21 - v2.4.1

This Mac hotfix includes everything from 2.4.0 and fixes the two remaining floating-window interactions.

- new: (macOS) When a supported call app like Zoom, Teams, Slack, FaceTime, Webex or Discord starts using your microphone, miniti opens a small floating prompt offering to take notes — nothing records until you say so
- new: (macOS) When the call ends, miniti finishes the recording automatically after a short on-screen countdown you can cancel with one click, and continues the same meeting if the call comes back
- new: (macOS) A floating recording indicator opens for important start and ending decisions, then shows the timer, call status and controls even when the main window is closed or covered; drag it anywhere, collapse it, or turn it off under Settings → General → Appearance
- new: (macOS) The menu bar shows a red REC badge with the elapsed time while recording, and the ending countdown when a call finishes
- improvement: (macOS and iOS) Smart meetings can notice prolonged quiet in calendar-linked recordings instead of relying only on the separate calendar handoff path
- improvement: (macOS) Silence-based auto-stop is described as an advanced fallback for in-person meetings and unsupported call apps; supported calls end from the call itself
- improvement: (macOS) Browser calls use more conservative ending checks, since miniti cannot tell which site or tab is using the microphone
- improvement: (macOS) A meeting whose title improved after finishing no longer leaves two exported markdown files behind
- fix: (macOS) Dragging the floating recording window no longer expands or collapses it when you release the mouse
- fix: (macOS) Open meeting now reliably activates and brings the miniti window to the front, including after it was minimized, hidden or closed

### 2026-08-21 - v2.4.0

This release makes meeting boundaries automatic on Mac: miniti notices when a supported call starts and ends, and finishes the recording for you after a visible, cancellable countdown. Smart meeting prompts are also more dependable for calendar-linked recordings on every platform.

Available now on Mac. The iPhone and iPad update is with Apple for review and will release automatically after approval.

- new: (macOS) When a supported call app like Zoom, Teams, Slack, FaceTime, Webex or Discord starts using your microphone, miniti opens a small floating prompt offering to take notes — nothing records until you say so
- new: (macOS) When the call ends, miniti finishes the recording automatically after a short on-screen countdown you can cancel with one click, and continues the same meeting if the call comes back
- new: (macOS) A floating recording indicator opens for important start and ending decisions, then shows the timer, call status and controls even when the main window is closed or covered; drag it anywhere, collapse it, or turn it off under Settings → General → Appearance
- new: (macOS) The menu bar now shows a red REC badge with the elapsed time while recording, and the ending countdown when a call finishes
- improvement: (macOS and iOS) Smart meetings can now notice prolonged quiet in calendar-linked recordings instead of relying only on the separate calendar handoff path
- improvement: (macOS) Silence-based auto-stop is now described as an advanced fallback for in-person meetings and unsupported call apps; supported calls end from the call itself
- improvement: (macOS) Browser calls use more conservative ending checks, since miniti cannot tell which site or tab is using the microphone
- improvement: (macOS) A meeting whose title improved after finishing no longer leaves two exported markdown files behind

### 2026-08-20 - v2.3.0

This release helps you prepare for upcoming meetings and investigate important moments without interrupting the conversation.

Available now on Mac. The iPhone and iPad update is with Apple for review and will release automatically after approval.

- new: (macOS and iOS) Add locally stored prep notes to upcoming calendar meetings, then carry them into the live meeting notes automatically when recording starts
- new: (macOS and iOS) miniti can spot conversation moments worth investigating and run focused OpenAI research inside the app only when you choose to act, with cited web sources and optional Mac codebase context
- improvement: (macOS and iOS) Home now shows your next five connected-calendar meetings across the coming days, with a dedicated preparation view before you start
- improvement: (macOS) Saved meeting notes now use the same draggable, space-aware panel as live notes

### 2026-08-19 - v2.2.2

This release makes Coaching trends and CRM exports easier to review, and fixes navigation while searching meeting history.

- improvement: (macOS and iOS) Coaching focus sections now use clearer hierarchy, stronger next-step recommendations, and compact source examples with meeting details kept out of the quote
- improvement: (macOS and iOS) Coaching history keeps every metric in its own chart with labelled value and meeting axes that remain readable from a few meetings to hundreds
- improvement: (macOS) CRM exports now preview every task with its deadline and assignment details, and let you exclude irrelevant tasks before sending
- fix: (macOS) Back and forward trackpad gestures now work while meeting search is focused, then dismiss search focus automatically when navigation completes

### 2026-08-11 - v2.2.1

This release brings Smart meetings and the redesigned Settings experience to Mac, iPhone, and iPad. It also brings the latest Coaching improvements to iOS.

- new: (macOS and iOS) Smart meetings notices when a recording may have ended or another calendar meeting is approaching, then helps you save and start the right meeting; it is on by default and independent of existing auto-start and auto-stop settings
- new: (iOS) The Coaching overview highlights strengths, tracks trends across recent meetings, and suggests one practical focus for the next meeting with examples from your transcripts
- improvement: (macOS and iOS) Settings is reorganized into clear, searchable sections for recording, language, AI, calendar, integrations, data, and support; individual results open the exact control
- improvement: (macOS) Settings uses a stable, non-collapsible sidebar without the unnecessary collapse control
- improvement: (macOS) The navigation sidebar no longer repeats your plan and remaining minutes, which remain available on Home
- improvement: (macOS and iOS) Coaching opens immediately with its previous results and refreshes only changed meetings in the background
- fix: (macOS) Closing or minimizing the main window no longer leaves miniti running without a reliable way to reopen it from the Dock or menu bar

### 2026-08-09 - v2.2.0

This release is for macOS. The currently pending iOS release and its App Store submission are unchanged.

- new: (macOS) Send saved meetings to Twenty CRM people, companies, or opportunities, with optional tasks created from action items
- new: (macOS) Automatically sync calendar-linked meetings to a matching Twenty company using attendee domains
- improvement: (macOS) Attio and Twenty share one clear CRM send workflow, and Send to Attio now uses the official Attio logo
- fix: (macOS) Transcript turns stay in chronological order when microphone and system-audio results finalize out of order or after a reconnect
- fix: (macOS) Selecting live transcript text remains stable when an earlier transcript result arrives and is inserted above it

### 2026-08-09 - v2.1.1

This hotfix is available for macOS. The currently pending iOS release and its App Store submission are unchanged.

- improvement: (macOS) Live transcript text remains selectable across speaker turns without turning the transcript into an editable document
- improvement: (macOS) Narrow windows now use a compact navigation rail with an accessible overlay sidebar instead of clipping the full sidebar
- improvement: (macOS) Meeting history gives titles more room, keeps date and duration together, and shows background insight work on a separate status line
- fix: (macOS) Resizing the window during long live meetings no longer destabilizes transcript layout or trigger the associated crash
- fix: (macOS) Resume auto-scroll now follows new transcript text without the scrollbar bouncing between positions
- fix: (macOS) Zoned Out requests no longer compete with automatic insight updates for the same request allowance

### 2026-08-08 - v2.1.0

This release is available on macOS now. The currently pending iOS release is unchanged; these iPhone and iPad updates will follow in a later App Store release.

- new: (macOS now; iOS later) A new Coaching overview highlights your strengths, tracks trends across recent meetings, and suggests one practical focus for your next meeting, backed by examples from your transcripts
- new: (macOS) Swipe with two fingers to move backward and forward between Home, Coaching, and meetings you have visited
- improvement: (macOS now; iOS later) Refreshed styling makes Coaching, insights, actions, and recording controls clearer and more consistent across the app

### 2026-08-07 - v2.0.4

This release keeps the complete 2.0 update together, including everything from v2.0.0 through v2.0.3.

- new: (macOS and iOS) pin important meetings and browse history in clear Today, Yesterday, This Week, and Older groups
- new: (macOS and iOS) import your Granola meeting history from its CSV export, with duplicate protection and clear source labels throughout miniti
- new: (macOS and iOS) Settings now offers Compact, Standard, and Large interface scales, with platform-tuned sizing for transcripts, insights, and controls
- new: (iOS) choose whether live transcript text appears on the Lock Screen and Dynamic Island; it remains on by default, and tapping the activity returns to the active meeting
- improvement: (macOS and iOS) Training is now called Coaching throughout the app, using clearer system typography; select any meeting in the Coaching overview to open it and return easily
- improvement: (macOS) recording controls, Zoned Out, Shortcuts, Settings, post-meeting navigation, and every insight mode now share the same compact accent-tinted button style; Summary, Questions, and Coaching have slightly more breathing room, enabled Sales and Playbook become matching peer buttons when space allows, and More shows one dropdown arrow
- improvement: (macOS and iOS) insight text now matches transcript text size, and Discussion, Actions, Questions, Coaching, Sales, and Playbook content matches Summary instead of appearing smaller
- improvement: (macOS and iOS) normal update notices no longer take over the home screen with large release notes; macOS continues updating through Sparkle and iOS through the App Store
- improvement: (macOS) Send to Attio keeps its primary action visible, uses a clearer compact search control, and collapses the detailed payload checklist until you need it
- improvement: (macOS and iOS) when several people are grouped as “Others” in Coaching, you can expand the filler section to see each person’s totals and filler-word detail
- improvement: (macOS and iOS) speaker names remain readable when a meeting has many detected speakers
- improvement: (macOS and iOS) clearer system typography and roomier transcript lines make meetings easier to read while preserving miniti's compact navigation and original wordmark
- improvement: (iPad) regular-width layouts now use adaptive sidebar navigation while iPhone keeps its compact tab bar
- improvement: (iOS) navigation and small utility surfaces use current system styling without changing miniti's compact dark interface
- improvement: (macOS) the main window now resizes more freely and remembers collapsed navigation and insight panes
- improvement: (macOS) the navigation sidebar now gets out of the way when recording starts and returns when you save or leave the session
- improvement: (macOS and iOS) Reduce Motion now applies consistently across app transitions and animated status elements
- improvement: (macOS and iOS) starting, stopping, recovery, and post-meeting review now explain what is happening and offer clear next actions without implying you still need to save
- improvement: (macOS and iOS) first-run setup is shorter, adapts to small screens, and includes a live microphone check
- improvement: (iOS) insights use one descriptive mode menu with update timing, and Settings opens into searchable task-based categories
- improvement: (macOS and iOS) insights keep Summary, Questions, and Coaching prominent while optional Sales and Playbook views live in a specialist menu; Sales analysis only runs after you enable it
- improvement: (macOS and iOS) the main Start meeting button always begins a fresh meeting, while calendar meetings remain explicit choices in the upcoming list
- improvement: (macOS and iOS) after the final transcript is saved, you can return to meetings and start another recording while final insights finish safely in the background
- improvement: (macOS and iOS) transcript trims and speaker edits now participate in the system Undo command, while save, copy, and export confirmations stay inline
- improvement: (macOS and iOS) consecutive transcript chunks from the same speaker now appear as one clean turn with a single speaker label and timestamp
- improvement: (macOS and iOS) meeting finalization is now shown as non-interactive progress, with completion guidance appearing only when its action is available
- improvement: (macOS and iOS) longer meetings stay more responsive as live transcription, coaching analysis, transcript rendering, and audio meters do less work on the interface thread
- improvement: (macOS and iOS) live transcripts now render speaker turns independently for smoother long-meeting scrolling and resizing; each turn remains selectable, and Copy still includes the complete meeting
- improvement: (macOS and iOS) live transcript fragments and follow-to-bottom scrolling now update at a steadier, power-efficient pace without overriding manual scrolling
- improvement: (macOS and iOS) live AI insights now refresh less often during long meetings while still updating promptly when enough new conversation arrives
- improvement: (macOS and iOS) saving and reopening long meetings avoids repeated full-transcript work, including while opening sheets or editing speaker details
- improvement: (macOS and iOS) recovery autosaves now run once per minute and skip unchanged meetings, while stopping, saving, and backgrounding still persist immediately
- improvement: (macOS and iOS) managed Questions updates reuse prior context instead of repeatedly sending the full meeting as it grows
- improvement: (macOS) audio capture now reuses bounded working buffers during long recordings to reduce memory and processing churn
- fix: (macOS) clicking miniti in the Dock now restores the main window after it has been minimized
- fix: (macOS and iOS) finalized transcript and insight changes are more reliably saved when the app backgrounds, a meeting stops, or the Mac app quits
- fix: (macOS) system-audio-only recordings now detect and recover when the system capture callback stalls
- fix: (macOS) live transcripts no longer develop the recurring large blank gap before the newest line during long meetings or pane resizing; saved transcripts also keep their content aligned while resizing
- fix: (macOS) the Shortcuts action no longer receives an unwanted keyboard-focus highlight when the app opens
- fix: (macOS) future in-app updates no longer fail on the first attempt with a macOS security warning on affected Macs; installing v2.0.3 from an older version may still need one final retry because that update starts with the older updater
- fix: (macOS) opening Send to Attio immediately after saving a long meeting no longer risks freezing the app, including when Attio is not connected
- fix: (macOS) system audio leaking through speakers into the microphone no longer creates duplicated green “You” lines, while actual mic speech is preserved even when it overlaps playback
- fix: (macOS and iOS) resumed interrupted meetings no longer restore unfinished or blank transcript fragments
- fix: (macOS and iOS) stopping or saving a short meeting no longer loses the last visible transcript when transcription disconnects before finalizing it

### 2026-08-07 - v2.0.3

This release keeps the complete 2.0 update together, including everything from v2.0.0 through v2.0.2.

- new: (macOS and iOS) pin important meetings and browse history in clear Today, Yesterday, This Week, and Older groups
- new: (macOS and iOS) import your Granola meeting history from its CSV export, with duplicate protection and clear source labels throughout miniti
- new: (macOS and iOS) Settings now offers Compact, Standard, and Large interface scales, with platform-tuned sizing for transcripts, insights, and controls
- new: (iOS) choose whether live transcript text appears on the Lock Screen and Dynamic Island; it remains on by default, and tapping the activity returns to the active meeting
- improvement: (macOS) Send to Attio keeps its primary action visible, uses a clearer compact search control, and collapses the detailed payload checklist until you need it
- improvement: (macOS and iOS) when several people are grouped as “Others” in Coaching, you can expand the filler section to see each person’s totals and filler-word detail
- improvement: (macOS and iOS) speaker names remain readable when a meeting has many detected speakers
- improvement: (macOS and iOS) clearer system typography and roomier transcript lines make meetings easier to read while preserving miniti's compact navigation and original wordmark
- improvement: (iPad) regular-width layouts now use adaptive sidebar navigation while iPhone keeps its compact tab bar
- improvement: (iOS) navigation and small utility surfaces use current system styling without changing miniti's compact dark interface
- improvement: (macOS) the main window now resizes more freely and remembers collapsed navigation and insight panes
- improvement: (macOS) the navigation sidebar now gets out of the way when recording starts and returns when you save or leave the session
- improvement: (macOS and iOS) Reduce Motion now applies consistently across app transitions and animated status elements
- improvement: (macOS and iOS) starting, stopping, recovery, and post-meeting review now explain what is happening and offer clear next actions without implying you still need to save
- improvement: (macOS and iOS) first-run setup is shorter, adapts to small screens, and includes a live microphone check
- improvement: (iOS) insights use one descriptive mode menu with update timing, and Settings opens into searchable task-based categories
- improvement: (macOS and iOS) insights keep Summary, Questions, and Coaching prominent while optional Sales and Playbook views live in a specialist menu; Sales analysis only runs after you enable it
- improvement: (macOS and iOS) the main Start meeting button always begins a fresh meeting, while calendar meetings remain explicit choices in the upcoming list
- improvement: (macOS and iOS) after the final transcript is saved, you can return to meetings and start another recording while final insights finish safely in the background
- improvement: (macOS and iOS) transcript trims and speaker edits now participate in the system Undo command, while save, copy, and export confirmations stay inline
- improvement: (macOS and iOS) consecutive transcript chunks from the same speaker now appear as one clean turn with a single speaker label and timestamp
- improvement: (macOS and iOS) meeting finalization is now shown as non-interactive progress, with completion guidance appearing only when its action is available
- improvement: (macOS and iOS) longer meetings stay more responsive as live transcription, training analysis, transcript rendering, and audio meters do less work on the interface thread
- improvement: (macOS and iOS) live transcripts now render speaker turns independently for smoother long-meeting scrolling and resizing; each turn remains selectable, and Copy still includes the complete meeting
- improvement: (macOS and iOS) live transcript fragments and follow-to-bottom scrolling now update at a steadier, power-efficient pace without overriding manual scrolling
- improvement: (macOS and iOS) live AI insights now refresh less often during long meetings while still updating promptly when enough new conversation arrives
- improvement: (macOS and iOS) saving and reopening long meetings avoids repeated full-transcript work, including while opening sheets or editing speaker details
- improvement: (macOS and iOS) recovery autosaves now run once per minute and skip unchanged meetings, while stopping, saving, and backgrounding still persist immediately
- improvement: (macOS and iOS) managed Questions updates reuse prior context instead of repeatedly sending the full meeting as it grows
- improvement: (macOS) audio capture now reuses bounded working buffers during long recordings to reduce memory and processing churn
- fix: (macOS and iOS) finalized transcript and insight changes are more reliably saved when the app backgrounds, a meeting stops, or the Mac app quits
- fix: (macOS) system-audio-only recordings now detect and recover when the system capture callback stalls
- fix: (macOS) live transcripts no longer develop the recurring large blank gap before the newest line during long meetings or pane resizing; saved transcripts also keep their content aligned while resizing
- fix: (macOS) the Shortcuts action no longer receives an unwanted keyboard-focus highlight when the app opens
- fix: (macOS) future in-app updates no longer fail on the first attempt with a macOS security warning on affected Macs; installing v2.0.3 from an older version may still need one final retry because that update starts with the older updater
- fix: (macOS) opening Send to Attio immediately after saving a long meeting no longer risks freezing the app, including when Attio is not connected
- fix: (macOS) system audio leaking through speakers into the microphone no longer creates duplicated green “You” lines, while actual mic speech is preserved even when it overlaps playback
- fix: (macOS and iOS) resumed interrupted meetings no longer restore unfinished or blank transcript fragments
- fix: (macOS and iOS) stopping or saving a short meeting no longer loses the last visible transcript when transcription disconnects before finalizing it

### 2026-08-07 - v2.0.2

This release keeps the complete 2.0 update together, including everything from v2.0.0 and v2.0.1.

- new: (macOS and iOS) pin important meetings and browse history in clear Today, Yesterday, This Week, and Older groups
- new: (macOS and iOS) import your Granola meeting history from its CSV export, with duplicate protection and clear source labels throughout miniti
- new: (macOS and iOS) Settings now offers Compact, Standard, and Large interface scales, with platform-tuned sizing for transcripts, insights, and controls
- new: (iOS) choose whether live transcript text appears on the Lock Screen and Dynamic Island; it remains on by default, and tapping the activity returns to the active meeting
- improvement: (macOS) Send to Attio keeps its primary action visible, uses a clearer compact search control, and collapses the detailed payload checklist until you need it
- improvement: (macOS and iOS) when several people are grouped as “Others” in Coaching, you can expand the filler section to see each person’s totals and filler-word detail
- improvement: (macOS and iOS) clearer system typography and roomier transcript lines make meetings easier to read while preserving miniti's compact navigation and original wordmark
- improvement: (iPad) regular-width layouts now use adaptive sidebar navigation while iPhone keeps its compact tab bar
- improvement: (iOS) navigation and small utility surfaces use current system styling without changing miniti's compact dark interface
- improvement: (macOS) the main window now resizes more freely and remembers collapsed navigation and insight panes
- improvement: (macOS) the navigation sidebar now gets out of the way when recording starts and returns when you save or leave the session
- improvement: (macOS and iOS) Reduce Motion now applies consistently across app transitions and animated status elements
- improvement: (macOS and iOS) starting, stopping, recovery, and post-meeting review now explain what is happening and offer clear next actions without implying you still need to save
- improvement: (macOS and iOS) first-run setup is shorter, adapts to small screens, and includes a live microphone check
- improvement: (iOS) insights use one descriptive mode menu with update timing, and Settings opens into searchable task-based categories
- improvement: (macOS and iOS) insights keep Summary, Questions, and Coaching prominent while optional Sales and Playbook views live in a specialist menu; Sales analysis only runs after you enable it
- improvement: (macOS and iOS) the main Start meeting button always begins a fresh meeting, while calendar meetings remain explicit choices in the upcoming list
- improvement: (macOS and iOS) after the final transcript is saved, you can return to meetings and start another recording while final insights finish safely in the background
- improvement: (macOS and iOS) transcript trims and speaker edits now participate in the system Undo command, while save, copy, and export confirmations stay inline
- improvement: (macOS and iOS) consecutive transcript chunks from the same speaker now appear as one clean turn with a single speaker label and timestamp
- improvement: (macOS and iOS) meeting finalization is now shown as non-interactive progress, with completion guidance appearing only when its action is available
- improvement: (macOS and iOS) longer meetings stay more responsive as live transcription, training analysis, transcript rendering, and audio meters do less work on the interface thread
- improvement: (macOS and iOS) saving and reopening long meetings avoids repeated full-transcript work, including while opening sheets or editing speaker details
- improvement: (macOS and iOS) recovery autosaves now run once per minute and skip unchanged meetings, while stopping, saving, and backgrounding still persist immediately
- improvement: (macOS and iOS) managed Questions updates reuse prior context instead of repeatedly sending the full meeting as it grows
- improvement: (macOS) audio capture now reuses bounded working buffers during long recordings to reduce memory and processing churn
- fix: (macOS) long live and saved transcripts no longer develop a large blank gap between the transcript and the latest line
- fix: (macOS) future in-app updates no longer fail on the first attempt with a macOS security warning on affected Macs; installing v2.0.2 from an older version may still need one final retry because that update starts with the older updater
- fix: (macOS) opening Send to Attio immediately after saving a long meeting no longer risks freezing the app, including when Attio is not connected
- fix: (macOS) system audio leaking through speakers into the microphone no longer creates duplicated green “You” lines, while actual mic speech is preserved even when it overlaps playback
- fix: (macOS and iOS) resumed interrupted meetings no longer restore unfinished or blank transcript fragments
- fix: (macOS and iOS) stopping or saving a short meeting no longer loses the last visible transcript when transcription disconnects before finalizing it

### 2026-08-07 - v2.0.1

- improvement: (macOS and iOS) when several people are grouped as “Others” in Coaching, you can expand the filler section to see each person’s totals and filler-word detail
- fix: (macOS) long live and saved transcripts no longer develop a large blank gap between the transcript and the latest line
- fix: (macOS) future in-app updates no longer fail on the first attempt with a macOS security warning on affected Macs; installing v2.0.1 from an older version may still need one final retry because that update starts with the older updater

### 2026-08-07 - v2.0.0

- new: (macOS and iOS) pin important meetings and browse history in clear Today, Yesterday, This Week, and Older groups
- new: (macOS and iOS) import your Granola meeting history from its CSV export, with duplicate protection and clear source labels throughout miniti
- new: (macOS and iOS) Settings now offers Compact, Standard, and Large interface scales, with platform-tuned sizing for transcripts, insights, and controls
- new: (iOS) choose whether live transcript text appears on the Lock Screen and Dynamic Island; it remains on by default, and tapping the activity returns to the active meeting
- improvement: (macOS and iOS) clearer system typography and roomier transcript lines make meetings easier to read while preserving miniti's compact navigation and original wordmark
- improvement: (iPad) regular-width layouts now use adaptive sidebar navigation while iPhone keeps its compact tab bar
- improvement: (iOS) navigation and small utility surfaces use current system styling without changing miniti's compact dark interface
- improvement: (macOS) the main window now resizes more freely and remembers collapsed navigation and insight panes
- improvement: (macOS) the navigation sidebar now gets out of the way when recording starts and returns when you save or leave the session
- improvement: (macOS and iOS) Reduce Motion now applies consistently across app transitions and animated status elements
- improvement: (macOS and iOS) starting, stopping, recovery, and post-meeting review now explain what is happening and offer clear next actions without implying you still need to save
- improvement: (macOS and iOS) first-run setup is shorter, adapts to small screens, and includes a live microphone check
- improvement: (iOS) insights use one descriptive mode menu with update timing, and Settings opens into searchable task-based categories
- improvement: (macOS and iOS) insights keep Summary, Questions, and Coaching prominent while optional Sales and Playbook views live in a specialist menu; Sales analysis only runs after you enable it
- improvement: (macOS and iOS) the main Start meeting button always begins a fresh meeting, while calendar meetings remain explicit choices in the upcoming list
- improvement: (macOS and iOS) after the final transcript is saved, you can return to meetings and start another recording while final insights finish safely in the background
- improvement: (macOS and iOS) transcript trims and speaker edits now participate in the system Undo command, while save, copy, and export confirmations stay inline
- improvement: (macOS and iOS) consecutive transcript chunks from the same speaker now appear as one clean turn with a single speaker label and timestamp
- improvement: (macOS and iOS) meeting finalization is now shown as non-interactive progress, with completion guidance appearing only when its action is available
- improvement: (macOS and iOS) longer meetings stay more responsive as live transcription, training analysis, transcript rendering, and audio meters do less work on the interface thread
- improvement: (macOS and iOS) saving and reopening long meetings avoids repeated full-transcript work, including while opening sheets or editing speaker details
- improvement: (macOS and iOS) recovery autosaves now run once per minute and skip unchanged meetings, while stopping, saving, and backgrounding still persist immediately
- improvement: (macOS and iOS) managed Questions updates reuse prior context instead of repeatedly sending the full meeting as it grows
- improvement: (macOS) audio capture now reuses bounded working buffers during long recordings to reduce memory and processing churn
- fix: (macOS) opening Send to Attio immediately after saving a long meeting no longer risks freezing the app, including when Attio is not connected
- fix: (macOS) system audio leaking through speakers into the microphone no longer creates duplicated green “You” lines, while actual mic speech is preserved even when it overlaps playback
- fix: (macOS and iOS) resumed interrupted meetings no longer restore unfinished or blank transcript fragments
- fix: (macOS and iOS) stopping or saving a short meeting no longer loses the last visible transcript when transcription disconnects before finalizing it

### 2026-07-26 - v1.27.1

- improvement: (macOS and iOS) live transcription recovers on its own when it stops returning words mid-meeting, and keeps trying instead of giving up after the first few attempts
- fix: (macOS and iOS) meetings no longer auto-stop with "no speech detected" when live transcription drops while people are still talking
- fix: (macOS and iOS) a discarded meeting no longer reappears in history
- fix: (macOS and iOS) training mode counts "mhmm" as a filler word, and the default filler list no longer offers hesitations that could never be detected
- fix: (iOS) the Lock Screen and Dynamic Island recording activity no longer risks crashing the app when its meeting is discarded
- fix: (macOS and iOS) suggested questions, docs topics, and calendar attendees can no longer be lost from a saved meeting
- fix: (macOS and iOS) a meeting that stopped because live transcription failed now says so, instead of reporting a silent room
- fix: (macOS and iOS) deleting a meeting from history while its insights are being regenerated no longer brings it back
- fix: (iOS) recording recovers automatically after a phone call, Siri, or an alarm interrupts it, and after a failed switch between headphones and the built-in mic

### 2026-07-21 - v1.27.0

- new: (macOS and iOS) Docs insights tab keeps an updating list of topics from the conversation; each one looks up an answer grounded in your docs, with source links (auto for Pro and BYOK, manual with a monthly free allowance otherwise)
- new: (macOS and iOS) Settings lets you connect any docs MCP URL (for example a public product docs site)

### 2026-07-20 - v1.26.0

- new: (macOS and iOS) Settings can store a personal transcription dictionary for product names, acronyms, and other uncommon words
- new: (macOS and iOS) calendar meeting titles and attendee names help live transcription recognize people and company names more accurately
- improvement: (macOS) mic and system audio are transcribed on separate channels, so “you” vs remote speakers stays clearer during overlapping speech
- improvement: (macOS and iOS) action items sent to Attio are assigned to the connected Attio user
- improvement: (macOS and iOS) managed-mode transcription reconnects more reliably during longer meetings
- improvement: (macOS and iOS) live transcription stays connected more reliably during brief audio gaps

### 2026-04-29 - v1.25.1

- improvement: (macOS) markdown export indexes now use AGENTS.md as the AI agent entry point.
- fix: (macOS) in-app auto-updates now install correctly after downloading. Users already on the affected updater build may need to install this update manually once, then automatic updates should work again.

### 2026-04-27 - v1.25.0

- new: (macOS and iOS) saved transcripts can be trimmed before exporting, sharing, or regenerating insights
- improvement: (macOS) speaker labels no longer carry incorrect names across live transcription reconnects
- improvement: (macOS and iOS) automatic speaker naming is more conservative and waits for clearer transcript evidence before applying names
- fix: (macOS) notes editing now supports standard paste, undo, redo, cut, copy, and select-all shortcuts
- fix: (macOS and iOS) starting a new recording no longer picks up where an old unfinished session left off

### 2026-04-23 - v1.24.1

- new: (macOS) in-app auto-updater
- new: (macOS and iOS) home-screen card helps discover Google Calendar
- improvement: (macOS) audio capture reliability improved when switching to or from bluetooth headphones

### 2026-04-21 - v1.23.1

- improvement: (macOS and iOS, BYOK) Live insights stay faster and more reliable in longer meetings by updating from recent context instead of repeatedly reprocessing the full conversation.
- improvement: (macOS and iOS) Questions mode now prepares incremental rolling-state updates too. BYOK uses them now, and managed mode is client-ready to turn them on once the matching backend support is deployed.
- improvement: (macOS) Meeting history search feels more responsive in larger histories by waiting for a brief pause before running a full search while you type.
- improvement: (macOS and iOS) Live meeting updates do less repeated transcript work behind the scenes, which helps longer recordings stay lighter.
- fix: (macOS and iOS) Disconnecting Google Calendar now immediately clears pending reminders and auto-start countdowns instead of leaving stale meeting actions behind.
- fix: (macOS) Google Calendar connect no longer copies the sign-in URL to your clipboard, and both the Google Calendar and Attio connect callback flows are more robust.
- fix: (macOS and iOS) Managed mode now keeps the same device identity more reliably if secure keychain storage is temporarily unavailable.
- fix: (iOS) Real-time coaching nudges no longer target the wrong speaker in multi-person room audio, and monologue nudges recover properly after speaker changes.
- fix: (macOS) live transcript no longer leaves a large blank gap above the current line during long meetings.

### 2026-04-20 - v1.23.0

- new: (macOS and iOS) Automatic speaker naming - infers real names from transcript / calendar events. (opt in, via settings).
- new: (macOS and iOS) Rename any speaker yourself.
- new: (macOS and iOS) "i zoned out" button (😶). Tap during a meeting to catch up: current topic, questions directed at you, recent discussion, and key recent decisions.
- new: (macOS and iOS) Real-time nudges. Opt-in notifications when you've been monologuing ~1 min or filler words spike.
- new: (macOS and iOS) Upcoming meeting reminders. Opt-in system notification ~60s before each Google Calendar event starts (requires Calendar connected).
- new: (macOS and iOS) Select and copy text across the transcript and insights. You can now select any span — within a single line, across multiple speakers, or through insight sections — and copy just the part you want.
- new: docs website.

### 2026-04-19 - v1.22.0

- new: (iOS) Google Calendar integration now available on iOS. Works like the feature on mac. See upcoming meetings, tap to start rcording, option to auto start and stop.
- improvement: update backend infra using new domain

### 2026-04-18 - v1.21.0

- new: (macOS and iOS) Live system notifications for high-priority suggested questions during a meeting.
- improvement: (macOS) Attio send now shows the company domain or person email next to each record in the search results, so it's easier to pick the correct one.
- improvement: (dev) `fastlane ios test` derives the simulator device string and OS from `xcodebuild -showsdks` so unit tests run on Xcode 26.x where the simulator SDK version and `simctl runtime match` patch levels can differ (avoids Fastlane scan crash #29974).

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

- new: auto export as markdown to local folder (macOS), optional AGENTS.md index for AI agents. includes notes, insights, MEDDPICC, training metrics, and full transcript. works with obsidian and other AI tools.
- new: fast full text meeting search across titles, transcripts, notes, insights, topics, action items, MEDDPICC, and discussion flow.
- fix: iPad layout now fills the full screen width.

### 2026-03-11 - v1.15.0

- new: home screen redesign
- improvement: training stats include questions asked
- improvement: training stats detail improvements
- improvement: filler words info popup links to Settings
- improvement: added deepgram keyterms for "miniti", "Lightdash", and "Ahuja"
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

### 2026-03-08 - v1.12.4

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
