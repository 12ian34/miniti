# Settings, Privacy, Models and consent

3.5.0 reference: Privacy/Models/Help changes are live on Mac and submitted on iOS; 3.4.0 shipped the separate Sending tab. Shared tokens and native controls remain mandatory. Navigation/categories/search come from `SettingsDestination`, `SettingsGroup` and the catalog; root design rules live in [design.md](../../design.md).

## Navigation and layout

Local 3.6.0 correction: the iOS Home gear uses the same Settings sheet as account/search requests. Settings owns its navigation stack; never push it inside the Home stack. Native Back and edge-back gestures pop a Settings page; Done at the root dismisses the sheet. Regular-width Settings keeps its sidebar/detail layout. Simulator Back/Done navigation was checked; physical-device gesture/animation QA remains pending.

Single-word destinations grouped Setup / Meetings / Connections / Privacy / Support. Account precedes Plan and billing; Sign out and Delete sit below billing. Cloud and Models are in Setup. Sending is no longer a separate destination; its overview is part of Privacy. API is in Connections and visible even when its setup prerequisites are missing. Support contains Help and About. Help shows support details expanded with a whole-report Copy action; Account no longer contains the support disclosure.

macOS Configure opens the owning settings destination and anchor. Compact iPhone uses a value-based navigation path; regular iPad uses sidebar selection plus a bound detail path. An Account request clears stale detail navigation and focuses email. Resizing carries the visible top route/target to the new layout and clears the inactive stack. General is a real route; only nil selection returns to the list. Repeated requests are idempotent.

## Account

Your account shows full verified email and pending replacement separately. Ways to sign in offers email and a recovery-key backup; device controls follow. Switch account is separate from restoring Pro purchase. Billing copy distinguishes Polar license restore on Mac and App Store restore on iOS from account authentication.

Permanent key failure offers Sign in again and keeps Show recovery key; signed actions are hidden. Temporary failures disable signed actions and offer Try again immediately. Try again is a local proof with the existing key and sends no request. See [account contracts](accounts.md).

Home’s Keep access to your account card appears after a successfully saved first meeting when the account has no verified email and recovery key is not acknowledged. Loading/unavailable email state does not mean unprotected. Dismissal is per account; no extra post-purchase showing. Add email navigates to Account on iPhone; Cloud and API link to Account and share its email state. Pending verification explains how to finish. The broader first-use choice remains planned.

## Privacy and permission

The Privacy data-flow overview uses three groups: transcription/AI, sync/exports, account/connections. Each row has one model-decided status, one Configure action and optional details; unused rows are folded. Active recording routes come from the latched session. If the preference differs, a visible Next recording line explains it. Include Watch/import processing and queued exports; no claim that a meeting stays on the Mac merely because transcription is local.

Consent version remains 2 because 3.4.0 changed copy/layout, not recipients/data/purposes. Allow and Not now are outside the scrolling disclosure, stack on narrow layouts, honor Reduce Motion and fit minimum/accessibility sizes. Presentation sends nothing; Allow persists once. Audio disclosure includes Watch/imports. Do not claim this screen proves all AI paths are guarded: 3.4.0’s R2 scope is History and Watch; the wider audit is deferred.

Private mode is locked while starting, recording, resuming or finalizing with Stop the recording first. It is not a general ban on user-configured exports.

## Evidence and regression boundaries

[3.4.0 release evidence](../releases/3.4.0.md) owns actual renders/device checks and waivers. The blank selected iPad sidebar label and real resize/accessibility checks remain unverified unless evidence is recorded there. Historical [Settings design](../archive/settings-redesign-plan.md) and [UX implementation/reviews](../archive/account-sending-consent-ux-plan.md) retain detailed rationale; old “not implemented” wording in those archives is not current status.

## Models (local change, 2026-10-29)

Setup, Models lists every supported local model family: Nemotron 3.5 speech transcription (Mac only, downloaded on demand, existing disk-size/removal control), bundled Nemotron speaker separation (Mac/iOS), and CAM++ voice recognition (Mac/iOS, existing observed preparation status). Configure links go to Transcription for feature choices and Voices for remembered identities. No model is enabled, downloaded or deleted merely by opening the tab. Hosted OpenAI/Deepgram/Jev services are covered by Privacy, not presented as local models.

The persisted `sending`, `dataFlow` and `whatLeaves` destinations resolve to Privacy; `models` now resolves to Models. Search/deep-link anchors `sending.overview` and `privacy.models` are deliberately retained under their new owners. Both platforms now render the shared consent row at `privacy.thirdPartyAI`, so the overview's permission Configure link has a real target. iOS Configure within Privacy scrolls the current destination rather than pushing a second Privacy screen.

## Help and explicit reports (local change, 2026-10-29)

Help is available in managed mode, BYOK and signed-out/broken-key states. It shows account/device identifiers, app version/build, OS/architecture, sign-in/key status and the current relevant capture/transcription/cloud/permission preferences as a timestamped snapshot. Refresh details and log recaptures it. These are support context, not proof of account ownership. No hardware serial, user name, raw device name, credentials or meeting content is collected. The legacy `account.deviceID` and `about.support` search anchors now belong to Help.

The report box accepts 4,000 UTF-16 units and an optional reply email. Include diagnostic log is initially on: it includes up to 100 sanitized steps from the last 48 hours (including previous launches), with successful milestones, fixed outcome fields, UTC timestamps, error codes and first/last/repeat counts. The encoded event budget is 32,000 bytes; the local timeline is capped at 300 events and 96 KiB. Uninstrumented legacy errors retain a code-only fallback from the last 15 minutes. Raw debug messages can contain titles/paths/names and are deliberately never attached. Copy all and Preview use the same report as Send; unchecking the option removes those events. No send happens on opening Help, refresh, preview or copy. An explicit Send works independently of automatic diagnostics consent. The UI names the data and email-provider delivery, retains text after failure, and requires a matching accepted receipt before showing success. The backend is additive and must deploy before delivery works.

About puts Acknowledgements last. Both its outer disclosure and per-licence disclosures use `MinitiDisclosureStyle`, including Reduce Motion handling.

CAM++ status distinguishes configured voice features from model residency: Off only when both voice options are off; otherwise show the missing local-speaker requirement, unsupported hardware, not-loaded/preparing/ready/error state. Models and the Voices section use the same state-aware copy. Opening Models never changes the options or starts a download.

Home Feedback (3.5.0): a bottom-right control opens a short message/optional-reply sheet. Uses Help's server-only delivery path with a fixed feedback subject, but no diagnostic log/account details. Both forms share in-flight/cooldown admission and backend burst/hour/day limits. Account's API mode choices use shared `APIModeOptions`, two stacked full-width selectable rows on Mac and iOS, preserving the existing mode/usage-refresh handling.

## Local 3.6.0 delivery and sync status, not released

Cloud now separates Last checked (a completed pass) from Cloud count checked (a successful status read). Old or failed counts are labelled last known; local pending uploads/removals, protected recording/edits and oversized meetings stay visible. A failed count refresh does not undo uploads. See [cloud behavior](cloud-sync.md#local-360-implementation-not-released).

The shared delivery row offers Retry now for pending webhooks and Resend current meeting for terminal failures. Resend rebuilds from current saved data with a new delivery ID, rather than reviving a discarded body. Unavailable/deleted meetings, unfinished processing, missing configuration or save failure explain why it cannot proceed. Storage errors offer Try again; Discard failed remains separate. The same row is used on Mac and iOS. CRM retry behavior is unchanged. [Delivery mechanics and downgrade constraint](patterns.md#saved-ai-and-webhook-delivery-local-360-not-released) and [3.6.0 QA](../releases/3.6.0.md) are authoritative.

A changed webhook URL during final processing or held handoff leaves a visible Try again message. That action explicitly accepts the current URL for the waiting completion; clearing the URL waits for a configured destination. Already released queue rows retain the existing current-URL sender policy. Account changes alone do not cancel configured webhook exports, though old-account AI responses are still rejected.

Stopped-meeting and History AI Update controls show finishing and are disabled while final AI runs, with the same guard on the action itself. Coaching can still recompute locally. Changing a stopped meeting’s template persists the choice and invalidates only the old template job, leaving Summary, Sales and Questions independent.
