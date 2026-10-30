# Accounts, credentials and billing identity

Current baseline: Apple 3.4.0, reconciled 2026-10-27. [Roadmap](../roadmap.md) owns future work. Backend route/storage contracts live in [miniti-api](../../../miniti-api/docs/agents/04-api-reference.md). Do not implement historical proposals as current behavior.

## Identity and access

A managed account may be anonymous. Each installation has a P-256 key, short-lived bearer and refresh credentials; its stored recovery key is another way to regain access. Optional verified email works on free and Pro accounts with cloud off. A billing license key restores a purchase; it is not the account’s authentication key. Do not require email on either platform, merge accounts by email, or reintroduce a shared app API secret.

`ClientAuthManager` owns credentials. The coordinator still silently creates on ordinary first use in 3.4.0. Remaining unreadable/damaged classification, persisted retry delays and explicit first-use/signed-out/revoked choices are in [account access](../plans/account-access.md); they are not shipped promises.

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
