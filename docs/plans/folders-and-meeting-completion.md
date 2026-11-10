# Folders and meeting completion, 3.8.0

3.9.0 follow-through (Charlie's feedback that only 4 of 13 meetings were filed, 2026-11-10): series learning from calendar series and hand moves, summary evidence into existing broad folders only, wider but reviewed keyword lists, and a Mac History page with folder chips and a dismissible organise prompt. Current rules live in [meeting history and import](../reference/meeting-history-and-import.md).

Status, 2026-11-09: Mac 3.8.0 build 164 was released on 2026-11-09; iOS build 164 was confirmed live on the App Store on 2026-11-10. Final automated validation and signed-package verification pass. Specialist physical evidence remains unitemised; publication does not turn it into a pass. FO1/MC1 are included. See the implementation contract below and the [release record](../releases/3.8.0.md).

## Original scope and acceptance

The following requirements are the dated planning baseline. The local implementation contract below resolves matching, storage, completion and resource decisions; the release record owns current validation.

### Folders (FO1)

Requested: automatically create appropriate folders and group meetings, while allowing people to add, rename and edit folders that participate in the same automatic grouping.

Proposed first version: flat folders in History on Mac and iOS, one primary folder per meeting, with All meetings and Unfiled always available. Start with meaningful recurring customer, project or meeting-series groups. Avoid generating a folder for every meeting or generic subject. New folders can be created automatically when repeated evidence is strong; uncertain meetings remain Unfiled. Existing history gets an explicit preview-and-apply organisation action, rather than an uncontrolled background reshuffle.

Every folder has a stable ID, editable name and optional description of what belongs there. User-created folders are eligible for future matching immediately. Renaming preserves membership and identity. Manual moves override automatic assignments until the person explicitly requests regrouping. Deleting a folder retains its meetings. Include undo for moves and bulk organisation. Folder creation and automatic filing are separately controllable; manual organisation works offline.

Prefer calendar-series identity and explicit matching rules first; use existing authorised summary/context for semantic matching where available. Do not infer access to cloud AI from enabling folders. Private/local meetings must retain their existing content boundaries, and grouping must not enable cloud sync or exports. The implementation below selects bounded local matching with no classifier/provider request or additional consent flow. Folder names and descriptions are personal content, not diagnostic fields.

Storage design must cover SwiftData migration, local-only operation, optional cloud synchronisation, owner separation, conflicts, deletion tombstones and older clients preserving unknown folder metadata. A user-created folder on one device must not be silently duplicated or resurrected by another. Backend-first additive rollout is required if sync contracts change. Linux parity tracking and fixtures are required before changing the shared contract.

### Automatic completion (MC1)

Source inspection: AppState defaults smartMeetingsEnabled to true, autoStopMinutes to 5, and calendar auto-start/stop to false. macOS ending grace already reaches stopRecording automatically. MeetingView shows Done after stopping; it calls goHome while final insights run or saveAndOpenCurrentMeeting after settlement. These controls are not evidence saving requires a second click.

Proposed UX: stop or confidently detected call end completes and saves the meeting once, then presents its saved result without requiring Done. Final insights show progress and settle on the same saved meeting. Users may navigate away immediately after durable capture finalisation. Do not move the screen unexpectedly while someone is editing or selecting text. Preserve resume through the existing saved/session contract, with an explicit product decision if that contract cannot support this flow.

Keep conservative call-end detection and a visible Keep recording escape. Calendar end alone must not cut off an overrun; mute, reconnect, app switching, headphones changes and quiet periods must not be mistaken for call completion. iOS must have truthful platform-specific behaviour; do not promise macOS call detection there.

Recommendation: keep Smart meetings enabled for new installs. Offer automatic recording as the recommended explicit choice during setup, with cancel/skip controls and clear recording indication. Do not silently flip existing auto-start or disabled Smart meetings preferences. Starting capture and finishing a capture the person already chose are distinct choices. Calendar-based auto-stop should not become an unconditional default merely to remove Done.

## Delivery and acceptance

FO1 depends on an agreed folder persistence/sync contract. MC1 integrates after MT/SR recording ownership changes and uses the existing save/finalisation owner. Both remain in 3.8.0; no release split is implied.

- Folder tests: new/custom/renamed/deleted folders, manual override, ambiguous matches, no summary/network, repeat classification, bulk undo, interrupted migration, account switch, two-device conflicts and old-client round trips.
- Completion tests: manual/automatic Stop races, final-word drain, slow/failed AI, navigate away/relaunch, resume, save once, charge once, export once and next-meeting handoff. Use the real coordinator and held callbacks.
- Performance: classification runs after save/summary settlement, never per audio sample or transcript word. Define bounded batch size, concurrency, retry and provider spend before coding; compare History interaction and Stop latency to 3.7.0 with synthetic large histories.
- UI: native controls and existing ColorPalette/MinitiDesignSystem, keyboard moves/rename, VoiceOver, large text, Mac/iPhone/iPad empty/loading/error states and Reduce Motion.
- Rollout: retain folders/memberships on disabling automatic filing; rollback cannot delete data or reverse user choices. Verify migration and compatibility before release.

## Surface register and remaining decisions

FO1 owns History UI, meeting-history-and-import reference, cloud contract docs and new folder documentation. MC1 owns recording-lifecycle/settings references and meeting completion documentation. Both own the corresponding 3.8.0 changelog/store bullets after implementation, public roadmap projection, Linux tracking, and actual Mac/iPhone/iPad screenshots with synthetic meetings. Existing screenshots remain until replacement UI exists. Exact public page and asset paths must be inventoried in the release audit before implementation is declared ready.

Implemented decisions: flat folders with one primary assignment; recommended explicit auto-start setup on Mac, preserving existing preferences. The implementation contract below defines matching, cloud sync, resource bounds and existing-history preview. The release record distinguishes passing automated checks from pending physical, accessibility and rollout gates. The original product-planning pass itself ran no app tests.

Missed browser starts are separately selected as [CD1](browser-call-detection.md). MC1 and default changes alone do not fix browser recognition or calendar gating.

## Local implementation contract (2026-11-04)

Ian subsequently authorized the expanded scope. FO1 uses a flat catalog, one primary assignment and optional descriptions/title rules. Matching uses bounded local title/summary word evidence, not a paid provider or additional consent. The 2026-11-05 refinement below replaces per-title generation with broad purpose categories. Manual moves persist until explicit regrouping. Preview covers at most 1,000 recent finished meetings, 200 active folders, 1,000 retained IDs including deletion tombstones, 4,000 summary characters per match. Automatic work runs once after final processing, never on audio callbacks.

Catalogs are atomic local files scoped to the exact account ID (or local mode). Optional cloud sync adds `/api/sync/folders`: GET returns `{ revision, folders }`; PUT accepts the same shape with the last observed revision, uses an atomic compare-and-swap, and returns 409 on conflict. Folder records carry UUID `id`, `name` (80 characters), `description` (500), `titleRule` (120), `deleted`, and `localOnly: false`. Missing/removed tombstones are rejected. Different folder edits merge; same-folder conflicts preserve the local proposal for explicit resolution. Catalog names/descriptions are personal content, not diagnostics. Folders created from Local/private meetings remain local-only. No cloud gate is enabled by filing. Meeting document v1 adds optional `folder_id` and `folder_manual`; existing unknown-field echo keeps old clients compatible. No foreign key is required: a deleted/unknown folder resolves to Unfiled and cannot delete a meeting. Backend schema and route must precede the app rollout.

MC1 settles into the saved result **in place**, preserving selection/editing and Resume rather than forcing a route change. History is optional navigation, not completion. Final processing owns configured exports, including private-mode exports; navigation must not send another copy. Existing durable transcript, final AI and webhook owners remain authoritative.

Implementation and automated validation are complete for the local testing handoff. Physical/manual and rollout evidence remain open in the release checklist.

Rendered iPhone verification: native Create/Save remains in the persistent toolbar above the keyboard. The sheet explicitly inherits interface text size; a corrected largest-accessibility-size UI journey passes and its screenshot was visually inspected. Unicode input uses the backend UTF-16 length bounds, and keeping a conflict after remote deletion cannot bypass the active-folder limit. Both edge cases have regression tests. Mac/iPad, VoiceOver and signed upgrade remain release gates.

Review corrections (2026-11-04): renamed automatic folders retain their deterministic identity and title-rule matching. A local-only assignment omits shared folder fields from uploads; backend revision CAS preserves those fields on omission, including writes from older clients. Explicit null remains removal. A meeting keeps one durable CRM completion across Resume/Stop; Markdown uses a separate optional per-end checkpoint so its failure cannot hold CRM delivery. A stopped result left open does not block the next calendar event or restart its own event. Updated evidence is in the release record.


## Broader organisation and preview, 2026-11-05

Ian found per-title suggestions too specific. Automatic creation now suggests Team, Customers, Product & engineering, Hiring, Business planning, Partners & suppliers and Learning, only when at least two completed titles support a category. Whole-word/phrase title cues drive those suggestions; generic planning is subordinate to a more specific purpose, ambiguous or unrecognised titles stay Unfiled. This is bounded local matching, not a new AI classifier. Existing specific folders are retained, not deleted or silently renamed. User folders and edited descriptions/title rules participate in the existing matching path before broad fallback. Renamed category IDs keep matching; deleted IDs are not regenerated. The automatic-creation switch does not disable matching to existing folders.

Preview shows one disclosure per proposed folder, its purpose and count of meetings to file. Expanding reveals the underlying meetings; all moves still require Apply. Counts describe proposed changes, not the entire catalog. Folder creation/editing uses visibly bordered native text fields. Mac History uses the strict no-indicator setting, retaining lazy scrolling without the system-forced thumb resizing as estimated content height changes. Existing matching/storage/account/privacy and undo bounds remain unchanged. Regression and UI evidence is in the release record.

## Second review, 2026-11-05

Untouched legacy/local-only cloud fingerprints remain unchanged. Folder matching prepares custom tokens/category lookups once per batch; equal catalogs do not write/publish on polling. Renaming a broad category preserves title evidence. Optional completion-local Markdown eligibility prevents enable-later backfills. Invalidated final AI still completes owner-fenced filing/exports after saving. The fourth review supersedes draft crash exports: recovered drafts are filed locally but automatic exports wait for explicit completion, including recovered resumed drafts with an older completion marker. The release record owns regression evidence. The final-defaults section below resolves calendar transitions and upgrader folder defaults; the CRM decision is resolved below.


### Additional review safeguards, 2026-11-05

On upgrade, folder fields preserved as unknown extras by 3.7 are promoted before cloud sync starts. The extras are consumed once so an explicit later Unfiled choice cannot resurrect an old assignment. A folder-only edit records its content baseline; conflict/pull handling preserves the latest remote notes/transcript and reapplies the pending folder instead of treating filing as an edit to the entire meeting. Ordinary simultaneous content edits retain the existing conflict contract. Full-document upload remains the transport, so large bulk filing is correct but can still be slow; a bounded metadata-only transport remains follow-up performance work.

A single custom-folder name found only in a summary no longer qualifies. Title rules and title evidence still work. Concurrent additions beyond the shared 200-active/1,000-total bounds become retained, resolvable conflicts rather than an endlessly rejected catalog.

Completion recovery stages configured CRM deliveries from saved external attendees without waiting for a live Calendar connection. Explicit calendar association fills missing attendees while preserving manually populated attendees, title, notes and privacy. Join during an ad-hoc recording asks for association rather than silently attaching metadata. Markdown completion uses a content fingerprint as well as the stop time, allowing re-export after later saved edits. Ian confirmed on 2026-11-05 that automatic Attio/Twenty sync runs once at the first completed recording. Later edits or a resumed recording do not trigger another automatic send or update; the user resends later changes manually. This retains the existing completion identity and retry behavior. Automatic update-in-place is outside 3.8.0 scope.


Fourth review, 2026-11-05: clean legacy folder promotion rebases matching bookkeeping without timestamp changes; pre-existing edits remain dirty. Explicitly labeled persistence mutations ensure launch migration runs on success. Folder-only merges preserve unseen remote content during push, pull and reconcile; capacity recovery preserves IDs. Markdown change detection hashes exported content, excluding unrelated pin/folder metadata. See the [fourth-review disposition](../releases/3.8.0-evidence.md#fourth-review-corrections-2026-11-05) for tests and remaining release gates.

## Final defaults, confirmed 2026-11-06

Ian selected automatic creation/filing for newly completed meetings, including upgraders; existing history is never reorganised just by upgrading or opening a preview. History needs explicit Preview and Apply. A regression exercises automatic filing of the new meeting with older evidence left untouched, then explicit application to history. Continuing calls remain in one recording across calendar boundaries; next-meeting handoff requires an explicit action. CRM stays first-completion-only with manual resend. These resolve the earlier open product decisions.


FO1 ninth-review implementation: every legacy synced row without a folder baseline refreshes server membership before upload, including rows with no cached extras. Failed listed-document fetches have per-meeting five-minute backoff and a three-failure automatic bound; unrelated sync continues, activation preserves the bound and Sync now retries explicitly. Folder-only/baseline-only merges do not rewrite Markdown. See the [current audit](../releases/3.8.0-planning-audit.md#build-155-final-release-planning-audit-2026-11-06).


## Folder journeys and optional setup, 2026-11-08

Ian selected an optional organise-your-meetings setup task and a focused folder manager for 3.8.0. The overview offers Organise existing meetings, Create a folder and Manage your folders. Preview has folder descriptions/counts and a separate Apply action. Manual filing stays protected unless explicitly included through Preview options. Create/edit shows name and description first; title rules and local-only creation live under More options. Selecting an existing folder opens its editor, including deletion. Cancel/back retains saved data; Save returns to the list. Automatic filing stays visible on the overview, with automatic creation under More options. Existing defaults, matching, ownership, undo and cloud boundaries are preserved.

The optional setup task starts unreviewed, even when automatic filing is already enabled. Opening or hiding it does not complete it. Confirm folder choices marks it reviewed without changing settings or filing history; review persistence lives in HomeSetupState. The task has the same hide/General restore controls and help popover as the other tasks. Home loads at most 1,000 finished meetings, only when Preview is requested. It does not observe or fetch the whole history for the checklist. The existing History entry point uses its supplied meetings.

Current delivery: these changes are included in Mac 3.8.0 build 164, released on 2026-11-09, and iOS build 164, live on the App Store since its 2026-11-10 confirmation. Full hosted suites, all 31 iPhone UI journeys and signed-package verification pass. The [release record](../releases/3.8.0.md) retains specialist physical evidence limitations.


### Mac folder presentation refinement, 2026-11-09

Folder sheets use the miniti primary surface and dark appearance. More options, Preview options and category disclosures use the existing full-row MinitiDisclosureStyle with a platform minimum target. Clicking the label or empty row space toggles it. iOS navigation, form styling and keyboard-safe actions remain unchanged. Matching, filing and persistence are unchanged.
