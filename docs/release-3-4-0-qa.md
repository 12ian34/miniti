# 3.4.0 build 139 release QA

Consolidated manual QA for the 3.4.0 tree (through `28d247b`), written 2026-10-27. Tick each line with the device, date and result. Automated state before QA: macOS 1,037 tests and iOS 976 tests, zero failures, three skips each. This file authorises nothing: the Sparkle update, the website and the App Store submission wait for Ian's separate go.

Sources: enrollment plan A5 lines, [account-sending-consent-ux-plan.md](account-sending-consent-ux-plan.md) U2/U1/B6a QA, [reliability-follow-up-plan.md](reliability-follow-up-plan.md) R1–R3 device checks, [audio.md](audio.md) "Initial microphone failure".

Setup once: a throwaway macOS user (`iantest`) on imbp, a throwaway iPhone account on TestFlight build 139, never the personal Pro account for anything destructive. Keep keys and tokens out of notes. Read the debug log from Settings, Support after each step; admin events via `node ../miniti-api/scripts/admin-stats.mjs events --name client_auth`.

## 1. Builds

- [ ] `fastlane mac test` and `fastlane ios test` green on the combined tree.
- [ ] Mac DMG built by `fastlane mac release`, `scripts/release-info.sh` reports 3.4.0 build 139; installed over 3.3.0 on the personal account (reads only) and launched.
- [ ] iOS build 139 on TestFlight, installed over 3.3.0 on the personal iPhone.

## 2. A5, enrollment and keys (throwaway Mac user, build 139)

- [ ] Fresh user: first launch enrols once (one migrate 404, one create in the debug log), recording works.
- [ ] Delete the credential item, relaunch: silent recreate, server conflict, one rotation, created; admin events show `client_auth_device_rotated` once.
- [ ] Copy the credential and device id items into a second throwaway user, start a recording: `client_auth_key_unusable reason=sign:CryptoTokenKit:-10` then `client_auth_key_repaired` within seconds, same device id, recording proceeds.
- [ ] Relaunch the first user, start a recording: it re-binds with the recovery key and records (ping-pong between the two copies, no new account).
- [ ] Lock the login keychain, launch, Cancel the unlock dialog: nothing created, error says it could not save its sign-in.
- [ ] Settings, Account on the second user after the repair: Ways to sign in shows the key as usable again; Try again is not offered.
- [ ] macOS 26: not available; waived for this release (recorded in the enrollment plan).

## 3. Consent, U2 (Mac and iPhone)

- [ ] Fresh user first launch: both buttons visible at the minimum Mac window without scrolling; Return allows; the first screen ignores Escape.
- [ ] Settings, Privacy sheet: Escape cancels and leaves the stored answer alone.
- [ ] Largest accessibility text: body scrolls, Allow and Not now stay visible, footer never covers content.
- [ ] VoiceOver reaches both buttons and both links.
- [ ] iPhone SE size and iPad: same checks; the iPhone copy names watch recordings.

## 4. Sending, U1 (Mac and iPhone)

- [ ] Three groups, one status word per row, one Configure per row, Not in use folded with a count.
- [ ] Each Configure opens the right setting on the Mac; on the iPhone it navigates to the owning detail and scrolls to the row.
- [ ] While recording with Deepgram, switch private mode is refused (R1); the headline and the Deepgram row still say this recording goes to Deepgram.
- [ ] Minimum Mac Settings window and large text: nothing truncates, status stacks under the title when narrow.

## 5. Account and email, B6a (throwaway accounts only)

- [ ] Free account, cloud off: Add email, open the link in the browser, Account shows the full address with Verified without a relaunch; Support details show the same account id as before; cloud still off.
- [ ] Open the link on the other device instead: the first device picks it up on activation.
- [ ] Change the address: verified plus "Replacement pending" shown together until the new link is opened.
- [ ] Resend, and an expired link.
- [ ] Collision with the other throwaway's email: the message offers Switch account, nothing merges.
- [ ] Remove email: consequences sentence, returns to No email yet, web sign-in refused afterwards.
- [ ] Home card appears after the first saved meeting, not before, not while recording, not while offline; Not now persists across relaunch; a verified email removes it.
- [ ] Show recovery key and Replace recovery key, with the explained consequences; Switch account by email and by key.
- [ ] Key unusable (second-user copy before the repair, or a test build): Show recovery key kept, Replace, Add, Change, Remove email and Delete account hidden, Sign in again succeeds.
- [ ] Sign out offline with a healthy key: refused with the connection sentence, still signed in; online: signed out, Home clean.
- [ ] The Devices row's Sign out for this device behaves exactly like the bottom button.
- [ ] Account tab at the minimum Mac window, iPhone, iPad, large text, VoiceOver; the iPad sidebar's selected row shows its label (open question from the simulator render).
- [ ] iPad: Sending, Configure Cloud, then the Home card's Add email lands on Account at the root; resize the window across the size-class boundary and back, the visible screen survives.
- [ ] Existing credentials, keys and subscriptions unchanged on the personal devices (compare the admin device list before and after).

## 6. R1 to R3 on devices

- [ ] R1: start a cloud recording, open Settings, Privacy: the private mode switch is disabled with "Stop the recording first"; stop, switch it on, the next recording transcribes on the Mac; start a private recording, the switch cannot be turned off until stop.
- [ ] R2 History: Settings, Privacy, withdraw permission; History, Update on a saved meeting shows the permission sheet and the debug log shows no insights request; allow, Update works.
- [ ] R2 Watch (iPhone): withdraw permission, record on the watch, let it transfer: History shows the recording waiting for permission, the audio stays, no grant in the log; allow in Settings, Privacy: it transcribes once, without a tap.
- [ ] R3: on a Mac with cloud on, start a sync by pressing Sync now and immediately Switch account (throwaway accounts): no meeting from the old account appears under the new one, the Cloud tab shows the new account's status, no pause from the old account's answer.

## 7. Audio, the microphone failure path (Mac)

- [ ] AirPods Max (or any Bluetooth headset) microphone selected in the Home mic pill, mic plus system audio, a call app also using the headset: start recording. If the mic fails to start, remote speech keeps transcribing, the warning names the microphone, and the mic recovers within the three retries; own speech returns on the left channel without doubling the remote speech.
- [ ] Stop during the retry window: stops cleanly, no late warning, no second meeting.
- [ ] Switch output between Mac speakers and the headset mid-recording: transcription continues, counters keep moving.
- [ ] Built-in microphone selected: both sides transcribe.
- [ ] System-only and mic-only recordings, and a recording ended during the grace period.
- [ ] Transcript health lines in the debug log show converted buffers from every requested source within two seconds of start.
- [ ] Floating surface during a recording with a calendar handoff due: all four actions show their full names on two lines (Jose's report, 2026-10-27).

## 8. iPhone TestFlight 139

- [ ] Upgrade over 3.3.0 keeps the Pro account and records.
- [ ] Restore App Store purchases wording and sentence under Plan and billing.
- [ ] Email sign-in error copy: a dropped connection while waiting for the link says so, not "expired link".
- [ ] Live Activity and watch transfer unchanged.
