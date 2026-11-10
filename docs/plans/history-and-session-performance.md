# Large-history responsiveness and sustained-session budgets

Status: scoped future work, not implemented; version unassigned. Reconciled 2026-10-27. Priority is in [the roadmap](../roadmap.md). This is a bounded deliverable, not an ongoing maintenance programme. Confirm design and release scope before implementation.

## Scope

Original P0.7, P1.1 and P1.5; T15 performance evidence and relevant T09/T11/T12 journeys. Establish a 60+ minute recording baseline on Mac/iPhone and make History search/grouping and Coaching responsive on 10/100/1,000-meeting fixtures. Existing query grammar is shipped; do not redesign it or introduce semantic search.

## Implementation and tests

Measure CPU, memory slope, main-thread stalls, save-plan/apply/commit, view invalidation, battery/thermal behavior and scrolling. Debounce queries, compute a single immutable result snapshot per query/revision off the main actor, and replace repeated membership scans with sets where measured. Preserve rankings, snippets, quoted/field/date query semantics, pins, deletion, accessibility and search-focus navigation.

Coaching retains exact aggregate data, six independent metric scales, numeric sequence ticks and missing-data semantics. Downsample rendered points only if measured, preserving accessible/hover values. Exercise long transcripts, insights, live panes, resizing, recovery and hundreds of saved meetings. Record a repeatable benchmark procedure and hardware/toolchain, not a bare percentage.

## Design-system follow-through

Selected mapping, 2026-11-09: the [design audit](../research/design-system-audit-2026-11-09.md) and [order 3d disposition register](ui-consistency-and-accessibility.md#audit-ownership-register) assign this plan the broader D11 insight/card/content consolidation, D12 metric-help model and adaptive presentation, D14 single scroll ownership and D15 shared insight rails. Include notes-editor/section-header reuse, Coaching metric/filler presentation and the saved-review portion of D16 where these surfaces change. D13 keyboard checks apply to the changed controls. Immediate text metrics, contrast, tab parity, help hit targets and the temporary action-checkbox correction belong to 3d and are not deferred here.

Share content between live/saved meetings and Mac/iOS while keeping each screen's navigation, scroll container, pane sizing, save timing and selection owner. Use existing speaker presentations where semantics match; preserve grouped Others details, resolved-self identity, all six metric meanings, chart domains and missing-data handling. Reuse existing card, sidebar and help primitives, with deliberate platform density/presentation variants. Keep native iOS sheets and Mac popovers where appropriate.

Before extraction, record representative live/history results and performance on the same fixtures. Acceptance requires equal content/order/metrics, preserved transcript selection/correction and copy/export, one vertical scroll owner per insight screen, stable section/tab selection on updates, reachable keyboard/VoiceOver actions and no large-text clipping. Compare view invalidation, full-document work and scroll/measurement costs before and after; extraction alone is not evidence of a performance improvement. Validate smaller early extractions in the feature that ships them and update this scope to avoid duplicate work. Do not create a generic screen engine or mix persistence/AI-operation redesign into this package.

## Acceptance and rollback

Set explicit measured budgets before optimization; demonstrate stable resource behavior and responsive interaction with unchanged results. Retain the prior result engine as a reversible implementation until parity passes; no persisted index migration without its own compatibility design. Keep hardware limits explicit.


## Release contract

Record before/after evidence and run the affected backend checks and both Apple bundles for shared client changes. Update current reference docs and the per-platform release record. Preserve existing data and compatible old clients. Shared backend changes require Linux tracking. No deployment is authorized by this document. Close the whole stated scope when shipped; unrelated discoveries become separate roadmap items.
