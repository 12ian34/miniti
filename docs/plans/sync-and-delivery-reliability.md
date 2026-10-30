# Automatic sync and completed webhook delivery

Status: **implemented locally for 3.6.0**, 2026-10-30; combined validation and signed candidate packaging passed; physical-device release QA remains. Not published. [Roadmap](../roadmap.md) owns priority. This plan owns S1–S3 and R5–R7 in full; R4 and R8 remain in [reliability](reliability.md). Candidate build is recorded in the release evidence. Ian authorized implementation, tests and candidate preparation; deployment and publication remain separate.

## Customer report and evidence limits

Charlie, using 3.4.0, reports repeatedly opening Settings and pressing Sync, a recent "synced" timestamp without an increased meeting count until that manual action, and a webhook apparently sent before AI processing or cloud sync completes. The report does not yet distinguish an actually absent cloud meeting from a stale count. His exact session, destination and receiver expectations have not been inspected. No production content was accessed for this review.

Code was compared at shipped 3.4.0 (`d547e00`) and 3.5.0. The relevant paths remain in both. These are code-established mechanisms, not a completed on-device reproduction of Charlie's session:

| Finding | Evidence | Meaning |
|---|---|---|
| S1: count and timestamp have different freshness | `CloudSyncEngine.pass` updates `lastSyncedAt` after a successful pass, but calls `transport.status()` only when `refreshStatus` is true or status is nil. Poll/change passes do not refresh a populated count. `kick`, including Settings Sync now, passes true. `CloudSettingsView.statusSection` displays both together. | A meeting may already be uploaded while the count stays unchanged. A fresh timestamp alone does not prove the displayed count is fresh or all meetings were uploaded. |
| S2: stopped current meeting is excluded | `AppState+CloudSync.liveMeetingID` returns `currentMeeting?.id` regardless of recording/finalization state; `scan` excludes that ID. `stopRecording` can finish while leaving currentMeeting selected; `clearCurrentSession` clears it later. | A stopped meeting left on the session screen can be ineligible even for manual sync. Opening Settings itself does not release this exclusion. This is distinct from S1. |
| S2: eligibility transitions lack a dedicated trigger | Successful local commits call `noteLocalChange` (five-second debounce); `clearCurrentSession` does not explicitly kick sync when currentMeeting becomes nil. Polls run every 60 seconds, with a fallback full scan every five polls. | If the save-triggered scan ran while the meeting was excluded, a later clear can wait for a fallback scan unless another save/activation/manual action intervenes. Establish the precise sequence with a held-save/clock fixture. |
| S3: initial webhook can precede final AI | `stopRecording` calls `completeMeetingFinalization` before awaiting `generateFinalInsightsAndSave`. A queued return Home can call `goHome`, which enqueues `payloadFromLiveState` as `meeting.saved`. Final AI later enqueues `payloadFromMeeting` as `meeting.updated` only if the meeting is no longer current. | An initial saved event may contain live/intermediate insights. Returning Home is not proof final AI completed. Both events are independent of cloud acknowledgment. |
| R5: updated delivery can be lost | `DeliveryOutbox.enqueueWebhook` replaces the body of a pending item in place; `processDue` sends a snapshot and `apply` removes by the same ID on success. | An updated payload arriving while the older one is in flight can be removed by the old completion. This applies to the same event identity; `meeting.saved` and `meeting.updated` are different events, so R5 alone does not explain every early initial payload. |

## Deliverable and boundaries

A finished, durably saved, included meeting becomes eligible for automatic cloud upload without requiring Settings or Home navigation. Status distinguishes a successful check from pending work and counts with known freshness. A completion webhook contains the settled final AI result, or explicitly reports unavailable/failed processing, and later updates cannot be lost behind an older send.

Ian confirmed on 2026-10-30: the webhook is self-contained and carries the saved transcript and summary when available, plus the existing meeting fields. A recipient does not need to fetch the meeting from miniti cloud. If AI is disabled, fails or is interrupted, send the saved transcript with an honest processing outcome and no invented summary. Preserve transcript trimming and stale-insight omission.

Cloud remains optional; configured private-mode exports remain allowed. Neither Pro nor cloud acknowledgment is a prerequisite for the configured webhook. Charlie's exact receiver behavior can help support investigation, but it is not an unresolved product decision or a gate for this work. A separate cloud-ready event is outside 3.6.0.

## Release decisions and invariants

Version: **3.6.0**, selected by Ian on 2026-10-30. Build number is assigned during release preparation, greater than the latest uploaded build; record the selected candidate in the release evidence. This plan owns S1–S3 and R5–R7 in full. The separate [alert-clarity plan](incident-alert-clarity.md) remains selected work alongside this release and can deploy as soon as its own checks pass, independently of the app binaries. R4, R8, account access/ownership, recording-engine changes and video are excluded.

Scope reaffirmed after Claude's review, 2026-10-30: **retain S1–S3 and R5–R7 in 3.6.0**. Simplify the mechanism, not the selected outcomes. R6 and R7 are not moved to a later release. Use existing meeting/outbox storage and narrow helpers; a separate completion journal, receipt/tombstone retention subsystem and global AI deadline are not required.

1. Local saving, AI processing, cloud replication and webhook delivery are separate states. The user can leave a finished meeting and start another while the previous meeting processes.
2. Only durably saved revisions may be uploaded/exported. A failed save cannot be shown as completed or advance a delivery receipt.
3. Recording/final-transcript capture remains protected from remote overwrite. A stopped selected screen is not, by itself, active capture.
4. A late response can change only the meeting, content revision and request generation it belongs to. It cannot clear a newer task's state or trigger its exports.
5. A delivered webhook snapshot is immutable. A retry uses the same delivery ID and body; changed content or an explicit resend gets a new identity.
6. Delivery is at least once with stable IDs for receiver deduplication. A lost HTTP response cannot establish whether the receiver acted. Never promise exactly-once receipt or retraction of a request already sent.
7. Existing cloud exclusions, account fences, private-mode configured exports, consent checks, transcript trimming and terminal-payload disposal remain in force. No forced sign-out or account migration.

## Implementation order and ownership

| Order | Slice | Main files to inspect/change | Dependency / completion |
|---|---|---|---|
| 0 | Reproduce and capture baseline | `MinitiTests/CloudSyncEngineTests.swift`, `MeetingJourneyTests.swift`, delivery and History tests | Demonstrate stale count, stop/stay exclusion, early initial webhook, superseded delivery and late History response using real entry points. Preserve 3.4.0/3.5.0 behavior as evidence, not as desired assertions. |
| 1 | R7 response authority | `AppState.swift` History/final/topic/template paths; `Meeting.swift` revision helpers | Establish the content/request identity S3 will use. |
| 2 | R5 outbox identity and persistence | `DeliveryOutbox.swift`, production sender wiring and delivery tests | Required before S3 and R6; failed persistence is an observable failure. |
| 3 | S2 automatic eligibility | `AppState+CloudSync.swift`, recording completion/clear/resume paths, `CloudSyncEngine.swift` | Durable transcript completion starts upload independently of AI and current view. |
| 4 | S1 truthful status | `CloudSyncEngine.swift`, `CloudSettingsView.swift`, shared pending-count model | Build on S2 eligibility, without hot-path history scans. |
| 5 | S3 completion event | `AppState.swift`, `WebhookService.swift`, meeting-local completion marker and existing outbox | Use R7 authority and R5 durability; no live-state early completion send. |
| 6 | R6 resend action | Settings delivery UI, AppState action and production webhook sender | Rebuild current permitted data using R5/S3 identity and readiness. |
| 7 | Integrated verification | Both Apple bundles, controlled receiver and two-device cloud QA | No old test that accepts an empty body or only checks a timestamp can substitute. |

The file list is a starting inventory. Search all writers/readers of the changed fields, including import, resume, trim/undo and cloud application. Keep new helpers narrow and testable; no unrelated AppState/Settings rewrite. Backend changes are not assumed for these client fixes. Any additive webhook schema or backend contract must be documented and tracked for Linux the same day.

## R7: History responses belong to their input revision

`generateInsightsForMeeting` currently captures the transcript but primarily checks deletion before applying results. A trim can therefore be followed by stale AI results marked current. Existing final-insight revision checks are a baseline to preserve, not proof every History/topic/template entry point is covered.

Capture a request context before the first await: meeting ID, monotonic transcript/content revision, requested insight mode, relevant template ID and definition revision/fingerprint, and a per-meeting/per-operation request generation. Capture the existing account/session authority where the request uses managed auth. BYOK/local-only meetings must still work without requiring an account. Snapshot user-selected mode/template rather than re-reading the current UI selection after awaits.

Recheck authority after each await and immediately before the synchronous model mutation/commit. Only a successful commit may stamp freshness, update matching live state, enqueue a webhook or export Markdown. Loading/error completion belongs to the request token; an older response or error must not clear a newer request's indicator. Cancellation is an optimization, not the authority check.

Audit all relevant mutation paths: trim, undo, transcript corrections, speaker edits affecting the prompt, template replacement/deletion, meeting deletion/resume and cloud-applied content. Undo advances a revision; it must not return to an old numeric revision and accidentally authorize an old response. Use an existing monotonic revision when it covers all prompt inputs; otherwise add a narrowly scoped input fingerprint or revision. A cosmetic title change need not discard an unrelated summary unless title is actually an input/output ownership conflict. Preserve manual speaker-name precedence.

Apply the same guard to saved-meeting docs/topic/template responses and their export side effects. Final AI must use the same accepted input identity so it cannot race History work into restoring old content. Do not extend this into the deferred general AI-consent audit; preserve existing guards.

Acceptance: held summary/questions/Sales/template/topic answers, followed by trim/correction/undo/template edit/delete/resume/newer request/account change. Old answer/error writes no data, freshness, current spinner state, file or webhook. An unchanged request applies normally. Assert actual saved models and outgoing payloads, not just helper booleans.

## R5: immutable in-flight webhook completion identity

Use an immutable sent item plus a separately persisted, coalesced successor for the same meeting/event. Every new payload revision has a new delivery ID; retries of identical content keep their ID. Once a send has started, never mutate its body, event or delivery identity. Track the exact attempted revision through every outcome. Preserve the existing destination policy (the configured URL is checked at dispatch, and a removed URL prevents sending); do not introduce an unreviewed routing migration.

A successor must be written durably before enqueue reports success. Old success/retry/reject can settle only the old item. When an obsolete old revision fails transiently and a newer successor exists, supersede its future retry rather than sending old content after newer content; the successor keeps its own limits and identity. A terminal failure must not discard a valid successor. Keep at most the current attempted revision and the latest pending successor per meeting/event, with bounded metadata. Preserve the existing five-delay backoff and 24-hour payload lifetime unless a reproduced defect requires an explicit amendment.

Persist dispatch/settlement transitions atomically within the outbox file. On process death, an uncertain in-flight attempt retries with its original ID/body; it is not treated as confirmed success. Old-format rows must decode with conservative defaults. If disk writes fail, surface the delivery persistence error and retain recoverable state; do not claim queued/sent durability. Deletion/discard invalidates outstanding completions and removes pending successors. A request already past the network send cannot be recalled.

Tests with held production-shaped sender: v2/v3 during v1 success/retry/reject; lost response; kill/reload at each persistence boundary; failed disk write; removal/discard during send; changed/removed destination; max-age cleanup. Assert payload order and IDs observed by a receiver. Automatic deliveries must not retry a superseded revision after the successor was accepted.

## S2: lifecycle-driven automatic upload

Replace the implicit equivalence of currentMeeting and actively protected capture with an explicit lifecycle contract. The protected set includes starting, recording, resuming and draining/final-transcript commit. Once endTime and the final transcript revision are durably committed, the meeting becomes eligible even while it remains on screen and final AI runs. Queue a coalesced scan at that exact transition. Navigating Home is not the upload trigger. Later successful AI commits schedule another eligible revision.

Keep distinct outbound eligibility and inbound protection when needed: permitting a durable stopped snapshot to upload must not let a delayed remote pull overwrite unsaved/current local edits. Before applying upload receipts, pull data, tombstones or reconcile results, recheck meeting lifecycle, revision, exclusion/deletion and account generation. Resume re-protects capture immediately; an old upload acknowledgment may acknowledge its snapshot but must not mark newer content synced or overwrite it.

Use existing single-flight/debounce scheduling with a sticky rerun/dirty signal; a trigger during a scan or at the pass limit cannot disappear. Under an active app, open gates and no failure/backoff, request upload within the existing five-second debounce after durable completion. This is a scheduling bound, not a promise of server completion. Retain the periodic safety scan, but do not rely on five polls for normal completion. Offline/iOS suspension waits for permitted recovery/activation and displays pending work honestly.

Tests through AppState actions with real in-memory store and held transport: stop/stay; Home before/after save; start next meeting; AI pending/complete; Settings opened without Sync; save failure/retry; offline/relaunch; resume during held upload/pull; Local/private; delete/account change. Assert accepted remote ID/revision and preservation of local newer data. Exercise multiple local commits during a pass and the rerun cap.

## S1: truthful sync status and counts

Use authoritative server count/bytes, not speculative increments that can double-count retries or existing rows. Refresh status once after a pass that changed cloud contents, including uploads/deletions/restores, and on explicit Sync. For idle active polling, refresh no more than once per five-minute freshness interval; bypass that interval after real mutations. Coalesce concurrent requests and retain account/generation fences. A separate timestamp records when count/bytes were actually obtained.

Show "Last checked" for a completed sync pass. Show "In the cloud" alongside its count freshness; if the latest status refresh failed or the cached value is past the idle freshness interval, mark it as last known. Distinguish pending eligible uploads/removals, protected recording/final transcript, oversized/skipped rows and paused/offline states. Count work using cached scan results, updated by meaningful commits, not a full history scan on every UI render or audio sample. Cloud totals are account-wide; pending work is this device's work.

A successful empty poll cannot display "all synced" when eligible work remains, a scan was skipped, the batch cap left a backlog, local scanning failed, or a protected/failing revision is outstanding. A failed count refresh does not undo an acknowledged upload; preserve its receipt and show status freshness failure separately. Background work should catch up without opening Settings.

Tests: automatic upload/delete/restore refreshes count; existing-ID edit does not increment it; no-op polls honor freshness; partial/batch-capped uploads retain pending count; failed fetch/scan/status has honest text; delayed A status cannot update B. Assert shared presentation models and relevant view accessibility labels on Mac/iOS.

## S3: completion webhook from settled saved data

The first `meeting.saved` completion event is created after the final processing run for the durable transcript settles, regardless of which screen is open. Remove navigation-owned early sends only after auditing all current `meeting.saved` call sites (normal stop, no-AI/private, auto-stop, resume, imports). Preserve import behavior unless it goes through the same completion path; do not auto-export historical meetings on upgrade.

Keep `meeting.saved` and `meeting.updated` event names. Add a small optional processing object using existing JSON naming conventions and backward-compatible fields, without a separate schema-version framework: input transcript revision, processing state (`complete`, `partial`, `failed`, `skipped`, `interrupted`) and safe per-requested-mode outcomes. "Complete" covers the enabled/requested jobs, not disabled modes. Partial means some requested jobs succeeded; failed means none succeeded; skipped means no work was requested/permitted; interrupted is an unfinished run found after process death. Never include raw errors, credentials or stale AI as current content. Preserve `insights_stale` semantics and omit invalidated insight sections.

Preserve existing per-request timeouts and retries. There is **no new five-minute deadline** for the final AI run. A valid late result may still commit locally under the normal input/revision guards; webhook timing never cancels or invalidates otherwise valid AI work. Local saving and starting another meeting remain independent of AI completion. Send the initial event after the requested final jobs settle, including failure/skipped paths. On relaunch, an unfinished run is reported as interrupted rather than complete; do not regenerate AI or enroll automatically just to send a webhook. A later successful History Update sends updated saved data. Measure final-run durations before proposing any future global deadline.

### Small durable handoff

Use a small device-local completion marker associated with the meeting/run and the existing outbox. Persist a stable logical delivery ID and pending/handoff state; a meeting ID alone is insufficient because later updates need different delivery IDs. Preserve the outbox's immutable encoded payload once staged/attempted. Do not add this local bookkeeping to account-wide cloud fields.

The implementation must cover the save-before-enqueue crash window, which can lose a notification as well as duplicate it. Prefer a short staged handoff using the existing stores:

1. Persist the completion marker with the durable meeting/run state. Once processing settles, persist the immutable outbox item under that ID, initially held from dispatch.
2. Persist the marker's handoff acknowledgment, then release that exact outbox item for sending. A failed acknowledgment leaves it held and retryable. The ordinary outbox retry path takes over after release.
3. At launch, reconcile only pending markers and held rows. Pending plus an existing row reuses the row; pending without a row enqueues the current valid settled snapshot once. An acknowledged marker plus a held row releases it. An acknowledged marker without a row does not recreate a delivery: it may already have been sent, discarded or expired. Corrupt/missing outbox storage is a visible recovery problem, not permission to replay every meeting.

This is a proposed minimal implementation, not a new transaction framework. An equivalent simpler approach is acceptable if boundary tests demonstrate no silent lost handoff, no reuse of an attempted ID with changed content, and no replay of already handed-off meetings. Existing old meetings default to no marker, avoiding historical mass-export. Apply R7 checks when staging; deletion/discard cancels pending handoffs, and edits invalidating an unattempted staged payload use a new logical ID. Resume and interrupted runs must reconcile without sending an obsolete summary. Acknowledged marker metadata may be replaced by the next run; no delivered-body archive or separate receipt/tombstone collection is needed. Keep the existing outbox payload lifetime, including across restart, and show expired pending work through the R6 recovery path.

The scope is normal crash/relaunch recovery, not exactly-once delivery across storage corruption, restored backups or receiver side effects. Network retries remain at least once with the same ID/body.

Later relevant edits/AI updates produce `meeting.updated` from the current saved revision. Serialize initial and updated sends for a meeting within one device so an update does not overtake its pending initial event. Initial terminal failure becomes visible and must not block all future updated/resend events forever. Cross-device ordering and receiver exactly-once behavior are not guaranteed; publish revision/delivery identity guidance. No webhook waits for optional cloud acknowledgment and no new cloud-ready event is included in 3.6.0.

Tests: held AI + immediate Home/start-next; stay on finished screen; complete/partial/failure/skipped/interrupted; a valid final run exceeding five minutes; crash at each marker/outbox boundary; relaunch with an orphaned run; duplicate callbacks; trim/delete/resume/account switch; failed save/encoding/disk; terminal initial event then later update. Assert production JSON bodies, settlement metadata, durable state, event order and stable IDs through retries. Cloud off/private configured exports and a separately refused upload must not prevent permitted payload delivery.

## R6: resend the current saved meeting

Terminal failures intentionally discard bodies. Keep that disposal. Replace the webhook-specific "Retry now" behavior for failed deliveries with an explicit **Resend current meeting** action; it rebuilds from saved, current, permitted data, creates a new delivery identity and uses `meeting.updated` with the same processing/revision metadata. Existing pending retries continue retrying their immutable body. Keep CRM retry behavior unchanged.

If current AI work is running, say so and offer retry after it settles; do not send stale sections as complete. Trimmed/invalidated insights are omitted or flagged stale by the payload contract. Deleted/unavailable meeting, removed endpoint, encoding or persistence failure leaves an actionable error and Discard. Do not mark the failed item resolved until a durable replacement is accepted by the outbox. Coalesce repeated taps into one replacement operation; lose no replacement if the old completion arrives meanwhile.

Acceptance uses the production sender/body requirements: terminal 4xx and exhausted retry, successful nonempty resend, edits/trim/undo, pending AI, deletion, removed/changed endpoint, failed save, disk reload and unchanged CRM behavior. A test sender accepting an empty body is insufficient.

## Integrated regression matrix

| Scenario | Required observable result |
|---|---|
| Record, stop, remain on finished screen | Durable transcript uploads automatically; eventual count reflects server; completion webhook waits for AI settlement. |
| Return Home/start second meeting during first AI | First result goes only to its saved meeting; one initial completion handoff; second meeting state untouched. |
| History Update, then trim/undo/template edit | Old result/error cannot change model, freshness, spinner, Markdown, cloud content or webhook. |
| AI succeeds, webhook v1 held, edit generates v2/v3 | Latest successor survives v1 completion; immutable IDs/bodies; no stale retry after newer send. |
| Cloud succeeds but count fetch fails | Acknowledged meeting stays acknowledged; count is explicitly stale, pending state accurate. |
| Cloud off/Local/private configured webhook | No unwanted cloud upload; permitted webhook still works with honest processing state. |
| Offline completion then restart | Local transcript retained; eligible sync resumes; completion marker/outbox recovery cannot invent success or silently lose work. |
| Receiver accepts, response lost | Retry uses same ID/body; UI does not claim exactly-once receipt. |
| Failed webhook, edit/trim, manual resend | New identity sends current permitted saved state, never the purged old transcript. |
| Account switch/delete/resume at any held await | Existing authority/protection rules win; stale completion has no new model/export effect. Already-sent requests cannot be recalled. |

## Acceptance levels

- **Blocking automated regressions:** the integrated matrix above and each slice's named failure cases. Use representative held-response tests per distinct writer/commit path, with parameterized variants where useful; do not require every combination of mode, platform and fault. Verify actual saved state and production-shaped payloads. R7 still covers all named History/topic/template paths.
- **Release device QA:** the bounded checks in [3.6.0](../releases/3.6.0.md), including stop/stay, Home/start-next, two-device count/content, webhook payloads, offline/relaunch and relevant UI. Automated race fixtures need not be repeated manually at every await.
- **Deferred hardening:** a general delivery journal, delivered-receipt archive, backup-restore exactly-once semantics, global AI time budget and exhaustive fault/platform cross-product. These are not hidden release gates. A reproduced regression in the selected paths remains blocking.

## QA, delivery and rollback

Run targeted tests as each slice lands, then both full Apple bundles on the combined tree. Run affected backend tests, tsc/lint and real isolated storage tests if the implementation changes backend storage. Use production payload encoders and filesystem persistence fixtures; no live customer content, credentials, webhook destinations or test email.

Device QA on release-signed Mac and iPhone: two devices plus a controlled receiver, stop/stay versus Home, count and actual remote document comparisons, final AI failure, trim during History Update, offline/relaunch, webhook refusal/lost response/retry. Check compact screens, VoiceOver status and disabled resend reasons. Capture version/build, setup, timing, expected/actual and receiver IDs. Charlie's upgrade alone is not proof his exact session is fixed; request a sanitized receiver expectation/time only if reproduction remains ambiguous.

Deploy the separate alert backend update before relying on its new state/copy. If client work needs additive server fields, deploy them before the app. Update shared references, user docs, concise release notes and Linux tracking; do not describe independent cloud/webhook completion as an atomic distributed operation. [3.6.0 release checklist](../releases/3.6.0.md) owns final evidence. No push/release is authorized by this plan.

Rollback: new clients must decode existing meetings/outbox rows; test an upgrade from a copied synthetic 3.5.0 store. Before shipping, prove what an old binary does with the additive state. Do not prescribe downgrading if it would drop successors or replay completion markers; use a forward patch or disable only new dispatch while retaining durable work. Rollback never restores trimmed text or removes cloud exclusions. Keep delivery identities and completion markers and pending data available for repair.


## Implementation and review, 2026-10-30

All six selected slices are implemented locally. The release record owns final commands, counts, candidate bytes and remaining device checks; this is not a shipped claim.

| Contract | Implementation and regression evidence |
|---|---|
| S1/S2 | `CloudSyncEngine` refreshes authoritative status after mutations and on a bounded idle interval, tracks freshness and local pending/protected work separately, and retains rerun/reconciliation intent after failures. `cloudUploadProtectedMeetingID` protects capture/final transcript; selected and final-AI meetings still reject inbound overwrite. Durable stop, Home and final-AI completion trigger reconsideration. Held transport tests cover account change, lifecycle transitions, unsaved edits, failed saves and failed reconciliation. |
| R7 | Saved AI requests capture meeting/input fingerprint, mode, account/credential authority and an operation token. History, final AI, template and docs results apply only while current; retries recheck. Own successful template mutations rebase the fingerprint. Automatic speaker inference does not invalidate the parallel final summary, but manual speaker overrides do. A manual rename wins over a delayed AI title suggestion; rollback captures the values immediately before mutation. |
| R5 | Attempted bodies and delivery IDs are immutable. New edits create/coalesce an unattempted successor, with exact-ID completion. Writes must persist before publication; unreadable stores are not replaced. Original age survives staging and expiry; bodyless terminal work cannot silently retry. |
| S3 | Optional device-local `Meeting.webhookCompletionJSON` is staged before the first stopped save, then saved with that transcript. A ready snapshot is staged held in the existing outbox; acknowledgement is saved on the meeting before release. Restart reconciles only marked work, with interrupted processing after a crash. Changed unattempted snapshots receive a new ID. No overall AI deadline; failed or skipped AI still delivers a transcript with honest processing metadata. Home no longer sends live state. |
| R6 | Mac and iOS delivery controls call the same current-data resend action. A fresh delivery atomically replaces failed rows for that meeting, using its current saved permitted data and current destination. Repeated action does not duplicate it. Missing meeting/destination and processing work surface useful errors. |

Independent review covered cloud reconciliation, outbox handoff, AI ownership and the backend. Corrections adopted before final validation: preserve reconciliation intent on failed reads; defer incoming data across unsaved edits; coalesce newer edits before initial handoff; keep interrupted outcomes honest after History supersedes final AI; preserve manual rename on both accepted and failed AI commits; persist intent with the first stopped save; expose current-data resend on iOS too.

Storage validation uses a frozen synthetic 3.5.0 SQLite schema without the new marker field, then opens it under the current schema, verifies existing contents and cloud metadata, writes a marker and reopens again. Legacy outbox decoding/expiration and held-write failures have separate tests. No customer database is used.

**Downgrade constraint:** 3.5.0 does not understand held outbox rows and may send them before handoff acknowledgement. Resolve held work before a downgrade, or use a forward patch. Never delete the queue to make an older binary appear healthy.

Final combined source `c99d889`: Mac 1,121 executed/7 skipped/zero failures; iOS 1,059 executed/3 skipped/zero failures. Both include the synthetic SQLite upgrade; native delivery-control renders were inspected at Mac, compact, accessibility and regular widths. Release/device evidence remains in [3.6.0](../releases/3.6.0.md).
