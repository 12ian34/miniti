# Measured provider costs and prompt-cache effectiveness

Status: scoped future work, not implemented; version unassigned. Reconciled 2026-10-27. Priority is in [the roadmap](../roadmap.md). This is a bounded deliverable, not an ongoing maintenance programme. Confirm design and release scope before implementation.

## Scope

Original P0.1 phase 5 and P1.6: capture cached/input tokens, model, mode, prompt version, strategy and latency; build a dated managed-tier unit-economics model using actual usage, multichannel transcription, reconnects, payments/taxes, storage and infrastructure. Do not change prices or allowances in this plan.

## Dependencies and privacy

Use the logging plan’s trustworthy delivery/coverage rules where client signals are needed; authoritative provider/accounting records stay separate from diagnostics. Current pinned model routing comes from the backend, not old research. Never log prompts/transcripts. Historical financial scenarios in monetization are not current decision evidence.

## Implementation, acceptance and rollback

Produce free, typical Pro and heavy Pro cohorts, worst-case exposure and margin inputs. Establish cache baseline before changing prompt prefixes or partition keys. Caching is already automatic; do not invent an “enable caching” task. Any experiment must measure cost, cached-token share, latency and output-quality fixtures and record a keep/reject decision. A correct baseline with rejected optimizations is a complete result. Cover both managed model families and request modes. Update monitoring budgets deliberately from measured evidence. Revert prompt changes independently while retaining bounded accounting telemetry.


## Release contract

Record before/after evidence and run the affected backend checks and both Apple bundles for shared client changes. Update current reference docs and the per-platform release record. Preserve existing data and compatible old clients. Shared backend changes require Linux tracking. No deployment is authorized by this document. Close the whole stated scope when shipped; unrelated discoveries become separate roadmap items.
