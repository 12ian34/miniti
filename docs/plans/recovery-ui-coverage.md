# Account recovery and UI regression coverage

Local implementation update (2026-11-04): the selected 3.8.0 changes are present in the working tree. The [release evidence](../releases/3.8.0-evidence.md#local-implementation-evidence) owns commands, results and remaining manual/runner gates. This does not change the released 3.7.0 baseline or authorize publication.

Status, 2026-11-09: Mac 3.8.0 build 164 was released on 2026-11-09; iOS build 164 is waiting for App Review. Final automated validation and signed-package verification pass. Specialist physical evidence remains unitemised; publication does not turn it into a pass. All 31 iPhone UI journeys pass; native Mac UI automation remains unavailable on the build host. [Account access](account-access.md) owns production behavior, the [release checklist](../releases/3.8.0.md) owns evidence and the [roadmap](../roadmap.md#test-audit-follow-through) owns priority. This remains bounded T11/T12 scope, not a general UI rewrite.

## Deliverable

A small repeatable Mac/iOS UI harness proves that the real controls reach the expected account state and persisted result. Reuse 3.7.0 test isolation, injected services, controlled time and existing accessibility identifiers. The local project now has dedicated UI-test targets. The small `MinitiUITests` and `MinitiMobileUITests` XCUITest targets use the Testing host identities and deterministic test-only injected transports. Keep exhaustive coordinator cases in the existing hosted bundles. The `fastlane mac ui_test` and `fastlane ios ui_test` lanes now exist. The Mac runner is blocked by OS automation authorization; this is not a passing journey result. Test-only launch modes must not grant production permissions or ship account bypasses.

## Required journeys

| Journey | Evidence |
|---|---|
| Ordinary upgrade/launch | Existing enrolled account remains enrolled; no first-use prompt or identity replacement. |
| First use | Sign-in and continue choices are visible; cancellation creates no account; email and recovery-key actions reach the actual flow. Follow Ian's confirmed explicit-choice flow. |
| Credential unavailable | Locked/cancelled and corrupt credentials show the matching recoverable state; no destructive rotation or silent creation. |
| Throttled enrollment | Retry is unavailable until the persisted deadline, truthful time/reason is shown, relaunch does not bypass it. |
| Sign-out and revocation | Choice persists across relaunch; record cannot silently create an account; successful explicit recovery clears the marker. |
| Settings and device labels | Real Settings navigation reaches Account, recognizable labels and This device are visible, duplicates remain distinguishable and support IDs remain accessible. |
| Consent and cancellation | Required choices remain visible at large text; canceling a consent or account sheet does not start recording or send a request. |
| Record, Stop, History | With injected audio/transcript transport, start and finalization settle, History contains one saved meeting with final words, and account transitions do not apply stale results. |

Avoid assertions that inspect only the setup fixture. Each journey performs the UI action and checks coordinator requests, resulting state or reopened persisted data. Do not make CI depend on live email, paid AI, real Keychain prompts, microphone hardware or a production account. Unit/integration tests remain the main coverage for exhaustive state and concurrency combinations.

## Platform and accessibility bounds

Cover compact iPhone, regular-width iPad and the minimum supported Mac window size, including one large-text configuration. Verify keyboard focus/activation on Mac and useful accessibility labels/order on both platforms. Record a manual VoiceOver pass for account choices, error/retry state and Stop/History; screenshots alone cannot establish accessibility. Reuse the supported iPhone 16 baseline when available. Hardware/device checks are separately opt-in, not silently added to hosted suites.

Test the web approval/sign-in interaction through the affected backend route and atomic link tests. If rendered web behavior changes, add its focused browser check to that change. Do not build an unrelated web account UI suite as a prerequisite for Apple work.

## Execution environments and runner setup

AC3 owns both new XCUITest lanes and their reproducible setup. These are separate UI runners, not another invocation of the hosted test bundle. [Apple's test-runner description](https://help.apple.com/xcode/mac/current/en.lproj/dev6061748b5.html) identifies the custom runner app; [Apple's security guidance](https://support.apple.com/en-lamr/guide/security-pdf/secddd1d86a6/web) explains that accessibility and automation capabilities require authorization. These sources do not establish that a particular GitHub runner image is already prepared.

| Lane | Initial 3.8.0 execution policy | CI promotion |
|---|---|---|
| `fastlane mac ui_test` | Required release evidence from a local interactive, unlocked Mac session using the isolated Testing host. Run serially so concurrent UI runs cannot steal focus. | A separate workflow_dispatch pilot may validate a disposable macOS runner. Do not claim required macOS UI CI until automation authorization and a clean-runner smoke test pass; local evidence remains required until that promotion is recorded. |
| `fastlane ios ui_test` | Required release evidence from local supported iPhone/iPad simulators, with exact runtime/destination recorded. | AC3 adds a separate GitHub macOS simulator job after a clean-runner launch/action smoke test passes. Record the job and runner image before making it required. No real device or provider credentials. |
| Existing hosted bundles | Continue both existing Testing lanes locally and in their existing CI jobs. | New UI setup must not weaken or replace their checks. |

Local setup must identify the selected Xcode, runner bundle/signing identity, launching process and simulator/runtime. Start with one isolated launch-and-control smoke test before the full suite. If macOS requests UI automation authorization, the person running the tests grants the requested permission for that actual runner/process through the system prompt or the corresponding Privacy & Security control; record which permission/process was required. Do not assume the Apple Events Automation pane alone covers XCUITest authorization. Keep the runner identity stable. This planning step grants no permission and changes no machine setting.

CI setup must be explicit in the dedicated job, with an attached log of its clean-machine smoke result. Consult the installed Xcode tooling/help for its UI automation mode rather than copying an unverified security command. Any unattended authorization setup belongs only to the disposable test runner or a deliberately provisioned test machine. Do not disable security protections or rewrite TCC databases on Ian's Mac. If runner authorization cannot be established, fail the UI preflight with the blocker and retain the required local release check; a skipped job is not a pass.

The launched app must select `MINITI_TEST_HOST` dependencies, process-local fake credentials and isolated defaults/data paths before constructing AppState. XCTest's hosted-bundle `TestRunSetup` does not automatically run inside an app launched by a separate UI runner, so AC3 must explicitly initialize and assert this app-side isolation. Reject real account credentials, provider endpoints and the installed app's container. Seed only test-owned fixtures; for relaunch-persistence journeys use a per-test temporary store and clear it after the journey, not between its launches.

A real Keychain permission prompt is an isolation failure, not an expected bootstrap step. Capture the failure, stop the lane and fix the configuration/injection; do not approve access to the installed account to get tests moving. Locked/cancelled/corrupt credential UI states use injected errors. Actual signed-app Keychain and upgrade behavior remains a separate explicitly chosen manual check. This preserves the [current Testing contract](../reference/testing.md).

Require the app to expose a test-only ready signal within 30 seconds, before any journey starts. If absent, terminate that isolated test launch, retain the result bundle/logs and fail with configuration/authorization context instead of hanging indefinitely. Keep runner launch timeouts explicit in the lane. Once implemented, document exact commands and setup in Testing/Fastlane docs and retain a clean-start smoke test for every supported UI execution environment.

## Acceptance and evidence

Apply the [3.8.0 design and screenshot matrix](../releases/3.8.0-planning-audit.md#ux-design-and-screenshot-acceptance): real rendered states on Mac, compact iPhone and regular iPad, synthetic personal data, shared components, keyboard/VoiceOver, large text and Reduce Motion. Record public/store asset replacement or retention separately from internal QA captures. No fabricated UI screenshots or uploads during planning.

Both Apple bundles pass with the `Testing` configuration; any dedicated UI runner has a documented isolated command and passes for the relevant targets. Record real test totals and justified skips in the [combined checklist](../releases/3.8.0.md), followed by physical credential/upgrade/VoiceOver evidence or an explicit waiver. Verify that no test writes personal preferences, credentials, SwiftData, Cloud or user model directories. This plan closes with account access, not before its UI journeys are implemented.
