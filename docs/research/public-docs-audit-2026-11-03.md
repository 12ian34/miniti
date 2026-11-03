# Public documentation audit, 2026-11-03

Local corrections only. No push, deployment, app release, external listing edit or customer data access.

## Scope and baseline

Read all 48 Mintlify MDX pages (47 navigation entries plus the landing page), `docs.json`, public Apple/Linux READMEs, and duplicated website product/LLM copy. Compared current guidance against Apple `v3.6.0`, Linux `v0.7.1`, current backend contracts and the release evidence. Local 3.7.0 behavior remains explicitly upcoming. This does not reclassify the implementation as released or close physical/provider/App Store metadata gates.

Public-docs baseline: `17a09a49ff42d2acec117b9de8330601b07087a6`. Backend reference: `f7f5b7e798e6242152f152e76598484adb233cb4`; local-only retirement paths are distinguished from production Luna activation. Linux reference: `017a57581ab283d8b270115621189f3b86d743fa`, with the released `v0.7.1` boundary preserved.

## Material corrections

- Minutes are account-wide. Polar Pro covers all platforms on the account; App Store Pro covers iPhone/iPad. Free Playbook lookups remain per device and count completed retrieval/grounding even without a matching answer.
- BYOK bypasses miniti for provider requests, but configured integrations and version checks still use the backend. Switching modes does not delete the managed account. Local transcription needs no Deepgram key.
- Raw debug logs can contain titles, names, paths and provider details. Help uses a separate sanitized timeline. Removed the instruction to share raw logs without reviewing/redacting them.
- Removed first-sentence voice-recognition and infallible AI-grounding promises. Clarified local labels can travel in enabled AI/cloud/export flows, and guest fingerprint deletion preserves the self fingerprint.
- Corrected obsolete Settings paths, template menus, webhook retry instructions, API setup and example fields. Webhook 3.6.0 is released; 3.7.0 remains upcoming.
- Linux is an independent release, with no released Apple cloud/local-model/private-mode/custom-template-editor parity. Corrected the tarball icon-directory prerequisite and removed the inaccessible widget repository link.
- Granola now documents transcript exports for eligible notes. Updated comparison, import guide, schema and website LLM copy from primary sources.
- Apple and Linux READMEs no longer make blanket no-network or full-parity claims. Apple README uses the actual Xcode 27.1 toolchain and Testing configuration.
- Embedded walkthrough videos remain earlier recordings and are labelled accordingly; no video or screenshot was fabricated or recaptured.

## Evidence key

- **B**: backend `lib/usage.ts` (`sponsorEligible`, account usage, docs lookup counters), `app/api/insights/route.ts` lookup admission/metering; Apple `ClientAuth.swift`, account/Cloud Settings and `docs/reference/accounts.md`.
- **C**: Apple `InsightsService.swift` training calculations, `DeepgramService.swift` language/filler lists, `CoachingAdvisor`/overview; 3.6.0 metric calculations also read at the released tag.
- **D**: `DebugLogger.swift`, Help/support report sanitizer, `docs/reference/settings.md`, backend support/diagnostic contracts.
- **E**: `WebhookService.swift`, `DeliveryOutbox.swift`, `Meeting.swift` markdown output, Attio/Twenty send paths and backend integration contracts; 3.6.0 sync/delivery plan.
- **H**: history/search/import services and `docs/reference/meeting-history-and-import.md`.
- **I**: `InsightsService.swift`, `InsightTemplates.swift`, `CustomInsightTemplates.swift`, AppState AI/catch-up/investigation paths, backend `lib/insights.ts` and route; deployed model evidence in `docs/releases/3.6.0.md`.
- **L**: `DeepgramService.swift`, on-device transcription/diarization services, `VoicePrints.swift` (10 s match/20 s learning), `VoicePrintSettingsView.swift`, `AppState+VoicePrints.swift`, local-model reference and transcription POC.
- **R**: `AppState.swift`, capture services, `DeepgramService.swift`, call lifecycle policies; recording/audio references. Hardware behavior remains subject to existing validation limitations.
- **S**: `AppState+CloudSync.swift`, Cloud/API settings, backend `lib/apiTokens.ts`, `lib/meetingApi.ts`, `lib/mcpServer.ts`, public v1 routes and cloud contract.
- **U**: `SettingsView.swift`, `MeetingView.swift`, mobile navigation/onboarding, `KeyboardShortcutsService.swift`, project deployment targets and Fastfile.
- **W**: `docs/reference/watch.md`, Watch queue/import/receipt/permission contracts and prerecorded API metering.
- **X**: Linux README, AGENTS, released changelog, Rust/frontend capability searches and package files. `file build/macos/miniti.app/Contents/MacOS/miniti` confirms the existing Mac distribution contains both x86_64 and arm64; Intel support was retained.
- **V**: primary vendor documentation listed below, fetched 2026-11-03. A page responding successfully does not prove a signed-in workflow works end to end.

## Page register

| Page | Disposition | Review focus / evidence |
|---|---|---|
| [coaching/delivery](../../../miniti-docs/coaching/delivery.mdx) | Corrected | C: session-average pace versus active speech; limits of clarity metric |
| [coaching/filler-words](../../../miniti-docs/coaching/filler-words.mdx) | Corrected | C: all 11 lists, normalization, local ASR spellings; no audio playback promise |
| [coaching/tracking-progress](../../../miniti-docs/coaching/tracking-progress.mdx) | Corrected | C/E: coaching export section and snake_case webhook fields |
| [compare/granola](../../../miniti-docs/compare/granola.mdx) | Corrected | V: current pricing, platforms, transcript exports and training controls |
| [features/ai-insights](../../../miniti-docs/features/ai-insights.mdx) | Reviewed, retained | I: production managed routing versus released BYOK and upcoming retirement |
| [features/apple-watch](../../../miniti-docs/features/apple-watch.mdx) | Reviewed, retained | W: transfer receipts, permission, audio retention, quota and background limits |
| [features/auto-start-stop](../../../miniti-docs/features/auto-start-stop.mdx) | Reviewed, retained | R: silence choices, calendar gating and foreground/background differences |
| [features/cloud-sync](../../../miniti-docs/features/cloud-sync.mdx) | Corrected | S/B: supported clients, entitlement coverage, BYOK state and sync timing |
| [features/docs-insights](../../../miniti-docs/features/docs-insights.mdx) | Reviewed, retained | I: lookup behavior and retrieved-source grounding |
| [features/granola-import](../../../miniti-docs/features/granola-import.mdx) | Corrected | H/V: current Data path and changed Granola export contents |
| [features/insight-templates](../../../miniti-docs/features/insight-templates.mdx) | Corrected | I/E: limits, flat More menu, Linux scope, valid JSON example |
| [features/investigations](../../../miniti-docs/features/investigations.mdx) | Corrected | I: bounded code excerpts and explicit requests; Linux scope |
| [features/markdown-export](../../../miniti-docs/features/markdown-export.mdx) | Corrected | E: Data destination and current export contents |
| [features/meddpicc-playbook](../../../miniti-docs/features/meddpicc-playbook.mdx) | Corrected | I/E: sales context, CRM platform scope, model fallibility; historical video note |
| [features/meeting-history](../../../miniti-docs/features/meeting-history.mdx) | Corrected | H/E: search and trimming; Linux CRM scope |
| [features/questions-mode](../../../miniti-docs/features/questions-mode.mdx) | Reviewed, retained | I/R: question types, opt-in prompts and two-minute cooldown |
| [features/realtime-nudges](../../../miniti-docs/features/realtime-nudges.mdx) | Corrected | C/R: inclusive eight-fillers threshold and consent/delivery paths |
| [features/smart-meetings](../../../miniti-docs/features/smart-meetings.mdx) | Corrected | R: call/quiet/calendar boundaries; corrected filter anchor |
| [features/speaker-names](../../../miniti-docs/features/speaker-names.mdx) | Corrected | L/I: names, local processing versus exported labels, upcoming failure handling |
| [features/speech-coaching](../../../miniti-docs/features/speech-coaching.mdx) | Corrected | C/R: overview, metrics and inclusive filler threshold; historical video note |
| [features/transcription](../../../miniti-docs/features/transcription.mdx) | Corrected | L/R: settings, dictionary, channel identity, local options, upcoming Stop behavior |
| [features/voices](../../../miniti-docs/features/voices.mdx) | Corrected | L: 10-second matching floor, guest versus self deletion, no first-sentence promise |
| [features/zoned-out](../../../miniti-docs/features/zoned-out.mdx) | Corrected | I/U: Catch me up label, bounded requests, no grounding guarantee |
| [get-started/choose-a-mode](../../../miniti-docs/get-started/choose-a-mode.mdx) | Corrected | B/U: account-wide minutes and local-transcription BYOK exception |
| [get-started/first-meeting](../../../miniti-docs/get-started/first-meeting.mdx) | Corrected | R/U: neutral mic identities and Linux system capture |
| [get-started/install](../../../miniti-docs/get-started/install.mdx) | Reviewed, retained | U/X: OS floors, universal Mac artifact, Linux packages and first microphone check |
| [get-started/introduction](../../../miniti-docs/get-started/introduction.mdx) | Corrected | B/L/S: Linux availability and complete data-flow boundaries |
| [get-started/permissions](../../../miniti-docs/get-started/permissions.mdx) | Corrected | R/U: microphone check, background interruptions and selected folders |
| [index](../../../miniti-docs/index.mdx) | Corrected | B/E/U: platform/feature coverage, schema and historical video note |
| [integrations/attio](../../../miniti-docs/integrations/attio.mdx) | Corrected | E/V: CRM settings, desktop availability and moved listing URL |
| [integrations/docs-mcp](../../../miniti-docs/integrations/docs-mcp.mdx) | Corrected | I/U: Playbook settings and grounding limitations |
| [integrations/google-calendar](../../../miniti-docs/integrations/google-calendar.mdx) | Corrected | R/E: Calendar settings, call-gated start and Linux scope |
| [integrations/twenty](../../../miniti-docs/integrations/twenty.mdx) | Corrected | E/U: CRM settings and desktop availability |
| [integrations/webhook-recipes](../../../miniti-docs/integrations/webhook-recipes.mdx) | Corrected | E/V: released 3.6.0, n8n body wrapper, Worker env binding, receiver outlines |
| [integrations/webhooks](../../../miniti-docs/integrations/webhooks.mdx) | Corrected | E: finalization, optional processing, immutable retries and finite delivery window |
| [platforms/ios](../../../miniti-docs/platforms/ios.mdx) | Corrected | R/W/U: capture, interruptions, settings and desktop-only capabilities |
| [platforms/linux](../../../miniti-docs/platforms/linux.mdx) | Corrected | X/B: released capability gaps, BYOK traffic, credentials, install directory and missing widget link |
| [platforms/macos](../../../miniti-docs/platforms/macos.mdx) | Corrected | U/X: universal distribution, actual settings and desktop feature scope |
| [pricing/byok](../../../miniti-docs/pricing/byok.mdx) | Corrected | B/I/L: local keys, provider billing and remaining integration traffic |
| [pricing/tiers](../../../miniti-docs/pricing/tiers.mdx) | Corrected | B: purchase-platform sponsorship, classifier exception and BYOK account state |
| [pricing/what-counts-as-a-minute](../../../miniti-docs/pricing/what-counts-as-a-minute.mdx) | Corrected | B/W: live versus Watch metering; per-device lookup accounting including no-match |
| [reference/account-and-recovery-key](../../../miniti-docs/reference/account-and-recovery-key.mdx) | Corrected | B/U: email recovery, platform coverage, sign-out limits, mailbox security |
| [reference/api-and-mcp](../../../miniti-docs/reference/api-and-mcp.mdx) | Corrected | S/V: routes/tools, API settings, current ChatGPT setup and Codex auth capability |
| [reference/debug-log](../../../miniti-docs/reference/debug-log.mdx) | Corrected | D: raw messages versus sanitized Help and opt-in telemetry |
| [reference/faq](../../../miniti-docs/reference/faq.mdx) | Corrected | B/D/S/L: all visible answers reconciled; 32 matching schema entries |
| [reference/keyboard-shortcuts](../../../miniti-docs/reference/keyboard-shortcuts.mdx) | Corrected | U: KeyboardShortcutsService; Catch me up label |
| [reference/languages](../../../miniti-docs/reference/languages.mdx) | Corrected | L/I: 11 Deepgram languages, smaller local set and model boundaries |
| [reference/troubleshooting](../../../miniti-docs/reference/troubleshooting.mdx) | Corrected | R/E/D: webhook retries/timeouts, consent and support guidance |

`docs.json`: all 47 navigation pages and local branding assets resolve. Landing-page/FAQ/comparison structured data is valid JSON. `AGENTS.md` in each changed repo is reconciled with these findings.

## External sources and unresolved public surfaces

Primary checks: [Granola pricing](https://www.granola.ai/pricing), [Granola export](https://docs.granola.ai/help-center/sharing/exporting-notes), [Granola training controls](https://docs.granola.ai/help-center/consent-security-privacy/model-training), [ChatGPT custom MCP](https://developers.openai.com/api/docs/guides/custom-mcp-server), [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli), [Claude Code MCP](https://code.claude.com/docs/en/mcp), [n8n webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/), [Workers secrets](https://developers.cloudflare.com/workers/configuration/secrets/).

- The old `attio.com/apps/miniti-app` returned 404. The [current listing](https://attio.com/apps/miniti) responds, but its external copy incorrectly promises full transcript exports and calls clarity a score. Corrected local links; did not edit/publish the external listing. Proposed replacement for its integration paragraph: “send a saved meeting to an attio person or company as a note containing its summary, notes, action items, decisions, topics and available sales or template sections. optionally create selected action items as tasks. full transcripts and coaching metrics are not sent.” Proposed coaching wording: “local metrics track detected fillers, pace, talk ratio, longest monologue, questions and average words per turn.”
- `github.com/12ian34/miniti-omarchy` returned public 404. Removed its public install recommendation; retained the working CLI/bar instructions. No repository visibility change was attempted.
- `platform.openai.com/api-keys` returns 403 to the anonymous automated fetch. Retained the correct signed-in key-management destination; did not claim an authenticated check.
- Published miniti docs and website still contain their previous copy until an authorized deployment. This audit prepares local changes only. Authenticated SaaS setup, recording hardware, historical video content and screenshot recapture were not exercised by this documentation pass.

## Validation

- `cd ../miniti-docs && python3 scripts/check-docs.py`: PASS, 48 pages, 47 nav entries, 239 internal page/anchor links, 6 JSON examples and 3 structured-data blocks. Includes exact parity for all 32 FAQ answers, asset existence, front matter and no MDX em dashes.
- `PATH=/opt/homebrew/opt/node@22/bin:$PATH mint validate --telemetry false`: PASS.
- `PATH=/opt/homebrew/opt/node@22/bin:$PATH mint broken-links --telemetry false`: PASS.
- `python3 /tmp/miniti-docs-example-check.py`: PASS, nine shell/JavaScript/Python examples parsed without running installation or network actions.
- `python3 /tmp/miniti-docs-external-links.py`: 28 distinct linked external page/image/video URLs, 27 HTTP 200, one authenticated OpenAI 403 as recorded above. Results saved locally at `/tmp/miniti-docs-external-links.json`.
- Website homepage JSON-LD parsed successfully; checked moved Attio URL and corrected free-plan copy. Static HTML/copy only, no application build required.
- `git diff --check`: PASS in every changed repository.

No app/backend code changed in this pass, so Apple/backend suites were not rerun. Their completed 3.7.0 results remain in the release record. No hardware tests, live OAuth approvals, sends or paid model calls were performed.

## Local commits

- Public docs: `e02c32663cf0aa44b29a3c6f41f4b180234033e5` (42 corrected MDX pages, agent context and validator).
- Linux public README/context: `2eb923de30df248d59b35cd856ebf1bfa3eb9760`.
- Website copy/context: `33298c31815847e21b440eccb670d3180375daa9`.
- Apple README/context, this register and the release evidence are in the local audit commit following `b5691b0`.
