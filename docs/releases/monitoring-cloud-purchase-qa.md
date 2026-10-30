# Monitoring, cloud privacy and purchase return: QA handoff

Release reconciliation, 2026-10-30: macOS 3.5.0 build 142 is live; backend/site are deployed; iOS build 142 is submitted, not confirmed available. [Release record](3.5.0.md) is authoritative for current delivery status. This handoff retains dated pre-release checks and commands; historical "local/unreleased" or "nothing sent" statements below describe those checks, not current deployment. Ian reported the grouped device/provider QA good; individual checks were not independently witnessed in this record.

Plans: [O1–O6](../plans/logging-and-monitoring.md), [C1](../plans/selective-cloud-privacy.md), [B6d](../plans/purchase-return.md). [Implementation contract](../reference/monitoring-cloud-purchase.md). Completing one plan does not imply the others are released.

## Pre-release automated snapshot (superseded by release record)

Latest Apple lanes (2026-10-30, `fastlane mac test` and `fastlane ios test` after the runner-only test fixes): macOS 1,072 executed / 3 skipped, iOS 1,010 executed / 3 skipped, zero failures; an earlier same-day run on this Mac showed 4 Mac skips because audio was playing. Latest backend: 658 passed / 5 skipped, typecheck/lint clean. Exact logs and change-specific evidence are recorded in the dated sections below; earlier totals are historical runs. Mac Home/feedback, Account mode layout and other listed Mac renders are verified. Real two-device cloud checks, sandbox checkout, compact/accessibility renders, inbox/alert delivery and UptimeRobot activation remain open. No commit, deployment or release is implied.

## Initial automated evidence (superseded totals, retained storage evidence)

- Backend full Vitest: 650 passed, 3 skipped; TypeScript and ESLint clean. This run included real Redis Lua and PostgreSQL/PGlite SQL checks. The remaining skips do not count as verification of Neon transport or production configuration.
- Initial Apple full suites: macOS 1,054 executed, iOS 992 executed; each 3 skipped, zero failures. Latest binaries were built with the corrected fixture, then the entire bundles passed with `test-without-building`. Logs: `/tmp/miniti-verified-mac.log` and `/tmp/miniti-verified-ios.log`.
- A new creation-path fixture initially failed because its calendar JSON omitted required start/end fields; corrected fixture passes on both platforms. It exercises a refused start retaining its choice, exclusion before capture, the next ordinary meeting, late association and sticky exclusion. No production behavior was changed to satisfy the invalid fixture.
- Existing held-transport cloud cases cover first upload then exclusion, delayed pull/delete, pending explicit restore and preservation of local originals. Real SQL covers exact revision, transcript guard, concurrent writers and account isolation.
- Diagnostic fixtures cover held flush plus new arrivals, simultaneous flush, account/consent clear, lost-response retry, relaunch/backoff, redaction, incident delivery to a test sink, cooldown and delayed events. Initial Deepgram completion tests cover 401/402/429/5xx, timeout, cancel and stale callbacks, not an actual provider refusal on hardware.
- Purchase tests cover fixed checkout correlation/account capture, unpaid/foreign checkouts, exact subscription readiness, duplicate callbacks, identity change, deadline and throttling. `node scripts/test-purchase-return.mjs` passes malformed/duplicate/platform and explicit-click cases.

Storage reproduction (isolated local services only):

```sh
# miniti-api; supply your local redis-cli/port and optional PGlite install path.
DIAGNOSTICS_REDIS_CLI=/path/to/redis-cli DIAGNOSTICS_REDIS_PORT=16379 \
SYNC_TEST_PGLITE_MODULE=/path/to/node_modules/@electric-sql/pglite/dist/index.js \
npx vitest run
npx tsc --noEmit
npm run lint
```

The temporary validation dependencies were outside the repositories; no production Redis or Neon write was used for these checks. Standard test runs skip these integration fixtures if their opt-in environment is absent.

## Rendered evidence and limits

Mac Debug: inspected Home's pre-recording choice and Settings, Cloud rules. No recording, cloud toggle or deletion was performed. The rules were subsequently moved ahead of status/web/deletion, and the preview gained an account fence. That final ordering still needs a render. Minimum window resizing was not verified. The app was opened on the existing profile, so background app behavior was possible; this was not an isolated synthetic-profile render.

The local website preview could not be reached by the in-app browser. Its JS contract tests passed, but its rendered layout is unverified. Compact iPhone, iPad, large text and VoiceOver remain open. Do not mark these checks complete from unit tests.

## Device QA Ian can run once the QA build is supplied

UX updated after Ian's 2026-10-29 review: the Home checkbox is removed. Use the new live/saved toolbar button instead; the earlier Home render evidence is superseded.

1. **Cloud/Local, Mac and iPhone:** with cloud enabled, start a synthetic meeting, click Cloud at the top right to choose Local, speak briefly, stop/save. Check the confirmation, crossed-out icon and retained local meeting; verify absence on the other device/web/API. The next normal Cloud meeting should sync.
2. **Rules:** Settings, Cloud → Add rule opens an editor. Enter `QA therapy`, save, preview a dummy matching calendar event and start it. It starts Local. Switch to Cloud to override this meeting; a late calendar update must not undo that choice. Remove the rule and verify existing exclusions stay excluded. A running private-mode recording cannot be opted into cloud.
3. **Existing copy (after backend deployment):** open a saved synced test meeting, choose Local while offline, check removal pending and the local original. Reconnect and confirm removal, then choose Cloud to restore without losing content. Test account changes while sync is held.
4. **Audio/diagnostics:** normal speech and ordinary silence; controlled unavailable microphone and initial provider refusal/timeout; useful failure copy and successful retry. Diagnostics off/BYOK sends no diagnostics.
5. **Layout:** same button style as Stop/Investigate/Zoned out, at top right in live and saved detail; four-second confirmation does not block controls. Mac minimum window, compact iPhone/iPad, large text and VoiceOver. Watch/imports are not covered by new rules.

## Purchase QA (sandbox, not a real charge)

Use a Polar sandbox token/product with the callback page and backend configured together in a test environment. Do not substitute a fabricated successful callback for a paid checkout test.

- Complete a purchase, return with miniti already open, then repeat with it quit. Account opens, initially confirming if needed, and shows Pro ready only after the matching webhook/entitlement.
- Delay the webhook, cancel/leave checkout unpaid, disconnect the app and test throttled/manual retry. The 30-second task stops and leaves useful retry/fallback instructions.
- Repeat a callback; sign out or switch accounts during a held check. No duplicate flow, transferred entitlement or stale usage is applied.
- Check old/absent Mac app, Linux and unknown-platform page fallbacks. Receipt/license restore remains available. iOS StoreKit is unchanged.
- Inspect the HTTPS page on narrow and wide browsers. Checkout IDs must be removed from the URL before analytics and never become analytics properties or visible link attributes.

## UptimeRobot and production activation

Ian's free UptimeRobot account provides HTTP monitoring; sign in at activation time. **No monitor is created yet.** It would report a false outage while the endpoint is undeployed.

After deployment, add an HTTP monitor for `https://api.miniti.app/api/health/monitoring`, every 5 minutes, expecting HTTP 200, with Ian's chosen existing alert contact. No auth header or secret is needed; the route exposes only a health bit. This does not change the hourly incident/provider cadence.

The route remains unavailable until jobs/check state and accepted digest evidence are fresh. Inspect the authenticated admin data for the cause; never fabricate heartbeats or send dates to turn it green. Deployment does not prove mail reached an inbox. Confirm the destination and authorize one controlled alert/recovery mail test before performing it. Verify a controlled stopped-job/mail-failure scenario through staging or a dedicated test monitor, without disabling production protections casually.

## Delivery order and rollback

1. Finish the listed local/device/sandbox checks and review the diff. Choose release version/build.
2. With deployment authorization, deploy the HTTPS return page first, then additive backend contracts. Pushing backend main deploys automatically. The website push for the page must be scoped to the purchase page and its test script: the regenerated changelog, the new screenshots and the LLM text in the same working tree describe the unreleased build and go live only with the apps.
3. With the site and backend live, complete the QA that needs them before any client ships: real two-device cloud deletion and restore, the sandbox purchase return with the app open and quit, one authorised Help report and one Feedback message confirmed in the inbox, real cron state, UptimeRobot activation and the approved mail-path check. Public Help/cloud docs are updated for the actual shipping build, not prematurely published from this local status.
4. Only then run the release lanes, repeat the relevant 3.4.0 A5 checks, and distribute the apps.

`PURCHASE_RETURN_ENABLED=off` stops new callback URLs while keeping the page/receipt fallback. `OPS_CLIENT_INCIDENTS=off` disables only the new incident policy; document the resulting reduced coverage. Keep diagnostic queue compatibility and additive receipt handling on rollback. Cloud rollback must preserve existing exclusions, pending deletions and explicit restore intent; do not revert the backend restore support while new clients still depend on it. Ownership B0–B3 and Linux parity remain separate plans.

## UX revision after Ian's QA, 2026-10-29

The rejected Home checkbox is removed, including calendar preparation/countdown variants. Blue Cloud/Local lives in live and saved meeting toolbars, with a four-second confirmation and honest conditional/pending copy. Add rule now opens a focused sheet; Save validates blank, duplicate, length and capacity. Explicit live choices override later title-rule associations; private recording protection remains. Focused cloud suites passed 40 tests on each platform before the final pending-status render polish. Full rerun and rendered evidence are recorded below.

The screenshot fixture was also corrected to reapply after root model-context wiring/restoration, so synthetic recording previews actually show the live toolbar instead of Home. This affects screenshot mode only.

Final toolbar/editor verification: the full macOS bundle executed 1,056 tests, 4 skipped, 0 failures; the full iOS bundle executed 994 tests, 3 skipped, 0 failures. The extra macOS skip was the silence-from-birth audio test: the test detected audio playing on this Mac, so its required silent condition was unavailable. The final toast-placement-only polish was rebuilt successfully on iOS and included in the macOS full run. Native macOS inspection using the seeded in-memory screenshot store confirmed the live Cloud control at the far right beside the recording actions, the Local icon/label and confirmation, saved detail in both states with pending-removal/restore text, and Add rule opening a focused editor and saving a test rule. Confirmations sit at the bottom right so they do not cover the control. The synthetic runs restore the user's defaults on exit. Compact-device/accessibility and real two-device/backend deletion/restore checks remain the manual gates above.

## Settings regrouping, 2026-10-29

Ian requested the data-flow overview inside Privacy and a Models destination under Setup. Implemented on both Apple platforms, including old Sending destination migration and retained search anchors. Models lists supported local speech (Mac), speaker and voice models with existing controls/Configure links. The shared permission row now renders on iOS at the overview's existing permission target. No model activation or download policy changed.

Verification: macOS targeted Settings/data-flow suite, 222 tests, 0 failures; iOS Settings/data-flow/navigation suite, 208 tests, 0 failures. Both Debug targets built. Native Mac review confirmed Models in Setup, all three local model families, voice Configure landing and scrolling to Transcription, Voices, and Privacy containing both controls and the overview. Real iPhone/iPad layout/accessibility remains part of device QA. Historical 3.4.0 Sending evidence is unchanged.

## Help/reporting and About, 2026-10-29

Local O5: support details moved from Account into Help, shown expanded. The default-on log option adds only bounded sanitized diagnostic fields (extended by O6), not raw debug strings. Preview and Copy all use the same payload as explicit Send; optional reply email and a bug description are user supplied. Old Device ID/support search anchors now reach Help. About acknowledgements moved last and both disclosure levels use the shared style.

Native Mac render checks: expanded metadata, default checked inclusion, report preview, About order and acknowledgement expansion. No Send action was clicked and no real email was sent. Targeted app tests: Mac 214, iOS 200, zero failures. Backend full suite: 653 passed, 5 skipped; typecheck/lint clean, then support tests/typecheck/lint rerun after routing static 5xx errors into existing ops monitoring. Final combined app suites: macOS executed 1,060 tests, 4 skipped, 0 failures; iOS executed 998 tests, 3 skipped, 0 failures. The Mac-only extra skip again required silence while this machine was playing audio; the three fixture-dependent model tests were also skipped.

Remaining delivery checks: deploy additive backend first; confirm `SUPPORT_EMAIL` or existing `ALERT_EMAIL` and Resend config; with Ian's explicit authorization send one synthetic report and verify inbox receipt. Check signed-out/BYOK, offline and throttled client copy, duplicate retry after a lost response, checked/unchecked diagnostic preview/copy and compact iPhone/iPad/accessibility. A provider acceptance receipt is not proof of inbox delivery. Reports are not stored server-side beyond email.

CAM++ status correction (2026-10-29): enabled voice preferences no longer read Off when the model is unloaded. Shared copy distinguishes missing local-speaker selection, unsupported hardware, idle, download, ready and failed states. Seven voice tests passed per Apple platform; both final Debug builds passed. Native Mac inspection confirmed the actual enabled-but-Deepgram-selected state now reads “Enabled, waiting for Speakers to be set to This Mac in Transcription.” No feature preference was changed.

Changelog draft (2026-10-29): `CHANGELOG.md` now opens with six concise Unreleased bullets for this scope. The header became `Unreleased - v3.5.0` on 2026-10-30, so the website changelog now lists it marked unreleased; the ship date replaces Unreleased only when a platform goes live. Published 3.4.0 and older entries are unchanged. Assign the release version/date and mirror iOS/Mac notes through the release runbook only when this scope is ready; current store/appcast notes still describe the shipped release.


## O6 diagnostic timeline QA (local 2026-10-29)

- On a normal recording, Help should show start, audio/connection/transcript progress and final outcome. A long quiet recording must not produce word/buffer logs or a false transcript failure solely from silence.
- Restart the app after a failed operation and verify the sanitized history remains in Help Preview and Debug Copy/Save. No transcript/title/email/key values should appear as event fields. Clear in Debug removes the retained timeline.
- Simulate an existing auth failure without deleting credentials: the timeline must name load/sign/refresh phase, safe error domain/code, recovery availability and observed repair outcome. Opening Help performs no extra sign, Keychain read or repair (existing support metadata reads are unchanged).
- Cloud pending removal/upload, pause reason and purchase pending/confirmed paths should appear without meeting/checkout identifiers. The report should contain relevant successful steps as well as failures.
- Deploy the extended support parser before the new client; use the existing explicitly approved inbox QA to check the fixed fields/counts render. No new automatic upload or real mail was performed for O6.

Automated O6 evidence on the combined local tree: macOS 1,067 tests executed, 4 skipped, 0 failures (`/tmp/miniti-timeline-final-mac.log`); iOS iPhone 17 Pro simulator 1,005 executed, 3 skipped, 0 failures (`/tmp/miniti-timeline-final-ios.log`). Backend 655 passed, 5 skipped, typecheck and lint clean (`/tmp/miniti-timeline-api-final.log`). Six dedicated timeline regressions cover the hour-long retry sequence, sanitization, bounds, restart/clear and failed storage; two backend cases cover structured mail and rejected fields. The existing auth, recording, cloud and purchase regression suites pass with the hooks in place. Swift/backend enums and field vocabularies match (48 codes, 11 vocabularies). Documentation link validation: 118 files, no missing targets/anchors. No live provider check, inbox test, deployment, commit or release was performed for O6.

Home feedback QA: verify the bottom-right control stays clear of Home content and the iPhone tab bar; open/cancel without a request, submit a synthetic message only during the approved inbox test, confirm the feedback subject and absence of diagnostic/account data. Check failure retains text, repeated clicks cannot send concurrently, 429 tells the user how long to wait, and Help shares those limits. Verify both API mode options are separate rows with wrapping/selection at compact and accessibility sizes; switching retains the existing refresh behaviour.

Feedback/API-mode verification: macOS 1,070 executed / 4 skipped, iOS 1,008 executed / 3 skipped, zero failures (`/tmp/miniti-feedback-full-mac.log`, `/tmp/miniti-feedback-full-ios.log`). Backend 658 passed / 5 skipped, typecheck/lint clean (`/tmp/miniti-feedback-api.log`). New fixtures cover minimal feedback payload, shared in-flight/cooldown behaviour, 429 retention, feedback subject/recipient, and burst/hour/global limits. Rendered Mac Debug Home and Feedback sheet with native UI inspection: bottom-right placement, focused message editor, disabled empty Send, optional reply field, clear no-log notice. Cancelled without sending. Account shows two separate selectable mode rows; no mode was changed. iPhone/iPad compact/accessibility visual QA and real inbox delivery remain open.

## Independent-review follow-up (2026-10-30)

Private financial doc relocation is now explicitly ignored and public links removed, including archive links. Source-comment paths and coverage guidance point at current references or historical archive paths; old path-shaped link labels are corrected. Release checklist now blocks app distribution until the purchase-return site and additive backend receipts/restore/status/report contracts are live. No deployment was performed.

Cloud availability correction: test a finished never-synced meeting with cloud off, free and BYOK. Local must not claim a remote removal; Cloud must explain eligibility/settings rather than promise an active upload. A known cloud copy still shows pending removal offline, and a held first upload must still be removed after an exclusion. Explicit restoration remains protected from pulled deletion. The duplicate unreachable restore checks are removed. Home `feedback`, shortcuts and settings now use the same shared label/font component.

Review-fix verification (2026-10-30): full macOS 1,072 executed / 4 skipped, full iOS 1,010 executed / 3 skipped, zero failures (`/tmp/miniti-review-claude-mac.log`, `/tmp/miniti-review-claude-ios.log`). The held first-upload test verifies the in-flight marker clears; new availability regressions cover never-synced cloud-off/BYOK rows and preserved removal protection. Mac Debug Home was rendered: lowercase feedback uses exactly the shared shortcuts/settings font and chrome. Ignore verification confirms the private financial doc is excluded from addable untracked files; no public Markdown links remain. Documentation checker: 118 files, no missing targets/anchors. Nothing committed, deployed or released.
