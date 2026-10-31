# Managed lightweight model migration, 3.6.0

Status: implemented and validated locally on 2026-10-31. Not deployed or released. The [release record](../releases/3.6.0.md) owns rollout evidence. No commercial pricing change.

## Bounded decision

Only managed `speaker_names`, `catchup`, `docs_topics` and `template_draft` move to `gpt-6-luna`, reasoning `none`, only with explicit `INSIGHTS_LIGHTWEIGHT_LUNA=on`. The default remains GPT-5 mini with low reasoning. Backend `lib/insights.ts` centrally selects the model and reasoning. The client-supplied model remains ignored.

Standard summaries, Questions, MEDDPICC, meeting-template filling, grounded Docs answers and investigations retain GPT-5.4 mini with low reasoning. `INSIGHTS_INCREMENTAL_QUALITY_MODEL=off` still restores GPT-5 mini with low reasoning for incremental quality requests. Template drafting creates a definition from a description; it does not fill a meeting template.

Apple and Linux BYOK choices are unchanged. Prompts, refresh cadence, normalization, language and speaker-name evidence rules, timeouts, bounded retries, allowances, local defaults and account/private-mode boundaries are unchanged. No automatic cross-model retry.

## Rollback

Set `INSIGHTS_LIGHTWEIGHT_LUNA=off` in the backend environment and redeploy. This restores only the four lightweight modes to `gpt-5-mini-2025-08-07` with low reasoning. The switch is case/whitespace insensitive and read per request. Only `on` enables Luna. Unset, blank, `off` or unrecognized values retain GPT-5 mini low. It is independent of the incremental-quality switch. No client update or data migration is involved.

## Accounting

The backend now preserves reported cache writes from both Chat Completions and Responses usage shapes, through daily per-model counters and cost rollups. Cache reads and writes are disjoint subsets of total input. Writes replace ordinary input charges; output already includes reasoning tokens. Old records without writes remain valid and existing model prices remain unchanged. Official pricing/usage references and operator configuration are in the [backend patterns](../../../miniti-api/docs/agents/03-patterns.md) and [environment reference](../../../miniti-api/docs/agents/02-environment.md).

The estimate assumes Standard short-context requests and default 30-minute caching. No 12-hour cache policy, tier or accounting redesign is introduced. Lifetime per-device counters still combine models and use fallback pricing; retry usage still reflects the last reported call. These existing estimates are not a replacement for provider billing.

## Evidence

- Reviewed the private synthetic evaluation, its run metadata and raw outputs for the four modes. The 108 comparison calls returned valid JSON without provider failures or retries. Of these, 36 covered six fixtures across the four selected modes: explicit, ambiguous and long-transcript speaker naming, catch-up, Docs topics and template drafting. The corrected rubric passed 42/42 lightweight checks in each 12-call arm. The long-speaker rubric initially required full names despite the prompt permitting spoken first names; offline rescoring accepted only the correct first or full names for every model, without rerunning requests. The Luna-none arm ran later rather than interleaved, so timing/cache differences limit latency conclusions. The evidence supports this narrow selection; it does not establish production savings, universal latency improvements or freedom from hallucinations. Private financial analysis and raw artifacts remain untracked.
- New focused tests exercise all four parsed requests through the actual generators, provider model/reasoning, rollback, unaffected quality choices, independent incremental fallback, language/name handling, response normalization and bounded same-model failure retries.
- Old/new usage parsing and cost tests cover reads, writes, output/reasoning, missing fields, clamping, price overrides, KV persistence and mixed old/new monthly rollups.
- Final default-off backend suite: 721 passed, 5 existing opt-in integration/live tests skipped. The unset/off/on provider cases cover all four selected modes; the routing matrix also covers blank, whitespace, mixed case and unrecognized settings. A pre-existing random PKCE negative-test collision found during this run was fixed separately, without changing authentication code. Next type generation, TypeScript, ESLint and production build passed. See release record for commands and limitations.
- Four new live calls used small synthetic fixtures through current backend functions and parsing, with explicit `store:false` and Standard service tier in the smoke harness. All succeeded without retries and returned compatible results. Private smoke evidence records every usage object, source hash and cost. No customer transcripts, production endpoint writes or persistent account changes.
- No Apple source change, hosted tests, hardware run or new app build for this migration. Existing build 146 Apple results remain evidence for that binary, not a new device pass. The prior preference-backup waiver does not authorize a later hardware run.

## Rollout, not yet authorized

1. Luna now defaults off in code. Before any authorized backend push/deployment, verify production has no explicit `INSIGHTS_LIGHTWEIGHT_LUNA=on`. An unset variable requires no change. Later explicit activation affects all managed app versions and Linux immediately. Deploy alert clarity/recovery work first with the previous lightweight routing retained. No production setting has been changed locally.
2. Review at least a day of hourly alert runs. This validates the backend/alert baseline, not Luna quality while disabled. Before separate authorized activation, review synthetic explicit/ambiguous/long-transcript speaker cases and the other selected tasks; then set `INSIGHTS_LIGHTWEIGHT_LUNA=on`, redeploy and inspect selected-model telemetry, errors, latency and naming reports. Do not treat no errors as proof of correct names. Rollback uses the setting above plus redeploy; already-saved names are not repaired by rollback.
3. Website/public-docs 3.6.0 release commits stay local until the corresponding app rollout. The purchase-return page is already live; no early push of unrelated release copy is needed. Luna is omitted from shipped release-note promises while off. Remove upcoming labels and announce it only after activation is verified.

4. Linux [parity tracking](../../../miniti-linux/PLAN.md#tracking-managed-lightweight-luna-2026-10-31-local-only) records shared managed routing and unchanged BYOK. Linux client gaps remain separate.

The separate Retina DMG artwork was finalized through `fastlane mac dmg` after Ian explicitly authorized DMG notarization only. The release record has final bytes/hash/Sparkle signature and verification. The app was not recompiled; the IPA is unchanged. Publication and deployments remain unauthorized.
