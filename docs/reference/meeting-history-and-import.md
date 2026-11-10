# Meeting search, imports and saved results

Current baseline, reconciled through released 3.6.0. [Patterns](patterns.md) owns persistence; [cloud](cloud-sync.md) owns sync deduplication. Large-history optimization is a [separate plan](../plans/history-and-session-performance.md).

## Search

Shared query grammar supports AND words, quoted phrases, person/title/date/range and field operators; unknown operators stay plain text. Use local-calendar date boundaries. Search projections/cache are keyed by meeting and transcript revision. Optional calendar event title is populated for new records, not invented for old ones. Preserve ranking/snippets/pins/grouping while optimizing. Semantic search, saved searches and Spotlight are not implied. [Shipped search design](../archive/meeting-search-plan.md) retains detailed grammar; its “today” paragraph describes the old implementation. The weeks-old meeting manual check has no recorded completion.

3.9.0 local correction: applying a custom date range inserts both after:/before: tokens in one query update. Existing date filters are replaced once while words, phrases, people and devices remain. Single-date presets still replace the previous date selection. Both platform controls use the same batch insertion contract.

## Granola

3.4.0 accepts the current emailed ZIP or CSVs, column aliases and duplicate protection. Unlabelled exports do not contain speaker identities or word timings: keep one S1 and sentence turns, estimate duration at 150 words/minute and say it is estimated. Never infer speakers by alternating lines. Preserve summary cleanup and explicit external-source/id keys.

ZIP supports stored/deflate entries, not encrypted/ZIP64; unsupported archives should ask the user to unzip. A real 33-meeting export was parsed in the standalone harness; sandbox-host file access can hang on permission UI, so this is not equivalent to a full import interaction test. Mac/iPhone picker, repeat-import and cloud duplicate checks remain evidence tasks. Linux parity is separate. [Import record](../archive/granola-import-plan.md).

## Saved results and exports

User edits, transcript trims, deleted meetings and template changes must retain current data. R7’s late History result fences shipped in [3.6.0 sync/delivery](../plans/sync-and-delivery-reliability.md): request, transcript, account and template authority reject stale results without clearing newer work. Custom templates persist a per-meeting definition snapshot so editing/deleting a template does not break old exports. Cloud pulls do not trigger CRM/webhook sends. R5/R6 also shipped in 3.6.0: released webhook bodies have immutable delivery IDs, and terminal failures can resend current saved data with a new ID. Device/receiver waivers remain in the release record.

## Folders (3.8.0 local candidate)

History on Mac/iOS has All meetings, Unfiled and flat editable folders. Each meeting has one optional primary assignment; a manual move stays authoritative until explicit regrouping. Folder names, descriptions and title rules participate in bounded local matching after final AI settlement. No new AI request, transcription upload or model consent is involved. Automatic filing and creation are separate switches. Creation suggests broad purposes from repeated title evidence, not a folder per repeated title. Since 3.9.0 an unfiled meeting first follows the folder of earlier meetings in the same series (calendar series ID, or the title with dates and numbers removed), with hand-chosen folders outranking automatic ones, so manual moves teach later meetings. Strong summary evidence (two or more different phrases of exactly one broad category) can file into a broad folder that already exists, never create one; the broad keyword lists are wider. Preview groups proposed moves by folder, with counts, descriptions and expandable meeting titles. Existing custom folders, manual moves and renamed identities remain authoritative. Existing history changes only through an explicit preview/apply, at most 1,000 recent finished rows; Undo reverses the latest move/batch in the current session. Folder deletion retains meetings and resolves memberships to Unfiled.

`MeetingFolderStore` owns an atomic, account-scoped catalog file and three-way sync; optional SwiftData membership columns preserve legacy stores through additive migration. Shared catalogs sync independently of meetings so empty user-created folders can travel. Local/private-derived folders and their membership never upload. Same-folder conflicts preserve the local proposal for an explicit choice. Tombstones cannot be silently resurrected. The [folder plan](../plans/folders-and-meeting-completion.md) owns bounds, compatibility and rollout.


Mac 3.8.0 local export setup: the optional Markdown folder and AGENTS index can also be configured during first-use/Home setup. App history remains in its local database. Bookmark/path replacement is atomic from the user's perspective. AGENTS updates replace only the `miniti:meetings` comment block, appending it to existing unmarked content and preserving outside text; malformed markers stop the index write. This does not enable cloud sync, change private-mode export permission or backfill history automatically.

Second review, 2026-11-05: automatic Markdown eligibility is snapshotted at Stop; enabling it later never backfills completed history on launch. Explicit bulk export remains available. Filename collision lookup is bounded to one same-minute meeting. The exact old miniti-generated AGENTS header/list migrates into the maintained block, preserving appended human notes; arbitrary instructions remain untouched. Folder batches precompute custom match tokens; a broad-folder rename retains title-based purpose matching unless its rule/description is explicitly customised.


3.8.0 folder navigation: History → Folders opens three journeys: Organise existing meetings (preview then Apply), Create a folder, and Manage your folders (select one to edit or delete). Automation stays on the overview. Matching rules and device-only creation are optional editor controls. Home offers the same manager through an optional setup task.
