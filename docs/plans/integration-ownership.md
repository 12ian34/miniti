# Account integration connections and explicit routing

Status: planned, not implemented. Version: unassigned. Scope reconciled 2026-10-27. [Roadmap](../roadmap.md) owns priority; this file owns completion. One release may include several completed plans. Ordered backend deployments inside a plan are not separate unfinished product releases.

## Deliverable and boundary

B5: account-owned Google/Attio/Twenty connections, explicit selection where ambiguous, compatible adoption and real disconnect. No automatic CRM workflow expansion.

## Prerequisites and decisions

B0–B3 complete. Preserve existing device connections and OAuth state in flight. A phone using CRM Y must not silently use another device’s CRM X.

## Implementation contract

### B5: integrations as account connections (miniti-api, clients)

**Today:** `{provider}:token:{deviceId}`, no account view, no TTL, no Attio or Twenty disconnect.

**Proposed authoritative record:** `conn:{accountId}:{provider}:{connectionId}` hash (tokens, upstream identity label, `connectedByDevice`, `connectedAt`, `scope`), index `conn:{accountId}:{provider}`. Each installation keeps a routing choice per provider: `auth:installation:{id}.routing.{provider} = connectionId | legacy | none`, written by the client when the person chooses, by migration otherwise. Device-side `@AppStorage` keeps auto-export and routing preferences, never tokens.

**Resolution order on every status, search and send:** (1) explicit `connection_id` in the request; (2) the installation's stored routing; (3) if the account has exactly one connection for the provider **and** the installation has no legacy token, that one; (4) otherwise `409 connection_required` with the list, and the client asks. An installation that has a legacy device token resolves to it (2 = `legacy`) until the person picks something else; the account connection never pre-empts it.

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

## Acceptance and delivery

Test lower/uppercase legacy adoption, concurrent adoption, token refresh, explicit/installation/sole-connection/ask order, account changes, disconnection and old clients. Record admin adoption counts and Linux routing parity.

Run affected backend checks and both Apple bundles when shared client code changes. Record actual device, old-client and storage evidence in the release record; a skipped check is unverified. Deploy additive backend support before its client readers. Preserve existing account IDs, data, credentials and unrelated work. Record Linux compatibility/tracking for every shared change. No push, deploy or release is authorized by this plan.

Close this plan only when its complete stated scope has delivery evidence. Independent discoveries get a new roadmap item; release blockers are recorded as explicit scope amendments before implementation.

Rollback: retain legacy fallback until adoption and reader parity are proven; preserve adopted tokens and selection metadata. Define the exact safe rollback deployment before removing any fallback. [History](../archive/enrollment-identity-plan.md).
