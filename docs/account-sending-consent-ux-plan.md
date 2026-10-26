# Account, Sending and consent UX for 3.4.0

Implementation plan for the three user-experience slices Ian chose to hold 3.4.0 for on 2026-10-26: U2 (concise consent), U1 (Sending readable at a glance) and B6a (visible account identity and optional email). The specifications live elsewhere and are not repeated here: U1 and U2 in [reliability-follow-up-plan.md](reliability-follow-up-plan.md) § "User experience additions", B6a in [enrollment-identity-plan.md](enrollment-identity-plan.md) § B6. This document says what gets built, in which files, in which order, with which tests, and what has to be repeated before the release.

## Status

| Slice | What | Repo | Status | Release |
|---|---|---|---|---|
| U2 | Consent screen: compact disclosure, Allow and Not now outside the scroll, truthful copy, same consent version | miniti | planned 2026-10-26 | 3.4.0 build 139 |
| U1 model | `DataFlowSummary` gains groups, a status word per row, one Configure jump, details text, a "not in use" set | miniti | planned 2026-10-26 | 3.4.0 build 139 |
| U1 views | `DataFlowRowsView` rewritten for Mac and iOS; iOS rows navigate to the owning setting | miniti | planned 2026-10-26 | 3.4.0 build 139 |
| B6a api | Email routes guarded for any managed account: no Pro, no cloud allowlist, no user cloud switch | miniti-api | planned 2026-10-26, deploy before the client | any deploy |
| B6a state | `AccountEmailState` in `AppState`, bound to the account id, loaded outside the Cloud tab | miniti | planned 2026-10-26 | 3.4.0 build 139 |
| B6a account | `ManagedAccountSettingsSection` restructured into Your account, Ways to sign in, Devices, Plan and billing; eight states with their copy | miniti | planned 2026-10-26 | 3.4.0 build 139 |
| B6a home | "Keep access to your account" card replaces the recovery key nudge; per-account dismissal | miniti | planned 2026-10-26 | 3.4.0 build 139 |
| B6a copy | Recovery key language, sheets, Cloud tab link, restore wording per platform | miniti | planned 2026-10-26 | 3.4.0 build 139 |
| Review | Astra pass after each slice; findings fixed before the next slice starts | both | planned | before build 139 |
| QA | A5 repeat on build 139 plus the U2, U1 and B6a lines below | both | planned | release gate |
| Release | RELEASE.md steps 1 to 10 with build 139 on both platforms; the 137 DMG and the 138 TestFlight build are discarded | both | planned | after QA |

## Decisions taken while planning

- **Version stays 3.4.0.** Nothing shipped. Build 139 on both targets (the Mac DMG was 137, the TestFlight build 138; both are superseded). `CURRENT_PROJECT_VERSION` and `CFBundleVersion` are set by hand before the Mac lane, as RELEASE.md step 1 says.
- **Order: U2, U1, B6a.** Smallest and most isolated first. Each slice is one commit series, reviewed by Astra, with its findings fixed before the next starts. The B6a backend change goes first within B6a so the client is tested against the deployed contract.
- **U2 keeps consent version 2.** Recipients (Deepgram, OpenAI), data categories and purposes do not change; the rewrite drops claims that were not true ("audio is never stored", "nothing leaves this device") and shortens the rest. Nobody is asked again. If implementation finds a recipient, datum or purpose that was missing from version 2, the version is bumped deliberately and this file says why.
- **Email guard.** Email read, add and remove require device authentication with proof, the configured cloud store (Neon) and email delivery, and the existing per-account `cloud_manage` rate limit. They no longer require Pro, the cloud rollout allowlist or the person's cloud switch. BYOK stays refused (`cloud_requires_managed`). The server-wide `CLOUD_SYNC_ENABLED` switch still applies because the email lives in the same store; it is an operator kill switch, not a user gate.
- **Cloud tab keeps web sign-in, loses the email form.** Settings, Cloud links to Settings, Account for the address. Web sign-in and new-device approval keep working exactly as today with the account's email.
- **iOS gets email management for the first time.** Today the iPhone has no add, change or remove email control at all (only Join by email and the Cloud tab's web sign-in). The shared `ManagedAccountSettingsSection` carries it, so both platforms get the same section.
- **The Home card trigger is "first saved meeting on an enrolled managed account".** Today the key nudge shows as soon as the account exists. Moving it after the first meeting is what B6a specifies; the first launch stays uninterrupted.
- **Not in this batch:** A4's choice state, any change to automatic enrollment, account merge, compulsory email, B1 subscription ownership, the Linux implementation (a note in `../miniti-linux/PLAN.md` only), the R-series reliability fixes. U1 states what the code routes today; it does not claim R1 or R2 are fixed.

## U2: concise consent

**Files:** `Miniti/Views/TermsAcceptanceView.swift` (shared by both targets), `AppState.currentTermsVersion` (unchanged, 2), `MinitiTests/AppStateComputationTests.swift` (consent gate tests, extended).

**Layout.** `VStack { header; ScrollView { disclosure }; actionBar }`. The action bar is a sibling of the ScrollView, never inside it, with the safe area respected on iOS and a thin top divider. The hexagon and the 28 pt lockup go; a single `miniti` lockup at the existing monospaced identity size for a title bar remains. Vertical padding 40 becomes `MinitiDesignSystem` section spacing. Buttons keep their current styles and accessibility labels. On compact widths (iPhone, narrow Mac window under 420 pt) the two buttons stack vertically, Allow first. Reduce Motion drops the fade-in.

**Copy, final, checked against the code paths:**

> **Use cloud transcription and AI?**
>
> **Deepgram** receives live audio, the meeting title and attendee names, and returns the transcript.
>
> **OpenAI** receives the transcript, your notes, the meeting title and attendee names, and returns summaries, action items, questions and speaker names.
>
> On the managed plan, audio goes straight from this device to Deepgram and text goes to OpenAI through miniti. With your own keys, both go straight to the provider.
>
> Choose Not now and miniti still opens: you can read, import and export meetings, and recording asks again. Change this any time in Settings, Privacy.

Below, in the dim style: "Privacy policy · Terms". On macOS one more line: "Private mode in Settings, Privacy keeps transcription on this Mac." Removed: "audio is never stored" (Watch recordings and imports are files the app holds; Deepgram's retention is theirs to state), "nothing leaves this device until you allow it" (the version check and managed enrollment run before consent), "two companies" (TypeSafe, the docs server and webhooks are separate opt-ins with their own disclosure).

**Behaviour unchanged:** `allow` calls `setThirdPartyAIConsent(true)`; `decline` on the first screen records the declined version, on the sheet dismisses without writing; `hasAcceptedTerms` still gates every recording start and network insight; presenting the screen sends nothing.

**Tests.** Existing consent-gate tests stay. Add: the disclosure strings name both recipients and the four data categories (title, attendees, audio, transcript and notes), so a later edit cannot drop one silently; the terms version is still 2 and the test fails with a message pointing here if it changes; decline on the sheet leaves acceptance untouched.

**QA.** First launch and the Settings, Privacy sheet on the Mac at the minimum window size and at the default; iPhone SE size and iPad; macOS display scaling; the largest accessibility text (actions stay visible, body scrolls); VoiceOver reaches both buttons and both links; keyboard: Return allows, Escape cancels on the sheet; Reduce Motion. Capture the Mac first run on a fresh user, the case that needed scrolling.

## U1: Sending readable at a glance

**Files:** `Miniti/Models/DataFlowSummary.swift` (model and shared view), `Miniti/Views/SettingsView.swift` (`SendingSettingsView`), `MinitiMobile/Views/SettingsView_iOS.swift` (the Sending detail, line 819 today), `MinitiTests/DataFlowSummaryTests.swift`.

**Model.** `Row` gains `group: Group` (`.transcriptionAndAI`, `.syncAndExports`, `.accountAndConnections`), `status: Status` (`.usedForRecordings`, `.onRequest`, `.automaticExport`, `.off`, `.paused`, `.notConnected`, each with its text), `summary: String` (one line, essential data and purpose), `details: String?` (payload, retention, path, the longer text that lives under Details today), `configure: Jump?` (exactly one), `inUse: Bool`. `DataFlowSummary` gains `groups: [(Group, [Row])]` in a fixed order and `notInUse: [Row]` (unconfigured or disabled optional recipients, with a reason each). `sends` goes. The header line becomes `headline: String`: while recording, one sentence from the latched session engine ("This recording: audio to Deepgram, transcript to OpenAI" / "This recording: transcribing on this Mac, transcript to OpenAI" / "This recording stays on this Mac"); otherwise "Based on your current settings. This is a routing summary, not a network monitor." The live sentence reads `sessionTranscribesOnDevice` and `isRecording`, never the next-session preference.

**Rows and their status words** (the model decides, the tests assert the text):

| Row | Group | Status when on | Summary (one line) | Details |
|---|---|---|---|---|
| Deepgram | Transcription and AI | Used for recordings / Off / Paused (private mode) | Live audio, meeting title and attendee names, for the transcript | Straight from this device; managed mode supplies a token; on-device transcription sends audio only when the language model is not ready; speaker separation note |
| OpenAI | Transcription and AI | Used for recordings / Off / Paused | Transcript, notes, title and attendees, for summaries, action items, questions, speaker names and the enabled extras | Through miniti on the managed plan, straight with your key; catch-up and investigations on request |
| TypeSafe (Jev) | Transcription and AI | Used for recordings / Off | The last minutes of transcript, for the sales nudge and speaker names | Managed only, opt-in |
| Your docs server | Transcription and AI | On request or Used for recordings (per tier) / Not connected | Short searches drawn from the transcript, for Playbook | Through miniti on the managed plan; the transcript itself is not sent |
| miniti cloud | Sync and exports | Automatic export / Off / Paused (with the pause reason) | Finished meetings, so your other devices see them | Pro, account-level switch, per-meeting keep-off, private-mode meetings never |
| Webhook | Sync and exports | Automatic export / Not connected | Each saved meeting as JSON, including the transcript | Https only; allowed in private mode because you configured it |
| Attio or Twenty (Mac) | Sync and exports | Automatic export / On request / Not connected | Title, summary, notes and action items; never the transcript | Which CRM is automatic |
| miniti account | Account and connections | Used for recordings (managed) / On request (BYOK: version check) | Device id, app version, minutes used | Enrollment, usage checks, the version check at launch |
| Diagnostics | Account and connections | Automatic export / Off | Errors and reconnects, never transcript or audio | Share Diagnostics |
| Google Calendar | Account and connections | Used for recordings / Not connected | Upcoming events are read through miniti; nothing is written | Read only |
| Saved audio on this device | footer, not a row | | Watch recordings and imports are files on this device until transcribed | |

"Used for recordings" means the route is taken when a recording runs; it never claims traffic right now. The footer keeps "Stays on this device: history, search, export, coaching, voice fingerprints". Rows never reorder with recording state; `notInUse` holds the optional recipients that are off, with a count ("3 not in use") and a reason each on expansion; Deepgram and OpenAI are always in their group, even when off.

**Views.** Mac: a `Form` with three `Section`s titled by group, each row a two-line layout (title and status on one line, summary wrapping below), a `DisclosureGroup("Details")` only when `details` exists, and one `Configure` link button that calls `jumpToSetting`. A final `Section("Not in use")` is one `DisclosureGroup` with the count in its label. Thin dividers, no cards, no coloured dots. iOS: the same structure in the Sending detail; `Configure` is a `NavigationLink` to the owning detail. `jumpToSetting` is Mac-only today because iOS Settings is driven by `NavigationStack` paths; U1 adds `SettingsDestination_iOS(for: catalogID)` that maps the catalog ids the rows use to the iOS detail destinations, and a test asserts every configure target has a mapping on both platforms. Text never truncates; status stacks under the title under 360 pt. VoiceOver: title, status, summary read as one element; Configure and Details stay separate actions.

**Copy truth rules** applied in the model text: no "nothing leaves", no "nothing about your meetings", no "nothing is stored" anywhere; audio path and text path stated separately; voice prints named as local; private mode described as pausing cloud AI, not as a network ban (webhook and CRM rows stay visible and active in private mode when configured).

**Tests.** Rewrite `DataFlowSummaryTests` around the table: for managed defaults, BYOK, consent unanswered and declined, on-device transcription with and without fallback, private mode with a configured webhook and CRM, cloud on, off and paused, calendar connected, diagnostics off, recording with each engine, assert the group, the status text and the summary of the affected rows, not row counts; every `configure` target exists in `SettingsSearchCatalog` and in the iOS destination map; the headline follows the latched engine; the not-in-use set matches the off switches; no text contains the banned phrases.

**QA.** Rendered on the Mac at the minimum Settings window and the default, iPhone compact, iPad, large text; long webhook and docs hostnames wrap; each Configure opens the right place on both platforms; details collapsed still show recipient, status and summary; keyboard and VoiceOver reach every control; Ian reviews the rendered layout before the slice is called done.

## B6a: visible account identity and optional email

### Backend first (miniti-api)

**Files:** `lib/cloud.ts` (new `requireManagedAccountDevice` or an option on `requireCloudDevice` that skips the allowlist and tier checks), `app/api/account/email/route.ts` (uses it), `app/signin/confirm/route.ts` (unchanged: it consumes a `confirm_email` link and needs the store, not the allowlist), `app/api/auth/email/start|status` (unchanged: they already run on the store guards and their own limits), `docs/agents/08-cloud.md` (the email contract moves to "any managed account"), the route tests.

**Contract.** `GET /api/account/email` and `POST`/`DELETE` answer for any enrolled managed device: 401 without device auth, 403 `cloud_requires_managed` for BYOK, 503 `cloud_unavailable` when the store or the server switch is off, 503 `email_unavailable` when delivery is not configured, 429 on the per-account limit, 409 `email_in_use` unchanged, 202 with `pending` on send. The web sign-in page, tokens, connected apps, sync push and pull keep every gate they have. Removing an email still revokes web sessions and connected apps and the response still says how many.

**Tests.** A free account with the cloud switch off and no allowlist entry adds, reads and removes an email; an account outside the allowlist adds an email and is still refused on `/api/cloud/*`; BYOK refused; store off refused; the existing collision, pending and removal tests pass unchanged. Then `vitest`, `tsc`, `eslint`, push (deploys), confirm with a curl against production from an enrolled free account before the client work starts.

### Client state (`AppState`, `MinitiAPIService+Cloud.swift`)

`AccountEmailState`: `.loading`, `.unavailable(message)`, `.none`, `.pending(address)`, `.verified(address)`. Published on `AppState`, loaded by `refreshAccountEmail()` on enrollment, on the account id changing, when Settings, Account appears, and after add, remove and resend. Every response is bound to the account id captured at request time; a response for another account is dropped (the A-to-B rule from A2d's bookkeeping reset). A failed fetch is `.unavailable`, never `.none`. The three API calls move out of the cloud-gated path: they use the ordinary managed request path and do not check `cloudSyncEnabled` or the pause reason. `CloudSettingsView` stops loading email and shows "Email: Settings, Account" with a jump. iOS has no Cloud email form today, nothing to remove there.

Persisted per installation, keyed by account id: `accessCardDismissedAt`, `accessCardFollowUpShown`. `showRecoveryKeyNotice` is replaced by `showAccessCard`, true when: managed and enrolled, at least one meeting saved on this installation, not recording, no verified email, recovery key not acknowledged for the current key, not dismissed for this account (or one follow-up allowed after Pro purchase or restore or first cloud enable, coalesced, once). Key rotation clears the acknowledgement; the existing `markRecoveryKeyAcknowledged` stays.

### Account section (`ManagedAccountSettingsSection`, shared by both targets)

Four groups inside the existing Account tab (tab names stay single words):

1. **Your account.** Verified email in full with "Verified", or "No email yet", or "Check your email: link sent to address" with Resend (rate-limit wait shown) and Change. Plan line: "Free" / "Pro" / "Pro, from another device on this account". A disclosure "Support details" holds the account id, device id, key kind (Secure Enclave or software) and the app build.
2. **Ways to sign in.** Email row: Add email / Change / Remove (Remove states: web sessions and connected apps on this account stop; whether a recovery key is still available). Recovery key row: "Saved" or "Not yet saved" with **Show recovery key** and **Replace recovery key** (confirmation explains: the old key stops working, signed-in devices stay signed in, save the new one). Email-joined device: "This device does not hold the recovery key. Show it on a device that does, or replace it here." Key unusable: "Sign in again" (email or recovery key through `reauthenticate`) and Try again for temporary errors; the old credential stays until the server accepts the new key. Switch account: the existing move sheet, renamed "Switch account", with its consequences line. "Address belongs to another account": the 409 copy offers Switch account, never merge.
3. **Devices.** Unchanged list and cap; the removal confirmation says "It can sign back in with the account's email or recovery key."
4. **Plan and billing.** Mac: "Restore Pro purchase with a license key" plus "This restores a purchase. It does not sign you into an account." iOS: "Restore App Store purchases". A line for new devices: "Bought Pro already? Sign in to that account first." Sign out this device and Delete account move to the end, under a divider, in the error colour as today; the sign-out confirmation names both ways back in.

The unenrolled rows keep today's policy and copy except that the retry text offers "Sign in with email" beside "Restore with recovery key". No new state machine: `awaitingChoice` is A4.

Loading and offline: while `AccountEmailState` is `.loading` the email row shows a progress view; `.unavailable` shows "Could not check this account's email" with Retry and no nudge anywhere.

### Home card (`RecoveryKeyNudgeCard` becomes `AccountAccessCard`, both `MeetingView`s)

Title "Keep access to your account". Text "Add an email so you can sign in on another device or recover access if this one stops working. This won't turn on cloud sync." Buttons: **Add email** (opens the Account section with the email field focused, or an inline sheet on iOS), **Use a recovery key instead** (the existing key sheet, which sets the acknowledgement), **Not now** (dismiss for this account). Pending verification shows the card in its quiet form: "Check your email to finish" with Resend. Never shown while recording, during onboarding, over the consent screen or over a recovery sheet. Same `MinitiDesignSystem` card tokens as today.

### Copy sweep

`RecoveryKeySheet` ("This key is your Miniti account. It is the only way…") becomes "Another way to sign in. Save it somewhere safe: it signs this account in on a new device if you have no email, or if email is unavailable." `RestoreRecoveryKeySheet` and `EmailSignInSheet` titles say "Sign in with a recovery key" and "Sign in with email". The sign-out and removal dialogs name both methods. The Cloud tab's "email cannot enroll a device" sentence goes. Every sentence is checked for em dashes and for "miniti" lowercase.

### Tests (client)

`ClientAuthTests` and a new `AccountEmailStateTests`: state reducer for the five states; A-to-B discard; failed fetch is unavailable; add then pending then verified after a refresh; remove returns to none; `showAccessCard` rules (first saved meeting, not recording, dismissed per account, verified suppresses, acknowledged suppresses, rotation un-suppresses, one follow-up after Pro or cloud enable); the Account section copy table: for each of the eight states a test asserts the primary action title and the sentence shown (through a small view model, `AccountSectionModel`, so the views stay thin); the Mac and iOS restore button titles; no banned phrase ("only way", "your account is", "Reveal", "Rotate", "Create one") in the account copy. Full macOS and iOS bundles green.

### QA (B6a)

On the throwaway Mac user and a throwaway iPhone account (never the personal Pro account): free account, cloud off, add an email, confirm the link, see it verified in full on both devices; resend and expired link; collision with the other throwaway account's email offers Switch account; remove email shows the consequences and returns to "No email yet"; the Home card appears after the first saved meeting, not before, not while recording, dismiss persists across relaunch, verified email removes it; Show and Replace recovery key with the explained consequences; an email-joined device shows the right sentence; the A2d key-unusable copy still offers Sign in again (repeat the same-Mac second-user copy); Account at the minimum Mac window, iPhone, iPad, large text, VoiceOver; existing credentials, keys and subscriptions unchanged before and after (compare the admin device list).

## Build, review, QA repeat, release

1. Each slice: implement, tests green on macOS, iOS bundle compiles (full iOS run at the end), commit, paste block for Astra, fix findings, commit.
2. After B6a: bump to build 139 (pbxproj every target, `Miniti/Info.plist`), changelog bullets added under the unreleased 3.4.0 entry (drafts below), iOS release notes mirrored, `fastlane mac test` and `fastlane ios test`.
3. A5 repeat on build 139, because the auth views changed: fresh user enrols once; credential deleted then relaunch rotates once; the same-Mac second-user copy of a Secure Enclave credential repairs at the first signing attempt; the first user re-binds on relaunch; locked keychain Cancel creates nothing; iPhone TestFlight upgrade keeps Pro and records. Then the U2, U1 and B6a lines above.
4. RELEASE.md steps 1 to 10 with 139. The Mac DMG is rebuilt by `fastlane mac release`; the appcast values from the 137 build are discarded. iOS: `fastlane ios beta` with `build:139`, then `fastlane ios metadata` and `fastlane ios submit version:3.4.0 build:139`.

**Changelog drafts** (final wording at build time, in the changelog skill's voice):

- new: (macOS and iOS) Settings, Account shows your account the way you think of it: your verified email, how you sign in, your devices, your plan. Add an email on any account, free or Pro, with cloud off. It is the easiest way back in on a new device
- improvement: (macOS and iOS) the recovery key is a backup, not your account. Show it or replace it from Settings, Account, with plain words about what each does
- improvement: (macOS and iOS) Settings, Sending is three short groups: transcription and AI, sync and exports, account and connections. Each row says who gets what, whether it is used for recordings, on request, automatic or off, with one Configure link
- improvement: (macOS and iOS) the first-run permission screen is shorter and Allow and Not now stay on screen without scrolling

## Open questions

None that block the start. Two to confirm during review: whether the Home card's one follow-up after Pro purchase is wanted at all (the plan allows it; the simplest build omits it), and whether iOS should open an inline email sheet from the Home card or navigate to Settings, Account (the plan says either).
