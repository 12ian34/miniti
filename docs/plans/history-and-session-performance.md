# Large-history responsiveness and sustained-session budgets

Status: scoped future work, not implemented; version unassigned. Reconciled 2026-10-27. Priority is in [the roadmap](../roadmap.md). This is a bounded deliverable, not an ongoing maintenance programme. Confirm design and release scope before implementation.

## Scope

Original P0.7, P1.1 and P1.5; T15 performance evidence and relevant T09/T11/T12 journeys. Establish a 60+ minute recording baseline on Mac/iPhone and make History search/grouping and Coaching responsive on 10/100/1,000-meeting fixtures. Existing query grammar is shipped; do not redesign it or introduce semantic search.

## Implementation and tests

Measure CPU, memory slope, main-thread stalls, save-plan/apply/commit, view invalidation, battery/thermal behavior and scrolling. Debounce queries, compute a single immutable result snapshot per query/revision off the main actor, and replace repeated membership scans with sets where measured. Preserve rankings, snippets, quoted/field/date query semantics, pins, deletion, accessibility and search-focus navigation.

Coaching retains exact aggregate data, six independent metric scales, numeric sequence ticks and missing-data semantics. Downsample rendered points only if measured, preserving accessible/hover values. Exercise long transcripts, insights, live panes, resizing, recovery and hundreds of saved meetings. Record a repeatable benchmark procedure and hardware/toolchain, not a bare percentage.

## Acceptance and rollback

Set explicit measured budgets before optimization; demonstrate stable resource behavior and responsive interaction with unchanged results. Retain the prior result engine as a reversible implementation until parity passes; no persisted index migration without its own compatibility design. Keep hardware limits explicit.


## Release contract

Record before/after evidence and run the affected backend checks and both Apple bundles for shared client changes. Update current reference docs and the per-platform release record. Preserve existing data and compatible old clients. Shared backend changes require Linux tracking. No deployment is authorized by this document. Close the whole stated scope when shipped; unrelated discoveries become separate roadmap items.
