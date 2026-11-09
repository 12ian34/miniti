# Design system consistency audit

Date: 2026-11-09. Source baseline: `bc112e3e`, after the 3.8.0 release documentation update. Scope: macOS and iOS, with adjacent Watch and Live Activity observations.

The design system has useful shared controls, tabs, cards, colour roles and layout contracts. Adoption is incomplete, and several shared primitives still allow callers to omit accessibility requirements. The largest opportunity is to share feature content between live and saved meetings and between platforms, while retaining native platform navigation and presentation.

This is a source audit, not a rendered screen or device certification. It covers the 29 files in the two app view folders, the palette, app roots, shared data-flow UI, extension surfaces, design documentation and relevant test coverage. Findings below distinguish source-confirmed differences from runtime checks. No app behaviour was changed by the audit.

Subsequent planning decision, 2026-11-09: Ian selected [UI consistency/accessibility](../plans/ui-consistency-and-accessibility.md) at [roadmap order 3d](../roadmap.md#design-system-audit-follow-through), after 3.8.0 and before account ownership. The plan's [D01–D21 register](../plans/ui-consistency-and-accessibility.md#audit-ownership-register) owns immediate scope, later feature ownership and explicit deferrals. Version is unassigned; this does not change release availability or turn these findings into implementation evidence.

## Existing foundations to keep

- Both app targets already compile `ColorPalette.swift` and `MinitiDesignSystem.swift`. Shared code does not have to live in the `Shared/` directory to be shared.
- `MinitiControlLabel` keeps native `Button` and `Menu` ownership. `MinitiTabLabel` and `MinitiTabStripSurface` centralise lowercase neutral tabs. `MinitiCardSurface` and `MinitiFadingDivider` offer reusable content chrome.
- The Coaching overview is shared across platforms and has a consistent metric taxonomy and layout tokens. Preserve its six independent chart scales and existing content hierarchy.
- Account, cloud, consent, folders, templates, voice settings, data-flow rows, Home setup and help already contain substantial shared UI. `DataFlowRowsView` is a useful pattern: common content with platform-specific navigation supplied by the caller.
- iPad navigation already adapts, and the app roots suppress SwiftUI animations under Reduce Motion. An unguarded `withAnimation` inside those roots is not, by itself, evidence of a shipped motion defect.
- The new Home utilities, documentation links and calendar disclosures explicitly size their hit areas. Preserve these recent improvements.

## Findings

Priority here is local audit triage: P1 affects readability or interaction, P2 is visible consistency or component ownership, P3 is smaller maintenance or copy debt. These are not release commitments.

### D01 P1 System text scaling stops at the attributed text bridge

The iOS selectable-text view sets `adjustsFontForContentSizeCategory = false`. Its attributed font builder creates `UIFont.systemFont(ofSize:)`; transcript callers pass sizes from `InterfaceScale`, with no system Dynamic Type scaling in that path. Increasing the app's scale can increase text, but increasing the system accessibility text size does not increase these attributed fonts. Ordinary semantic SwiftUI text elsewhere does grow, producing inconsistent reading sizes within the same app.

Evidence: [text bridge](../../Miniti/Views/SelectableTextView.swift#L416), [font builder](../../Miniti/Views/SelectableTextView.swift#L816), [transcript inputs](../../Miniti/Views/TranscriptView.swift#L146), [scale implementation](../../Miniti/Models/ColorPalette.swift#L24).

Enforce one resolved prose-metrics contract combining interface scale and system text size, consumed by both SwiftUI and attributed renderers. Keep transcript measurement, mutation and selection logic intact. Verify long live and saved text at accessibility sizes; do not just turn on automatic UIKit scaling and risk applying scale twice.

### D02 P1 Sales and template prose ignore interface scale on several surfaces

Live Mac Sales/templates use `interfaceScale.insightBodySize`, while saved Mac versions hardcode 12 points. Live and saved iOS Sales/templates hardcode 13 points, while the default iOS transcript/summary size is 15 and Large is 17. This directly breaks the documented equal reading-size contract. Notes are separately hardcoded to 12 on Mac and 14 on iOS; they need an explicit prose role too.

Evidence: [live Mac Sales/templates](../../Miniti/Views/MeetingView.swift#L2224), [saved Mac templates/Sales](../../Miniti/Views/MainWindow.swift#L2572), [live iOS Sales/templates](../../Miniti/Views/InsightsView.swift#L487), [saved iOS templates/Sales](../../MinitiMobile/Views/HistoryView_iOS.swift#L950), [saved Mac notes](../../Miniti/Views/MainWindow.swift#L2501), [iOS notes](../../MinitiMobile/Views/HistoryView_iOS.swift#L902).

Make `MEDDPICCBulletText` resolve the standard insight prose metrics itself, including line spacing. Share Sales/template content across live/history so a caller cannot silently select a smaller font. Preserve intentionally compact navigation typography.

### D03 P1 Shared controls do not guarantee platform hit sizes

`MinitiControlLabel` and `MinitiTabLabel` default to a fixed 30-point height on both platforms, despite the system defining a 44-point iOS minimum icon target. iOS live tabs override this to 44; the shared Coaching tabs do not. The investigation-suggestion CTA explicitly chooses 36. Metric-help buttons are an 11/12-point symbol plus two points of padding, and their close controls are 22 points. The generic disclosure style defaults its minimum height to nil; acknowledgements and data-flow disclosures use that default.

Evidence: [control defaults](../../Miniti/Views/MinitiDesignSystem.swift#L23), [Coaching tabs](../../Miniti/Views/InsightsView.swift#L2441), [iOS investigation CTA](../../MinitiMobile/Views/MeetingView_iOS.swift#L657), [metric help](../../Miniti/Views/InsightsView.swift#L1927), [saved help](../../MinitiMobile/Views/HistoryView_iOS.swift#L1226), [disclosure default](../../Miniti/Views/MinitiDesignSystem.swift#L383), [acknowledgements](../../Miniti/Views/AcknowledgementsView.swift#L44).

Separate visual height from interactive minimum size. Make platform-sized hit regions the default for shared tabs, compact controls, icon actions and disclosures. Retain the compact symbol inside a larger target. Validate resulting hit frames at runtime, particularly inside native Forms and toolbars.

### D04 P1 Meaningful text and actions use decorative or disabled contrast

Question context uses `#484F58` on the dark app surface. Its copy action uses `#52525B` on `#1C1C1F`. Live coaching uses the same very dim colour for metric explanations and units. These are useful text and available controls, rather than purely decorative separators. The menu-bar recording label uses small white text on the recording red. Calculated opaque-colour contrast is approximately 2.40:1 for the question context, 2.20:1 for the copy action, and 3.35:1 for the menu-bar label, below the project's 4.5:1 ordinary-text target. These are source-colour calculations, not screenshot measurements.

Evidence: [question card](../../Miniti/Views/InsightsView.swift#L817), [coaching explanation and units](../../Miniti/Views/InsightsView.swift#L670), [menu-bar recording label](../../Miniti/MinitiApp.swift#L673), [palette](../../Miniti/Models/ColorPalette.swift#L243).

Use readable semantic text tokens for explanations, metadata and actionable labels. Add foreground-on-accent tokens rather than assuming white works on every accent. Reserve disabled/decorative tokens for those actual roles.

The design document also incorrectly says placeholder text is exempt from WCAG contrast. W3C explicitly includes placeholder text in this criterion. Correct that statement when reconciling the design spec. See [W3C Contrast Minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).

### D05 P1 Saved iOS action items imply persistent completion but only change local view state

Saved iOS actions use `TerminalListItem(style: .checkbox)`. Clicking its `[ ]` button toggles a local `@State isCompleted`, strikes through the text and dims it. It does not write completion into the meeting. Live insights and saved Mac actions use non-interactive bullet/arrow presentations. The same action therefore appears to support task completion only on one surface, without a durable completion model or a descriptive checkbox accessibility contract.

Evidence: [saved iOS actions](../../MinitiMobile/Views/HistoryView_iOS.swift#L713), [local checkbox state](../../Miniti/Views/InsightsView.swift#L3731), [saved Mac actions](../../Miniti/Views/MainWindow.swift#L2235).

Choose a consistent product contract. A small correction would use the same non-interactive action-row component everywhere. Persistent task completion would need explicit feature scope, storage and sync ownership; it should not be introduced as a styling refactor.

### D06 P1 Dark appearance is not enforced consistently on macOS

The iOS root forces dark appearance. The Mac main window, Settings and Debug Log scene roots do not set a dark colour scheme, and the app source contains no global `NSAppearance` override. Some individual sheets do force dark. Custom palette backgrounds stay dark, but native `Form`, `List`, `.primary`, `.secondary` and system control surfaces can follow the OS appearance.

Evidence: [Mac scene roots](../../Miniti/MinitiApp.swift#L416), [Mac Settings root](../../Miniti/MinitiApp.swift#L531), [native Settings surfaces](../../Miniti/Views/SettingsView.swift#L30), [iOS root](../../MinitiMobile/MinitiApp_iOS.swift#L117), [folder sheet exception](../../Miniti/Views/MeetingFolderViews.swift#L112).

This is a confirmed source-enforcement gap; the precise visible outcome needs a launch with macOS set to Light. Add a consistent app-owned appearance boundary, while allowing system-owned menu-bar presentation to retain appropriate platform behaviour.

### D07 P2 Palette adoption remains incomplete

The two view folders contain 413 literal `Color(hex: "...")` calls across nine files. Several live feature paths still bypass the palette. This includes colours that already have precise semantic names. `PermissionStatusBadge` and `PermissionBadge_iOS` also use system `.green`/`.red` rather than status tokens.

Evidence: [live Mac insight colours](../../Miniti/Views/MeetingView.swift#L2153), [live iOS insight colours](../../Miniti/Views/InsightsView.swift#L436), [permission badges](../../Miniti/Views/SettingsView.swift#L1219), [iOS badge](../../MinitiMobile/Views/SettingsView_iOS.swift#L1640).

Migrate by role, not a global hex-to-accent substitution. A green speaker label, a success state and a start button should depend on different semantic contracts even when their current colours match. Keep `Theme` as a migration alias only where its meaning is unambiguous.

### D08 P2 Live and saved insight categories actually change colour

Live Sales arrays use `8B5CF6` for economic buyer and `6366F1` for competition; saved Sales uses the palette's `A78BFA` and `818CF8`. The old competition colour computes to approximately 4.45:1 on the app background, just below the design target. The live arrays bypass the palette's prior contrast corrections.

Standard insights also differ: saved Mac discussion uses yellow, while live and saved iOS use amber; saved Mac topics use `Accent.purple`, while live and saved iOS use the softer topics colour. Saved Mac summary and actions use `Theme`'s base blue/green rather than the GitHub blue/green used in live sections.

Evidence: [live Mac Sales array](../../Miniti/Views/MeetingView.swift#L2228), [live iOS Sales array](../../Miniti/Views/InsightsView.swift#L490), [canonical Sales colours](../../Miniti/Models/ColorPalette.swift#L333), [saved Mac standard insights](../../Miniti/Views/MainWindow.swift#L2201), [saved iOS standard insights](../../MinitiMobile/Views/HistoryView_iOS.swift#L690).

Introduce a shared section descriptor for title, semantic accent, ordering and value. Both live and saved data should render through it. Use named fields rather than single-letter Sales identifiers, which cannot distinguish both D fields or both C fields.

### D09 P2 Saved iPhone meeting tabs bypass the shared tab component

Live iPhone transcript/insights/notes tabs use the shared strip, 44-point labels, full-width hit surfaces and selected accessibility traits. Saved meeting tabs rebuild the strip with 12-point text, 8-point vertical padding, different selected fill, 4/6-point radii and no explicit selected trait. Both label sets are already lowercase; the difference is their component and interaction contract.

Evidence: [live tabs](../../MinitiMobile/Views/MeetingView_iOS.swift#L514), [saved tabs](../../MinitiMobile/Views/HistoryView_iOS.swift#L573).

Use one `MeetingSectionPicker` on both screens, backed by the improved tab primitives. Keep state ownership in the live or historical screen.

### D10 P2 Utility actions still define their own chrome and semantic colour

Update/regenerate controls, copy actions and sidebar toggles still hand-build their fonts, padding, borders and fills. Even callers of the new primitive can select inconsistent roles: the labelled Cloud/Local storage utility uses `.primary` blue, while ordinary utilities are documented as neutral. Smart-meeting End buttons can be amber or untinted, while the main Stop action uses the recording role. The iOS association action is green/prominent while its Mac equivalent is a neutral bordered button.

Evidence: [saved Mac update control](../../Miniti/Views/MainWindow.swift#L2136), [iOS update control](../../MinitiMobile/Views/MeetingView_iOS.swift#L563), [Cloud/Local utility](../../Miniti/Views/CloudSettingsView.swift#L524), [Mac smart-meeting actions](../../Miniti/Views/MeetingView.swift#L285), [iOS smart-meeting actions](../../MinitiMobile/Views/MeetingView_iOS.swift#L694).

Define action roles centrally, including the distinction between normal stop, destructive discard, affirmative start and neutral storage/configuration. Share button labels and status presentation, while preserving native confirmation and toolbar behaviour.

### D11 P2 The card and section system has competing implementations

Only three call sites use `MinitiCardSurface`, all inside `InsightsView.swift`. The same source folders contain 195 literal `cornerRadius:` arguments and 451 numeric-padding matches. These are inventory signals, not 646 independent defects: some geometry is intentionally feature-specific.

Insight section wrappers are a concrete duplication: `LiveInsightSection`, `DetailInsightBlock`, `InsightsPlainBlock_iOS`, `HistoricalDetailBlock_iOS` and `TerminalSection` separately define header type, accent bars, indent, spacing and surfaces. The Mac live header is bold, Mac saved is semibold, iOS headers are larger, and another variant draws a bordered markdown-style card. Platform density can differ, but those differences currently have separate owners.

Evidence: [live Mac section](../../Miniti/Views/MeetingView.swift#L2550), [saved Mac section](../../Miniti/Views/MainWindow.swift#L2531), [live iOS section](../../Miniti/Views/InsightsView.swift#L705), [saved iOS section](../../MinitiMobile/Views/HistoryView_iOS.swift#L1181), [terminal card](../../Miniti/Views/InsightsView.swift#L1861).

Create a shared insight-section layout with deliberate density/surface variants. Reuse card chrome for actual app-owned cards, without turning every plain text section or native Form into a card.

### D12 P2 Metric help has separate data, controls and modal implementations

Live help uses `TerminalSectionInfo` and its own iOS fullscreen overlay; saved iOS help duplicates these as `HistoricalMetricInfo_iOS` and another fullscreen overlay. New documentation help instead uses an adaptive popover/sheet with explicit accessibility labels, larger targets and scrollable explanation content. The older help surfaces use custom dimming backgrounds, rounded fonts, shadows, fixed-size close buttons and non-scrolling card bodies.

Evidence: [live metric help](../../Miniti/Views/InsightsView.swift#L1920), [saved metric help](../../MinitiMobile/Views/HistoryView_iOS.swift#L1220), [documentation help](../../Miniti/Views/MinitiDesignSystem.swift#L617).

Share a general help-content model and adaptive presentation, with specialised metric/documentation content. Use explicit labels and dismiss actions, keep actions visible, and allow long guidance to scroll at accessibility sizes. Preserve the Coaching overview's inline metric explanations rather than hiding those behind help again.

### D13 P2 Keyboard focus is opted out at many ordinary Mac controls

Numerous ordinary actions explicitly apply `.focusable(false)`, including investigation, catch-up, insight update, history rows and sidebar navigation. Some also have keyboard shortcuts; others depend on pointer use. This conflicts with the system's stated native-focus ownership and needs a full keyboard-navigation pass before claiming keyboard accessibility.

Evidence: [investigation](../../Miniti/Views/MeetingView.swift#L3439), [catch-up](../../Miniti/Views/MeetingView.swift#L3527), [saved insight update](../../Miniti/Views/MainWindow.swift#L2178), [sidebar item](../../Miniti/Views/MainWindow.swift#L1634), [copy action](../../Miniti/Views/InsightsView.swift#L872).

Treat non-focusability as an explicit exception for surfaces that must not steal focus, such as the floating recording panel. Review ordinary window controls individually. Verify focus order and visible focus at runtime; source alone does not establish every affected key-navigation outcome.

### D14 P2 iOS live insights have two vertical scroll owners

`MeetingView_iOS.liveInsightsContent` creates a vertical `ScrollView`, containing `InsightsView`, whose live iOS branch creates another vertical `ScrollView`. History owns its scroll layout separately. This makes toolbar/content movement, available-height calculation and gesture ownership harder to keep consistent.

Evidence: [outer scroll view](../../MinitiMobile/Views/MeetingView_iOS.swift#L543), [inner scroll view](../../Miniti/Views/InsightsView.swift#L373).

Make reusable insight content return content only. Let each screen own one vertical scroll container and pinned actions. Gesture or clipping symptoms need a device check; the nested ownership is source-confirmed.

### D15 P2 Mac insight rails have missed the shared sidebar-footer work

Home uses `MinitiSidebarToggleLabel` and shared Sidebar measurements. Live and saved meeting insight rails still own separate 26-point toggle buttons, shortcut hints, footer padding and divider treatments. Live uses a flat divider and a panel background; saved uses `GradientDivider` and the secondary background. Both duplicate toggle icon logic and opt out of focus.

Evidence: [shared toggle](../../Miniti/Views/MinitiDesignSystem.swift#L456), [live insight rail](../../Miniti/Views/MeetingView.swift#L1941), [saved insight rail](../../Miniti/Views/MainWindow.swift#L2369).

Reuse the sidebar toggle label and footer measurements across Home, live and saved rails. Keep each rail's content and collapse state with its feature owner.

### D16 P2 Banners and status displays repeat layout and presentation logic

Recording issues, smart-meeting prompts, investigation suggestions and post-meeting review each have separate Mac/iOS implementations. They repeat icons, title/detail spacing, tint choices, countdown wording and action selection. Post-meeting status copy already differs. Usage displays also repeat entitlement/loading/remaining-minutes presentation and colour policy, although some older variants appear to be preview-only.

Evidence: [Mac banners](../../Miniti/Views/MeetingView.swift#L142), [iOS banners](../../MinitiMobile/Views/MeetingView_iOS.swift#L621), [Mac review status](../../Miniti/Views/MeetingView.swift#L427), [iOS review status](../../MinitiMobile/Views/MeetingView_iOS.swift#L1235), [Mac managed status](../../Miniti/Views/MeetingView.swift#L3196), [iOS managed status](../../MinitiMobile/Views/MeetingView_iOS.swift#L1420).

Share a status-banner layout and feature-specific presentation data. Let width select an inline or stacked action area. Keep recording mutations in `AppState` and preserve platform-only capabilities. Share usage status computation and accessible wording even where the compact visual layout differs.

### D17 P2 Settings reuse is partial and leaves simple duplicate sections

Permission badges are effectively identical. Playbook MCP settings repeat URL validity, probe lifecycle and disclosure copy. Speaker-naming pickers repeat their choice model and bindings. Delivery status rows repeat error/retry/discard behaviour. The local speaker-model status uses a progress presentation on Mac and plain status text on iOS.

Evidence: [Mac Playbook section](../../Miniti/Views/SettingsView.swift#L1756), [iOS Playbook section](../../MinitiMobile/Views/SettingsView_iOS.swift#L1580), [Mac speaker names](../../Miniti/Views/SettingsView.swift#L2096), [iOS speaker names](../../MinitiMobile/Views/SettingsView_iOS.swift#L1713), [Mac delivery row](../../Miniti/Views/SettingsView.swift#L2167), [iOS delivery row](../../MinitiMobile/Views/SettingsView_iOS.swift#L1682), [Mac model progress](../../Miniti/Views/SettingsView.swift#L1973), [iOS model status](../../MinitiMobile/Views/SettingsView_iOS.swift#L1655).

Extract shared settings sections and small state presenters. Retain native Form/navigation wrappers, iOS URL keyboard configuration, Mac device pickers and purchase rails. Private mode is Mac-only (`AppState.privateModeAvailable`); the Mac-only speaker-picker lock is intentional capability-specific behaviour, not a current iOS privacy defect. A shared picker should retain that distinction.

### D18 P2 Live Activity palette copies have already become stale

The widget explicitly claims to mirror the main palette, but its primary text is `E6EDF3` rather than `FAFAFA`, background is `0B0B0D` rather than `09090B`, dim is `6E7681` rather than `A1A1AA`, muted is `C9D1D9` rather than `D4D4D8`, and disabled is `3F3F46` rather than `71717A`. The latter is used for the meaningful “tap to return to miniti” instruction. Watch maintains a third small palette.

Evidence: [Live Activity constants](../../MinitiLiveActivity/MinitiLiveActivityLiveActivity.swift#L5), [widget return instruction](../../MinitiLiveActivity/MinitiLiveActivityLiveActivity.swift#L48), [Watch palette](../../MinitiWatch/WatchPalette.swift), [canonical palette](../../Miniti/Models/ColorPalette.swift#L220).

Extract dependency-light colour tokens that can compile into all targets, or generate these small palettes from one source. A separate module does not prevent sharing a source file. Avoid pulling all of `ColorPalette.swift` into extensions unchanged: it currently also contains interface-scale UI and app-facing helpers. Document legitimate extension-specific colours as variants.

### D19 P2 Design documentation contradicts the current implementation and itself

The overview says “no gradients” and the elevation section rejects shadows/glow, while the same spec explicitly defines fading dividers and chart area fades. The implementation adds coloured hover shadows to Coaching examples and custom shadows to help/shortcut overlays. The YAML-style card-surface entry says surface-card, while `MinitiCardSurface.standard` uses `Background.tertiary`. Historical build notes remain appended alongside current contracts. The placeholder exception in D04 is also incorrect.

Evidence: [design spec](../../design.md), [card implementation](../../Miniti/Views/MinitiDesignSystem.swift#L162), [Coaching hover shadow](../../Miniti/Views/InsightsView.swift#L3098), [metric overlay shadow](../../Miniti/Views/InsightsView.swift#L2082), [shortcut overlay](../../Miniti/Views/MainWindow.swift#L2990).

Reconcile one current specification with explicit exceptions for functional fades, overlays and chart fills. Move dated iteration notes to release evidence. Decide whether hover glow is intended before changing it. Generate or validate the documented tokens against source instead of maintaining competing definitions.

### D20 P3 Copy and text-role policy are not fully centralised

Primary iOS navigation is `Record / Coaching / History`, while Mac uses Home and the design calls for lowercase product-authored tabs. The custom tab component enforces lowercase, but native app tab titles bypass it. Native Settings/toolbar labels use a mixture of title and sentence case. Mac post-meeting copy and General settings also retain capitalised `Miniti`, despite the lowercase product-name rule. Small text exceptions include 9-point CRM task metadata and the transcript correction shortcut, below the documented 10-point text minimum. Tiny SF Symbol sizes are a separate concern and should not be counted as text violations.

Evidence: [mobile navigation titles](../../MinitiMobile/Views/MainTabView.swift#L23), [navigation copy helper](../../Miniti/Views/MinitiDesignSystem.swift#L132), [post-meeting wording](../../Miniti/Views/MeetingView.swift#L481), [General copy](../../Miniti/Views/SettingsView.swift#L1255), [CRM metadata](../../Miniti/Views/MainWindow.swift#L3759), [correction shortcut](../../Miniti/Views/TranscriptView.swift#L524).

Define explicit copy roles for product navigation, compact actions, prose and system-standard actions. Settle Home versus Record and the scope of lowercase tabs once, then feed both shells from shared navigation descriptors. Use a small typography role set rather than copying numeric font sizes between features.

### D21 P3 Watch level animation lacks the app motion boundary

The Watch level meter adds `.animation(.linear(duration: 0.2), value: level)` without reading Reduce Motion, and the Watch root does not install the suppression modifier used by the phone and Mac. The live audio value itself can continue updating; the authored tween should be optional.

Evidence: [Watch meter](../../MinitiWatch/WatchViews.swift#L79), [Watch app root](../../MinitiWatch/MinitiWatchApp.swift#L7).

Use a small shared motion helper that can compile independently for Watch, or guard this animation locally. Verify Watch behaviour separately from the two app targets.

## Component reuse map

Names below are proposed responsibilities, not instructions to create a separate type for every row immediately.

| Shared responsibility | Existing pieces to consolidate | Platform responsibility to retain |
|---|---|---|
| Resolved text metrics | `InterfaceScale`, attributed font builder, fixed Sales/template/notes sizes | Mac/iOS base sizes and UIKit/AppKit text implementations |
| Compact control and icon-action contracts | `MinitiControlLabel`, hand-built copy/update controls, help close buttons | Native action ownership, toolbar presentation, focus and shortcuts |
| Meeting section picker | Live and historical iOS transcript/insights/notes strips | Screen-local selection state |
| Insight mode selector and specialist menu | `InsightsModeTabs`, `InsightsModeTabs_iOS`, already-shared `InsightTemplateMenu` | Settings-opening adapter and native menu sizing |
| Insight content sections | The five section wrappers, standard insight loops, Sales arrays, template content | One scroll owner and pane arrangement per screen |
| Coaching metric content and help | Live/saved Mac and live/saved iOS metric rows, filler details and help models | Optional presentation density, existing metric semantics |
| Status banners and usage presentation | Smart/recording/investigation/review banners, managed status variants | Applicable actions and inline versus stacked layout |
| Settings sections | Permission status, Playbook probe, speaker names, delivery state, local-model status | Native Form, navigation, keyboard and platform capabilities |
| Notes editor and section header | `NotesEditor`, `SavedNotesView`, iOS notes, `SectionHeader`, `InsightsSectionHeader`, `DetailSectionHeader` | Bindings, save timing, focus and text selection |
| Sidebar footer | `MinitiSidebarToggleLabel`, live/historical insight toggle labels and rails | Collapse state and feature-specific content |
| Catch-up and investigation result content | Mac popover bodies and iOS sheet bodies | Popover/sheet shell, available research scopes |
| Extension-safe visual tokens | Main palette, Live Activity constants, `WatchPalette` | Watch/Live Activity layouts and deliberate material variants |

For Coaching, reuse the existing `TrainingMetrics.speakerPresentations()` where its semantics match. Live iOS still manually merges “Others”; saved iOS and other paths use speaker presentations. Preserve grouped speaker details and resolved-self identity when extracting. This requires semantic regression checks as well as visual ones.

Before migrating a legacy component, check callers. For example, `UsageBanner` and `ManagedStatusView` currently have only preview references in the scanned app source. Delete or quarantine unused UI after verifying target and dynamic references, instead of investing in a replacement for an unreachable screen. The inventory counts include definitions and previews, not just rendered production surfaces.

## Enforce the design system at the correct boundary

1. **Strengthen primitives first.** Add platform hit-area defaults, resolved text metrics, named foreground-on-accent roles, and a reusable icon/copy action. `MinitiControlLabel` should remain a label or be paired with a style that preserves native button semantics; avoid a universal button that owns navigation or domain mutations.
2. **Share content before screens.** Consolidate section descriptors, metric presentation, status wording and settings sections. Keep `NavigationSplitView`, iPhone stacks, toolbars, sheets, purchase rails, permissions and capture controls platform-specific where required.
3. **Add a baseline-aware source check.** Reject new literal colour construction outside palette/token files and intentional export/assets code. Flag new duplicated card/control chrome, unreviewed `.focusable(false)` and undersized text as review items. Do not blanket-ban numeric dimensions, `.primary` in native system surfaces, or compact navigation fonts. Capture existing debt explicitly and ratchet it down by migrated surface.
4. **Test outcomes rather than token equality alone.** Existing `ColorPaletteTests` check values, roles and taxonomy. Add meaningful regressions for resolved text scaling, contrast role pairs, native target sizes and selected semantics. A test that only asserts a 30-point constant cannot detect the iOS Coaching tab problem.
5. **Keep a small component gallery and paired screen fixtures.** Exercise the same content on live/history and Mac/iOS, including disabled, loading, empty, error, selected and long-content states. Use the existing isolated UI harness. Check minimum Mac size, narrow iPhone, regular iPad, interface scales, accessibility sizes, Reduce Motion, VoiceOver and keyboard navigation. Validate custom controls in native containers as well as in isolation.
6. **Keep one current spec.** Document approved native/platform exceptions beside their shared component. Put release iteration history in release records. Changing code should update the same contract rather than appending another conflicting rule.

The selected [implementation sequence and ownership](../plans/ui-consistency-and-accessibility.md) now governs follow-through: immediate text/hit-area foundations and bounded insight parity at order 3d, then assigned account/integration/content work in existing plans. Extension tokens and other explicitly deferred items have no version commitment. User-visible changes will need the normal changelog and Linux tracking required by `AGENTS.md`; this documentation-only audit does not change a shared backend or feature contract.

## Coverage and evidence limits

The source inventory includes Home/setup/calendar, live recording, stopped review, history/detail/search/folders, standard/Sales/template/questions/Playbook/Coaching insights, transcript correction and speaker controls, Settings/account/cloud/integrations/privacy/help/models, onboarding/consent/recovery/update, the recording indicator, Watch and Live Activity. Shared account, consent and folder logic was not subjected to a new behavioural audit here.

Runtime checks remain necessary for actual control hit frames, keyboard/VoiceOver focus order, large-text clipping, light-system Mac appearance, nested-scroll gestures, and safe-area/keyboard presentation. No simulator/device run, visual snapshot comparison, build or test suite was performed for this documentation-only audit. Existing release test passes are not evidence that these design issues are absent.

Reproducible source counts, scoped only to `Miniti/Views/*.swift` and `MinitiMobile/Views/*.swift`: 29 files, 32,001 lines; 413 literal hex constructor calls; 812 `.font(.system(size:)` matches; 195 numeric `cornerRadius:` arguments; 451 numeric-padding matches; 33 `MinitiControlLabel` call sites; seven `MinitiTabLabel` call sites; three `MinitiCardSurface` call sites. Fixed fonts, custom geometry and platform differences are not automatically defects. Non-literal `Color(hex: field.color)` calls and raw hex strings inside descriptor arrays are additional to the literal-constructor count.

Literal constructor locations: `InsightsView.swift` 146; `MeetingView.swift` 128; `TranscriptView.swift` 44; `UsageBanner.swift` 34; `MainWindow.swift` 25; `HistoryView_iOS.swift` 16; `MeetingView_iOS.swift` 15; `LimitWarningBanner.swift` four; `SettingsView.swift` one. Review active callers before assigning migration effort.
