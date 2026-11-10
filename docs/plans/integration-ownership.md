# Account integration connections and explicit routing

Status: selected for 3.9.0 by Ian on 2026-11-09, moved to 3.10.0 by Ian on 2026-11-10, not implemented. Original scope reconciled 2026-10-27; release assignment and integration updated 2026-11-09. [Roadmap](../roadmap.md) owns priority; this file owns completion. One release may include several completed plans. Ordered backend deployments inside a plan are not separate unfinished product releases.

Scope direction confirmed by Ian, 2026-11-09: CRM and calendar connections belong to the signed-in account. B5 is selected alongside B0–B4 and UI1–UI3 for [3.9.0](../releases/3.9.0.md). Implementation and migration evidence remain pending. B4 is not a prerequisite for B5 backend work; both integrate into the same account-switching review and release acceptance.

## Deliverable and boundary

B5: account-owned Google/Attio/Twenty connections, explicit selection where ambiguous, compatible adoption and real disconnect. No automatic CRM workflow expansion.

## Prerequisites and decisions

B0–B3 complete. Preserve existing device connections and OAuth state in flight. A phone using CRM Y must not silently use another device’s CRM X.

Release compatibility prerequisite: follow [AO4's S0–S7 capability and publication contract](../releases/3.9.0.md#backend-stages-and-client-publication). Compatible Mac/iOS/Linux binaries must be public before S2 gates old attach, email join, restore-into-account and create on a reused installation ID. The gate is blanket by version for those operations, not by whether connections exist; proven same-account repair/replay retains the narrow recovery exception. Shipped copy promises connections move with the device, so old consent does not authorize stopping calendar auto-start or CRM automatic sends. New clients show the account-owned review only under fresh `account_v1` capability and verified B5 adoption/routing readiness. Partial/paused stages cannot claim the complete consequences. All [B3 entry points](account-ownership.md#account-change-entry-points), including restore, credential repair and post-revocation create, must apply this contract.

## Account ownership behavior

- Google Calendar, Attio and Twenty authorizations belong to the miniti account. Signing in on another supported device makes those connections available without another provider login, unless the provider requires reauthorization. Adding a recovery method to a guest account keeps its existing account ID and connections; mandatory email is not introduced.
- Signing out, removing a device or moving it from A to B leaves A's connections with A. The departed device loses access to A's tokens, cached calendar/CRM results and queued connection operations. B must never adopt A's legacy tokens merely because they share the same installation ID. Other devices on A continue using A's connections.
- Connection ownership and device preferences are distinct: calendar selection, recording automation and automatic CRM sending keep their explicit settings. Availability on another device does not turn on automatic recording or sending. Existing per-device connection choices survive migration; ask when multiple eligible connections make the destination ambiguous. An explicit `none` stays disconnected on that device and must not fall through to the sole-connection default.
- Distinguish **stop using on this device** from **disconnect from this account**. The first clears local routing/use; the second removes the shared connection, explains that other devices will lose access, and revokes upstream where supported. Account deletion removes its connections; ordinary sign-out does not.

Migration gate: bind legacy credentials to their verified source account before allowing the installation to move **or be re-created on the same ID after sign-out/removal**, or leave unresolved credentials unavailable pending explicit reconnection. Capture/retain the pre-revocation source under B1 step 2's shared serialization before any installation overwrite; source evidence must survive revoke/cleanup. Never infer ownership from replacement membership on the first status call after transfer or create. A new key plus an old device ID grants no access to the old tokens. OAuth state captures its initiating account; a callback after transfer/sign-out/re-create must not bind to the destination or restore departed-account UI. Define atomic adoption/refresh/disconnect fencing and same-upstream-identity deduplication before implementation. Existing fallback reads must enforce the captured owner; a 30-day legacy-key TTL is not an authorization boundary.

Test A → sign-out/remote revoke → create Y on the same ID before adoption/backfill, including both UUID spellings, lost create response, refresh/OAuth callback held across re-enrollment and unknown source evidence. Only A may retain/adopt A's connections; Y stays disconnected. Same-account authorized repair restores A's routing without changing token ownership, and fresh/rotated-ID create adopts no old-ID token.

## Implementation contract

### B5: integrations as account connections (miniti-api, clients)

**Today:** `{provider}:token:{deviceId}`, no account view, no TTL, no Attio or Twenty disconnect.

**Proposed authoritative record:** `conn:{accountId}:{provider}:{connectionId}` hash (tokens, upstream identity label, `connectedByDevice`, `connectedAt`, `scope`), index `conn:{accountId}:{provider}`. Each installation keeps a routing choice per provider: `auth:installation:{id}.routing.{provider} = connectionId | legacy | none`, written by the client when the person chooses, by migration otherwise. Device-side `@AppStorage` keeps auto-export and routing preferences, never tokens.

**Resolution order on every status, search and send:** (1) explicit `connection_id` in the request; (2) the installation's stored routing; (3) if the account has exactly one connection for the provider **and** the installation has no legacy token, that one; (4) otherwise `409 connection_required` with the list, and the client asks. An installation that has a legacy device token resolves to it (2 = `legacy`) until the person picks something else; the account connection never pre-empts it.

Every explicit ID, stored route and legacy fallback is authorized against the current account before returning status/data, refreshing tokens or dispatching work. The same rule covers calendar list/event reads. A stored `none` terminates resolution without default selection. Sign-out/account change clears account-scoped caches and fences held responses; queued sends retain their original account/connection and cannot be rerouted by destination defaults.

**Migration:** on the first status call after deploy, if the installation has a legacy token and the account has no connection for the provider, the token is adopted as an account connection **and** the installation's routing is set to that `connectionId`. If the account already has a connection to a different upstream identity, the legacy token is wrapped as a second account connection (so it can be shared and cleaned up) and the installation's routing points to it; nothing is overwritten and the other devices' routing is untouched. Legacy keys are renamed `…:adopted` with a 30-day TTL.

**Lifecycle:** disconnect routes for all three providers remove the connection, clear every installation routing that pointed to it, and revoke upstream where the API offers it (Google yes; Twenty if its revocation endpoint exists, **unverified**; Attio **unverified**). Rotation, revoke and transfer leave account connections alone; a transferred installation keeps its routing only if the destination account holds that connection, else `none`. Account deletion removes them.

**Tests:** resolution order including the Mac-X / phone-Y scenario (phone keeps Y); adopt when empty; wrap when different; shared use from a second device after an explicit choice; `connection_required`; disconnect clears routing; legacy TTL; transfer resets routing to the destination's connections; account deletion cleanup.

## State-machine acceptance criteria

Mapped on 2026-11-09 from the [Apple-app inventory](../research/implicit-state-machines-2026-11-08.md): V1 (OAuth, search and manual CRM send), A1 (calendar connection evidence) and D3/D4 (completion and durable delivery). These refine B5 and the roadmap's remaining T16 coverage; shipped sync/webhook behavior remains owned by the [sync/delivery plan](sync-and-delivery-reliability.md).

- Hold OAuth/status/search/send responses across adoption, account transfer and disconnect. Assert that a late response cannot restore a disconnected connection, overwrite the current selection or silently route the phone's CRM Y to the Mac's CRM X. Distinguish unresolved/failed status from confirmed disconnection.
- Capture the intended account and connection for queued and in-flight sends. Test transfer or disconnect before dispatch and during a request: retain attribution, never silently reroute, and document whether an already-authorized remote request may finish.
- Cover note-success/task-failure and lost-response retries under an explicit duplicate-prevention contract before changing connection ownership. Assert which remote operation is retried and which successful operation is preserved.
- Preserve the distinction between completion staged, durably handed off, released for sending and remotely acknowledged. Re-run relevant first-completion/outbox regressions so an ownership change cannot release an incomplete payload or make a local marker claim remote success.

Record these results with the OAuth and partial-send tests required by T16. A unified export engine or new automatic CRM workflow is outside this deliverable.

## Design-system follow-through

Use the shared primitives from [UI consistency/accessibility, order 3d](ui-consistency-and-accessibility.md). The [design audit](../research/design-system-audit-2026-11-09.md) assigns this plan delivery-status presentation from D16, applicable connection/Playbook/delivery Settings sections from D17 and changed-control focus checks from D13. Share connection validity/status, probe result wording and retry/discard presentation. Keep iOS URL keyboards, native navigation and platform-specific providers, and leave routing/authorization in the existing B5 and outbox owners. Playbook section reuse does not expand B5 into a new server-owned Playbook connection model.

Acceptance: unresolved, connected, disconnected, queued, partially sent and failed states are distinguishable; large text and keyboard/VoiceOver reach the appropriate actions; note-success/task-failure retry preserves the successful send. Preserve native provider capability differences and Mac-only private mode. Unrelated speaker/model settings and recording banners stay deferred. Record closed audit findings here and in the shared disposition register.

## Acceptance and delivery

Test lower/uppercase legacy adoption, concurrent adoption, token refresh, explicit/installation/sole-connection/ask order, account changes, disconnection and old clients. Record admin adoption counts and Linux routing parity.

Also test sign in on a second device without a new OAuth grant; guest recovery-method addition; A-to-B transfer before the first adoption/status call; OAuth callback after transfer; old-account calendar/CRM cache invalidation; explicit `none` with one available connection; same-upstream concurrent adoption; disconnect racing token refresh; device removal leaving other devices connected; and account-wide disconnect leaving every client unable to use stale routes. Automatic recording/sending preferences must remain unchanged. Define compatible old-client handling of `connection_required` before enabling adoption for them.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

Rollback: retain legacy fallback until adoption and reader parity are proven; preserve adopted tokens and selection metadata. Define the exact safe rollback deployment before removing any fallback. [History](../archive/enrollment-identity-plan.md).
