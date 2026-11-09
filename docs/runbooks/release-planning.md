# Release planning audit

Use this workflow whenever planning, materially revising or reviewing an upcoming miniti release. The reusable [release-planning skill](../../.cursor/skills/release-planning/SKILL.md) is versioned in this repository, with relative discovery links under `.agents/skills` and `.claude/skills`. This document preserves the project-specific contract. Planning establishes scope and acceptance criteria. It does not establish that runtime checks passed or authorize publication.

## Start from the existing release

Read root AGENTS.md, the current release record, roadmap and owning plans. Inspect working trees in every affected repository. Preserve concurrent work. Reconcile original architecture stages before assigning release packages: enrollment A/B stages, reliability R stages and release-specific packages have separate names and responsibilities.

The Apple roadmap is the sole priority index. Keep one versioned checklist in `docs/releases/`, linked to bounded owning plans. A release-wide audit can be a sibling `X.Y.Z-planning-audit.md` with findings and a surface register. Keep detailed evidence there rather than expanding AGENTS.md. Use plain dated attribution for outside reviews; public files must contain no private conversation URLs/IDs.

## Required coverage

| Area | miniti-specific checks |
|---|---|
| Regression | Record/Stop/resume, no first words, held final words, reconnect/account/meeting-generation races, save once, report once, relaunch, Watch receipts, existing defaults and upgrade from the prior release. Preserve user settings/history/credentials. |
| API and data compatibility | Apple and Linux old/new requests, strict response decoders, headers/proofs, retry and error categories, legacy queue decoding, unknown versions, stale/lost replies, backend-first rollout and post-client rollback. Exact prompt copies and shared fixture pins remain aligned if touched. |
| Account/billing | Check every mutation of usage periods/counters and actor/target membership, not only the route being edited. Distinguish device-level fixes from later B0–B3 ownership migration. Test case variants of device IDs, resets, deletion/revocation and receipts before claiming exactly once. |
| UX/accessibility/design | User-visible state/actions and cancellation on Mac/iPhone/iPad. ColorPalette, MinitiDesignSystem, InterfaceScale, native Button/Menu, MinitiControlLabel, lowercase/no-em-dash copy, Reduce Motion, large text, focus/keyboard, VoiceOver and truthful errors. No hidden account creation or changed consent. |
| Performance/cost | No new persistence/network/array scans on PCM or per-word hot paths; coalesced UI state, bounded queue/retry/timers, async disk writes, Redis operations and provider calls. Define controlled comparisons to the released build and explicit bounds for the new work. |
| Security/privacy | Enrolled proofs and owner checks at mutation/replay time, atomicity and partial failures, raw errors/tokens/content in logs, device names, consent/private mode, BYOK exclusions, deletion/retention, finite inputs and request limits. Internal App Store disclosure review only when affected; no special reviewer outreach. |
| Testability | Both hosted Apple bundles use Testing; hardware/provider tests are opt-in. Meaningful fake-clock/transport tests, real isolated Redis/Postgres where concurrency matters, wire tests and rendered/device evidence. A simulated long recording is not long hardware validation. |
| Operations/recovery | Start/end/retry outcomes, coverage gaps, admin counters and useful bounded diagnostics. Define deployment order, old-client behavior and rollback that preserves existing receipts/queues/account state. |

Every selected workstream needs a row for each applicable concern or an explicit reason it does not apply. Use statuses: covered by contract, plan corrected, decision needed, implementation evidence pending, or not applicable with reason. Keep confirmed user decisions distinct from engineering choices and measured evidence. A passing planning audit does not make the release shippable.

## Required surface register

For each affected surface record **path, change, owning package, timing and evidence**. Do not replace this with “update docs”.

- Internal: `docs/roadmap.md`, bounded plans, references, release record, relevant AGENTS.md/runbooks and Linux PLAN.md. Public roadmap order follows the internal index; internal accounting/test work need not become marketing features.
- Public docs: inventory exact MDX pages in `../miniti-docs`, navigation/FAQ structured data, platform scope and existing examples. Update content once implemented, mark genuinely upcoming content explicitly, and distinguish Mac availability from iOS submission/availability.
- Website: `../minitidotapp/roadmap/index.html`, `llms.txt`, `llms-full.txt`, privacy/FAQ/homepage duplicates, screens/captions and generated changelog. Preserve the full shipped showcase, emojis and historical dates.
- Changelog/store copy: future bullets can be drafted inside the release plan; promote only implemented behavior into CHANGELOG.md and localized Fastlane release notes. Use the project's changelog skill/style, flat new/improvement/fix bullets, platform tags and iOS-appropriate notes. Never rewrite historical releases to describe planned work.
- Screenshots: list affected new/changed states, exact capture destinations and retained assets. Use the real app with synthetic data; inspect every selected result for layout, accurate labels, platform/copy and privacy. See [capture runbook](../../scripts/screenshots/README.md). App Store captures need a separate keep/replace decision for each affected device family and locale; uploads remain release work. If the active environment requires device-panel tooling, adapt capture control accordingly instead of blindly running an older simulator-control script.
- Version/distribution: plan the later build/version/appcast/download changes without advancing them during planning. Mac, iOS and Linux have independent availability. Follow [RELEASE.md](../../RELEASE.md) when actually releasing.

## Evidence and completion

Run doc checks and a cross-repository link/anchor check for changed plans, including newly added release records. Use the release-planning skill's private-reference scanner on candidate public text and inspect screenshots manually for personal data when captures exist. These checks are not a general secrets audit or runtime validation.

From the Apple repository, the reproducible link command is `python3 .cursor/skills/release-planning/scripts/check_plan_links.py --changed . --changed ../miniti-api --changed ../miniti-linux --changed ../minitidotapp --changed ../miniti-docs`, using only the sibling checkouts present and involved in the task. It checks inline local Markdown links and common section/HTML anchors; it does not validate live URLs or every Markdown extension. Run its `test_check_plan_links.py` after changing the helper. Keep evidence scripts in the repository rather than relying on a temporary local file.

Document required implementation commands and acceptance thresholds before coding; execute runtime tests only when implementation or the requested investigation warrants it. Record commands/revisions, actual results, relevant skips and manual evidence. Undefined or unmeasured performance is pending, never green by assertion.

A planning pass completes when findings have dispositions, selected decisions are reflected consistently, every required publication surface has an owner/trigger, the release plan links the evidence, and validation of the edited docs/skill has passed. Repeat the audit after material scope changes and at implementation completion. The [3.8.0 audit](../releases/3.8.0-planning-audit.md) is the first application of this workflow.
