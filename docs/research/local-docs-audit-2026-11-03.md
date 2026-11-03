# Local documentation audit, 2026-11-03

Reconciled current guidance in the Apple repository against the local 3.7.0 source, Fastlane/CI configuration and recorded 3.5.0/3.6.0 delivery evidence. This follows the [public documentation audit](public-docs-audit-2026-11-03.md). Changes are documentation only; no app/backend behavior, version/build, release notes, downloads or production state changed.

## Scope and disposition

| Surface | Check and result |
|---|---|
| `AGENTS.md`, Cursor/Copilot entry points | Corrected tracked-doc availability, local foundation status, Linux feature-parity claims and historical rollout wording. Current instructions lead to the roadmap and isolated test setup. |
| `docs/roadmap.md` | Removed stale recovery/AI implementation-pending text and old iOS latest-version language. Kept the full selected 3.7.0 package and the next-release speaker-restoration assignment. Default-on still waits for M1 evidence, without a release assignment. |
| All 24 `docs/plans/` status/ownership records | Reconciled delivered 3.5.0/3.6.0 status and the six selected 3.7.0 owners. Marked initial two-second ASR settlement and pre-migration routes as superseded checkpoints. Later account/Watch/link/ownership/performance work stays planned. The 3.6.0 Luna plan identifies its historical fallback IDs and points to the new retirement contract. |
| All 16 tracked `docs/reference/` pages | Corrected current auth, model loading/routing, speaker failure, local/private usage, voice-print deletion, cloud eligibility, webhook timing/retry, Settings/Help, test isolation and distribution guidance. Preserved measured historical limitations and separate physical-device gates. |
| Both `docs/runbooks/` pages | Corrected availability, diagnostics retention/deduplication, monitoring deployment and user-reported UptimeRobot setup. Added current 3.7.0 validation and local two-model probe guidance without claiming deployment. |
| `RELEASE.md`, `fastlane/RUNBOOK.md` | Added current 3.7.0 prerequisites, preserved completed rollout history via links, corrected Testing/iPhone 16 defaults, GitHub asset hosting and independent platform availability. Old disabled-Luna rollout steps must not be repeated. |
| `design.md`, screenshot and generated Fastlane guides | Corrected the contradictory monospaced-navigation instruction. Screenshot Debug isolation limits remain separate from XCTest; generated lane inventory and dated POC records are not rewritten as new validation. |
| Five tracked Cursor skills | Corrected obsolete release/version/target guidance, added Watch/Testing boundaries, preserved semantic color/identity rules and unreleased-versus-published changelog handling. Their frontmatter validates. No release workflow was executed. |
| Archive disposition index and release evidence | Updated current owner/status mappings in the archive index. Historical plans, old changelog entries and measured release/POC results remain dated history. Added this audit to 3.7.0 evidence rather than rewriting prior test results. |

## Source checks

The relevant implementation boundaries were checked in `AppState.swift`, `OnDeviceDiarizationService.swift`, `DeepgramService.swift`, `TestRunSetup.swift`, `TestSupport.swift`, `WebhookService.swift`, the cloud/delivery references, `ColorPalette.swift`, `fastlane/Fastfile` and `.github/workflows/tests.yml`. The public-doc audit supplies the same-day account, privacy, voice and platform findings. Release records supply deployment and availability evidence; source defaults alone do not establish production configuration.

Notable corrections include removal of the architecture map's obsolete shared-secret auth description, its `goHome`/detached-webhook description and its claim that every local speaker failure restores Deepgram. Distribution no longer directs new large DMGs into Netlify Blobs or describes removed Home update banners. Hosted test instructions no longer ask for access to the personal Keychain or rely on restoring live preferences.

## Validation and limits

- `python3 scripts/check-doc-links.py`: current local Markdown file links resolve.
- `python3 /tmp/check-miniti-current-doc-anchors.py`: current-doc section links, including available sibling targets, resolve. Legacy heading aliases were retained where headings changed.
- `python3 scripts/check-release-metadata.py`: local version/build metadata agrees; no published availability check or metadata mutation.
- Skill creator `quick_validate.py` for the five changed `.cursor/skills/` directories: passed using `uv run --with pyyaml python`; the system Python first lacked PyYAML. The temporary dependency stayed in uv's environment, with no project dependency change.
- `git diff --check`: passed. Changes are restricted to documentation and agent guidance.

The exact final check counts and documentation commit are recorded in [3.7.0](../releases/3.7.0.md#local-documentation-reconciliation-2026-11-03). Full app/backend suites were not repeated for these documentation-only changes; the review-correction results remain the latest code validation.

This audit does not turn research estimates, old hardware observations or incomplete QA into current guarantees. Physical/provider checks, internal App Store metadata correction, remote CI, packaging and rollout remain open. The live public docs/site and external Attio listing still require their separately authorized publication corrections. Nothing was pushed, deployed, submitted or released.
