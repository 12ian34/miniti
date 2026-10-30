# Historical plan disposition

Reconciled 2026-10-27. This register preserves where old material went; it does not set priority. [Roadmap](../roadmap.md) is the only execution-order document. Archives contain historical instructions, rejected alternatives and dated statuses. Current reference docs and bounded plans take precedence. No implementation or deployment happened during this cleanup.

## Old documents and their destinations

| Original document | Disposition and current owner |
|---|---|
| [roadmap.md snapshot](roadmap-through-3.4.0.md) | Replaced by short roadmap. Full evidence retained; old platform/subscription rules and delivery states are not current policy. Item mapping below. |
| [enrollment-identity-plan.md](enrollment-identity-plan.md) | A1–A2e/B6a delivered. Remaining A2f/A3/A4/B6b/B6c → account-access plan; B0–B3 → account-ownership; B4 → meeting-ownership; B5 → integration-ownership; B6d → purchase-return. B7 parity/admin follows each owner. A5 observations/waiver → releases and validation register. Current auth → reference/accounts. |
| [reliability-follow-up-plan.md](reliability-follow-up-plan.md) | R1, narrowed R2, R3 and auth fixes delivered. R4–R8 → reliability plan. Wider R2 deferred candidate. U1/U2 duplicates retired in favor of Settings reference. |
| [account-sending-consent-ux-plan.md](account-sending-consent-ux-plan.md) | Delivered implementation/review history. Current contract → reference/settings and accounts. QA evidence remains releases/3.4.0. |
| [ops-alerting-plan.md](ops-alerting-plan.md) | Deployed behavior → runbooks/operations; O1–O4 → logging-and-monitoring plan. Config/deployment observations remain dated history. |
| [admin-stats-access-plan.md](admin-stats-access-plan.md) | Delivered script/token and deployment history → operations runbook. Bot/rotation verification → validation register. Admin MCP is an unselected idea, not required work. |
| [cloud-sync-plan.md](cloud-sync-plan.md) | Shipped protocol → reference/cloud-sync plus backend 08-cloud. C1 → selective-cloud-privacy plan. APNs/web History/write scopes/etc → roadmap candidates. No claim all old open questions remain unsettled. |
| [test-quality-and-coverage-plan.md](test-quality-and-coverage-plan.md) | Dated audit retained; split by ownership in table below. Counts and mutation experiments describe the audited commit, not a new run. |
| [p0-hardening-batch-2026-09-plan.md](p0-hardening-batch-2026-09-plan.md) | Shipped 2.9.0 record: admin auth, store recovery, persistence, test seams and templates. Extracted conventions remain patterns/testing; Mac drill was completed. |
| [join-links-speaker-clones-inline-corrections-plan.md](join-links-speaker-clones-inline-corrections-plan.md) | Shipped 2.7.0; source/Join/correction gotchas → reference/recording-lifecycle. Old uncommitted/release instructions are superseded. |
| [meeting-search-plan.md](meeting-search-plan.md) | Shipped query behavior → reference/meeting-history-and-import. Manual check unrecorded; scaling → performance plan. Previously undiscoverable from doc index. |
| [calendar-auto-start-waits-for-call-plan.md](calendar-auto-start-waits-for-call-plan.md) | Shipped call-wait behavior → reference/recording-lifecycle. Manual late/no-show check unrecorded. Previously undiscoverable from doc index. |
| [settings-redesign-plan.md](settings-redesign-plan.md) | Shipped hierarchy/navigation → reference/settings. Its “not implemented” U1/U2/B6a follow-up is superseded by 3.4.0. |
| [smart-meetings-plan.md](smart-meetings-plan.md) | Shipped original contract; later call-lifecycle policy takes precedence. Durable transition/save/notification rules → reference/recording-lifecycle. |
| [call-lifecycle-and-recording-presence-plan.md](call-lifecycle-and-recording-presence-plan.md) | Shipped lifecycle/presence; current reference links detailed regression matrices. Original spikes/estimates are historical. |
| [automatic-in-room-diarization-plan.md](automatic-in-room-diarization-plan.md) | Shipped source/identity contract. Its “deferred local diarization/voice prints” subsequently shipped; other deferred ideas remain candidates only. |
| [apple-watch-plan.md](apple-watch-plan.md) | Shipped 3.1.0; capture/receipt rules → reference/watch. Physical validation unrecorded; retry bug R4 → reliability. |
| [voice-prints-plan.md](voice-prints-plan.md) | Shipped 3.2.0; thresholds/privacy/evaluation remain evidence; reference/local-models owns current behavior. T13 evaluation remains candidate work. |
| [on-device-diarization-plan.md](on-device-diarization-plan.md) | Shipped optional 2.10.0. Clock/coverage fixes and notices preserved. Default-on/complete hardware validation are separate unresolved choices. |
| [local-transcription-plan.md](local-transcription-plan.md) | Shipped optional Mac 2.12.0. Current language/fallback rules → reference/local-models. Phone feasibility, pinning/CDN and default-on remain candidates. |
| [jev-system-one-plan.md](jev-system-one-plan.md) | Naming/nudge slice shipped 2.10.0. Current rules → reference/local-models; calibration/other uses remain candidates. Old “no integration/not deployed/no naming” statements are superseded. |
| [granola-import-plan.md](granola-import-plan.md) | Apple work shipped 3.4.0. Format/estimate/ZIP gotchas → reference/meeting-history-and-import; manual checks and Linux parity remain separate. |
| [docs-insights-api-spec.md](docs-insights-api-spec.md) | Historical client-to-backend handoff. Backend owns current contract. Acceptance reconciliation → validation register, not a new implementation request for already-present routes. |
| release-3-4-0-qa.md | Moved to [releases/3.4.0.md](../releases/3.4.0.md); no unchecked device result changed to passed. |
| architecture/audio/ui-states/monetization/distribution/patterns/testing | Moved to reference with links rebased and known current-state contradictions corrected. Historical coverage/financial figures remain explicitly dated. The relocated financial model remains private and gitignored, with no public link. |
| local-ai-research/local-transcription-research/jev-eval-report | Moved to research; measurements are dated and not release commitments. The Jev report remains local/gitignored as before; it is not a required tracked dependency. |
| structural-simplification-audit-2026-08-16 | Moved to research; immutable audit evidence, revalidate findings before adoption. |
| ANDROID_PLAN.md | Moved to research/android-original-plan.md with explicit warning: shared-secret design, lockstep versions and ordinary update banners are obsolete. Requires a new plan before implementation. |

## Original roadmap item mapping

| Old ID | Disposition |
|---|---|
| P0.1 admin/auth | Admin separation and installation protocol shipped; production enforcement, long-tail direct migration, token/HMAC rotation overlap and broad legacy-key retirement require explicit verification before a separately scoped change. Current accounts/backend references and validation register own this check. |
| P0.1 phase 2 | backend-registration-and-registry plan; no UUID-only admission exemption. |
| P0.1 phase 3 | account-ownership B2 owns atomic finalization; preserve missing-session/cap/retry cases, do not implement a competing ledger. |
| P0.1 phase 4 ownership/admin | account-access, account-ownership, meeting-ownership, integration-ownership, with Linux/admin requirements per slice. Old automatic linking/cross-rail rules superseded. |
| P0.1 phase 5 | usage-cost-and-cache plan. Deepgram reconnect verification remains recording/monitoring regression, not a new refresh feature. |
| P0.2/P0.3 | Shipped store recovery/persistence policy; remaining evidence in validation register. |
| P0.4 | durable-checkpoints plan. |
| P0.5/P0.6 | CI/seams/smoke/coverage delivered; missing infrastructure/CI checks → test-foundation, feature regressions → owning plans. |
| P0.7/P1.1/P1.5 | history-and-session-performance plan. Existing search grammar remains shipped. |
| P0.8 | Filler overlap fixed; sidecar experiment remains unselected candidate. |
| P0.9/P1.2 | HTTPS/redaction and persisted outbox shipped; R5/R6 → reliability. Connectivity-aware retry remains a follow-up candidate, not implied delivered. |
| P0.10 | This docs cleanup; unresolved evidence/Android re-plan retained explicitly. |
| P0.11 | Shipped R1/narrow R2/R3/U1/U2/B6a/audio/auth; remaining R4–R8 → reliability; broader R2 deferred. |
| P0.12 | Test mapping below; no giant all-tests release commitment. |
| P1.3 | Short-interjection/UtteranceEnd measured experiment remains candidate. |
| P1.4 | A1 telemetry shipped; retention/schema/delivery/alert work → logging-and-monitoring. |
| P1.4a | Enrollment split as above; all unresolved D decisions remain open in their owner. D1 release scope and D8 optional-email availability are settled. |
| P1.6 | usage-cost-and-cache plan; historical financial model must not set limits/prices. |
| P1.7 | Unused limit screen removed, no pending work. |
| P1.8 | backend-runtime and redis-client, separate plans. |
| P1.9 | selective-cloud-privacy plan. |
| P2.1/P2.6/P2.7/P2.8 | Templates, join/corrections, calendar filters and cloud shipped; optional expansions and Linux parity stay explicit. |
| P2.3/P2.4/P2.5 | CRM fields/workflows, actionable entities and localization remain candidates; existing task previews/notes not re-planned. |
| P3.1 | Local transcription/speakers/private mode shipped optional; local insights/phone/default-on evaluation remain candidates. |
| P3.2/P3.3/P3.4 | Android needs re-plan; Linux exists and owns its own tracker; Windows requires demand/spike. |
| P3.5/P3.6 | Jev first slice and Watch shipped; calibration/Watch validation and R4 remain explicit. |
| Limitations/guardrails | Preserved in current reference, AGENTS, release runbooks and this snapshot. No code/runtime/Redis migration bundled with money/auth; historical managed shared-key and Whisper statements are not current architecture. |

## Test audit disposition

| Original slices | Current owner / remaining scope |
|---|---|
| T01/T06/T07/T14 | test-foundation: honest runner/isolation, insights handler coverage, real storage, cross-client fixtures. |
| T02/T04/T05 | account-ownership: exact/concurrent usage and Apple/Polar purchase/entitlement lifecycle. Implement before its cutovers. |
| T03/T10 | reliability R4–R6: real sender payloads, outbox races and complete Watch retry/import lifecycle. |
| T08 | Shipped R1/narrow R2/R3 and credential regressions retained; R7/R8 tests in reliability; ownership races in their plans. Wider R2 remains deferred. |
| T09 | Shipped audio/auth boundaries retained; monitor handshake tests in logging; lifecycle/handoff/resource tests in checkpoints/performance. |
| T11 | Disk reload/abrupt exit in durable-checkpoints; broader migration/recovery journey improvements are candidates pending scope. |
| T12 | Each UI change owns required render/interaction/accessibility checks. Broader UI harness is candidate work; no test-count proxy for rendered QA. |
| T13 | Local-model/voice-print quality/privacy candidate; preserve existing tests and corpus limits. |
| T15 | history-and-session-performance. |
| T16 | Diagnostics ingestion → logging; delivery integration → reliability; remaining CRM partial-failure tests are candidates. |
| T17 | test-foundation removes brittle checks only after replacements; current coverage remains dated evidence until remeasured. |

All old source text remains in this archive or research, with relative links repaired. Archiving means “not current instructions”, not “every checkbox passed”.
