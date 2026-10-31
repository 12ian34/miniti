# Managed lightweight model migration, 3.6.0

Status: implemented and validated locally on 2026-10-31. Not deployed or released. The [release record](../releases/3.6.0.md) owns rollout evidence. No commercial pricing change.

## Bounded decision

Only managed `speaker_names`, `catchup`, `docs_topics` and `template_draft` move to `gpt-6-luna`, reasoning `none`. Backend `lib/insights.ts` centrally selects the model and reasoning. The client-supplied model remains ignored.

Standard summaries, Questions, MEDDPICC, meeting-template filling, grounded Docs answers and investigations retain GPT-5.4 mini with low reasoning. `INSIGHTS_INCREMENTAL_QUALITY_MODEL=off` still restores GPT-5 mini with low reasoning for incremental quality requests. Template drafting creates a definition from a description; it does not fill a meeting template.

Apple and Linux BYOK choices are unchanged. Prompts, refresh cadence, normalization, language and speaker-name evidence rules, timeouts, bounded retries, allowances, local defaults and account/private-mode boundaries are unchanged. No automatic cross-model retry.

## Rollback

Set `INSIGHTS_LIGHTWEIGHT_LUNA=off` in the backend environment and redeploy. This restores only the four lightweight modes to `gpt-5-mini-2025-08-07` with low reasoning. The switch is case/whitespace insensitive and read per request. Unset or any other value enables Luna. It is independent of the incremental-quality switch. No client update or data migration is involved.

## Accounting

The backend now preserves reported cache writes from both Chat Completions and Responses usage shapes, through daily per-model counters and cost rollups. Cache reads and writes are disjoint subsets of total input. Writes replace ordinary input charges; output already includes reasoning tokens. Old records without writes remain valid and existing model prices remain unchanged. Official pricing/usage references and operator configuration are in the [backend patterns](../../../miniti-api/docs/agents/03-patterns.md) and [environment reference](../../../miniti-api/docs/agents/02-environment.md).

The estimate assumes Standard short-context requests and default 30-minute caching. No 12-hour cache policy, tier or accounting redesign is introduced. Lifetime per-device counters still combine models and use fallback pricing; retry usage still reflects the last reported call. These existing estimates are not a replacement for provider billing.

## Evidence

- Reviewed the private synthetic evaluation, its run metadata and raw outputs for the four modes. The 108 comparison calls returned valid JSON without provider failures or retries. The evidence supports this narrow selection; it does not establish production savings, universal latency improvements or freedom from hallucinations. Private financial analysis and raw artifacts remain untracked.
- New focused tests exercise all four parsed requests through the actual generators, provider model/reasoning, rollback, unaffected quality choices, independent incremental fallback, language/name handling, response normalization and bounded same-model failure retries.
- Old/new usage parsing and cost tests cover reads, writes, output/reasoning, missing fields, clamping, price overrides, KV persistence and mixed old/new monthly rollups.
- Full backend suite: 717 passed, 5 existing opt-in integration/live tests skipped. Next type generation, TypeScript, ESLint and production build passed. See release record for commands and limitations.
- Four new live calls used small synthetic fixtures through current backend functions and parsing, with explicit `store:false` and Standard service tier in the smoke harness. All succeeded without retries and returned compatible results. Private smoke evidence records every usage object, source hash and cost. No customer transcripts, production endpoint writes or persistent account changes.
- No Apple source change, hosted tests, hardware run or new app build for this migration. Existing build 146 Apple results remain evidence for that binary, not a new device pass. The prior preference-backup waiver does not authorize a later hardware run.

## Rollout, not yet authorized

1. Review and deploy the backend with the intended `INSIGHTS_LIGHTWEIGHT_LUNA` setting. Existing clients receive the managed routing without a binary update. The backend branch also contains previously prepared alert changes; review the combined deployment.
2. Confirm a small synthetic managed request for each selected mode, model telemetry and usage accounting. Observe latency/errors before making production claims; roll back with the setting above if needed.
3. Publish the matching docs/changelog only with the authorized 3.6.0 rollout, removing upcoming labels when deployment is confirmed. Preserve the existing site purchase-page → additive backend → app order for the wider release.
4. Linux [parity tracking](../../../miniti-linux/PLAN.md#tracking-managed-lightweight-luna-2026-10-31-local-only) records shared managed routing and unchanged BYOK. Linux client gaps remain separate.

The separate dark DMG artwork requires repackaging the installer, notarizing/stapling it and replacing its byte count, hash and Sparkle signature before publication. It does not require recompiling the app. A local preview is not a release-ready installer.
