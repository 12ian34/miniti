# Account access, recovery and explicit choices

Status: planned, not implemented. Version: unassigned. Scope reconciled 2026-10-27. [Roadmap](../roadmap.md) owns priority; this file owns completion. One release may include several completed plans. Ordered backend deployments inside a plan are not separate unfinished product releases.

## Deliverable and boundary

Finish A2f, A3/A3a, A4/B6b and recognizable device labels B6c. Unreadable credentials pause safely; throttling is respected; first use, sign-out and revocation offer a persisted choice instead of silently creating an account. No subscription, usage-ledger or meeting-ownership migration.

## Prerequisites and decisions

A1–A2e and optional email B6a shipped in 3.4.0. D2 proposes an explicit choice after sign-out; retain it as a product decision to confirm before implementing A4. Backend A2f ships before client retry behavior. A3 precedes A4 within this bounded plan. No mandatory email; adding an email owned elsewhere is explicit sign-in/switch, never merge.

## Implementation contract

### A2f: migrate admission does not count a not-eligible answer (miniti-api, any deploy)

`/api/auth/migrate` currently charges `auth_migrate` (100/day per network) and `auth_migrate_device` (5/hour per device) before checking eligibility. A never-enrolled installation spends migration admission on each 404. Separate request protection from migration admission, in this order:

1. After bounded body/shape validation, charge `auth_migrate_probe` (500/day per network) for **every** attempt. If exhausted, return 429 with `Retry-After` before any device eligibility lookup. It is an outer request budget, despite its probe name; eligible requests spend it too.
2. Apply the existing per-device 5/hour limit, then look up migration eligibility. A 404 spends the outer and per-device budgets, but not `auth_migrate`.
3. Eligible attempts spend `auth_migrate` (100/day), including successful migrations and signature/conflict refusals. Preserve authoritative eligibility/proof checks at the write path; this read is not authorization.

A bucket checked only after a failed lookup does not bound that lookup: rotating UUIDs bypasses the per-device protection. No deployment-side per-IP protection is assumed. The outer limit bounds eligibility reads, not the limiter's own bounded counter work. Tests: 404 increments outer/per-device only; eligible 201/409 increments all applicable budgets; the sixth request for one device is refused; the 501st network request with fresh device IDs is refused **without an eligibility-store read**. Verify normal migration and restore paths remain compatible. Rollback by redeploy.

### A3a: the coordinator stops paying for answers it already has (miniti, with A3)

Today `ManagedEnrollmentCoordinator.ensure` calls migrate first on every trigger, treats a 429 from migrate as a generic failure (create is never tried), and retries on the next `usage` or `start` trigger, which the log on 2026-10-26 showed once a minute. Change, all in the coordinator so the tests stay unit tests:

- After one `notEligibleForMigration` for the current device id, remember it (UserDefaults in the sandbox container, keyed by device id) and start at create on later attempts. Drop the memory when the device id changes or a credential is stored.
- A 429 from migrate defers the whole attempt; it never falls through to create, because a throttled migration says nothing about eligibility and create can rotate the device id.
- Any 429 (from migrate or create) records a not-before time from a valid positive `Retry-After` (delta seconds or HTTP date); absent, invalid, zero or past values use a 60 s fallback. Do not combine a 60 s minimum with a promise never to exceed a shorter server window. Persist the deferral across launch; clear it after successful enrollment, and guard late responses against a changed device/account context. Until then `ensure` returns false without a request, the error reads "Too many sign-in attempts from this network. miniti will try again at HH:MM." and the Settings retry button is disabled with the same time. The server's message (A2e contract) is shown when it names the reason.
- Events: `client_auth_enrollment_deferred` with `until` once per deferral, never per skipped trigger; `client_auth_key_rebound` when the 2.12.1 invalid-proof path replaces the key with the recovery key (same device id, allowed fields only), because the 2026-10-26 QA showed that path runs with no trace in admin events.

Tests: not-eligible memory skips migrate on the second attempt and is dropped on device id change and on store; 429 on migrate sends no create; 429 sets the not-before and the next `ensure` sends nothing; `Retry-After` 0 and absent both give 60 s; a stored credential clears the deferral. The A5 line for this slice is above the A3 lines.

### A3: a credential the app cannot read is not a credential it does not have (miniti, release after 3.4.0)

- `ClientAuthCredentialStore.load()` → `found(credentials) | missing | unreadable(reason)`; undecodable → `unreadable(.undecodable)`.
- Manager keeps `credentialState`. While unreadable, `isEnrolled` is false, and every `ensureManagedEnrollment` and Settings refresh re-reads once before deciding. `isEnrolled` stays synchronous.
- The coordinator defers on unreadable with its own copy: macOS "miniti's saved sign-in is in a locked keychain. Unlock it and try again."; iOS "miniti could not read its saved sign-in. Unlock your device and try again."; damaged "miniti could not read its saved sign-in. Restore with your recovery key or email in Settings, Account, or set this device up again." Settings, Account shows the state with **Restore**, **Sign in by email** and **Set up this device again** (confirmed).
- Rotation precondition: at the start of `createAccount`, before the draft, the store state is read. Only `missing` permits rotation later in that call, and the draft written in that call carries `absenceConfirmed: true`. A resumed draft permits rotation only if it carries the marker. Anything else surfaces `deviceAlreadyEnrolled` to the coordinator.
- Tests: fake backend returning -25308 and -25293 at launch then success in the same process (no network, then a normal grant); corrupt bytes → unreadable, no rotation, no creation; draft with marker rotates once on conflict; legacy draft without marker does not; `MinitiAPIService.send` on unreadable throws `notEnrolled` as before; coordinator tests extended.
- Risk: a healthy Keychain misclassified as unreadable blocks managed mode until Settings. Mitigations: the classification is A2a's, tested; the Settings action always exists; A1 events show unexpected statuses. Rollback is a release with the old store semantics; the stored format gains one optional field only.

### A4: explicit choice states (miniti, after A3)

The evening incident adds truthful create/admission-limit handling. Recovery uses authenticated restore paths, not a quota exemption based on the revoked device UUID; see the incident section for the abuse and replay tests.

Defines every state and what the app does. "Healthy launch" is the first row and is unchanged.

| State | Detected by | App does |
|---|---|---|
| **First use** | no credential item, no device id item, no local marker | show B6's Home choice (sign in to an existing account by email or recovery key, or continue without signing in) **before** anything is created; the coordinator holds `awaitingChoice`, persisted so it survives relaunch; Start fresh is today's silent creation made explicit |
| **Draft** | found, `accountID` empty, no token | resume the draft on the next trigger, as today |
| **Enrolled** | found, decodes, account or token present | nothing; the launch path is one Keychain read |
| **Temporarily unreadable** | `unreadable(status)` other than decode failure | defer with the A3 message; re-read on each trigger; never create |
| **Damaged or lost** | `unreadable(.undecodable)`, or a device id with no credential and no local marker on a device the server knows (`409 device_already_enrolled`) | choice sheet: Restore (recovery key), Sign in by email, Set up as new |
| **Signed out** | `clearLocal()` after the user chose Sign out; a local `signedOutAt` marker is written in `UserDefaults` | Account shows signed out with the three choices; recording in managed mode prompts the same sheet; **no automatic account creation** |
| **Revoked** | `401 installation_revoked` or `device_auth_required`; local marker `revokedAt` | as signed out, with copy "This device was removed from its account."; `clientAuthStatus` refreshed at once |
| **Explicitly starting fresh** | the person tapped Set up as new and confirmed | rotate the device id if the server knows the current one, create, event `client_auth_device_rotated chosen: yes`; marker cleared |

Conflict on create (`409 device_already_enrolled`) with no marker is "damaged or lost" and shows the sheet; it does not rotate. The sheet copy: "This device already belongs to a miniti account. Restore it with your recovery key, sign in by email, or set it up as new." The pre-2.6.0 legacy migration path is unchanged: migrate still runs first for a device with no credential and no marker, and only a conflict reaches the sheet.

Tests: each state row through the coordinator with the stub; sign out writes the marker and the next trigger makes no network call; revoke refreshes status and writes the marker; each choice through the stub (recovery key re-binds, email link restores or attaches, set up as new rotates once and creates); marker cleared after a successful restore, sign-in or fresh start.

#### B6b: returning and first-use choices, with A4

A4's persisted `awaitingChoice` state precedes new account creation and returns after explicit sign-out/revoke. Home offers **Sign in to an existing account** and **Continue without signing in**; email is the primary sign-in route and **Use a recovery key** remains available. No credential or account is created before the choice. Existing healthy installations never see this as forced onboarding. Settings retains **Switch account** even when an email is present. Apply the same state/copy rules as B6a; account transfer and local-meeting consent still follow B3/B4's staged compatibility contract rather than being silently changed by the new labels.

#### B6c: recognizable device labels

Use editable labels, “This device”, and last reported metadata. macOS can suggest `Host.current().localizedName`; iOS uses a generic fallback or a user-entered label unless Apple's user-assigned-name entitlement is obtained. Handle duplicate labels; keep IDs available in support details. This is separate from A0a's metadata update and does not infer ownership from a name.

**Honest recovery statement:** “If you lose access to all your devices and have neither a saved recovery key nor a verified email, we cannot recover your account.” These controls simplify access; B1 is still needed so removing a device cannot remove account Pro.

## Acceptance and delivery

Prove each coordinator transition with a real action and injected transport/store: absent, locked/cancelled, corrupt, conflict, revoked, signed out, successful recovery, failed persistence and stale response. A migrate 429 never causes create. Retry deadlines survive restart and respect the server. First/second launch after an ordinary upgrade retains identity on both platforms; every fresh-start rotation is explicitly chosen. Verify cold/warm first-use choices, optional email and typed recovery key, signed-out relaunch and remote revoke on release-signed devices. Labels use a recognizable device name without logging it in diagnostic payloads.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

## Device evidence carried forward

3.4.0's macOS 26 migrated-key scenario was waived by Ian because no such Mac was available; it is not a pass. Before A3 ships, verify recovery on macOS 26 with an observed allow-listed code or explicit email/recovery-key authentication that needs no broken-key signature. Unknown errors never trigger destructive replacement. On macOS 27, cancelling the Keychain prompt produced -128; A3 must classify -128/-25308 as unreadable, not absent. A2c prevented creation through a failed draft write in 3.4.0; preserve that protection.

Two migrated copies can currently re-bind one installation back and forth. Include both copies in QA and expose the conflict; do not infer distinct identities from the same UUID. Use test accounts for revoke/move scenarios. Preserve ordinary upgrade, locked Keychain, damaged credential, backup restore, lost response and failed-write scenarios from [A5's evidence](../archive/enrollment-identity-plan.md#a5-device-qa-on-release-signed-builds).

Rollback: backend compatible redeploy and client release rollback, preserving credentials and persisted choice/defer markers. A rollback must not reinterpret unreadable state as permission to enroll. Historical decisions/tests: [enrollment record](../archive/enrollment-identity-plan.md).
