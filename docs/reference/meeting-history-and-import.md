# Meeting search, imports and saved results

Current baseline, reconciled after 3.4.0. [Patterns](patterns.md) owns persistence; [cloud](cloud-sync.md) owns sync deduplication. Large-history optimization is a [separate plan](../plans/history-and-session-performance.md).

## Search

Shared query grammar supports AND words, quoted phrases, person/title/date/range and field operators; unknown operators stay plain text. Use local-calendar date boundaries. Search projections/cache are keyed by meeting and transcript revision. Optional calendar event title is populated for new records, not invented for old ones. Preserve ranking/snippets/pins/grouping while optimizing. Semantic search, saved searches and Spotlight are not implied. [Shipped search design](../archive/meeting-search-plan.md) retains detailed grammar; its “today” paragraph describes the old implementation. The weeks-old meeting manual check has no recorded completion.

## Granola

3.4.0 accepts the current emailed ZIP or CSVs, column aliases and duplicate protection. Unlabelled exports do not contain speaker identities or word timings: keep one S1 and sentence turns, estimate duration at 150 words/minute and say it is estimated. Never infer speakers by alternating lines. Preserve summary cleanup and explicit external-source/id keys.

ZIP supports stored/deflate entries, not encrypted/ZIP64; unsupported archives should ask the user to unzip. A real 33-meeting export was parsed in the standalone harness; sandbox-host file access can hang on permission UI, so this is not equivalent to a full import interaction test. Mac/iPhone picker, repeat-import and cloud duplicate checks remain evidence tasks. Linux parity is separate. [Import record](../archive/granola-import-plan.md).

## Saved results and exports

User edits, transcript trims, deleted meetings and template changes must retain current data. R7’s late History result fence is still planned in [reliability](../plans/reliability.md); final-insight fencing is not proof every History path is protected. Custom templates persist a per-meeting definition snapshot so editing/deleting a template does not break old exports. Cloud pulls do not trigger CRM/webhook sends. Delivery retries/coalescing are R5/R6, not completed by the existence of the persisted outbox.
