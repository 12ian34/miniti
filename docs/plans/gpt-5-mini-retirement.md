# GPT-5 mini retirement, 3.7.0

Selected by Ian on 2026-11-03 for 3.7.0. Implemented locally on Apple, backend and Linux; validation and distribution remain incomplete. Nothing deployed or released. The [roadmap](../roadmap.md#selected-next-release-370) owns priority; the selected test foundation remains first. Linux has its own release version and must deliver the corresponding BYOK update before the same provider deadline.

## Deadline and current exposure

OpenAI's [official deprecation schedule](https://developers.openai.com/api/docs/deprecations#2026-06-11-gpt-5-and-o3-model-deprecations), rechecked on 2026-11-03, schedules both `gpt-5-mini` and `gpt-5-mini-2025-08-07` for shutdown on **2026-12-11**. Complete deployment and client distribution before that date, allowing time for App Review and users to update. GPT-5.4 mini is a separate model and is not covered by this retirement entry.

The pre-migration source audit found the dependencies below. They still describe released 3.6.0 Apple BYOK and the pre-retirement backend; local 3.7.0 replacements are recorded under Local implementation evidence. This table is not a map of the current working tree:

| Surface | Pre-migration dependency | Delivery owner |
|---|---|---|
| macOS and iOS BYOK | `OpenAIModel.gpt5Mini`, direct insight-service defaults and AppState call sites use the pinned model for insights and helper tasks. Investigations use GPT-5.4 mini. | Apple 3.7.0 |
| Linux BYOK | `src-tauri/src/insights/mod.rs` selects `MODEL_MINI` for every mode except investigation. | Linux release, tracked in its PLAN.md |
| Managed fallback configuration | `miniti-api/lib/insights.ts` selects GPT-5 mini for lightweight tasks when Luna is not enabled, and for incremental quality work when `INSIGHTS_INCREMENTAL_QUALITY_MODEL=off`. | Shared backend |
| Hourly provider monitoring | `miniti-api/lib/opsHealth.ts` probes GPT-5 mini even when production insight routes use Luna/GPT-5.4 mini. | Shared backend |
| Supporting surfaces | Settings model descriptions, routing tests, accounting model registry and current operator documentation reference the old model. Historical usage still needs its original prices. | All three repositories |

The 2026-11-01 activation record establishes that normal managed requests use Luna or GPT-5.4 mini with the current production configuration. This does not remove the BYOK or monitoring dependencies. Client-supplied managed model fields are ignored by the backend; updating those fields alone cannot migrate direct BYOK calls.

## Selected model split, 2026-11-03

Ian approved this split for 3.7.0. Apply the same task mapping to managed requests and Apple/Linux BYOK wherever the task is implemented. This selects the models; direct-client compatibility and release validation remain required.

| Workload | Selected model | Reasoning |
|---|---|---|
| Standard summaries: live/incremental, final and saved meetings | `gpt-6-luna` | `none` |
| Lightweight tasks: `speaker_names`, `catchup`, `docs_topics`, `template_draft` | `gpt-6-luna` | `none` |
| Sales/MEDDPICC, Questions, meeting-template filling and grounded Playbook/Docs answers | `gpt-5.4-mini-2026-03-17` | `low` |
| Investigations | `gpt-5.4-mini-2026-03-17`, unchanged | `low` |
| Backend fallback/rollback destinations | `gpt-5.4-mini-2026-03-17` | `low` |

Template drafting creates a template definition and uses Luna; filling that template from a meeting uses GPT-5.4 mini. Coaching's local calculations remain local. The [existing evaluation](lightweight-luna.md#standard-summary-evaluation-and-scope-extension) supports the selected Luna workloads, not an all-Luna migration. Model capabilities were checked against the official [Luna](https://developers.openai.com/api/docs/models/gpt-6-luna) and [GPT-5.4 mini](https://developers.openai.com/api/docs/models/gpt-5.4-mini) documentation during selection.

Preserve the independent managed switches: lightweight/standard Luna flags select Luna only when explicitly on; off/unset/blank/invalid select GPT-5.4 mini low. `INSIGHTS_INCREMENTAL_QUALITY_MODEL=off` retains precedence and selects GPT-5.4 mini low for incremental quality requests, including standard summaries even when standard Luna is on. For other quality modes this now matches their normal model. These are configuration rollback paths, not new automatic cross-model retries. BYOK uses the task mapping above directly and does not inherit server environment switches.

Hourly health checks probe the two distinct supported models, Luna none and GPT-5.4 mini low, once each; remove the GPT-5 mini probe. Preserve historical GPT-5 mini usage and prices. Quantify BYOK cost changes during validation: heavier tasks move to GPT-5.4 mini while summaries and helpers move to Luna; this is not a promise of lower cost for every usage mix.

The separately selected [operator-email follow-up](operator-alert-emails.md) owns preserving provider rejection details and deriving alert impact from these routes. Keep the two plans aligned; model retirement alone does not fix misleading alert copy.

## Selected scope

1. Implement the approved model split above. Verify account availability, endpoint/schema compatibility, reasoning settings, structured output, tool support, cost and latency for each affected workload. Reuse existing managed evaluations while validating the direct BYOK request paths on each client.
2. Update Apple and Linux direct calls, defaults and explicit call sites. Cover live/incremental, final and saved-meeting insights, speaker naming, catch-up, Playbook topics/answers and template generation/filling wherever implemented. Keep investigations on their existing model unless a separately evidenced compatibility need is recorded.
3. Replace both backend paths that can select GPT-5 mini. Preserve independent lightweight/standard switches and incremental rollback precedence, with a supported rollback destination. Do not automatically expand normal managed Luna routing or add cross-model retries.
4. Update hourly health probes to cover supported active/fallback models without querying the retired model. Preserve access/quota/billing failure alerts and hourly cadence. Update cost accounting for new models while retaining old model prices and historical usage attribution.
5. Correct current Settings model descriptions and implementation/operator documentation across clients. Keep historical release notes, model evaluations and usage records intact. Update public model documentation when the implementation ships; this maintenance work does not add a public roadmap feature or reorder the product ideas.

## Acceptance and release evidence

- Verify the selected exact model IDs and reasoning/request configuration through real request builders and record comparison evidence. Use bounded synthetic fixtures, not customer transcripts. Validate factual fidelity, owners/dates, grounded answers/citations, ambiguous speaker naming and template schema compliance, plus measured latency and token cost. In particular, prevent inherited BYOK `low` defaults from overriding Luna's selected `none`.
- Test actual direct-request construction and response parsing on Apple and Linux, and the backend routing matrix with on/off/unset/blank/invalid settings. Verify no supported runtime path, rollback setting or scheduled probe selects either retiring ID. Retained historical/test-baseline references are not runtime dependencies.
- Preserve bounded retries/timeouts, saved-AI authority, account/credential fences, prompts and cadence unless a necessary compatibility change is explicitly documented and tested. Keep allowances, commercial pricing, audio engines and private-mode behavior unchanged.
- Run the affected backend checks and both Apple test bundles after test isolation is ready; run Linux checks and record its own client validation. Synthetic provider access checks do not establish content quality or physical-client QA.
- Ship and verify the backend migration and Apple 3.7.0, with Linux on its independent release line, before 2026-12-11. Record per-platform availability, actual provider model telemetry and the first scheduled health check using the replacement set. Do not infer iOS availability from submission.
- Document the upgrade path for older BYOK binaries: backend deployment cannot replace a model hardcoded into direct client calls. Include user-facing update guidance and decide any minimum-version policy explicitly; do not silently introduce a force-update gate. A supported rollback must not restore GPT-5 mini after shutdown.

## Boundaries and handoff

This is a retirement-driven compatibility migration, separate from the delivered [managed Luna rollout](lightweight-luna.md), the [recording follow-up](recording-reliability-followup.md) and later broad model-quality work. The model split is approved; production configuration, release and deployment remain unchanged; local implementation evidence follows. Backend AGENTS.md and Linux PLAN.md point here; update their current contracts alongside implementation rather than rewriting historical rollout evidence.

## Local implementation evidence, 2026-11-03

- Apple direct Chat Completions requests now explicitly send model-specific reasoning for every mode and helper. Responses investigations remain pinned quality/low. AppState and both Settings views use the approved split. The request tests exercise full/incremental task selection, helper output decoding, and a 404 model-access error with clear key-access guidance and exactly one request, without cross-model retry.
- Backend fallback/rollback routes now resolve to pinned GPT-5.4 mini. Both supported models are probed once with explicit reasoning; historical costs remain intact. Normal enabled-Luna routing is preserved.
- Linux uses the same task split and explicit reasoning through its actual chat body builder. Rust suite: 220 passed, 1 ignored live-enrollment case; frontend build passed. These are macOS-hosted checks, not Linux desktop/audio QA.
- Apple macOS full isolated suite passed at `Test-Miniti-2026.11.03_12-02-10-+0000.xcresult`. The generic iOS Simulator test build passed; the iPhone 16 Device panel discovery problem prevents claiming a replacement iOS execution pass. The earlier Duo run predates this migration.
- No live provider requests, model-account capability census, new cost/latency measurements or content-quality evaluation occurred here. Existing managed evaluations remain supporting evidence only. Those release validation limits, plus device checks and distribution, remain open. Older BYOK binaries still need an app update; no minimum-version gate was introduced.


Final local validation supersedes the earlier iOS discovery limitation above: the project runner executed the complete suite on iPhone 16/iOS 27.0. Both Apple bundles, backend types/lint/build/full tests and Linux Rust/frontend checks pass on the combined tree. Device-panel interaction remains unavailable, and no provider-account availability, price/latency or physical-recording result is inferred. Upcoming public model/update guidance is prepared in `../miniti-docs`, including no silent cross-model retry and the need to update older BYOK binaries. No public docs were pushed. Final evidence is in [3.7.0](../releases/3.7.0.md#combined-local-validation-2026-11-03).

Review correction (2026-11-03): direct Luna requests map OpenAI 404 `model_not_found`, or 400/403 naming Luna, to a plain-language model-access message. AppState presents it on both platforms; local diagnostics use fixed `model_access`, without automatic BYOK reporting or cross-model retries. Full Questions prompts now match the backend verbatim, including previous-summary context and baseline rules, checked against the additive shared review fixture. Linux parity is tracked in its PLAN.md. See the [review evidence](../releases/3.7.0.md#review-corrections-2026-11-03).
