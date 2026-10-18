# P0 hardening batch: admin auth, store recovery, persistence errors, regression tests

Working plan, started 2026-09-13. This file is the status record for the batch; the roadmap keeps the priority. **Shipped as miniti 2.9.0 (build 120) on 2026-09-13**: macOS live via Sparkle and DMG the same afternoon, iOS build 120 submitted for review the same day; Sparkle update from 2.8.0 verified on a real Mac. Backend: admin auth 93940d2, CRM template notes ec9a7e2, appcast and version 9e60b05.

## Status

| Part | Item | State | Notes |
| --- | --- | --- | --- |
| 1 | P0.1 Phase 1 admin auth (miniti-api) | deployed 2026-09-13 (miniti-api 93940d2) | `lib/adminAuth.ts`, `POST/DELETE /api/admin/session`, four routes on `checkAdminAuth`, dashboard on the cookie. Secrets set in prod + preview, pushed, verified live: no-cookie and client-key admin reads 401, cross-origin login 403, `/api/usage` with the client key still 200, dashboard sign-in, label change, and sign-out done by Ian |
| 2 | P0.2 SwiftData startup recovery | built | `PersistentStore.swift` (open, read-only fallback, classification, `-MinitiStoreURL` drill flag), `StoreRecoveryView.swift`, both entry points free of `fatalError`, Settings export/import degrade. 13 tests green on macOS and iOS 2026-09-13. iOS simulator drill run 2026-09-13 with `-MinitiStoreURL` on a garbage file: recovery screen rendered with the corruption copy, scratch file byte-identical afterwards. macOS drill done by Ian 2026-09-13: corrupt store showed the screen, every button worked, file byte-identical, a fresh scratch store launched normally; sandbox denial now classifies as `io` (found during the drill) |
| 3 | P0.3 persistence commit policy + banner | built | `AppState+Persistence.swift`, `PersistenceIssueBanner.swift`, all 34 saves and 6 fetches migrated, `.saveFailed` correction outcome, stale finalization gated on the save. Design change during build: no `rollback()` (SwiftData traps on a rolled-back cascade delete), failed deletes stay pending and retry. 18 tests green on macOS 2026-09-13; full macOS suite green |
| 5 | P2.1 custom template editor (headline for 2.9.0) | built | macOS 729 / iOS 683 tests green 2026-09-13, backend 421; smoke gate passed on both platforms with the new `settings-templates` scene. Backend note change (`formatMeetingNoteContent` template block) is uncommitted in miniti-api and must deploy before the client ships | Templates page in Settings on both platforms, sheet editor with validation and a preview against a past meeting, custom templates in the More menu, meetings keep a copy of their template, template sections in Attio/Twenty notes, JSON export/import |
| 4 | P0.6 transport seam, journey tests, smoke gate, coverage | built | `MinitiAPIService(session:auth:)`, `InsightsService(session:)`, Deepgram config/endpoint seams, XCTest host skips launch network; `TestSupport.swift` + transport, calendar wire-format, journey, and six-series Coaching tests; `scripts/screenshots/smoke.sh` with iOS ready marker and `store-recovery` / `persistence-issue` scenes; `code_coverage: true` on both lanes + `scripts/coverage.sh`. Full suites green 2026-09-13: macOS 713 tests, iOS 667. Coverage 24.8% overall (Services 51.6%, Models 42.8%, Views 12.3%), dated table in testing.md. Smoke gate passed: iOS 15/15 scenes on the simulator, macOS 13/13 on 2026-09-13. Real-app network check done by Ian 2026-09-13 on the Debug build: usage, calendar, Deepgram session, live save, and post-stop insights all flowed through `MinitiAPIService(session:auth:)`; no persistence failures in the debug log. Nothing owed before release |

## Part 5. P2.1: custom insight templates (added 2026-09-13, same release)

- **Model**: `InsightTemplate` is reused unchanged. Custom templates get ids `custom_<12 chars>`, a default icon, and a short name derived from the name. `CustomInsightTemplates` (new file) owns storage in UserDefaults (`customInsightTemplates.v1`, like the personal dictionary), validation against the existing limits (8 sections, 60-char titles, 300-char guidance, 60-char name), section-key derivation from titles, JSON export/import, and a `Draft` type the editor edits.
- **Resolution**: `AppState.insightTemplate(id:)` = built-in, else custom. `availableInsightTemplates` = built-ins then custom. Every `InsightTemplate.builtIn(id:)` lookup in AppState and the views goes through it. `Meeting` gains `templateDefinitionJSON`, written whenever a template is applied to a meeting, so history, exports, webhooks, and CRM sends keep rendering after a custom template is edited or deleted (built-ins are still resolved by id).
- **UI**: `SettingsDestination.templates` ("Templates") on both platforms. The page lists built-ins (duplicate) and yours (edit, duplicate, export, delete, new, import). The editor is a sheet: name, summary, sections with title and guidance, live validation, and "preview with a meeting" that runs the template against a chosen past meeting without saving anything. The More menu's Templates submenu lists custom templates under the built-ins plus "manage templates…".
- **CRM**: `AttioMeetingPayload` carries `template { name, sections[{title, value}] }`; `formatMeetingNoteContent` in `miniti-api` prints it after MEDDPICC (Attio and Twenty share it). Backend change is additive and must deploy before the client ships.
- **Not in scope**: free-text prompts, cross-device sync (export/import covers moving one), versioning beyond "edit in place".
- **Tests**: `CustomInsightTemplateTests` (validation, key derivation, store round trip, export/import, resolution, deleted-template rendering from the meeting snapshot, duplicate of a built-in); backend `attio.test.ts` template block.

## Context

`docs/roadmap.md` ranks these as the top open P0 items. Ian chose to do four of them now and defer CI (P0.5), the abrupt-kill window (P0.4), the 60-minute Instruments run (P0.7) and doc reconciliation (P0.10):

- **P0.1 Phase 1** (miniti-api): every `/api/admin/*` route still authenticates with `API_SECRET_KEY`, the same legacy client secret. Any device could read and mutate admin data. Replace it with a server-only admin secret and a signed session cookie.
- **P0.2** (miniti): both app entry points `fatalError` when the SwiftData container cannot open, so a corrupt or unmigratable store makes the app unlaunchable exactly when the user needs to export.
- **P0.3** (miniti): 28 of 34 production `save()` calls are `try?`, 5 of 6 fetches collapse failure into "return early", and nothing reaches the user. Decision taken: **app-root banner + DebugLogger line + diagnostics event**.
- **P0.6** (miniti): no network mocking, no journey tests, no coverage measurement. Decision taken: **no XCUITest target**; harden logic tests, add a transport seam, and turn the screenshot harness into a launch smoke gate.

Nothing gets committed or deployed by me; Ian commits and runs the rollout steps. Order of work: Phase 1 backend first (independent repo), then P0.2, P0.3, P0.6 in the app.

---

## Part 1. P0.1 Phase 1: separate admin authentication (miniti-api)

### Design

Stateless HMAC-signed session cookie with a KV revocation list, so logout genuinely invalidates and the test KV stub (no TTL support) can still exercise expiry through a fake clock.

- **New `lib/adminAuth.ts`** (Edge-safe, WebCrypto only, because 3 of 4 admin routes are `edge`). Reuse `hmacSha256`, `timingSafeEqualBytes`, `b64urlEncode/Decode`, `randomId` from `lib/clientAuth.ts`.
  - `adminConfigured()`: both `ADMIN_SECRET_KEY` and `ADMIN_SESSION_SECRET` present and non-empty, else every admin route returns `500 internal_error` "Server misconfigured" (fail closed, mirrors `checkApiKey`).
  - `verifyAdminSecret(provided)`: constant-time compare of UTF-8 bytes against `ADMIN_SECRET_KEY`, no length leak.
  - `issueAdminSession(now)`: token `v1.<b64url payload>.<b64url sig>`, payload `{ jti, iat, exp }`, `exp = iat + 12h`. Cookie `miniti_admin_session=<token>; Path=/api/admin; HttpOnly; Secure; SameSite=Strict; Max-Age=43200`.
  - `verifyAdminSession(request, now)`: parse cookie header manually (no `next/headers`, the test shim replaces `NextResponse`), check signature, `exp`, and `kv.exists('admin_session_revoked:<jti>')`.
  - `checkAdminAuth(request, { mutation })`: returns `Response | null` like `checkApiKey`. Mutations additionally require `Origin` header equal to `new URL(request.url).origin` (missing Origin is rejected). Never falls back to `X-API-Key`.
  - `revokeAdminSession(jti, exp)`: `kv.set('admin_session_revoked:<jti>', 1, { ex: remaining seconds })`.
  - `logAdminEvent(event, fields)`: same `[admin] event=<name> k=v` shape as `logAuthEvent` in `lib/clientAuth.ts:598`. Events: `admin_login_success`, `admin_login_failed` (reason: bad_secret | rate_limited | misconfigured), `admin_logout`, `admin_session_rejected` (reason: missing | bad_signature | expired | revoked | bad_origin), `admin_device_updated` (device prefix + fields changed, no values that are secrets). Never log the secret or the token.
- **New route `app/api/admin/session/route.ts`** (`edge`):
  - `POST` body `{ secret }`. Rate-limit by network bucket: add `admin_login: { maxRequests: 5, windowMs: 60_000 }` to `LIMITS` in `lib/ratelimit.ts` and key on `bucket:${await networkBucket(request)}` (from `lib/clientAuth.ts:491`). Wrong secret → 401 with the same timing as success path. Success → `204` with `Set-Cookie`, via `Response` headers (not `NextResponse.cookies`).
  - `DELETE`: requires a valid session, revokes its `jti`, returns `204` with an expiring `Set-Cookie` (Max-Age=0).
- **Replace `checkApiKey` with `checkAdminAuth`** in `app/api/admin/{client-events,costs,devices,usage-chart}/route.ts`. `POST /api/admin/devices` passes `{ mutation: true }` and replaces its three prose `console.log` lines with `logAdminEvent('admin_device_updated', …)`.
- **Dashboard `app/admin/page.tsx`:**
  - Delete the `admin_key` `sessionStorage` read/write/remove (lines 224-227, 326-329, 337) and the `X-API-Key` header from all 7 fetches.
  - Add one `adminFetch(path, init)` helper: `credentials: 'same-origin'`, and on `401` sets `authenticated=false` and `sessionMessage='session expired, sign in again'`. Route all 7 calls through it so the 6 that currently swallow 401 handle expiry.
  - Login form posts to `POST /api/admin/session`; the password field state is cleared after submit. Add a "sign out" button calling `DELETE`.
  - Keep `.cursor/skills/admin-dashboard/SKILL.md` accurate (line 17 mentions sessionStorage).
- **Env and docs:** `.env.example` (two new vars with `openssl rand -base64 48` hint), `docs/agents/02-environment.md` (two new rows; rewrite the `API_SECRET_KEY` row to "clients only"), `docs/agents/04-api-reference.md` (line 58 "Admin routes are unchanged" claim, headers table, admin route notes, new session endpoints, dashboard section), `docs/agents/05-runbook.md` (lines 12, 102, 107, test inventory), `.cursor/skills/vercel-deploy/SKILL.md:52`.

### Tests (vitest, `test/setup.ts` stub)

- `lib/adminAuth.test.ts`: missing env → 500; wrong secret → 401 (bytes differ only in last char); valid secret → cookie has every required attribute; tampered signature, expired (`now` injected), revoked jti → rejected; mutation without Origin or with cross-origin Origin → 403; GET does not need Origin; client `X-API-Key` alone → 401.
- `app/api/admin/session/route.test.ts`: login success/failure, rate limit after 5 failures (429 with `Retry-After`), logout revokes and a reused cookie is 401.
- Update the four existing admin route tests: replace `process.env.API_SECRET_KEY = API_KEY` / `X-API-Key` fixtures with a shared `test/adminSession.ts` helper that sets both admin env vars and returns a `Cookie` header; add to each a "legacy client key is rejected" case. `lib/validate.test.ts` keeps its `checkApiKey` tests (still used by clients in `observe` mode).

### Rollout (Ian)

1. `vercel env add ADMIN_SECRET_KEY` and `ADMIN_SESSION_SECRET` for production and preview **before** pushing, otherwise the dashboard 500s.
2. Push `main` (deploys). Sign in at `/admin`, run one device label change, sign out, confirm the old cookie is rejected.
3. `curl -H 'X-API-Key: <client key>' https://api.miniti.app/api/admin/devices` → 401.
4. Roadmap: mark Phase 1 shipped; runbook line 107 removed.

---

## Part 2. P0.2: recover from SwiftData startup failure (miniti)

### Design

- **New `Miniti/Services/PersistentStore.swift`** (compiled into both targets):
  - `enum PersistentStoreOpenFailure: Error { case migration, corruption, io, unknown }` plus a content-free `debugSummary` (error domain + code + the SwiftData/CoreData `NSError` reason text, never a store path with user data). Classification from `NSError.domain/code` (NSCocoaErrorDomain 134110/134140 family → migration, 11/259/SQLite → corruption, 4/13/512-ish file errors → io).
  - `struct PersistentStore { static func open(schema:) -> Result<ModelContainer, PersistentStoreOpenFailure> }`. Steps: honour a `#if DEBUG` `-MinitiStoreURL <path>` launch argument (so a manual drill and tests can point at a scratch file instead of the real store), try the normal read-write `ModelConfiguration`, and on failure attempt a **read-only** open (`ModelConfiguration(schema:url:allowsSave:false)`) so the recovery screen can offer export. Result carries `readOnlyContainer: ModelContainer?` alongside the failure. Never delete, move, or recreate the store.
  - Logs one `DebugLogger.shared.log(.app, "Persistent store open FAILED: category=… \(summary)", level: .error)`.
- **App entry points** (`Miniti/MinitiApp.swift:342-357`, `MinitiMobile/MinitiApp_iOS.swift:79-93`): replace the `fatalError` closure with `PersistentStore.open`. Keep the `ScreenshotMode.makeSeededContainer` short-circuit. Store the outcome in `@State private var storeState: PersistentStoreState` (`.ready(container)` | `.failed(failure, readOnly: ModelContainer?)`).
  - `WindowGroup`: new **first** gate branch `if case .failed = storeState { StoreRecoveryView(...) }` before `requiresForceUpdate`. Attach `.modelContainer` only in the `.ready` case. `AppState` stays exactly as is: `modelContext` is simply never assigned, which is an already-tested mode (`testSaveFenceReportsFailureWithoutModelContext`).
  - macOS `Settings` scene: attach a **fallback in-memory** container in the failed state so `@Environment(\.modelContext)` never traps; `SettingsView`'s Export-all and Granola import buttons read `appState.persistentStoreFailure != nil` and show "unavailable until the meeting database opens". `Window("Debug Log")` and `MenuBarExtra` need nothing.
  - Add `@Published private(set) var persistentStoreFailure: PersistentStoreOpenFailure?` on `AppState`, set from the entry point.
- **New `Miniti/Views/StoreRecoveryView.swift`**, modelled on `ForceUpdateView.swift` (⬢ glyph, lowercase headline, `ColorPalette.Background.primary`): headline "can't open your meetings", one sentence that the data has not been touched, the category in plain words (e.g. "the database needs a newer version of miniti" for migration), then actions:
  - **try again** → re-runs `PersistentStore.open`; on success the gate falls through to the normal app.
  - **export diagnostics** → macOS opens the existing `debug-log` window; iOS presents `ShareLink` with `DebugLogger.shared.exportText()`.
  - **export meetings** (only when the read-only open succeeded) → reuse the markdown export path behind `exportAllMeetings()` in `SettingsView.swift:1692` / `SettingsView_iOS.swift`, moved into a shared `MeetingExporter` so it takes a `ModelContext` argument. Writes a zip/folder via `NSSavePanel` on macOS and share sheet on iOS.
  - **show database folder** (macOS only) → `NSWorkspace.shared.activateFileViewerSelecting` on the Application Support directory, for manual backup.
  - **get help** → `https://miniti.app/support`, the link both Settings views already use.
- **Diagnostics event:** `enqueueDiagnosticEvent("persistent_store_open_failed", category: .app, level: .error, details: ["category": …, "domain": …, "code": …])` fires once the app is in managed mode with sharing on (AppState already guards that).

### Tests (`MinitiTests/PersistentStoreTests.swift`)

- Open a temp URL containing random bytes → `.corruption` (or `.unknown`) and the read-only attempt also fails; the file is byte-identical afterwards (never deleted).
- Open a temp URL that a fresh container created → `.ready`.
- Open with a schema that cannot migrate the temp store (write with a one-entity schema, reopen with an incompatible required attribute) → `.migration`. If SwiftData refuses to produce this deterministically, cover classification with hand-built `NSError`s instead and say so in testing.md.
- Manual drill added to `docs/testing.md`: run the Debug build with `-MinitiStoreURL /tmp/bad.store` after `head -c 4096 /dev/urandom > /tmp/bad.store`, walk each button, then relaunch without the flag and confirm real history is intact.

---

## Part 3. P0.3: centralize and surface persistence errors (miniti)

### Design: one policy in `AppState`, one banner at the app root

`AppState` already is the persistence layer (the revision-fenced queue lives there), so the policy is a new extension file `Miniti/Models/AppState+Persistence.swift`, not a new service.

- **Types**
  - `enum PersistenceOperation: String, CaseIterable` with cases named for the user action: `pin, unpin, delete, discard, rename, speakerEdit, transcriptTrim, transcriptRestore, correction, insightsRegeneration, finalInsights, templateChange, docsTopics, docsLookup, staleMeetingFinalize, sessionReference, historyLoad, interruptedMeetingCheck, exportAll`. Each has `userLabel` ("pin", "delete", "rename", "speaker change", "correction", …).
  - `struct PersistenceIssue: Identifiable, Equatable { id, operation, kind: .save | .load, occurredAt }`. `message` computed: "{label} didn't save" or "couldn't load your meetings". Retry is a stored closure on AppState (`persistenceRetry`), not on the struct, so the struct stays `Equatable`.
  - `@Published private(set) var persistenceIssue: PersistenceIssue?`.
  - Internal (not private) seams for tests: `var persistenceSave: (ModelContext) throws -> Void = { try $0.save() }` and `var persistenceFetch: ...` are overkill; a single `var persistenceSaveHandler` is enough. Fetch failure is injected by handing AppState a context whose container was destroyed, or by a `persistenceFetchHandler` seam with the same shape. Pick the handler seam for both (deterministic).
- **`@discardableResult func commit(_ op: PersistenceOperation, in context: ModelContext? = nil, mutate: () throws -> Void, revert: (() -> Void)? = nil) -> Bool`**
  1. run `mutate()` on the main actor; 2. `try persistenceSaveHandler(context ?? modelContext)`; 3. on throw: run `revert?()` (the explicit inverse, e.g. toggle pin back; **no context-wide `rollback()`**, because the live-meeting queue shares `mainContext` and a rollback would drop its unsaved state), log `Persistence \(op) FAILED: domain=… code=…` (no `localizedDescription`, it can echo attribute values), `enqueueDiagnosticEvent("persistence_failed", category: .app, level: .error, details: ["op": op.rawValue, "domain": …, "code": …])`, set `persistenceIssue`, store `persistenceRetry = { self.commit(op, in: context, mutate: mutate, revert: revert) }` only for idempotent operations (all except `delete`/`discard`, which re-run the delete explicitly, and `staleMeetingFinalize`, which is re-run by the next launch). Return `false`.
  4. On success, clear `persistenceIssue` if it belongs to the same operation.
- **`func load<T>(_ op: PersistenceOperation, _ body: () throws -> T) -> T?`**: same logging/event/issue path with `kind: .load`, returns `nil` on failure so callers can tell "failed" from "empty".
- **Migration of every site from the inventory** (34 saves, 6 fetches). Pattern once, applied everywhere:
  - History views: `MainWindow.swift:444,605,1804-1814,2038` and `HistoryView_iOS.swift:162,167,425-435,845` call `appState.commit(.pin) { meeting.isPinned.toggle() } revert: { meeting.isPinned.toggle() }` etc. Speaker **rename** `onSave`/`onClear` (`MainWindow.swift:1795,1799`, `HistoryView_iOS.swift:416,420`) gain an explicit `commit(.speakerEdit)` (today they never save at all).
  - Delete (`MainWindow.swift:605`, `HistoryView_iOS.swift:162`, `AppState.swift:5941`): keep `noteMeetingDeleted` **before** `modelContext.delete` (the documented invariant) and add `retractMeetingDeleted(_:)` in `revert` so a failed delete does not orphan the meeting's pending saves. Verify in a test that `modelContext.insert(meeting)` after a pending delete restores the row; if SwiftData refuses, fall back to `refreshMeetings()` after a `rollback()` guarded by `pendingMeetingSaves.isEmpty && currentMeeting == nil`.
  - Insight saves (`AppState.swift:3985,4223,6130,6659,7864,7869,7937,8002,8058,8097,8104,8356`): wrap each `try? modelContext.save()` in `commit(.finalInsights / .insightsRegeneration / .templateChange / .docsTopics / .docsLookup)`; no revert needed (in-memory values are still correct, retry re-saves).
  - Transcript trim/restore (`AppState.swift:6338,6385`): already `do/catch`; route through `commit(.transcriptTrim)` and make `SelectableTextView.applyPendingTrim()` (`SelectableTextView.swift:1129`) rely on the banner rather than staying silent.
  - Corrections (`AppState.swift:6277`): add `DictionaryCorrectionOutcome.saveFailed` and return it when the save throws; the three editor call sites (`TranscriptView.swift:539-560, 788-800`, `SelectableTextView.swift:1087-1107`) already render `message(...)`, so add the copy "correction didn't save" there.
  - Stale finalization (`AppState.swift:6600`): only log "Finalized stale interrupted meetings" and spawn `PendingSessionEndReport` for meetings whose save succeeded; failure sets an issue with no retry (next launch retries).
  - Session reference (`AppState.swift:8677,8683`): `commit(.sessionReference)`.
  - Live queue (`AppState.swift:7035`): keep behaviour, add the diagnostics event and set `persistenceIssue(.finalInsights? no: .liveTranscript)` once (not per 60 s tick: only when transitioning from success to failure), cleared by the next successful commit of the queue.
  - Fetches: `resumeInterruptedMeeting` (`AppState.swift:6448`) → `load(.interruptedMeetingCheck)`; `clearManagedSessionReference` (`8673`) → `load(.sessionReference)`; `MainWindow.refreshMeetings()` (`619`) → `load(.historyLoad)` and keep the previous array; `SettingsView.exportAllMeetings()` (`1693`) → `load(.exportAll)` plus the existing inline message.
- **Banner:** new `Miniti/Views/PersistenceIssueBanner.swift` (shared, platform-conditional styling), copied from `RecordingIssueBanner` (`MeetingView.swift:352-390`): amber strip, message, "retry" when `persistenceRetry != nil`, dismiss X → `dismissPersistenceIssue()`. Mounted once at the root: macOS `MainWindow` top of the content column (above the split view), iOS `MainTabView` above the tab content. Lowercase copy in Ian's voice.
- **Docs:** `docs/patterns.md` gains a "Persistence commit policy" section (use `commit`/`load`, never bare `try? save()`, the revert rule, why no `rollback()`); `docs/architecture.md` persistence section updated; add a one-line lint in `docs/testing.md` review checklist: `grep -n "try? .*\.save()" Miniti MinitiMobile` must return nothing outside `ScreenshotMode.swift`.

### Tests (`MinitiTests/PersistencePolicyTests.swift`, runs in both bundles)

Shared helper `MinitiTests/Support/TestContainers.swift` (dedupe the three identical in-memory container helpers) and `TestAppState.make(container:)`.
- With a throwing `persistenceSaveHandler`: pin, delete, rename, speaker edit, transcript trim, saved-insight regeneration, stale-interrupted finalization each set `persistenceIssue` with the right operation, run `revert`, and emit exactly one `persistence_failed` client event (assert via `pendingClientEvents`).
- Retry: handler flips to succeeding, `persistenceRetry()` clears the issue and the change is durable (`fetch` sees it).
- Delete failure leaves the meeting fetchable and not in `deletedMeetingIDs`.
- `DictionaryCorrectionOutcome.saveFailed` returned when the save throws on a saved meeting.
- `load` failure returns `nil`, sets a `.load` issue, and `resumeInterruptedMeeting` does not treat it as "no draft".
- Stale finalization with a failing save does not enqueue a `PendingSessionEndReport`.
- Live queue failure sets the issue once across three periodic ticks and clears after a successful save.

---

## Part 4. P0.6: automate critical UI and network regressions (miniti)

### Seams (production code, minimal)

- `MinitiAPIService.init(session: URLSession = .shared, auth: ClientAuthManager = .shared)`; `send()` uses `self.session`/`self.auth` (lines 59-90). **After this change run the built app end to end** (memory: `send()` recursion once froze the Mac; see `verify-app-network-path`).
- `InsightsService.init(session:)` replacing the six `URLSession.shared` uses.
- `DeepgramService.connect` takes `sessionConfiguration: URLSessionConfiguration = .default` and a `#if DEBUG` `endpointURL` override so a `URLProtocol` stub can reject or drop the WebSocket handshake.
- `AppState.setupServices()` gains an internal `serviceFactory` hook used only by tests; `isRunningUnderXCTest` additionally suppresses the launch-time `refreshUsage/checkForUpdates/calendar` tasks so tests stop hitting production.

### Test additions

- `MinitiTests/Support/StubURLProtocol.swift`: move the private stub out of `ClientAuthTests.swift:192`, add scripted responses per request, delay, and `URLError` injection.
- `MinitiTests/MinitiAPIServiceTransportTests.swift`: for `/usage`, `/session`, `/insights`, `/client-events`, one CRM route and one calendar route: timeout (`.timedOut` → `.networkError`), offline (`.notConnectedToInternet`), 401 `token_expired` retried exactly once then success, 401 second time → `.authRevoked`, 402 → `.limitReached` with parsed fields, 403 `device_disabled`, 429 → `.rateLimited`, 500/502/504 → `.serverError`, malformed JSON → `.invalidResponse`, cancellation propagates `CancellationError`, stale response (older insights generation ignored by `AppState` when a newer request completed first).
- `MinitiTests/MeetingJourneyTests.swift` (AppState level, in-memory container, stubbed Deepgram results): start a meeting through the post-audio entry point (the same method the Deepgram delegate calls with a parsed result; if `startRecording` is entangled with `AudioCaptureService`, split a `beginMeetingSession(source:)` seam), append final segments, stop, assert the meeting has `endTime`, ordered segments, appears in the history fetch, pin survives relaunch of a second `AppState` on the same container; interrupted-session recovery end to end (kill mid-meeting simulated by a fresh AppState); Settings search catalog round trip.
- `TrainingMetricsTests`: six-series chart with gaps, axis ticks for 1/7/40/400 meetings, empty history, grounded-example metadata sizing values (the numbers the view reads), latest-marker index.
- `ColorPaletteTests`: CRM task card leading-alignment invariant (the 2.8.0 layout regression) expressed as the layout constants the view uses.
- Calendar decoder fixture test: real `/api/google/events` payload with `hangoutLink`, description-pasted Meet link, attendees, `skipReason` → the 2.7.0 "links and attendees dropped" regression. Fixtures live in `MinitiTests/Fixtures/*.json` added to both test targets.
- Navigation: keep existing policy tests; add one for `MainNavigationHistory` + search focus state transitions when a text editor gains and loses focus.

### Smoke gate via the screenshot harness

- `scripts/screenshots/smoke.sh`: builds Debug, runs every macOS scene through `capture-mac.sh` (already exits non-zero on missing window/render failure), and every iOS scene through `capture-ios.sh` with a new check: `ScreenshotMode.finish` on iOS writes a `screenshot-done` marker in the app's temporary directory, and the script fails if `simctl get_app_container … data` does not contain it. Add two scenes: `store-recovery` (launches with a corrupt scratch store) and `persistence-issue` (seeds `persistenceIssue`), so both new screens are rendered every release.
- Document in `scripts/screenshots/README.md` and `docs/testing.md` as the launch smoke matrix; it replaces nothing in the manual matrices.

### Coverage

- `fastlane mac test` / `ios test` gain `code_coverage: true`; new `scripts/coverage.sh` runs `xcrun xccov view --report --json` on the latest `.xcresult` and prints per-file percentages for `Miniti/Models`, `Miniti/Services`, `Miniti/Views`.
- `docs/testing.md`: replace the v1.17.0 numbers with dated results, fix "10 test files" (there are 11 plus the new ones), add `ClientAuthTests` to the list, add the new files, and name the manual-only hardware boundaries explicitly.

---

## Files touched (representative)

miniti-api: `lib/adminAuth.ts` (new), `lib/ratelimit.ts`, `app/api/admin/session/route.ts` (new), `app/api/admin/{client-events,costs,devices,usage-chart}/route.ts` + tests, `app/admin/page.tsx`, `test/adminSession.ts` (new), `.env.example`, `docs/agents/{02,04,05}*.md`, two `.cursor/skills` files.

miniti: `Miniti/Services/PersistentStore.swift` (new), `Miniti/Views/StoreRecoveryView.swift` (new), `Miniti/Views/PersistenceIssueBanner.swift` (new), `Miniti/Models/AppState+Persistence.swift` (new), `Miniti/MinitiApp.swift`, `MinitiMobile/MinitiApp_iOS.swift`, `Miniti/Models/AppState.swift` (save/fetch sites listed above), `Miniti/Views/MainWindow.swift`, `MinitiMobile/Views/HistoryView_iOS.swift`, `MinitiMobile/Views/MainTabView.swift`, `Miniti/Views/SettingsView.swift`, `MinitiMobile/Views/SettingsView_iOS.swift`, `Miniti/Views/SelectableTextView.swift`, `Miniti/Views/TranscriptView.swift`, `Miniti/Services/{MinitiAPIService,InsightsService,DeepgramService}.swift`, `Miniti/ScreenshotMode.swift`, `MinitiTests/Support/*` (new), the new test files, `scripts/screenshots/smoke.sh` (new), `scripts/coverage.sh` (new), `fastlane/Fastfile`, `docs/{testing,patterns,architecture,roadmap}.md`, `CHANGELOG.md` (`Unreleased - v2.9.0`: new: recovery screen; fix: saves that fail now say so; flat bullets, lowercase miniti, no em dashes).

New files must be added to **both** app targets and both test targets in `Miniti.xcodeproj`.

---

## Verification

Backend:
```
cd ../miniti-api && npm test && npm run lint -- --max-warnings=0 && npx next typegen && npx tsc --noEmit && npm run build
vercel   # preview; then curl the preview /api/admin/devices with and without the cookie
```

App:
```
fastlane mac test
fastlane ios test
grep -rn "try? .*\.save()" Miniti MinitiMobile   # expect only ScreenshotMode.swift
scripts/screenshots/smoke.sh
scripts/coverage.sh
```
Then build and run the real app (`RELEASE.md` local build steps): start a meeting in managed mode, confirm usage/insights/client-events still flow after the `MinitiAPIService` seam change; run the P0.2 manual drill with `-MinitiStoreURL`; force a save failure in Debug (temporary throwing handler behind a launch flag) and confirm the banner appears on macOS and iOS with a working retry.

Out of scope, stated: P0.4, P0.5, P0.7, P0.10, P0.1 Phases 2, 3, 5, and the enforcement ladder.
