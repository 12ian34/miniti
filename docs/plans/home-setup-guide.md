# Home setup guide, 3.8.0 (SG1)

Ian selected this addition on 2026-11-04 after an older-install upgrade showed simultaneous, differently sized email and calendar panels and an unresponsive Add email action. Implementation and publication gates are owned by the [release record](../releases/3.8.0.md). Release execution is authorized; physical QA is in progress.

## Evidence and chosen experience

The previous Home views independently mounted a 380-point account card and a 480-point calendar card. Their state conditions could both be true after onboarding. Add email called `openAccountEmailSettings`, which set the iOS Settings presentation flag; the Mac Home path had no owner opening its Settings window. Settings also listened only for a changed email target, missing a target set before its section appeared. This explains plausible source-level failures; the reported old-version upgrade has not been physically reproduced.

One shared, optional Home guide replaces both nudges. Record remains ahead of it. The approved checklist revision below supersedes the intermediate tabbed design. The heading is “make it yours”; visible task rows, completion checks and current-state summaries sit directly on Home, with one expanded control group and no containing card. Hide/reopen remains available, with a short fade/collapse into a labelled neutral button; Reduce Motion disables the animation. Home's utility bar is outside its scroll area, whose indicators are hidden; compact windows and accessibility sizes retain scrolling. Viewing the guide never creates an account, starts a download or changes a setting.

- Account: “claim your account” completes only with verified email; an acknowledged recovery key remains a backup and pending verification remains pending. Email opens the owned sheet with cancellation, delivery feedback and retry. Save recovery key opens the existing explicit acknowledgment sheet.
- Files on Mac: first-run setup and the Home files tab share the saved export folder, automatic Markdown export and AGENTS.md index switches with Settings, Data. The destination is visible even with export off. Viewing setup does not enable exports or write files; a cancelled picker changes nothing.
- Calendar: unchecked status is not disconnected. Resolved/disconnected state offers Connect Google Calendar; connected state shows actual integration, automatic-start and calendar-end switches. Those switches update the same preferences as Settings. Legacy dismissal preferences remain compatible.
- Transcription on Apple-silicon Macs: the Deepgram / This Mac picker applies the real next-recording setting and starts the existing model preparation path on explicit local selection. Readiness is shown separately; local fallback remains an explicit switch. Private mode retains its existing control restrictions. iOS and unsupported Macs omit this step.

Existing configuration is preserved. Audio choices apply directly, but its task only completes after explicit review confirmation. The previous keep/skip choice controls are removed; independent task hiding remains. Switching accounts closes owned sheets and clears sensitive temporary values. Signed-out account choice has priority; starting/recording/resuming/finalizing and an imminent calendar start suppress the guide.

## Validation and release audit

SG1 owns upgrade/configured/pending/unavailable/legacy-dismissal policy tests, preference persistence without settings side effects, a real UI Add email/cancel/send/pending journey, direct calendar-tab selection and hide/relaunch. Largest-text UI screenshots must prove reachability; a passing test alone is insufficient. Both hosted Apple bundles use Testing; hardware stays opt-in. Mac runner authorization, signed old-version migration and Mac/iPad/VoiceOver checks remain manual release gates.

No API, billing, schema, provider prompt or Linux runtime change. Existing email routes and owner/generation guards remain authoritative. There are no new telemetry fields or permission categories. Work is a bounded setup-state calculation, no audio/transcript callbacks or polling. Native controls, ColorPalette and MinitiDesignSystem own appearance; the hide/reopen transition uses the shared motion token and respects Reduce Motion. Rollback ignores the new preference keys without changing account/calendar/model choices.

Local references: accounts, UI states, Settings, testing and design. Public sources: upcoming first-meeting/account/calendar notes, website roadmap/LLM copies, candidate changelog/iOS notes. Existing marketing/store images stay on released behavior; synthetic guide/email screenshots are QA artifacts, not replacement store assets. Linux PLAN records shared UX parity as future tracking. The [release audit](../releases/3.8.0-planning-audit.md) owns the combined surface register.

Local verification completed 2026-11-04: five Mac hosted regressions (four shared on iOS), three new iPhone action journeys, and full hosted suites/UI suite passed. Normal/largest-text iPhone guide captures and the native Mac guide component were visually inspected. Exact counts, commands, artifacts and manual limits are in the release record. No publication occurred.


## Onboarding/defaults discussion, 2026-11-05

Ian requested recommendations, not a preference migration, and confirmed that both local transcription and local speaker separation should be recommended separately. No defaults are changed by this follow-up. The existing first-use flow already covers account choice/consent, a microphone meter and an explicit recommended automatic-recording choice on Mac. The Home guide adds recovery, calendar and local transcription choices. Avoid duplicating this as another mandatory wizard.

Recommended next refinement. Ian selected separate recommendations for both local models; hardware/language eligibility and default changes still need a concrete policy:

- Recording readiness: explain mic/system-audio permission and distinguish a detected call from an armed calendar start. Offer a short explicit test recording, with visible Start/Stop and a usable result. Do not start audio merely by opening setup.
- Calendar: recommend connection for titles, attendees, upcoming meetings and automatic recording; show the actual auto-start switch beside it. Recommend on for a connected calendar after a clear choice, preserving existing preferences. Smart Meetings stays on; confirmed call end keeps a cancellable finish. Calendar end alone must not stop an overrun. Keep the five-minute silence fallback conservative.
- Launch at login: currently off. Recommend it beside automatic recording, as an explicit OS-backed choice, so detection is available after restarting the Mac. Keep the menu-bar and recording indicator on.
- Transcription language: show the current language beside engine choice and let people change it directly. Suggest a supported system language for a fresh install, but never overwrite an existing language choice.
- Local transcription: recommend as an explicit choice on validated Apple-silicon hardware and supported languages, with download size, readiness, expected latency and the distinction between local audio processing and cloud AI summaries. A fast Mac alone does not prove superior accuracy. Current in-repo measurements show language-dependent tradeoffs. No arbitrary RAM/chip cutoff or default-on claim is established by this work.
- Local speaker separation: treat separately from transcription. Keep default off until the existing device-quality gates are met; Your voice/Remember voices remain opt-in. Ian confirmed a separate recommendation for this model as well as transcription. Each choice needs its own explanation and setting; selecting one must not silently enable the other.
- Recovery: offer email directly and keep recovery key as backup. Do not make cloud sync a consequence of adding email.
- Progressive discovery: introduce folders after useful history exists; offer Sales, templates, CRM and exports when relevant. Avoid adding all Settings to onboarding.

Default stance for discussion: mic/system audio, Smart Meetings, recording indicator, automatic folder filing and speaker-name inference on; calendar auto-start a recommended explicit choice; local transcription conditionally recommended; cloud sync, voice memory, local-to-cloud fallback and integrations/exports explicit choices; specialist insights and coaching notifications off until requested. Existing installs retain their choices. Recommendations are not implemented defaults.


## Calendar recommendation and local files, selected 2026-11-05

Ian confirmed Smart Meetings should remain on by default and automatic calendar recording should be recommended after connection. Existing values stay unchanged; the connected-calendar controls explain the recommendation, and a connection initiated there stays on the calendar choices after return. First-use automatic/manual actions apply their stated preference. No global default or upgrade migration is added.

Ian also requested a visible local destination and AGENTS.md option during onboarding. Mac first-use recording setup and Home's files tab now share `HomeMeetingFilesSetup`, bound to the existing AppState properties and security-scoped folder chooser. Copy distinguishes the app's local history from optional Markdown copies, displays the real default/chosen destination, and offers automatic completed-meeting export plus an index updated on exports. Choosing a folder does not itself enable exports; both switches retain their existing defaults (off). Interacting with these controls keeps the files tab open so enabling exports cannot collapse the guide before the index choice. Existing history export remains the explicit Settings, Data action. iOS keeps its existing share flow and does not show the Mac-only files step.

Selecting a new folder saves the bookmark and display path together. Failure preserves the previous pair and reports the error. Index updates replace only a miniti-marked block; an existing unmarked AGENTS.md is preserved and the block is appended. The exact legacy miniti-generated header/list is migrated into the marked block, preserving any appended human notes; unrelated unmarked instructions remain untouched. Text outside the block survives later updates. Missing, repeated or reversed block markers stop the index write without changing the file; meeting Markdown still saves independently. Private-mode configured exports remain allowed. No cloud setting, provider permission or model choice is changed.

Validation covers file-step platform/configuration state, a rendered Mac destination/control group with no preference mutation, actual temporary-folder exports/bookmark persistence, preservation of existing AGENTS instructions and trailing notes, malformed markers, and a failed replacement-folder selection. Native picker/VoiceOver and signed-install checks remain separate manual gates. See the release record for results.

<a id="checklist-proposal-2026-11-05-not-implemented"></a>

## Approved checklist proposal, 2026-11-05, implemented locally

Ian rejected the new tabbed guide as busy and corporate and asked to restore the earlier sense of structure and completion. This dated proposal was subsequently approved; the implementation section below owns current behavior and the release record owns validation. The original research rationale follows.

### Research and interpretation

- [UX Collective, Guide to onboarding UX patterns](https://uxdesign.cc/menu-of-ux-onboarding-patterns-and-when-to-use-them-3df2e3880fd1) describes a persistent checklist around the most valuable experiences, ordered into manageable steps, with their value and progress visible. Its checklist examples include Quora and Acorns. For miniti, this supports visible task rows and completion checks rather than navigation tabs that hide the remaining work.
- [Nielsen Norman Group, Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/) recommends showing the important choices first and revealing specialised options on request. Apply this within a checklist row: one expanded task, a short explanation, its real controls, and an optional details disclosure. Do not turn Home into a second Settings window.
- [Nielsen Norman Group, Mobile-App Onboarding](https://www.nngroup.com/articles/mobile-app-onboarding/) recommends brief, optional onboarding and help at the point of use. Keep Record available, avoid a compulsory feature tour, and introduce folders once there is history to organise.
- [Intercom's checklist guidance](https://www.intercom.com/help/en/articles/6890711-checklists-faqs) explicitly warns that adding steps can make completed users appear incomplete again. Preserve dismissed/completed upgrade state rather than reopening setup each time miniti gains a feature. This is a useful lifecycle lesson, not a recommendation to copy Intercom's enterprise styling or messenger UI.

These are design principles and examples, not evidence of a measured conversion improvement for miniti. The accessible introduction/indexed excerpts of UX Collective's [Grammarly case study](https://uxdesign.cc/onboarding-a-complex-product-a-case-study-of-grammarly-8e700001053b) were also checked; its full member-only article was not available and is not treated as fully reviewed evidence.

### Proposed experience

Use a compact vertical checklist headed **make it yours**, directly on the Home background. Keep the primary Record action visually ahead of setup. Each row has a native disclosure action, a quiet outlined state circle that becomes a check when configured, a short title, and a one-line current-state summary. Keep all titles visible and one row expanded. Use restrained dividers, normal system typography and generous spacing; no outer card, dashboard tiles, horizontal tabs, percentage ring, confetti or decorative illustrations. Colour communicates state rather than making each task a different accent.

Suggested rows, tailored to the platform and actual configuration:

| Row | Collapsed summary and expanded choices |
| --- | --- |
| Ready to record | Actual microphone/system-audio readiness. Existing grants show a check; a missing permission shows the required action. An optional short test has explicit Start and Stop. Opening setup never captures audio. |
| Connect your calendar | Connected calendar or a short benefit: titles, attendees and automatic recording. Once connected, show the real automatic-start switch with a recommendation. Smart Meetings stays on by default; calendar end alone must not cut off an overrun. |
| Save your meetings | Explain that app history is stored locally. On Mac, show the current Markdown destination, Change folder and the optional automatic-copy switch. Show “Help AI assistants find your meetings” with a short explanation of how folder-aware AI tools use saved notes; keep AGENTS.md details in help. Choosing a destination alone does not enable exports or move the app database. |
| Keep access to your account | Recognisable verified email or recovery-key status. Offer the working email/recovery actions. Pending verification stays pending; adding email does not enable cloud sync. |
| Choose how audio is processed | Eligible Macs only. Two separately labelled choices inside this row: transcription and speaker separation. Each has its own recommendation, current setting and readiness. Choosing one never enables the other. Show download size/readiness only when relevant. |

This is five rows at most, with platform-specific omissions; five is an initial design choice, not a research-derived magic number. The readiness row should usually already be checked after first use. Avoid duplicating required account/consent/permission setup. Folders, CRM, sales modes, coaching, voice memory and advanced AI settings belong in contextual discovery after a useful first meeting.

A check means the task is actually configured or an explicit choice is saved. “Deepgram selected” and “automatic recording off” are valid completed choices; a check must not falsely mean local models are downloaded or a calendar is connected. Use separate neutral “not connected”, “not now” or “downloading” text where applicable. Merely opening a row is not completion. Optional deferral is distinct from success, never a repeated prompt to enable everything. Show progress only if it can express this honestly; the row checks are sufficient without a numeric counter.

Selections apply immediately to the real settings, with the selected value still visible. Keep the row open while the person finishes related controls, especially folder destination/export/index. Do not auto-advance or collapse it after the first toggle. Native fields remain recognisable input boxes. Keyboard focus, VoiceOver labels and checked/expanded state must be explicit.

Hide becomes a quiet, reversible “set up miniti” link with the existing 180 ms fade/collapse; Reduce Motion removes motion. Preserve previous dismissals and configured choices on upgrade. Do not introduce a preference migration. Local transcription and local speakers remain separate recommendations subject to the existing hardware, language and quality gates, not new automatic defaults.

### Review before implementation

Prepare normal and compact Mac/iPhone layouts showing: new install, mostly configured upgrade, pending email, unavailable model and long folder path. Verify all row titles are scannable, Record and settings utilities remain reachable, and only one control group is open. At ordinary Mac window sizes the guide should fit comfortably; small windows and accessibility text must retain scrolling rather than clipping content to eliminate a scrollbar. Use one scroll owner, no inner scrolling card. Include keyboard, VoiceOver, Reduce Motion, model-download failure and dismissal/relaunch checks.

The proposal did not authorize default resets. Ian subsequently approved implementation; see the implementation section below. Research alone is not release-readiness evidence.


## Checklist implementation, 2026-11-05

Ian approved the researched proposal. The Home guide now shows recording access, calendar, Mac files, account recovery and eligible-Mac audio processing as vertical rows with state icons and current-value summaries. One task expands at a time. Native buttons own disclosure/focus; shared spacing, dividers, palette and Reduce Motion-aware transitions are reused. Existing first-run account/consent and microphone test remain; the Home access row reads actual microphone authorization and requests it only after an explicit action. It does not claim system-audio permission has been verified: macOS checks that when capture begins. The existing Home/first-use audio test remains available rather than adding a second capture owner.

All saved audio defaults remain valid choices, including Deepgram. Audio processing starts unticked and requires explicit review confirmation; model readiness/download/error stays separate. Files are already saved in the app, so that row can show a configured check without enabling optional Markdown exports. Calendar connection and pending email use actual evidence; deferred tasks use a neutral icon. Explicit actions keep the selected row open while related controls are changed. Earlier dismissals remain compatible; the visibility follow-up below supersedes automatic collapsing of configured guides.

Mac audio presents independent Transcription and Speakers controls bound to the Settings preferences, retaining the existing model preparation paths and private-mode restrictions. Supported tested languages get a local-processing recommendation; other languages recommend Deepgram. Speaker copy recommends local processing for voices around one microphone, with the bundled-model explanation. These are optional recommendations on supported Apple silicon, not a new hardware benchmark, default migration or guarantee on every Mac. M1 physical quality/default-on gates remain open. No voice-memory setting is changed. File setup labels the existing AGENTS option “Help AI assistants find your meetings” and explains its benefit; the filename and preservation contract live in help.

The changelog and both iOS note locales are rewritten against released tag v3.7.0. Intermediate improvements and repairs to new 3.8.0 code are consolidated into final new-feature descriptions or omitted; internal review evidence is preserved. The canonical changelog skill and AGENTS guidance now require this comparison for future releases. Validation belongs in the release record; there is no publication or version bump.


## Setup visibility and documentation links, 2026-11-05

The fixed Home footer places `set up miniti` at bottom left using the same utility-control styling as Feedback at bottom right. Its configured/eligible task count includes hidden tasks in the denominator and never counts an unfinished hidden task as complete. Completed prerequisites count toward progress even when omitted from Home. Audio needs explicit review, and account needs verified email; pending email and a recovery key alone do not complete it. Eligibility is platform/account/permission dependent, so the total is not hardcoded.

The guide no longer automatically collapses when all tasks are configured or deferred. New installs begin expanded; existing explicit collapse preferences remain. Hide collapses it into the footer control. Hide permanently removes both guide and footer control until restored in Settings, General. Every expanded task offers Hide for now, including incomplete and configured tasks. General lists individually restorable hidden tasks and a guide visibility/expand control. Restoring a task shows the guide without changing its feature settings. Account dismissal stays scoped to the current account; restoring calendar clears its earlier nudge deferral. Dismissal/collapse are independent persistent choices and respect Reduce Motion.

Small native info links use one shared topic catalog and accessible labels. Setup links cover recording access, account recovery, calendar, transcription, speaker separation and exports. Settings adds them beside Smart meetings, Google Calendar and model controls. Info buttons now open a short explanation in a native popover, with an explicit Read the docs link to the specific public page. iOS and accessibility text sizes use a scrollable sheet with a native Close control. Viewing help changes no permission, model download or setting. All six page URLs returned HTTP 200 and the speaker-separation anchor exists during local validation.


## Calendar-first checklist refinement, 2026-11-05

The follow-up to private build 152 puts upcoming meetings before the optional setup guide on Mac and iOS. Calendar rows sit under collapsible today/tomorrow/later headings, replacing `tom`; later starts collapsed. Completed setup headings are muted and struck through, retaining visible checks. Each row exposes its docs link and Hide for now control beside the expander even while collapsed. All-complete guides open with no task expanded. Existing permanent dismissal and General restoration remain.

Task copy gives one short benefit, then the direct controls. Mac transcription and speaker choices remain separate and keep their existing defaults. Shared model status displays provider-reported approximate progress during preparation in setup and Settings; zero/end fractions show preparation activity rather than a false completed download. A compact Home status icon opens Models settings and reflects the selected local engines. It describes readiness for future recordings, not a live engine switch. Calendar auto-start remains recommended after connection, without migrating existing preferences.

The release record owns validation and review disposition. These changes are not in the build 152 DMG.


Fourth-review details (2026-11-05): iOS task hide and documentation links use 44-point targets, ongoing overnight events remain in today, and idle model status says not loaded. Retry times follow locale and include the day for later dates. No preference defaults changed. The release record owns verification.


### Sixth-review refinements, 2026-11-06

Mac Home gives its scroll content a viewport minimum height, preserving centered spacing when it fits. Setup dismissal removes the guide and its Home button until restored in General; the current labels are documented below. VoiceOver reads configured task counts as “N of M”. Saved defaults remain valid choices and are not silently changed. A failed anonymous enrollment exposes an explicit “Continue setup offline” action during first use, only after the person chose anonymous access; it does not grant managed recording, consent or Cloud access. Approved email joins retain their link for a deliberate retry. Calendar association retains the offered event when it leaves the upcoming feed; iOS uses a calendar icon and vertically arranged actions to fit larger text.


## Accessibility-size header correction, 2026-11-06

Final iPhone UI validation found a task header taller than the viewport: at the largest Dynamic Type size, inline help/hide controls squeezed text into a narrow column. Accessibility sizes now place those actions on their own trailing line under the full-width task button; they remain available while collapsed. Normal-size layout and settings/defaults are unchanged. The journey scrolls the Home scroll view, checks the task header fits the viewport, then opens and closes the email sheet. Final results and the initial failed full run remain in the development evidence.


## Build 156 hands-on setup feedback, 2026-11-06

Ian reported a hang opening Recording access and uneven trailing controls. Home now reads cached microphone authorization; system reads and explicit permission requests run off the main actor, with concurrent status refreshes coalesced. Unknown status is shown as checking, never as an existing grant. Status refreshes when Home appears or the app becomes active. Opening a row neither requests access nor starts capture. This removes synchronous permission IPC from rendering; the reported hang's exact cause is unconfirmed without a process sample.

Disclosure, info and hide controls share vertical alignment and minimum icon hit areas. The shared info control opens a concise native explanation with a separate docs link and Close action, including in Settings. iOS uses a native sheet, with a larger scrollable presentation at accessibility text sizes. At accessibility text sizes the trailing utilities retain their separate row.

Calendar hiding still respects the existing nudge deferral and explicit task dismissal. Restore shows the task without connecting the account or enabling automatic recording; completion follows actual connection evidence. The help explains this distinction. No existing calendar preference is migrated. These source changes postdate private build 156; validation and replacement-package status belong to the release checklist.

2026-11-07 follow-up: Ian confirms the build-157 Recording access hang is gone. A minor expansion-lag report prompted focused layout measurement and removal of repeated visible-item computation. The available hosted layouts in the BYOK fixture take about 6–13 ms locally; the account task is absent in that fixture. This excludes animation/frame time and does not close general responsiveness QA. Mac Recording settings also uses the asynchronous permission cache. The current release checklist owns build-158 package status.


## Remaining-choice refinement, 2026-11-07

These source changes postdate private build 158. Audio processing starts unticked for every eligible Mac installation, regardless of saved model choices. Opening the task or changing a picker does not tick it. “I've reviewed these choices” persists a separate review flag, without changing either engine or waiting for a model download. Existing task/guide dismissals remain respected.

“Claim your account” explains free email recovery and optional Pro cloud storage/device sync. Only verified email completes it; the recovery key remains available as backup. No account is recreated and Cloud is not enabled. Recording access and calendar tasks disappear from Home once permission/connection is confirmed, while still contributing to progress. Unknown permission remains a pending task while the asynchronous read runs or reports unavailable, keeping the progress denominator stable. It never claims that permission is denied. Revoked permission or disconnected calendar makes the relevant task eligible again, subject to explicit hiding. General restores user-hidden tasks; normal Settings owns already-completed prerequisites.

Mac Home's fixed status/navigation header now has an opaque palette background so scrolling content cannot bleed through it. No recording, account, calendar or model defaults change. Validation and package status belong to the release checklist.


### Scoped build-156/157 review corrections, 2026-11-07

Setup presentation preferences, revision and cached permission evidence now live in HomeSetupState, observed only by the relevant guide, footer and Settings subtrees. Persisted keys and dismissal semantics are unchanged. Four setup-only actions produced 34 broad AppState notifications in the baseline probe and zero after isolation; this measures invalidation, not end-to-end frame time. Settings on both platforms uses the asynchronous permission cache. Refresh requests during a read retain the latest pending query, explicit requestAccess results supersede older reads, and an unavailable check is reported after three seconds without blocking the UI or starting overlapping OS reads. A stuck synchronous OS call may still occupy its worker until it returns. Mac didBecomeActiveNotification adoption remains a recorded follow-up, not part of this fix.

## Setup clarity and calendar headers, 2026-11-07, after build 159

Audio comparisons in Mac Home and Settings use aligned provider and benefit columns, matching callout typography and shared spacing. Transcription and speaker separation retain independent controls and the explicit review confirmation. Preferences and defaults are unchanged.

“Collapse guide” closes the checklist while keeping its Home button. “Remove guide from Home” removes both until restored in Settings, General. Neither new action has a timer. Individual task hiding also persists until restored in General, without marking completion; its hint explains this. An unexpired calendar snooze saved by an older version remains respected until its original expiry; this upgrade-only case is not a new task-hide action. Today/tomorrow/later headers use a full-width native button, including the empty space and chevron, with the shared Reduce Motion-aware disclosure animation.

These source changes follow build 159 and are not in that DMG or TestFlight build. The release evidence owns focused checks and the scoped Claude review. Full suites are required again before the next package.

### Approved build 160 copy/layout polish, 2026-11-07

Guide headings, field labels and action labels use lowercase, while provider/product names retain their spelling and explanatory prose uses sentence case. Audio uses “speaker separation” consistently in its heading, picker accessibility label and summary. The explicit review action is “confirm audio choices”. Home and Settings put provider benefits before each picker, followed by model status. The removal footer keeps its visible restoration caption and drops the duplicate hover tooltip. These are source-only copy/layout changes for the next candidate, with no defaults or visibility-state changes.

## Home presentation selected for 3.8.0, 2026-11-08

Historical layout and evidence. The 2026-11-09 refinement below supersedes action placement and the Mac calendar arrangement.

Ian selected this layout for the current release. Mac and iOS Home remove the large hexagon, miniti wordmark and tagline. Start meeting and its language choice remain near the top, with 40pt of header clearance (page plus section spacing), without vertical recentering when switching panels. The content remains scrollable on small windows. Setup and upcoming meetings occupy one shared area: opening setup hides the calendar, while collapsing or removing setup returns to it. The calendar button beside set up miniti shows or hides the calendar; showing it collapses setup. An explicit calendar hide persists across launches. This presentation choice does not disconnect Google Calendar, disable calendar display in Settings or change automatic recording. Pending automatic-start prompts retain priority.

The calendar control appears for an enabled, connected calendar, including when there are no upcoming events. The empty state says No upcoming meetings. Native buttons use shared neutral Home control chrome, with an emphasized visible state and calendar/calendar.badge.minus icons. Setup and calendar stay adjacent. On iOS, the presentation controls are centered above a separate centered Feedback row. On Mac, Feedback stays at the right and moves to a second row only when needed. Home controls retain the shared iOS minimum hit size and transitions respect Reduce Motion. HomeSetupState owns presentation invalidations so changing panels does not invalidate History. Existing consent, account, recording and task-completion behavior is unchanged. Build 160 predates this source change.

Focused validation: 27 Mac setup tests, 18 iOS setup tests and four iPhone UI journeys pass. Mac Home setup/calendar and iPhone calendar/footer captures were inspected. See the [dated evidence](../releases/3.8.0-evidence.md#home-presentation-update-2026-11-08). Full suites and matching packaging remain required before the next candidate.

Account entry styling, 2026-11-08: Home and onboarding use a centered, cardless account prompt with a short heading and explanation. Account choices use neutral shared control chrome, wrap with large text, and share the 320pt maximum action-column width and corner treatment with Start meeting. Recording keeps its green emphasis. Error, pending, retry and recovery actions retain their behavior.


## Folder journeys and optional setup, 2026-11-08

Ian selected an optional organise-your-meetings setup task and a focused folder manager for 3.8.0. The overview offers Organise existing meetings, Create a folder and Manage your folders. Preview has folder descriptions/counts and a separate Apply action. Manual filing stays protected unless explicitly included through Preview options. Create/edit shows name and description first; title rules and local-only creation live under More options. Selecting an existing folder opens its editor, including deletion. Cancel/back retains saved data; Save returns to the list. Automatic filing stays visible on the overview, with automatic creation under More options. Existing defaults, matching, ownership, undo and cloud boundaries are preserved.

The optional setup task starts unreviewed, even when automatic filing is already enabled. Opening or hiding it does not complete it. Confirm folder choices marks it reviewed without changing settings or filing history; review persistence lives in HomeSetupState. The task has the same hide/General restore controls and help popover as the other tasks. Home loads at most 1,000 finished meetings, only when Preview is requested. It does not observe or fetch the whole history for the checklist. The existing History entry point uses its supplied meetings.

Source is newer than private build 161. Focused runtime and rendered validation are recorded in the release evidence; full suites and a new package are required before the next distribution.


## Bottom recording controls and Mac calendar sidebar, 2026-11-09

Ian selected this refinement while performing physical QA. Language sits above Start meeting in a fixed bottom area. On iOS, setup/progress, calendar and feedback occupy one equal-width, equal-height footer row below Start. Footer labels grow through xxxLarge; at accessibility sizes, native long-press large-content viewers keep each compact navigation action readable without consuming the content viewport. Guide prose retains the full selected text size, with status and chevron above full-width task text at accessibility sizes. The scrollable guide and calendar retain their mutually exclusive behavior. Keyboard-presented setup sheets keep their own existing actions.

On Mac, the footer retains setup/calendar at left and feedback at right. Language and Start sit just above it in the main column. Upcoming meetings use a separate right sidebar with an expand/collapse rail. Setup and calendar can be visible together; collapsing or removing the guide does not change the Mac calendar preference. At narrower content widths, the calendar overlays Home with a dismissible backdrop instead of increasing the window minimum. Its section and scroll state survive collapse and width transitions. Pending automatic-start prompts still take priority.

Presentation state remains in HomeSetupState. No new AppState publication, history query, timer, audio capture, account, sync or automation behavior is introduced. iOS Home no longer observes an unused full-history query. Sidebar geometry stays local to Home and does not set NSWindow constraints. Native buttons, semantic design tokens and Reduce Motion behavior remain required. The release record owns focused and full validation and the replacement package; build 162 predates this layout.
