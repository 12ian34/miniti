# Per-meeting cloud storage and calendar-title rules

Status: delivered in macOS 3.5.0 build 142 on 2026-10-30; shared backend/site deployed. iOS build 142 submitted, availability not confirmed. This is the implementation record, not future build scope. [Release evidence](../releases/3.5.0.md) owns delivery and remaining evidence; [roadmap](../roadmap.md) owns subsequent work.

## Product contract

C1 gives a live or saved meeting a small Cloud/Local control at the top right. It uses the same `MinitiControlLabel` chrome as the meeting actions: faint blue, cloud icon and Cloud when included, crossed-out cloud and Local when excluded. Ian explicitly rejected the Home checkbox; there is no pre-recording checkbox on Home, calendar preparation or countdowns. On compact iPhone the control is in the top navigation bar; recording actions remain at the bottom.

Clicking changes this meeting only and shows a brief confirmation: “This meeting will be saved to the cloud.” or “This meeting won't be synced to your cloud.” Paused/unavailable account sync gets conditional wording instead of a promise of an immediate upload. Removing an existing copy explicitly says removal is pending until acknowledged. The local original remains. Cloud storage choice does not alter Deepgram, AI, webhooks or CRM exports.

A running private-mode meeting stays Local; the control cannot opt it into cloud during that recording. Saved meetings can be deliberately included later. Ordinary recordings upload only once finished and outside the live meeting, so choosing Local while recording happens before initial upload eligibility. Existing synced meetings and resumed recordings can already have a cloud copy; do not claim this choice erases previous copies instantly.

## Rules and creation-time safety

Settings, Cloud keeps literal case-insensitive title-contains rules, trimmed nonempty input, OR across rules. No regex, inferred sensitive category or AI classification. Rules are local and labelled On this device. They affect new calendar recordings, not calendar visibility or saved meetings. Watch/import controls and recurring-series filters remain out of scope.

Add rule is an enabled action that opens a focused editor with an example. Save rule requires a valid new value; empty, duplicate, over-120-character and 30-rule capacity states explain the problem. No silently disabled Home-style input flow. Preview shows next-seven-day matches and reasons, is bounded to 50 calendar events, and discards responses after account changes.

The common creation path applies rules/private mode before any save. Without a manual override, late calendar association may only add exclusion. An explicit Cloud/Local toolbar choice remains authoritative for that meeting; later calendar matching cannot reverse it. Rule removal or renaming never lifts an existing exclusion. The next meeting gets its own decision; no previous one-off setting leaks into it.

## Sync safety and additive backend amendment

A delayed initial push after exclusion must retain local content and queue deletion at the server's acknowledged revision, even when the local revision was zero. Pull and reconcile cannot overwrite or delete an excluded local original. Pending and failed removals stay visible in History and saved detail. Do not promise immediate erasure from backups or downstream exports.

The existing Put on the cloud action previously met a permanent server tombstone refusal that could delete the local original. The implemented fix adds signed upload-envelope `restore_deleted: true`, requested only by an explicit include action and persisted as local `Meeting.cloudRestoreRequested` until accepted. Same account checks, exact base revision and transcript guard apply; ordinary uploads cannot resurrect tombstones. Pending restore survives pulls/reconciliation; a fresh exclusion cancels it. No synced-document field, SQL schema migration or account-ownership change. Deploy backend before clients.

## Code and validation

`CloudSettingsView.swift` owns shared storage control, confirmation overlay, pending status and rule editor. `AppState+CloudSync.swift` owns validation/actions and cloud queueing; the common `startNewMeeting` path owns creation defaults. Both live and saved views on Mac/iOS use the same control. [Full compatibility contract](../reference/monitoring-cloud-purchase.md).

Automated regressions cover live toggle persistence, isolation from another meeting, late-rule override, private-mode lock, saved-copy deletion queue and truthful pending feedback, rule validation, creation-time latching, held initial upload/exclusion, delayed pulls/deletes and explicit restore. Production SQL was exercised in local PostgreSQL/PGlite for exact revision, transcript guard, account isolation and concurrent writers. Neon transport remains separately unverified.

Device QA: record a synthetic meeting, choose Local during recording, stop/save, verify absence on another device/web/API. Follow with a normal Cloud meeting and verify sync. Add a therapy-title rule through the editor, preview/start, override once, remove the rule and verify saved exclusions stay excluded. Separately exclude a saved synced test meeting offline, observe pending state, reconnect/remove, then explicitly restore after the new backend is deployed. Check Mac minimum width, iPhone/iPad, large text, VoiceOver, failed starts, resume, auto-start and handoff. No production content needs to be used.

## Delivery

Keep current users' defaults and data. Align the Privacy data-flow overview, public Help at shipping time and Linux parity tracking. Run both Apple bundles and affected backend checks. No push/deploy/release is authorized by this plan. Close only with device and delivery evidence. Rollback must preserve sticky exclusions, pending deletion and explicit restore intent; do not remove additive backend restore support while new clients depend on it.

Design revision history: the original pre-recording Home checkbox was built and tested, then rejected by Ian's UX review on 2026-10-29. The toolbar/editor design above supersedes those earlier surface and one-off-choice acceptance checks.

### Availability review correction (2026-10-30)

Never-synced meetings on cloud-off/free/BYOK accounts must not invent a pending cloud removal. Queue deletion when a copy is evidenced (revision, prior sync metadata or an existing tombstone), when that meeting's upload is in flight, or when a finished meeting can currently sync. The engine exposes only the in-flight meeting-ID check; it does not add network work. Keep known deletion work while paused/offline. Explicit include still preserves restore intent for remotely tombstoned meetings, but the UI explains the actual gate (off, managed/Pro required, signed out, private mode or offline) instead of promising an upload that cannot run. Legacy zero-revision tombstones are not presented as known pending cloud copies while syncing is unavailable. The redundant inner restore guards in manifest/change application are removed; the outer guards continue protecting explicit restore intent.
