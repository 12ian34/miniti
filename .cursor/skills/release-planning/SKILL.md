---
name: release-planning
description: Plan or deeply audit an upcoming software release across regressions, API and data compatibility, UX/design, performance, security/privacy, and release documentation/assets. Use for release scoping or readiness-plan reviews; it does not implement features or publish a release unless separately requested.
---

# Release planning

Produce one evidence-backed release plan that an implementing agent can follow, with a complete impact register and no false claims of runtime readiness. Preserve the user's selected scope and decisions. Read the repository's AGENTS.md and its planning/release runbooks; use the established roadmap, plan and evidence locations. Follow any project-specific release-planning runbook rather than creating a competing priority index.

## Audit the actual change

1. Establish the baseline: versions/platform availability, working-tree changes, original multi-stage plans, known waivers, prior reviews and explicitly selected scope. Keep published, submitted, implemented and merely planned states separate. Do not reset concurrent work or assume all clients share a release line.
2. Trace each workstream to current producers, consumers, state owners, persistence and API paths. Read enough source to test the plan's assumptions. Inventory sibling repos and callers before designing a changed wire/storage contract. Prefer concrete failure sequences to generic risk lists.
3. Evaluate every dimension below for each workstream. Classify it **covered by contract**, **plan corrected**, **decision needed**, **implementation evidence pending**, or **not applicable with reason**. A passing link checker never means a feature is safe.

| Dimension | Required planning evidence |
|---|---|
| Regression and data integrity | Before/after invariants, existing-user upgrade, interrupted operation, restart, cancellation, late responses, duplicate delivery, account changes and rollback. Name behavioral tests that would fail on the old bug. |
| API/backward compatibility | Old/new clients against supported server versions; strict decoders, optional fields, status/error semantics, auth scope, idempotency, retries, retention expiry and migration/downgrade. Cover every client and a safe deploy order. |
| UX and accessibility | Real first-use, success, pending, empty, degraded and error states; actions and cancellation; destructive transitions; focus/keyboard, screen reader, text scaling and supported layouts. Preserve existing consent and explicit user choices. |
| Design system | Name existing tokens/components and their ownership, product copy rules and native control behavior. Avoid invented parallel styling; identify affected rendered states and how they will be inspected. |
| Performance and cost | Audio/UI hot paths, writes, timers, retry/network cadence, concurrency, queue/storage bounds and provider/infra cost. Define meaningful structural limits and a measured comparison to the current release; do not invent measured results or arbitrary universal performance thresholds. |
| Security/privacy | Trust boundaries, actor and target authorization at mutation time, secrets/content in logs, replay/races, account separation, deletion/retention, consent/private mode and abuse bounds. Reuse tested authentication; avoid incidental security projects unrelated to the release. |
| Operations and rollout | Observability, failure categories, coverage gaps, compatibility deployment order, recoverable rollout and rollback, ownership of verification and what would stop rollout. No customer mail, live data writes or publication implied by planning. |
| Documentation and assets | Internal roadmap/plans/references/agent notes; public roadmap; public docs and FAQs; website duplicates/structured data; platform changelog/store notes; screenshots, captions, accessibility text and translations. Inventory concrete files and assign update/no-change decisions with reasons. |

4. Record findings by severity with source evidence, consequence, disposition, owning work package, regression/check, and remaining gate. Fix bounded planning defects within the user's scope. Ask only for genuinely unresolved product choices; preserve already confirmed answers. Do not silently split a selected release or expand a later ownership migration.
5. Create a release surface register: **surface/path, affected change, action, responsible work package, timing, evidence**. Name screenshots required from implemented UI and ones deliberately retained. Do not generate fictional product screenshots or publish anticipated behavior as current. Draft future changelog copy in the plan when implementation has not landed; preserve historical entries.
6. Consolidate into the existing release checklist with distinct work-package IDs, dependencies, acceptance tests, performance/resource checks, security/compatibility tests, documentation/assets ownership and rollout gates. Keep original architecture-stage identifiers unchanged and map release packages to them.

## Validate and hand back

- Run applicable existing doc/fixture checks and inspect the diff. New helper scripts need positive and negative tests. Run runtime suites only if the scope warrants it; a planning-only pass lists future commands without claiming they ran.
- Include new release records and sibling links with `python3 <skill-dir>/scripts/check_plan_links.py --changed <repo> [--changed <sibling>]`. Explicit files/directories also work. This checks inline local Markdown links and common heading/HTML anchors, not remote URLs, reference-style links or every Markdown extension. Run `test_check_plan_links.py` after changing the helper. Keep validation helpers in the repository so evidence is reproducible.
- Scan candidate public text for private chat/app references with `python3 <skill-dir>/scripts/check_public_refs.py --changed <repo> [--changed <sibling>]`. This is a narrow URI check, not a general secrets scanner or screenshot privacy review. Explicit file/directory arguments are also supported. Do not copy private conversation IDs into public evidence, even when citing a useful review; use plain dated attribution there.
- Reconcile roadmap/version/platform wording across affected source copies without moving shipping/version pointers prematurely. Record local changes separately from published copies. Leave unrelated public assets unchanged unless affected.
- State whether the **plan** is complete, the remaining implementation/manual evidence, material limitations and changes made. Link the canonical plan and audit. Do not call the release safe to ship merely because planning checks passed.

For miniti, the repository's `docs/runbooks/release-planning.md` supplies the project-specific owners, conventions and surface map. Read it when present. Invoke `$release-planning` again after implementation scope changes and before release preparation to reconcile the audit with actual results; it complements the release/publishing runbook.
