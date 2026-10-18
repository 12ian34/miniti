# Cloud sync, cloud storage, and API/MCP access plan

> Started 2026-10-15 from a user request: meetings synced between devices, stored in the cloud, and reachable from the user's own tools through a REST API and an MCP server. Optional, default off, must not touch existing users, must coexist with private mode. Nothing is built; this document is the plan and its status table. Ships as 3.0.0 on macOS and iOS (Ian, 2026-10-15), together with the quiet-mic live transcript fix below; Linux follows on its own line.

## Status

| Step | Status | Notes |
|---|---|---|
| Product shape and tier | decided 2026-10-15 | One switch in a new top-level Settings group, Cloud. Pro only. Managed accounts only: BYOK never syncs. Free users see the switch disabled with an upgrade line. The copy says plainly that miniti stores and can read the copy. |
| Storage | built 2026-10-15 | Neon Postgres project `miniti-api` (Frankfurt `eu-central-1`, Postgres 18, created through the Vercel Marketplace on 2026-10-16 after the first London project was deleted; Free plan for the allowlist phase), `db/migrations/001_cloud.sql` applied through `npm run db:migrate`, `lib/db.ts`, `lib/cloudStore.ts` (Postgres and in-memory twin), `lib/cloudStore.integration.test.ts` green against the real database. Redis keeps auth, usage, and the `cloud:seq:{account}` poll cache. |
| Contract | written 2026-10-15 | `../miniti-api/docs/agents/08-cloud.md`: document, routes, client protocol, tokens, OAuth, web sign-in, REST, MCP. |
| Backend: `/api/sync/*`, guards, purge hooks | built 2026-10-15 | `lib/cloud.ts` (kill switch `CLOUD_SYNC_ENABLED`, `CLOUD_SYNC_ALLOWLIST`, BYOK and legacy refusal, Pro gate, account-keyed limits), six routes including the batch fetch, purge on account delete, 14 route tests. |
| Backend: web sign-in, email on the account, device enrollment by email, OAuth 2.1 server, cron | built 2026-10-15 (see 08-cloud.md for the final contract) | Email confirmation and magic links through Resend, `miniti_web_session` cookie, `/signin` pages, `POST /api/auth/email/start` + status poll + restore/attach with `login_link_id`, `/.well-known/*`, `/oauth/register`, `/oauth/authorize` with consent, `/oauth/token` with PKCE and rotating refresh, `/oauth/revoke`, connected-app listing, `GET /api/cron/cloud-maintenance`. |
| Backend: tokens, REST `/api/v1`, MCP | built 2026-10-15 | `lib/apiTokens.ts` (PAT and OAuth bearer verifier, `WWW-Authenticate` with the protected-resource metadata), `POST/GET/DELETE /api/account/tokens`, `/api/v1/me`, `/api/v1/meetings`, `/api/v1/meetings/{id}`, `/api/v1/meetings/{id}/transcript?format=json|markdown|srt`, `/api/v1/action-items`, `POST /api/mcp` (stateless Streamable HTTP, five read tools, `miniti://meetings/{id}`), 39 tests. |
| Client: schema | built 2026-10-15 | `Meeting.updatedAt`, `syncedAt`, `cloudRevision`, `syncFingerprint`, `localFingerprint`, `syncExcluded`, `syncStateRaw`, `syncExtraJSON`, all optional or defaulted; `MeetingTombstone` model added to `PersistentStore.schema`. Lightweight migration; the copied-2.12.x-store check on both platforms is in the manual matrix. |
| Client: `MeetingSyncDocument`, `CloudSyncEngine`, transport | built 2026-10-15 | Fingerprint dirty detection so no write path stamps anything; push, tombstones, pull, manifest reconcile, conflict rules, pause reasons; `MinitiAPIService+Cloud.swift`. `MeetingSyncDocumentTests` (7) and `CloudSyncEngineTests` (22) against an in-memory server; macOS 882 and iOS 819 tests green on 2026-10-15. |
| Client: AppState wiring, Settings → Cloud | built 2026-10-15 | Sixth settings group with one destination and six search rows; `AppState+CloudSync.swift`; private mode snapshots `cloudSyncEnabled` and pauses the engine; private meetings `syncExcluded` for life; tombstones on user deletes; History reload and macOS auto-export after pulls; sign out, move, and delete reset bookkeeping; activation and commit triggers. Settings → Cloud on both platforms: switch and enable sheet, status, web sign-in email, connected apps, tokens shown once, delete cloud copy. |
| Client: new-device sign-in by email, per-meeting Keep off the cloud menu | built 2026-10-15 | `startEmailSignIn` / `emailSignInStatus` / `attachToAccount(loginLinkID:)` / `restoreAccount(loginLinkID:)` in `ClientAuthManager`, `AppState.joinAccount(approvedLinkID:)`, `EmailSignInSheet` behind "Sign in with email" (unenrolled) and "Join by email" (enrolled) in Settings → Account, "Create one" for a device without a recovery key; History context menu on both platforms; macOS delete alert says when the cloud copy goes too. |
| Docs, changelog, privacy policy, website, public docs, Linux note | done 2026-10-15 | `### Unreleased - v3.0.0` entry and iOS release notes; AGENTS, architecture, patterns, monetization, testing, settings plan; privacy policy (cloud section, Neon and Resend as subprocessors), pricing cards, llms.txt; miniti-docs `features/cloud-sync` and `reference/api-and-mcp` plus account, tiers, mode, platform and FAQ pages; `../miniti-linux/PLAN.md` parity note. Independent review 2026-10-15 (lost deletes, feed pruning, scan cadence, pause mid-pass, segment diffing, 401 handling) fixed the same day. |
| Vercel env and deploy | done 2026-10-16 | `DATABASE_URL`, `CLOUD_SYNC_ENABLED=false`, `CLOUD_SYNC_ALLOWLIST`, `RESEND_API_KEY` (the website's key), `CLOUD_EMAIL_FROM`, `WEB_SESSION_SECRET`, `CRON_SECRET`, `CLOUD_PUBLIC_URL`. Deploy with the switch off, then Ian's account on the allowlist. |
| Manual validation | partly done 2026-10-16 | Ian ran first enable, recording each way, rename, pin, delete, trim, email sign-in and join by email on his Mac and phone; the rest is covered by the shared wire fixture, the engine tests and the backend route tests. Claude.ai connector and Claude Code with a real token still untested live. |
| Staged rollout | shipping 2026-10-16 | macOS 3.0.0 (build 130) live on GitHub, appcast and MACOS_LATEST; iOS build 130 uploaded and submitted; website and docs deployed. `CLOUD_SYNC_ALLOWLIST` still holds Ian's account until he removes it (the classifier blocked the agent). App Privacy labels (email, user content) to be added by Ian in App Store Connect. |

## What the user gets

- A meeting recorded on the Mac appears in History on the iPhone within a minute of being saved, and the other way round. Edits (rename, pin, speaker names, trims, notes, insight regeneration) follow.
- The cloud copy survives a lost or wiped device: restore the recovery key on a new install and History comes back.
- Settings → Cloud → API access issues tokens for the user's own tools. A REST API lists, searches, and returns meetings as JSON; an MCP server exposes the same to Claude Code, Cursor, and similar.
- Private mode keeps its promise. While it is on, nothing is uploaded or downloaded, and meetings recorded under it never sync unless the user says so for that one meeting.
- Nothing changes for anyone who leaves the switch off. No new network calls, no schema change they can notice, no new prompts.

## Decisions (Ian, 2026-10-15)

1. **Pro only.** Cloud sync, the API, and the MCP server are Pro features. A free install shows the switch disabled with one line and the upgrade action the Account tab already has. A Pro that lapses stops syncing (the switch stays on, the status line says why); the cloud copy stays until the user deletes it or the account, nothing is purged on a lapse, and nothing local is touched.
2. **No BYOK.** BYOK installs have no backend account and never will for this. In BYOK mode the Cloud group shows one sentence ("Cloud needs the managed plan") and nothing else; `cloudSyncEnabled` is ignored when `appMode == .byok`, and switching a syncing install to BYOK pauses the engine and says so.
3. **The server can read the data, and the copy says so.** No application-level encryption: the API, MCP search and a future web History need the service to read meetings. Neon and Vercel encrypt at rest and in transit. The switch copy: "miniti keeps a copy of these meetings on its servers and can read them, so your other devices, your tools and you on the web can too." The privacy policy gets the same sentence.
4. **Cloud is a Setup tab under Account.** First built as a sixth top-level group on 2026-10-15; after using it Ian moved it into Setup on 2026-10-16 (General, Account, Cloud) because a setup choice belongs next to the account, not at the bottom of the sidebar. One destination, `cloud`; the settings tests pin only Privacy and Support.
5. **Pulled meetings follow macOS auto-export.** A meeting that arrives from another device is written to the markdown folder like any other when auto-export is on, so the `AGENTS.md` index covers phone meetings. Webhooks and CRM auto-sends never fire for pulled meetings.
6. **OAuth from v1, with a login page.** Hosted connectors need it, and a web sign-in is the door to a web History later. The account stays anonymous by default; turning Cloud on offers to add an email for web sign-in (below). Personal access tokens stay for scripts.

## Design

### Where the data lives

**Why not Redis.** Upstash is configured with eviction, holds small hashes, and `kv.keys` scans would not survive content keys. A 1 hour meeting is 60 to 150 KB of JSON; a user with 1000 meetings is 100 MB. That is content, not state.

**Why Postgres over Vercel Blob.** Blob is fine for "store this document" but the API and MCP need "meetings with Sasha about pricing after 1 September", the same queries `MeetingSearchQuery` runs locally. Postgres gives per-account tables, a change sequence for sync, a generated `tsvector` for search, and Neon branches for test databases. Neon is a Vercel marketplace integration, so its bill can feed the admin cost ledger the way Upstash does today (`lib/costs.ts`).

**Tables** (all keyed by `account_id`, the `acct_…` id from `auth:account:*`):

- `meetings`: `account_id`, `id` (lowercase UUID), `revision` (bigint, server-assigned, +1 per write), `updated_at` (client clock, the LWW key), `server_updated_at`, `deleted_at` (tombstone), `created_by_device`, `updated_by_device`, `start_time`, `end_time`, `title`, `language`, `external_source`, `external_id`, `document` (jsonb, everything except segments), `transcript` (jsonb array of segments), `size_bytes`, `search` (generated tsvector over title, summary, notes, transcript text). Primary key `(account_id, id)`. Unique partial index on `(account_id, external_source, external_id)` where both are non-null, so two devices importing the same Granola CSV cannot create two cloud meetings.
- `meeting_changes`: `account_id`, `seq` (bigserial), `meeting_id`, `revision`, `kind` (`upsert` | `delete`), `at`. The pull cursor is `seq`. Rows older than 90 days are pruned; a client whose cursor is older than the oldest row does a manifest reconcile instead.
- `api_tokens`: `account_id`, `id`, `name`, `token_hash` (sha256), `prefix` (first 8 chars for display), `scopes`, `created_by_device`, `created_at`, `last_used_at`, `revoked_at`.
- `account_storage`: `account_id`, `bytes`, `meeting_count`, `updated_at`, maintained by the write path, shown in Settings and admin.

Purge rules: a tombstoned meeting is hard-deleted 30 days later. `deleteAccount` (`lib/clientAuthStore.ts`) gains a step that deletes every row for the account and revokes every token in the same operation. A "Delete cloud copy" action in Settings does the same for meetings and tokens without deleting the account. Revoking one device never deletes account data; it only stops that device syncing.

### Wire format

One JSON document per meeting, `schema_version: 1`, snake_case, lowercase UUIDs on the wire (Swift uppercases `uuidString`; parse case-insensitively and lowercase on encode), ISO 8601 timestamps with fractional seconds. The document is the union of the Swift `Meeting` and the Linux `Meeting` struct. Fields a client does not know are preserved and echoed back untouched (`extra` object), so an older client cannot strip a newer client's fields.

- Identity and timing: `id`, `title`, `calendar_event_title`, `start_time`, `end_time`, `language`, `updated_at`, `created_at`.
- Flags: `pinned`, `sync_excluded` is never on the wire (an excluded meeting is never sent).
- Transcript: `transcript_revision`, `transcript_edited_at`, `segments[{id, speaker, text, start, end?, confidence, source, final}]`. Only final segments. `speaker` is the integer identity (mic speakers are 1000+), never the resolved label; `speaker_names{id: name}`, `speaker_overrides[ids]`, `self_speaker_ids[ids]` travel with it.
- Insights: `summary`, `action_items`, `key_decisions`, `topics`, `discussion_flow`, `notes`, `insights_updated_at`, `meddpicc{…}` as one object (Linux shape; Swift maps to its eight columns), `questions[]`, `doc_topics[]`, `template{id, definition?, sections{}}`, `investigations[]` (Linux has them, Swift ignores and echoes).
- Provenance: `external_source`, `external_id`, `external_url`, `imported_at`, `managed_session_id`, `calendar_event_id`, `attendees[{email, name, domain, response_status?, is_organizer, is_self}]` (Linux `name` is the Swift `displayName`; both sides map), `join_url`, `inferred_environment`.
- Not synced, by design: `lastExportedMarkdownFilename` (per device), coaching numbers (recomputed from segments; filler preferences are per device so numbers may differ slightly between devices, which is already true between the Mac and the phone), the live recording state.

The webhook payload stays as it is. It is a lossy export shape (resolved speaker labels, no segment ids) and is the right shape for the REST API's default response, but not for sync.

### Sync protocol

All routes require device auth (`checkClientAuth`, `kind === 'device'`, legacy `X-API-Key` callers refused) and the ES256 `X-Request-Proof` on writes. Rate limits are account-keyed, new `sync_*` entries in `lib/ratelimit.ts`. Node runtime, not edge.

- `GET /api/sync/manifest` → `[{id, revision, updated_at, deleted}]` for the account. Used on first enable, after a cursor gap, and by the "repair" button.
- `GET /api/sync/changes?since=<seq>&limit=50` → `{changes: [{seq, id, revision, kind, document?}], next_since, has_more}`. Deletes carry no document.
- `PUT /api/sync/meetings/{id}` with body `{base_revision, document}`. `base_revision` is the revision the client last saw (0 for new). On match: write, `revision + 1`, append a change row, return `{revision}`. On mismatch: `409 {server_revision, server_updated_at, document}`; the client resolves (below) and retries with the new base. Body limit 2 MB; over that the server returns `413 meeting_too_large` and the client marks the meeting skipped and shows it in Settings → Cloud, instead of retrying forever.
- `DELETE /api/sync/meetings/{id}` with `{base_revision}` → tombstone, change row.
- `GET /api/sync/status` → bytes, meeting count, tier allowance, oldest retained change seq.
- `DELETE /api/sync/account` → removes every meeting and token for the account (the Settings "Delete cloud copy" action).

**Conflicts.** Last writer wins per meeting on `updated_at`, with one override: a document whose `transcript_revision` is lower than the server's never replaces the server's segments (trims are destructive and must not be undone by a stale device). Two devices rarely edit the same meeting at once; when they do, the later edit wins and the earlier device sees the result on its next pull. No field-level merge in v1; the document is small enough that whole-document replacement is correct and testable.

**Push triggers.** The engine never reads live recording state. It only reads committed SwiftData rows where `updatedAt > syncedAt` and `endTime != nil` and `syncExcluded == false`, so an in-progress recording is never uploaded and the save queue's revision fence stays the single truth. Triggers: 5 s after any `commit` or finalized save (debounced per meeting), app becomes active, every 5 minutes while the app is open, and after each successful pull. On iOS a push that was running when the app backgrounds completes under the same background-task lease the save fence uses.

**Pull triggers.** App becomes active, every 60 s while in the foreground (the Mac and the phone are usually both open during a meeting day), and after a push. The poll is cheap by design: every write bumps `sync:seq:{account}` in Redis, and `GET /api/sync/changes` answers from that key with `304`-style "nothing new" without touching Postgres unless the sequence moved past the client's cursor, so the database can sleep through idle hours (see Costs). Applying a pull: on the main actor, through `AppState+Persistence.commit` with new operation cases (`.syncInsert`, `.syncUpdate`, `.syncDelete`), never across a task hop with a model object in hand, and never for an id in `deletedMeetingIDs`. After inserts the engine posts `.minitiMeetingsImported` so the macOS History list reloads; iOS `@Query` views update on their own.

**Upload of the backlog.** On first enable the engine lists local meetings, fetches the manifest, and uploads oldest first in batches of 10 with progress in Settings → Cloud ("312 of 1,140 meetings uploaded"). It is resumable: the dirty flags are the queue, there is no separate payload queue to lose. A fresh install that restores the recovery key and turns sync on downloads the same way.

**Why not the DeliveryOutbox.** It fails items after 24 h and 5 attempts, carries payload bodies, and `removeAll(forMeeting:)` on delete would erase a pending sync delete. Sync state belongs in the rows (`syncedAt`, `cloudRevision`, tombstones), not in an outbox. The outbox stays for webhooks and CRM.

**No realtime in v1.** Polling at 60 s in the foreground is enough for "finish the meeting on the Mac, open the phone". Silent push through APNs is the later upgrade; it needs an APNs key and a device token registry and is not a blocker.

### Client changes (Swift)

**Schema**, all additive, lightweight migration:

- `Meeting.updatedAt: Date?` (nil for existing rows; treated as `max(startTime, insightsUpdatedAt, transcriptEditedAt)` until first write). Set in every write path: rename, pin, speaker edits, corrections, trims, notes, template change, insight regeneration, final insights. The one place that makes this safe is `AppState+Persistence.commit`, which every one of those paths already goes through; the live save path (`persistMeetingSavePayload`) sets it too.
- `Meeting.syncedAt: Date?`, `Meeting.cloudRevision: Int = 0`, `Meeting.syncState: String?` (`skipped_too_large`, `conflict_pending`), `Meeting.syncExcluded: Bool = false`.
- New `@Model final class MeetingTombstone { id: UUID; deletedAt: Date; cloudRevision: Int }`, added to `PersistentStore.schema`. Written inside the same transaction as every hard delete (`noteMeetingDeleted` callers), removed once the server acknowledges. Adding an entity is a lightweight migration; it is still tested against a copied 2.12.1 store on both platforms using the DEBUG `-MinitiStoreURL` override before any other client work, because the v1.24.0 incident is the reason this file exists.

**`SyncEngine`** (`Miniti/Services/SyncEngine.swift`, shared by both targets): a `@MainActor` `ObservableObject` owned by `AppState`, with `enabled`, `status` (idle, pushing n of m, pulling, paused: private mode, paused: offline, error), `lastSyncedAt`, `cloudBytes`, `cloudMeetingCount`. It talks to the backend through `MinitiAPIService.send(_:)` so bearer tokens, proofs, refresh, and the `invalid_proof` recovery stay in one place. The encoder/decoder lives in `MeetingSyncDocument.swift`, a pure struct with round-trip tests against fixtures shared with Linux (`../miniti-api/test/fixtures/sync-documents/`).

**Settings → Cloud** (macOS `SettingsView.swift`, iOS `SettingsView_iOS.swift`, new `SettingsGroup.cloud` with the single destination `SettingsDestination.cloud`, `SettingsSearchCatalog` rows `cloud.sync`, `cloud.signin`, `cloud.status`, `cloud.connected`, `cloud.tokens`, `cloud.delete`):

- The switch: "Keep a copy of your meetings on miniti's servers". Copy under it: "miniti keeps a copy and can read it, so your other devices, your tools and you on the web can too. Off by default." A Pro line when the tier does not allow it; one sentence and nothing else in BYOK mode.
- Turning it on opens one sheet: what will be uploaded (count and size), the sentence above, an optional email field ("Add an email to sign in on the web and connect tools like Claude. You can skip this."), and Turn on. Skipping keeps the account anonymous; the email can be added later from the same tab.
- Web sign-in: the email on the account (add, change, remove), "Send me a sign-in link", and the list of connected apps with their granted scope, last use and a Disconnect button (these are the OAuth grants).
- Status line: last synced, meetings in the cloud, size, a "Sync now" button, and the skipped list if any.
- API access: token list (name, prefix, created, last used), New token (name, scopes read only in v1, shown once with a copy button), Revoke. The MCP URL and the Claude Code and Claude.ai connection steps in two lines each.
- Delete cloud copy: confirmation sheet, then `DELETE /api/sync/account`, local meetings untouched, `syncedAt` cleared.
- Per meeting: History context menu gains "Keep off the cloud" / "Put on the cloud" (toggles `syncExcluded`; turning it on sends a delete for that id). Meetings with `syncExcluded` show the same lock the Home card already uses for private meetings.

**Private mode.** `setPrivateMode(true)` adds `cloudSyncEnabled` to the `PrivateModeRestore` snapshot and turns it off; `setPrivateMode(false)` restores it. While private mode is on the engine is paused (no push, no pull; the policy copy says the model download and update checks are the only network activity, and that stays true). Any meeting started while private mode is on is created with `syncExcluded = true` and keeps it after private mode ends; the user can put it on the cloud per meeting. `PrivateModeTests` gain cases for the snapshot, the pause, and the flag.

**Account events.**

- Sign out: engine off, bookkeeping cleared (`syncedAt = nil`, `cloudRevision = 0`, tombstones dropped), local meetings kept. Re-enrolling later re-uploads by id; the server upserts.
- Move this device to another account (`attachToAccount`): the device's meetings now belong to the destination account. Bookkeeping is cleared so they upload there; the source account's cloud copies stay where they are until that account deletes them. Settings says this in the move sheet.
- Delete account: the backend purge runs; locally the same as sign out.
- Device removed by another device: the next request fails auth, the engine shows "This device was removed from the account" and stops; local data stays.

### Web sign-in

The account stays anonymous unless the user adds an email. The email is a web identity only: it signs the user into miniti.app for OAuth consent and, later, a web History; it never enrolls a device, and restoring a device still needs the recovery key. That keeps the existing device model intact and limits what a stolen mailbox gives an attacker to what the web can see (reading meetings, which is already a lot, so the sign-in email says which device added the email and how to remove it).

- Adding an email is a device write (`POST /api/account/email`, proof required). The server sends a confirmation link through Resend; the email is attached only after the click. One email per account, one account per email; attaching an email already on another account is refused with a sentence that points at the recovery key move flow.
- `POST /api/web/login` takes an email and sends a magic link (15 minute, single use, hashed at rest, rate limited per email and per network bucket). The link lands on `miniti.app/signin` (hosted by `miniti-api`, dark theme like the admin and Attio pages) and sets a `miniti_web_session` cookie (HttpOnly, Secure, SameSite=Lax, 30 days, revocable, same stateless HMAC shape as the admin session plus a KV revocation list).
- Settings → Cloud lists web sessions and connected apps and can end any of them; removing the email ends every web session and OAuth grant.
- Tables: `account_emails`, `login_links`, `web_sessions`.

### OAuth 2.1 authorization server

Everything the MCP authorization spec (2025-06-18) asks of a remote server, on Node routes in `miniti-api`:

- `/.well-known/oauth-protected-resource` for `/api/mcp` and `/api/v1`, pointing at the authorization server; `/.well-known/oauth-authorization-server` with PKCE S256 required, `code` and `refresh_token` grants, DCR endpoint, revocation endpoint, scopes `meetings:read` (v1) and `meetings:write` (later).
- `POST /oauth/register`: dynamic client registration, public clients only (`token_endpoint_auth_method: none`), redirect URIs stored verbatim and matched exactly, 30 day idle expiry for unused clients. Claude.ai, ChatGPT, Cursor and Claude Code all register this way.
- `GET /oauth/authorize`: requires the web session (else redirects to the sign-in page and back), shows the consent page (client name, scopes in plain words, the account's meeting count), issues a 60 second single-use code bound to the PKCE challenge and redirect URI.
- `POST /oauth/token`: code exchange and refresh. Access tokens are opaque, `mna_` prefix, 1 hour, stored hashed in `api_tokens` with `kind: oauth`, `client_id`, `grant_id`; refresh tokens rotate within a family and reuse revokes the family (the same rule the device refresh tokens follow).
- `POST /oauth/revoke`: by token; the Settings Disconnect button revokes the whole grant.
- Tables: `oauth_clients`, `oauth_codes`, `oauth_grants`; tokens in `api_tokens`.
- Tests: metadata shape, DCR validation, PKCE mismatch, redirect mismatch, code reuse, refresh rotation and reuse revocation, consent requires a session, revoked grant fails the MCP call. A live check against Claude.ai's connector flow and Claude Code before release.

### REST API

Two bearer credentials, one verifier (`lib/apiTokens.ts`): OAuth access tokens from the flow above, and personal access tokens for scripts, `mnt_` prefix, 32 random bytes base64url, stored as sha256, created only from an enrolled device (write route with proof). Scopes in v1: `meetings:read`. Node runtime, rate limited per token (60/min) and per account. Every call records `last_used_at` so Settings can show it.

- `GET /api/v1/meetings?since=&until=&q=&cursor=&limit=` → list of meeting summaries (no transcript), newest first, `next_cursor`. `q` uses the Postgres tsvector; `with:` style operators from `MeetingSearchQuery` are a later slice.
- `GET /api/v1/meetings/{id}` → the webhook payload shape (`WebhookService` fields, resolved speaker labels, coaching computed server-side from segments in a port of `TrainingMetrics`, or omitted in v1 and listed as a follow-up).
- `GET /api/v1/meetings/{id}/transcript?format=json|markdown|srt`.
- `GET /api/v1/me` → account id, tier, counts, the credential's scopes and client.
- Writes (`notes`, action item done, rename) are `meetings:write` in a later slice; they go through the same `PUT /api/sync/meetings/{id}` path with a token actor so devices pull them like any other change.

Errors follow the existing `{error, message}` shape. The API is documented on miniti.app/docs with a curl example; the doc page is part of the release.

### MCP server

`POST /api/mcp` (Streamable HTTP, stateless, Node runtime) using `@modelcontextprotocol/sdk`. Tools: `list_meetings(since?, until?, query?, limit?)`, `get_meeting(id, include_transcript?)`, `search_meetings(query, limit?)`, `get_action_items(since?)`. Resources: `miniti://meetings/{id}`. Every tool result is the REST JSON, so there is one serializer. Tool descriptions are short and the server never summarises on the user's behalf; it hands transcripts to the caller's model.

Auth: a bearer token in the `Authorization` header, either an OAuth access token (Claude.ai and ChatGPT connectors, Claude Code and Cursor through their OAuth flows, which discover the authorization server from the protected-resource metadata and a `WWW-Authenticate` header on 401) or a personal access token (`claude mcp add --transport http miniti https://api.miniti.app/api/mcp --header "Authorization: Bearer …"`, scripts). Both resolve to an account id and scopes through the same verifier.

### Backend operations

- `CLOUD_SYNC_ENABLED` env kill switch; `CLOUD_SYNC_ALLOWLIST` of account ids for the staged rollout; both read at request time, never at module scope.
- `DATABASE_URL` from the Neon integration; `lib/syncStore.ts` holds all SQL behind a small interface; `lib/syncStore.memory.ts` is the in-memory implementation for route tests (the Redis shim pattern in `test/setup.ts`); one integration test file runs against a Neon branch when `SYNC_TEST_DATABASE_URL` is set and is skipped otherwise.
- Admin: a Storage card (accounts syncing, total bytes, largest accounts) and a `neon` line in the cost ledger (`lib/ledger.ts`, basis `actual` from the Vercel marketplace bill, else `estimate` from `account_storage`).
- Backups: Neon point-in-time restore covers the 7 day window on the launch plan; document the restore procedure in `docs/agents/05-runbook.md` before the first real account syncs, per the roadmap's backup guardrail.
- Client events: `sync_enabled`, `sync_disabled`, `sync_push_failed`, `sync_conflict`, `sync_skipped_too_large` (sizes and codes only, never content), so the admin dashboard shows adoption and failure rate.

### Quiet-mic live transcript (bundled fix, not sync)

Field report 2026-10-15 (new macOS user, 2.12.1, talking to the Mac alone, all permissions granted, Ian watching): nothing appeared for 5 to 10 s after pressing record, then a lot at once. Backend evidence for that device: Deepgram connected 1 s after start and 292 characters were transcribed in a 21 s session, so audio and Deepgram were fine; the wait was on the display side.

Cause, from code. With system audio on (the macOS default) every mic result passes through `AudioCaptureService.dominantSource(from:to:)` before it is shown. That check has a hard floor, `micSpeechFloor = 200` (Int16 RMS, about 0.006 of full scale): below it the words are tagged `.system` even when the system tap is completely silent. Two things then happen in `AppState`:

- `handleTranscriptUpdate` drops the interim line outright (`case .system: return`), so nothing types while the person speaks.
- The final-segment path holds each finished sentence in `pendingMicSegments` for `micEchoReconciliationDelay` (4 s) to reconcile against a system transcript that does not exist, then releases it. Add Deepgram's 1 to 3 s to finish a sentence and the result is the 5 to 10 s gap, then a burst.

Fix. When the system side carries no energy over the window there is no echo to suppress, so `dominantSource` returns `.mic` (or `.unknown`) regardless of mic loudness; the floor only applies when the system side is above its own floor. Keep every other branch as it is so real calls keep the echo guard. Add one diagnostics event, `first_transcript`, with milliseconds from `startRecording` to the first non-empty interim and to the first final, so the next report like this is answered from admin events instead of from reading code. Unreproduced on Ian's Mac; the 2 minute check is: system audio on, talk softly from a metre away, the live line must appear within 2 s.

### Linux

Same protocol, same fixtures, same document shape. Differences to absorb on the Linux side: `import_source: "granola:<id>"` splits into `external_source` + `external_id`; attendee `name` maps to the wire `name` (Swift maps `displayName`); epoch seconds become ISO 8601; `created_at` is kept on the wire. Linux has no private mode, so `sync_excluded` is only user-set there. The additive SQLite migration pattern (`db/mod.rs`) takes the same five columns plus a `meeting_tombstones` table. Note in `../miniti-linux/PLAN.md` on the day the contract lands.

## As built and shipped (2026-10-16): the nuances a future agent needs

Everything above is the design. What actually ships in 3.0.0, and the edge cases that were found while building, testing and releasing it:

**Where the code is.** Client: `CloudSyncEngine` (engine), `MeetingSyncDocument` (wire form, fingerprint, id-based segment diff), `MinitiAPIService+Cloud` (transport), `AppState+CloudSync` (host, gates, Settings actions, email join), `MeetingTombstone`, `CloudSettingsView` (tab, enable sheet, log sheet, MCP snippets), `EmailSignInSheet` in `ManagedAccountViews`. Backend: `lib/cloud.ts` (guards, seq cache, purge), `lib/cloudStore.ts` (Postgres and memory twin), `lib/syncDocument.ts`, `lib/accountUsage.ts`, `lib/apiTokens.ts`, `lib/meetingApi.ts`, `lib/mcpServer.ts`, `lib/oauth.ts`, `lib/webSession.ts`, `lib/loginLinks.ts`, `lib/email.ts`, `lib/webPages.ts`, `lib/webAccount.ts`; routes under `app/api/sync`, `app/api/account`, `app/api/v1`, `app/api/mcp`, `app/oauth`, `app/signin`, `app/account`, `app/.well-known`, `app/api/web`, `app/api/auth/email`, `app/api/cron`. Contract: `../miniti-api/docs/agents/08-cloud.md`. Shared fixture: `../miniti-api/test/fixtures/sync-documents/meeting-v1.json`, embedded verbatim in `MeetingSyncDocumentTests`.

**Dirty detection and cadence.** No write path stamps anything. `scan` fingerprints every finished, non-excluded meeting (JSON columns canonicalised with sorted keys, sets sorted, no transcript text; `transcriptRevision` covers trims and corrections) and stamps `updatedAt` when the fingerprint moved; a legacy meeting's first observation keeps its own latest timestamp. The scan runs after any `commit` (5 s debounce), on activation, on the switch, and on every fifth 60 s poll; a plain poll only pulls. Every loop re-checks the pause reason between awaits, so private mode stops a backlog mid-way. The engine's phase, last-synced time and log are `@Published` on the engine itself; Settings observes the engine directly because `AppState.cloudSync` is a `let`.

**Deletes.** A user delete writes a `MeetingTombstone` whenever the meeting had a cloud copy or the switch is on, so a delete during the first upload still reaches the cloud; a `PUT` that completes for a meeting deleted meanwhile writes the tombstone itself. A tombstone that conflicts with a later edit elsewhere is retried with the server revision: the delete wins. Pulled deletes remove the local copy only when it had a cloud copy (`cloudRevision > 0` or a sync fingerprint). Meetings the cloud no longer lists are re-uploaded, never deleted.

**Conflicts.** Server tombstones win. A lower `transcript_revision` never replaces the server's segments; a device that renamed on a stale transcript takes the server's transcript, keeps its own scalars, and pushes the merge. Otherwise last writer wins on `updated_at` with one retry. `external_duplicate` (the same Granola CSV on two devices) replaces the local copy with the cloud one. `413` marks the meeting `skipped_too_large` and stops retrying until it changes. Pulled transcripts are applied by segment id, never by dropping every row, so a History view holding segments keeps valid objects. Documents without `end_time` are ignored (they are live meetings elsewhere).

**Account and device ids.** Usage records are keyed by the id as the app sends `X-Device-ID` (Swift sends `uuidString`, uppercase) while the auth layer lowercases, so one install can have two `device:` records with the subscription on only one. `deviceTier` (cloud gate), `findSponsor` (account-wide Pro) and `otherDevicesUsage` read both spellings. Minutes and docs lookups are per account since 3.0.0: counters stay per device, `withAccountUsage` adds the other installations at read time inside `getOrCreateDevice`; a record past its reset date counts as zero. A device that joined by email stores an empty recovery key; Settings → Account offers "Create one" (rotate), and the 2.12.1 `invalid_proof` auto re-bind cannot run for it.

**Email and web.** Adding an email sends a confirmation link; the email is attached only on click; the confirmation page hands back to the app through the `miniti-cloud://` scheme (both targets register it, Settings → Cloud reloads on `.minitiCloudCallback`). Magic links are 15 minutes and single use; the account page at `/account` lists plan, usage, devices, connected apps, tokens and sessions with the destructive actions only in the app. Emails use the website's Resend template (light title, green button, copy box, light and dark).

**Settings.** Cloud is a Setup tab under Account, one destination; the BYOK screen shows one sentence and its search rows are `requiresManaged`. The enable sheet counts the finished meetings that will upload. The log keeps 300 entries in UserDefaults. MCP snippets (Claude Code, Claude Desktop/Cursor/Windsurf JSON, Codex TOML, Gemini CLI, curl, and the Claude.ai/ChatGPT URL) carry the token only while a fresh one is on screen.

**Operations.** Neon project `miniti-api` (Frankfurt `eu-central-1`, Postgres 18) created through the Vercel Marketplace on 2026-10-16, so `DATABASE_URL` is injected by the integration; the first London project was deleted. Schema is applied with `npm run db:migrate` against the injected URL (`vercel env pull` to a gitignored file). `CLOUD_SYNC_ENABLED=true` since 2026-10-16; `CLOUD_SYNC_ALLOWLIST` was used for Ian's account during testing and removed before App Review. `pruneMaintenance` keeps each account's newest change row so an ancient cursor always gets `410`; the Redis seq cache is written forward-only. Vercel blocked Git deployments for a day when Ian signed into a second Vercel account with GitHub (the commit author mapped to a non-team member); re-signing into the team account with GitHub fixed it, and a git-free `vercel --prod --archive=tgz` from `git archive` was the workaround.

**Testing and release quirks.** Run tests through `fastlane mac test` and `fastlane ios test`; a direct `xcodebuild test` with `-only-testing` hangs the macOS host ("test runner hung before establishing connection"). The macOS test host shares the Mac's Keychain, so `AppState()` in a test may be enrolled. New Swift files need pbxproj entries and a path containing `+` must be quoted. The `fastlane mac release` lane does not bump `CURRENT_PROJECT_VERSION`; bump it and `CFBundleVersion` by hand before the lane (RELEASE.md step 1) and pass the same `build:N` to the iOS lanes. Apple's App Privacy labels cannot be set through an API key; Ian added Email Address and Other User Content, linked, App Functionality, on 2026-10-17.

**Not built.** APNs push (the Mac and phone poll every 60 s in the foreground), `meetings:write` scopes, a web History view, server-side coaching numbers in the API, Linux parity (tracked in `../miniti-linux/PLAN.md`), a Sparkle smoke test from 2.12.2 (no Mac on the old build was available), live checks of the Claude.ai connector and Claude Code with a real token.

## Costs (checked 2026-10-15)

Prices from neon.com/pricing, vercel.com/pricing and Resend's published plans on 2026-10-15. Neon is not part of Vercel: it is an independent company (owned by Databricks since 2025) whose native Vercel Marketplace integration replaced Vercel Postgres in late 2024 to early 2025. Installed through the Marketplace it is billed on the Vercel invoice like Upstash is today, so the admin ledger can read it the same way (`upstashFromVercel`). Ian's existing Neon project sits in his own org on the Free plan; installing the Marketplace integration creates a separate Neon org named Vercel, so the choice is: Marketplace for one invoice and the ledger (recommended), or the existing org and a configured ledger line.

**Unit prices**

| Item | Price |
|---|---|
| Neon Launch compute | $0.106 per CU-hour, no monthly minimum, scale to zero |
| Neon storage | $0.35 per GB-month |
| Neon instant restore history (Launch, up to 7 days) | $0.20 per GB-month of history |
| Neon egress | 500 GB per project included, then $0.10 per GB |
| Neon Free (allowlist phase only) | 100 CU-hours and 1 GB per project, 6 hour history, no card |
| Vercel Pro (already paid) | $20 per month with $20 usage credit |
| Vercel function invocations | $0.60 per million |
| Vercel Fluid active CPU | $0.128 per hour |
| Vercel fast origin transfer | $0.06 per GB |
| Upstash commands (Vercel marketplace, already paid) | about $0.20 per 100,000 |
| Resend | 3,000 emails per month free, then $20 per month for 50,000 |

**Per meeting and per user**

| Quantity | Estimate | Basis |
|---|---|---|
| Wire document, 30 minute meeting | 100 KB | 4,500 words of text at 150 words per minute is 27 KB; 300 segments carry ids, times, speaker, confidence; insights add 5 to 10 KB |
| Stored per meeting in Postgres | 150 KB | jsonb plus the tsvector and indexes, about 1.5 times the document |
| Pro typical, 33 meetings per month | 5 MB per month, 60 MB after a year | from the unit economics table in monetization.md |
| Pro heavy, 67 meetings per month | 10 MB per month, 360 MB after three years | |
| Backlog on first enable, 1,000 meetings | 150 MB once | |
| Storage cost per Pro user | $0.02 per month after a year, $0.13 after three heavy years | at $0.35 per GB-month |
| Egress per Pro user | under 20 MB per month, about $0.001 | 33 meetings pulled by one other device plus API reads |
| Foreground polling per Pro user | about $0.04 per month | 480 pulls per day on a Mac open 8 hours at 60 s: 14,400 invocations ($0.009), a Redis sequence check each ($0.03), a few seconds of CPU |
| Web sign-in email | $0 | well inside Resend's free tier until thousands of users |

So the marginal cost of cloud for a Pro user is 1 to 3 percent of the $5 subscription. Storage never matters at this size; polling and the Postgres compute floor are the costs that scale.

**The compute floor.** Neon bills while the compute is awake. With users spread over the day it will stay awake most of the time at the 0.25 CU minimum: 730 hours a month at 0.25 CU is 183 CU-hours, about $19 a month on Launch, before autoscaling during busy hours. That is the one fixed cost the feature adds. The plan keeps it near the floor by answering the 60 s poll from Redis (`sync:seq:{account}`, bumped on every write) and touching Postgres only when the sequence moved, so idle hours let the compute sleep and busy hours run small queries.

**Scenarios** (same mix as monetization.md: 15 percent Pro; half of Pro turn Cloud on; average 100 MB stored per syncing user after backlog)

| | 100 users | 1,000 users | 5,000 users |
|---|---|---|---|
| Syncing Pro users | 8 | 75 | 375 |
| Neon storage | 0.8 GB, $0.30 | 7.5 GB, $2.60 | 40 GB, $14 |
| Neon compute | $0 on Free during allowlist, then $19 to $25 | $25 to $35 | $60 to $150 (1 to 2 CU average) |
| Vercel invocations, CPU, origin transfer | under $1 | $3 to $5 | $15 to $25 |
| Upstash polling checks | under $1 | $3 | $15 |
| Resend | $0 | $0 | $0 to $20 |
| Total added per month | $20 to $27 | $35 to $45 | $105 to $225 |

The 100-user row is dominated by the $19 compute floor; it is the price of a real database before there are many users. (Revenue comparisons live in the private monetization notes.) Everything above the floor scales at roughly $0.10 to $0.15 per syncing Pro user per month.

**Not in these numbers.** Deepgram and OpenAI are unchanged; sync moves no audio and runs no models. A server-side coaching computation for the API would add CPU per read, not storage. A future web History adds Vercel bandwidth, not Neon cost. Engineering time is the real cost: in rough order, the backend store and sync routes, the client engine and settings, the OAuth server and sign-in page, then the API and MCP; the OAuth slice is about as large as the sync backend.

**Levers if it grows faster than revenue.** Poll every 2 to 3 minutes when the window is not frontmost; silent push to replace polling; a per-tier storage cap with "stop uploading and say so"; purging tombstones and `meeting_changes` on schedule (already in the design); Scale plan only if the 7 day restore window or branch count becomes limiting.

## Rules (regression contract)

- Everything is off until the user turns the switch on. With it off, no new route is called, no new column is read, and the only visible change is the Settings → Cloud tab.
- The engine never reads `currentMeeting` or live arrays; it reads committed rows. A recording in progress is never uploaded. A meeting in `deletedMeetingIDs` is never written by a pull.
- Pull writes go through `AppState+Persistence.commit` on the main actor. No model object crosses a task hop.
- A pulled meeting never fires `meeting.saved` or `meeting.updated` webhooks and never triggers Attio or Twenty auto-send. Those fire once, on the device that recorded or edited the meeting.
- Webhook and CRM sends for a locally edited meeting behave exactly as today; sync adds a push after them, never instead of them.
- Private mode on means the engine is paused and nothing is sent or received. Meetings recorded under private mode are `syncExcluded` for life unless the user changes that meeting.
- Sync never consumes managed minutes and never changes `canStartRecording`.
- Granola duplicates cannot be created by sync: the server enforces `(account, external_source, external_id)` uniqueness and the importer's `knownIDs` set already includes synced rows.
- A stale device cannot undo a trim: lower `transcript_revision` never replaces higher.
- Deleting a meeting locally deletes it everywhere; the confirmation copy says so when sync is on ("Delete on all devices").
- Nothing in this plan changes `ClientAuth`, token formats, or the shared auth vectors. Personal access tokens and OAuth tokens are new, separate credentials with their own vectors file.
- BYOK never syncs. `cloudSyncEnabled` is ignored in BYOK mode, the engine pauses on a switch to BYOK, and no BYOK install ever calls a `/api/sync/*`, `/api/v1/*`, `/oauth/*` or `/api/mcp` route.
- The web email never enrolls a device or restores an account. Device enrollment and recovery stay on the recovery key; a stolen mailbox cannot add a device.
- Cloud is a Setup tab under Account (moved out of its own group on 2026-10-16); single-word tabs and one question per tab hold.
- Managed accounts with sync off, BYOK installs, and installs below 3.0.0 are unaffected by the backend deploy: the new routes are additive and the old routes do not change.
- Quiet-mic fix: a mic result is never tagged `.system` while the system side is silent; with system audio off, or on iOS, nothing changes; a real call with both sides talking keeps today's echo suppression and 4 s reconciliation.

## Tests

- `MeetingSyncDocumentTests`: round trip of every `Meeting` field, uppercase and lowercase id parsing, unknown-field echo, MEDDPICC object mapping, attendee key mapping, fixtures shared with Linux and the backend.
- `SyncEngineTests` with the injectable `persistenceSaveHandler` and a fake transport: push selection (dirty, finished, not excluded), debounce, backlog batching and resume, 409 resolution both ways, trim-revision guard, 413 skip, pull insert/update/delete through `commit`, tombstone lifecycle, `deletedMeetingIDs` respected, notification posted after inserts, no webhook enqueued for pulled meetings.
- `PrivateModeTests`: snapshot includes the sync flag, engine paused, `syncExcluded` set on meetings started under private mode and kept after.
- `AppStateComputationTests`: the new `cloud` group and destination, its search ids, BYOK hides every row but the sentence.
- `dominantSource` table test: quiet mic plus silent system is `.mic`; quiet mic plus loud system is `.system`; loud mic plus loud system follows the 2x rule; the existing echo fixtures in `MeetingHandoffTests` and the interim-gating tests still pass. One `first_transcript` event per recording, with both durations, asserted in the diagnostics tests.
- Store migration: open a copied 2.12.1 `default.store` with the new schema on macOS and the iOS simulator, read every meeting, write one, reopen with 2.12.1 (expected to fail cleanly, documented).
- Backend: route tests for every `/api/sync/*`, `/api/v1/*`, `/api/account/email`, `/api/web/*` and `/oauth/*` route with the in-memory store, token hashing and revocation, magic-link single use and expiry, allowlist and kill switch, Pro gate, purge on `deleteAccount` (meetings, tokens, grants, emails, sessions), account-keyed rate limits, proof required on writes, legacy and BYOK callers refused; one Neon-branch integration test for the SQL.
- Manual matrix (in `docs/testing.md`): Mac records, phone sees it; phone records, Mac sees it; rename on both within a minute; trim on the Mac then edit speaker names on the phone; delete on one; Granola CSV imported on both devices; private meeting on the Mac stays off the phone; sign out and back in; move device to another account; airplane mode for an hour then reconnect; 1,000-meeting backlog upload with the app backgrounded on iOS; token in Claude Code lists and reads a meeting; revoke token, call fails; add an email, sign in on the web from a magic link, connect Claude.ai through the connector flow, read a meeting there, Disconnect in Settings and watch the connector fail; let Pro lapse and watch sync pause with the right line.

## Sequencing

1. Decisions above, then the contract in `../miniti-api/docs/agents/04-api-reference.md` and the fixtures.
2. Store migration test on both platforms with the new columns and tombstone model, nothing else in the diff.
3. Backend: Neon schema and `lib/syncStore.ts`, `/api/sync/*`, purge hooks, kill switch, allowlist, tests, admin storage card, runbook backup note. Deploy with `CLOUD_SYNC_ENABLED=false`.
4. Client: `MeetingSyncDocument`, `SyncEngine`, Settings → Cloud, private mode, account events, tests. Ian's account on the allowlist; the real manual matrix.
5. Web sign-in (email, magic link, sign-in page, sessions) and the OAuth server, with their tests and the live Claude.ai and Claude Code checks.
6. REST API, personal access tokens, MCP server, docs page, the connection steps in Settings.
7. Privacy policy (cloud copy, email, Resend and Neon as subprocessors), changelog, `docs/architecture.md`, `docs/patterns.md`, `docs/monetization.md` tier table, `settings-redesign-plan.md`, AGENTS.md feature lists and settings groups, Linux note.
8. Staged rollout: allowlist, then Pro. `meetings:write` and the web History view are later slices on the same foundation.
9. Bundled quiet-mic fix: `dominantSource` floor change, `first_transcript` diagnostics event, tests, the manual soft-voice check, changelog bullet tagged (macOS). Independent of every step above; can land first in the 3.0.0 branch.

## Open questions

- Storage allowance per tier and what happens at the cap (stop uploading and say so; never delete).
- Whether coaching numbers are computed server-side for the API or left to clients in v1.
- APNs silent push for near-instant pulls, and whether the Mac polls faster during a calendar meeting window.
- A web view of History at miniti.app: the sign-in page and sessions built here are its front door; the view itself is a later slice.
- Passkeys instead of, or next to, the email magic link: cleaner and phishing-resistant, but Linux browsers and cross-device sign-in need the QR flow; revisit after the email path ships.
