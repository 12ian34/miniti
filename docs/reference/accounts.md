# Accounts, credentials and billing identity

3.8.0 local candidate: missing credentials on a new install require Sign in or Continue without signing in. A pre-created UUID alone is not prior-account evidence. Supported legacy installs may migrate, but an ineligible migration cannot silently create an account without a choice. Sign-out/revoke/delete retain the choice marker. `loadResult()` distinguishes found, missing and unreadable without breaking existing optional `load()` callers. Locked/corrupt reads offer recovery or an explicit destructive-local reset confirmation. Background credential reads use a fresh `LAContext` with `interactionNotAllowed = true` through `kSecUseAuthenticationContext`; explicit Retry can request it once, outside the auth-state lock. A registered-device conflict never rotates identity from Continue alone. Retry-After persists per installation; migration-negative results cache per installation and clear on successful enrollment. Real Keychain prompts in hosted/UI tests are isolation failures. Device labels are account metadata: PATCH requires actor and target still active on the same account, manual labels survive metadata refresh, null restores the platform fallback. Existing accounts and local meetings are retained. See [3.8.0 evidence](../releases/3.8.0-evidence.md#local-implementation-evidence).

Current baseline: Apple 3.4.0, reconciled 2026-10-27. [Roadmap](../roadmap.md) owns future work. Backend route/storage contracts live in [miniti-api](../../../miniti-api/docs/agents/04-api-reference.md). Do not implement historical proposals as current behavior.

## Identity and access

A managed account may be anonymous. Each installation has a P-256 key, short-lived bearer and refresh credentials; its stored recovery key is another way to regain access. Optional verified email works on free and Pro accounts with cloud off. A billing license key restores a purchase; it is not the account’s authentication key. Do not require email on either platform, merge accounts by email, or reintroduce a shared app API secret.

`ClientAuthManager` owns credentials. The released 3.7.0 coordinator silently creates on ordinary first use. The local 3.8.0 behavior above replaces that path; [account access](../plans/account-access.md) retains the complete acceptance contract.

An ordinary attach changes the installation’s account in place. The app keeps local meetings and resets sync bookkeeping on a successful account change before refreshing status. Same-account repair preserves bookkeeping. R3 prevents old in-flight sync work applying to a new account; it does not establish meeting provenance or stop a future pass uploading the local library. That remains [meeting ownership](../plans/meeting-ownership.md).

## Credential concurrency contract

- Capture the credential snapshot and its generation under the lock before an asynchronous operation. Every credential writer commits against its operation’s expected generation, with check, store write and memory update under the same lock as local clear.
- Identity replacement advances the generation; token-only updates do not and cannot clear signing failure. Only a successfully signed proof or server-accepted persisted replacement establishes key usability.
- `authorize` returns the generation of the snapshot that actually signed. Bearer and proof belong to that snapshot. Carry this value through send, retry, mutation commit and revocation clear; do not read the current generation afterwards and relabel the request.
- Repair is bound to the failing generation; its shared task cannot repair another account. It returns the exact generation committed by repair. Continuation must still be under that generation, never whatever account happens to be current.
- Late refresh, attach, rotation, repair and reauthentication answers cannot undo sign-out or replacement. Late revoke/sign-out/delete completions cannot clear a newer credential or its cloud bookkeeping.
- An already-revoked response that cleared this operation’s credential counts as its successful local clear. A stale revoked response does not.

These are shipped regression contracts, not proposals. Test the real signing/commit boundaries with held responses, including repair inside rotate/attach, A→B→A, unsigned refresh after failure and store errors. Historical fixtures and fixes: [auth review record](../archive/reliability-follow-up-plan.md#auth-persistence-follow-up-required-before-340-built-2026-10-27-16a70ab).

## Broken or unavailable keys

Refresh grants are unsigned: a migrated Secure Enclave key may fail only at the first signed proof. Only allow-listed unusable errors justify automatic repair with a stored recovery key. Unknown, locked and cancelled errors retain credentials and offer Try again/Sign in again; successful local signing clears temporary failure. Three launches only makes the offer prominent, never authorizes replacement. No recovery key means explicit email or recovery-key authentication with a fresh key; retain the old credential until the server accepts the replacement.

The observed CryptoTokenKit `TKErrorCodeInvalidatedDeviceKey` (-10) is macOS 27-specific. Older OS errors require measurement; the macOS 26 device scenario was waived for 3.4.0 and remains a gate for A3. Never widen the destructive-repair allow-list from an unexplained sample.

Email reauthentication retains the old recovery key only for the same account; a switch must not carry it into another account. Typed recovery-key restore can also switch accounts and must reset old bookkeeping. Healthy-key offline sign-out fails visibly and retains the credential. Once the key has failed, sign-out can clear locally. The Devices row for this installation uses the same path.

Keychain uses the two-store classification/fallback in `KeychainSlot`. Developer ID macOS lacks the data-protection entitlement; login-Keychain fallback is intentional. A failed draft write sends no create request. See [distribution](distribution.md) for the 3.2.1 incident.

## Email and UI

Account email state has verified and pending addresses independently. Verified means protected even while replacement is pending. Fetch failure is unavailable, never no email. Reads are bearer-only; writes require proof; delivery configuration gates sending, not read/remove. Global service/storage guards remain.

Account generation and request sequence fence reads and writes. Mutations serialize and check generation after every await, including the reconciling read. One read runs with at most one pending refresh for the current account; sign-out discards it. Browser callback and activation while pending refresh state. Account, Cloud and API consume the same state. See [Settings](settings.md).

## Ownership still being migrated

Usage is presented per account but summed from device counters; subscriptions remain mirrored on device records and sponsorship is resolved at read time. Lowercase auth IDs and uppercase Apple usage IDs require compatible reads of both spellings until B0. Never globally lowercase keys without the full namespace/adoption design.

Existing sponsorship eligibility is Polar across platforms and Apple on iOS; purchase rails remain Polar on Mac and StoreKit on iOS. Deleting an account does not cancel upstream billing. The five-device cap stays. [Account ownership](../plans/account-ownership.md) owns subscription attribution, atomic usage, non-destructive source accounts and migration decisions. Do not infer production auth-enforcement flags from source defaults.

Integration tokens are still device-keyed. Read legacy lower/uppercase forms; do not silently choose another device’s connection. [Integration ownership](../plans/integration-ownership.md) owns the future migration. Linux uses the shared backend and auth vectors on its own release line.

3.8.0 local SG1: [Home setup guide](../plans/home-setup-guide.md) supersedes the independent Home account/calendar cards. It is optional, staged and resumable, preserves existing configuration/dismissals, and presents Add email directly. The approved vertical checklist keeps calendar and separate Mac transcription/speaker controls inline, bound to the real settings; one task expands at a time. Pending verification is not completion. The release record owns automated and remaining manual evidence.

3.8.0 second review: background device-ID reads also forbid keychain interaction. Temporary locked/denied keychain state never offers or permits destructive credential reset. Explicit Retry refreshes the same identity and enrollment/status; Continue advances only on success. Signed locked-keychain checks remain required.

## Legacy migration and pending-usage repair (3.8.0 local, 2026-11-06)

Accounts first shipped in 2.6.0. A supported earlier install may establish its first anonymous account while retaining its device identity and usage. Already enrolled accounts must be retained or explicitly recovered. Backend migration preflight and final eligibility both check lowercase and uppercase legacy device records; a newer lowercase usage row must not mask an eligible older uppercase row. Existing proof, installation binding and replay checks remain mandatory. No historical account merge or entitlement repair is implied.

Temporary unreadability of a signing key does not permit Sign out to bypass unsent managed usage. Explicit authenticated recovery/email repair remains reachable, with pending reports bound to their original owner. A permanently unusable key retains the deliberate local escape path. Live capture/finalization and a running Watch import still guard account transitions.

3.8.0 migration retry: upgrading clears the previous negative migration-probe cache once; explicit Continue reprobes legacy eligibility before creating a new account. Explicit sign-out/revocation choices remain authoritative. This repairs retry eligibility after a backend fix without resetting credentials or merging accounts. Pending usage that cannot be signed names keychain unlock/sign-in recovery instead of only asking to go online.

Confirmed Set up again skips the legacy migration probe and proceeds through the explicitly authorized account-creation/reset path. Recovery copy says unlock your device on iOS and unlock your keychain on macOS.

Anonymous Continue selects managed mode before enrollment, shows progress immediately and advances onboarding as soon as enrollment succeeds. The optional usage refresh runs after navigation. A temporarily unreadable device identity reports why setup cannot continue and never creates an account under a session-only ID.
