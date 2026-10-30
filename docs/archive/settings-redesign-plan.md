# Searchable settings redesign

> Historical implementation/review record, archived 2026-10-27. It includes superseded proposals and dated statuses, not current instructions. Use [the roadmap](../roadmap.md) for priorities and [the disposition register](README.md) for the current owner of remaining work and contracts. Old “not built”, “uncommitted” and release gates below describe their original snapshot.

> **Shipped regression contract:** The searchable category registry and adaptive macOS, iPhone, and iPad navigation described here are implemented. Retain this document as the information-architecture and regression contract for future Settings changes.

**Current navigation (3.4.0 QA build):** Setup is General, Account, Cloud, Sending. Connections is Calendar, CRM (macOS), Webhooks, API, Playbook, Data. Meetings, Privacy and Support retain the baseline below. Cloud arrived in 3.0.0, API in 3.2.1; Sending describes outbound data and links to the owning setting. `SettingsDestination` in `AppState.swift` is authoritative for order, group and legacy identifiers.

## Goal

Make a growing settings surface easy to browse and search without changing the behavior, storage key, or default of any preference. macOS uses a fixed sidebar/detail settings window with no collapse affordance; iPhone retains push navigation; regular-width iPad uses a sidebar/detail layout.

## Information architecture

The shared registry (`SettingsDestination`, grouped by `SettingsGroup`) introduced the following baseline in 2.12.0. The current additions below extend it. One tab per question, single-word titles. Recording is hardware, Transcription is speech to text, AI is everything after the transcript, Privacy is the off switch, About is support.

Setup
1. General — startup, appearance, shortcuts
2. Account — your account (email, plan, support details), ways to sign in (email, recovery key, switch account), devices, then plan and billing, usage and your own keys (B6a, 3.4.0 build 139)

Meetings
3. Recording — microphone, system audio, permissions, auto-stop, iOS Live Activity
4. Transcription — language, models (Transcription and Speakers, each Deepgram or This Mac), dictionary, corrections, fillers
5. AI — speaker names (Off, GPT, Jev), the models in use, provider mode, investigations
6. Templates — built-in and your own, with Draft it
7. Notifications — coaching nudges, calendar reminders, meeting decisions

Connections
8. Calendar — Google Calendar, meeting filters, auto start and stop
9. CRM — Attio and Twenty (macOS)
10. Webhooks — endpoint and delivery queue
11. Playbook — docs server (was "Docs MCP")
12. Data — Granola import, markdown export

Privacy
13. Privacy — private mode (macOS), share diagnostics, models on this device

Support
14. About — version, acknowledgements, docs, changelog, support, legal, debug log

Before 2.12.0 the tabs were General, Account & Plan, Recording & Audio, Language, AI & Models, Templates, Notifications, Calendar & Meetings, CRM, Webhooks, Docs MCP, Data & Export, Privacy & Support. `fromLegacyID` maps every old raw value (`language`, `docsMCP`, `dataExport`, `privacySupport`, `about`, and the older `audio`, `apikeys`, `mcp`, `integrations`) onto the new tabs, so persisted selections and deep links keep working. Catalog ids follow their tab (`transcription.*`, `playbook.server`, `privacy.*`, `about.*`); the `integrations.*` ids stay for calendar, CRM and webhook rows. A registry test asserts both.

The destination is persisted as `selectedSettingsDestination`. Legacy destination IDs such as `audio`, `apikeys`, and `about` resolve to Recording, Account, and About respectively.

## Search contract

- `SettingsSearchCatalog` is the shared source of setting labels, synonyms, destination, section breadcrumb, platform availability, and BYOK availability.
- Search matches every whitespace-separated query term across the label, section, destination title/subtitle, and synonyms.
- Results show the exact setting plus a destination/section breadcrumb.
- Selecting a result changes destination and scrolls the detail form to the setting's stable ID.
- Scrolling honors Reduce Motion.
- Search never indexes stored values such as API keys, account email, webhook URLs, or device IDs.
- macOS exposes an in-sidebar search field and `Command-F`; iPhone uses the native inline settings search field; iPad uses sidebar search.

## Platform behavior

### macOS

- Replace the fixed 500x400 toolbar `TabView` with a resizable settings window whose 230pt sidebar is deliberately non-collapsible.
- Use grouped, neutral native sidebar rows and a grouped native `Form` detail. The fixed layout avoids the malformed/low-value sidebar-collapse toolbar affordance.
- Keep `Command-,`, the Settings menu destinations, in-app direct links, and last-destination restoration.
- Keep the Google OAuth callback listener on the settings root so it survives destination changes and browser round-trips.

### iPhone

- Retain a `NavigationStack` landing page and push details.
- Show every destination available on iOS when search is empty; omit the macOS-only CRM destination.
- Show individual setting results, not category-only matches, while searching.

### iPad

- Use `NavigationSplitView` at regular width.
- Keep the selected destination visible while searching and editing the detail.
- Wrap detail content in its own `NavigationStack` so filler and personal-dictionary drill-downs continue to work.

## Regression boundaries

- Do not rename or migrate any existing `AppStorage` preference key.
- BYOK API keys remain visible only in BYOK mode. Every other destination and control keeps the same availability in Managed and BYOK modes; CRM remains platform-gated to macOS rather than mode-gated.
- Smart meetings remains visible with or without a connected calendar.
- Calendar auto-start/stop, silence auto-stop, and notifications stay independent.
- Granola file import, markdown security-scoped folder selection, StoreKit purchase/restore, license restore, Docs MCP testing, CRM toggles, and debug-log access keep their existing actions.
- Native controls retain keyboard, VoiceOver, focus, disabled, and accessibility ownership.

## Verification

- Build and run both app targets.
- Run both shared XCTest bundles.
- On macOS, test `Command-,`, `Command-F`, every Settings menu destination, last-destination restoration, search synonyms, empty results, direct scrolling, and Google OAuth while changing destinations.
- On iPhone, search for `silence`, `smart`, `dictionary`, `api key`, `webhook`, and `diagnostics`; each result must push the right form and scroll to the control.
- On iPad, repeat with sidebar selection and rotate between compact and regular widths.
- Switch Managed/BYOK and confirm API-key results appear/disappear without losing stored keys.
- Exercise every write-capable settings action listed in the regression boundaries.


## 3.0.0: Cloud

Cloud is a tab in the Setup group, directly under Account (General, Account, Cloud), one question: do your meetings live on miniti's servers too. It was briefly a sixth group on 2026-10-15; Ian moved it into Setup on 2026-10-16 after using it, because the bottom of the sidebar was the wrong place for a setup choice. The settings tests pin only Privacy and Support.


## API tab (3.2.1)

`SettingsDestination.api` sits in the Connections group between Webhooks and Playbook on both platforms, visible to everyone. It is `CloudSettingsSections(mode: .api)`: an intro section that states what the API and MCP give you and the one thing missing (BYOK: needs the managed plan; free: Upgrade to Pro; Pro with cloud off: open Cloud; no email: add one in Cloud), then, for Pro with cloud on, Connected apps and Tokens and setup (`MCPSetupRows`). Connected apps and tokens moved here from the Cloud tab; web sign-in stays in Cloud. Search ids `api.setup`, `api.connected`, `api.tokens`; legacy ids `tokens`, `connectors`, `connected` map here.

## Approved follow-up, not implemented (2026-10-26)

Account UX (B6a) was built on 2026-10-27 for 3.4.0 build 139 as specified in [enrollment-identity-plan.md](enrollment-identity-plan.md) and planned in [account-sending-consent-ux-plan.md](account-sending-consent-ux-plan.md): optional verified email first, the full address, recovery key as backup, Switch account and billing restore separated, email on free accounts with cloud off. The search rows are `account.email` (Your account) and `account.recoveryKey` (Ways to sign in).

Sending U1 and first-run consent U2 are in [reliability-follow-up-plan.md](reliability-follow-up-plan.md). Sending becomes three concise groups with truthful state labels, one primary settings action per row and expandable details. Consent becomes a short disclosure with the action area outside the scroll body. These retain shared tokens, native actions and adaptive platform navigation. Completion requires rendered review at minimum Mac window sizes, compact iPhone/iPad and accessibility sizes, not just model tests. Existing 3.4.0 UI is not yet this design.
