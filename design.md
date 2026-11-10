---
version: alpha
name: miniti
description: Terminal-inspired, dark-mode-only design system for the miniti macOS + iOS meeting assistant. Legible Apple system typography, near-black surfaces, and GitHub-accent status colors.
colors:
  primary: "#22C55E"
  on-primary: "#09090B"
  primary-container: "#3FB950"
  on-primary-container: "#09090B"

  secondary: "#3B82F6"
  on-secondary: "#09090B"
  secondary-container: "#58A6FF"
  on-secondary-container: "#09090B"

  tertiary: "#A855F7"
  on-tertiary: "#09090B"
  tertiary-container: "#A371F7"
  on-tertiary-container: "#09090B"

  background: "#09090B"
  on-background: "#FAFAFA"
  surface: "#0C0C0E"
  on-surface: "#FAFAFA"
  surface-panel: "#0F0F11"
  surface-tertiary: "#111113"
  surface-card: "#18181B"

  border: "#1C1C1F"
  border-light: "#27272A"
  border-subtle: "#30363D"
  border-hover: "#3F3F46"

  text-primary: "#FAFAFA"
  text-secondary: "#E6EDF3"
  text-muted: "#D4D4D8"
  text-dim: "#A1A1AA"
  text-meta: "#8B949E"
  text-disabled: "#71717A"
  text-placeholder: "#A1A1AA"
  text-subtle: "#484F58"

  success: "#3FB950"
  error: "#F85149"
  warning: "#F59E0B"
  info: "#58A6FF"
  recording: "#F85149"
  limit-reached: "#F85149"
  no-api-key: "#F59E0B"

  speaker-you: "#3FB950"
  speaker-1: "#58A6FF"
  speaker-2: "#A371F7"
  speaker-3: "#D29922"
  speaker-4: "#F778BA"
  speaker-5: "#79C0FF"
  speaker-6: "#FFA657"
  speaker-7: "#7EE787"

  meddpicc-metrics: "#3B82F6"
  meddpicc-economic-buyer: "#A78BFA"
  meddpicc-decision-criteria: "#EC4899"
  meddpicc-decision-process: "#F59E0B"
  meddpicc-paper-process: "#F97316"
  meddpicc-identified-pain: "#EF4444"
  meddpicc-champion: "#22C55E"
  meddpicc-competition: "#818CF8"

  insight-summary: "#58A6FF"
  insight-discussion: "#F59E0B"
  insight-actions: "#3FB950"
  insight-topics: "#A371F7"
  insight-meddpicc: "#F59E0B"

  coaching-fillers: "#E3B341"
  coaching-pace: "#79C0FF"
  coaching-clarity: "#BC8CFF"
  coaching-questions: "#FF9B71"
  coaching-talk-ratio: "#39C5CF"
  coaching-monologue: "#F778BA"

colorRoles:
  principle: "Control chrome communicates action and state; category color belongs inside content."
  controls:
    primary-navigation: "{colors.info}"
    secondary-utility: "neutral surfaces and text"
    start-resume-success: "{colors.success}"
    stop-discard-error: "{colors.error}"
    warning: "{colors.warning}"
  content:
    summary: "{colors.insight-summary}"
    questions: "{colors.tertiary-container}"
    coaching-metrics: "{colors.coaching-*}"
    sales: "{colors.meddpicc-decision-criteria}"
    playbook: "{colors.insight-topics}"
  rules:
    - "Tabs and ordinary utility buttons are neutral, including when selected."
    - "Product-authored tab labels are always lowercase; MinitiTabLabel owns this transformation."
    - "Do not pass arbitrary feature colors into controls; use MinitiControlRole."
    - "Use ContentAccent only for section headers, charts, transcript markers, and insight content."
    - "Within Coaching, each metric keeps its named coaching color everywhere; metric colors never double as CTA or trend-status tokens."

typography:
  display:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "56px"
    fontWeight: "700"
    lineHeight: "1.05"
    letterSpacing: "-0.01em"
  heading:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "20px"
    fontWeight: "700"
    lineHeight: "1.2"
    letterSpacing: "0em"
  subheading:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "15px"
    fontWeight: "700"
    lineHeight: "1.3"
    letterSpacing: "0em"
  body:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "13px"
    fontWeight: "400"
    lineHeight: "1.5"
    letterSpacing: "0em"
  body-emphasis:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "13px"
    fontWeight: "600"
    lineHeight: "1.5"
    letterSpacing: "0em"
  label:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "11px"
    fontWeight: "500"
    lineHeight: "1.3"
    letterSpacing: "0em"
  caption:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "10px"
    fontWeight: "500"
    lineHeight: "1.3"
    letterSpacing: "0em"
  micro:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "10px"
    fontWeight: "500"
    lineHeight: "1.2"
    letterSpacing: "0.02em"
  tagline:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12px"
    fontWeight: "500"
    lineHeight: "1.3"
    letterSpacing: "0.04em"

rounded:
  none: "0px"
  xs: "2px"
  sm: "4px"
  md: "6px"
  lg: "8px"
  xl: "12px"
  xxl: "16px"
  pill: "999px"

spacing:
  "0": "0px"
  "1": "2px"
  "2": "4px"
  "3": "6px"
  "4": "8px"
  "5": "10px"
  "6": "12px"
  "7": "14px"
  "8": "16px"
  "10": "24px"
  "12": "32px"

components:
  app-shell:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"

  sidebar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-dim}"
    typography: "{typography.label}"
    padding: "8px"

  panel:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "12px"

  card:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.lg}"
    padding: "12px"

  card-surface:
    implementation: "MinitiCardSurface"
    variants: "standard, inset, accented"
    rounded: "{rounded.lg}"
    padding: "12px"
    sizing: "content-driven by default; explicit height only for components whose contract requires it"
    note: "Use for Miniti-owned cards so fill, border, radius, and content padding remain consistent."

  fading-divider:
    implementation: "MinitiFadingDivider"
    color: "content accent into border-light, fading to transparent"
    height: "1px"
    note: "Use between related content headings and body copy when a full bordered surface would add unnecessary chrome."

  tab-strip:
    implementation: "MinitiTabLabel + MinitiTabStripSurface"
    backgroundColor: "{colors.background}"
    selectedBackgroundColor: "{colors.surface-card}"
    selectedTextColor: "{colors.text-primary}"
    unselectedTextColor: "{colors.text-muted}"
    rounded: "{rounded.lg}"
    note: "Use neutral contrast—not category color—for mutually exclusive views. Labels render lowercase through NavigationCopy."

  compact-control:
    implementation: "MinitiControlLabel + MinitiControlRole"
    roles: "primary, secondary, positive, recording, destructive, warning"
    rounded: "{rounded.md}"
    note: "Native Button and Menu own interaction semantics. Compact chrome keeps its visual height; the label reserves at least the platform minimum target in normal layout."

  terminal-header:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-muted}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "6px"

  button-primary:
    backgroundColor: "{colors.info}"
    textColor: "{colors.on-secondary}"
    typography: "{typography.body-emphasis}"
    rounded: "{rounded.lg}"
    padding: "14px"
  button-primary-hover:
    backgroundColor: "{colors.secondary}"
    textColor: "{colors.on-secondary}"
  button-primary-disabled:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-dim}"

  button-secondary:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-primary}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "7px"
  button-secondary-hover:
    backgroundColor: "{colors.border-light}"
    textColor: "{colors.text-primary}"

  button-positive:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.success}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "7px"

  button-recording:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.recording}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "7px"

  button-destructive:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.error}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "7px"
  button-destructive-hover:
    backgroundColor: "{colors.error}"
    textColor: "{colors.on-primary}"

  button-ghost:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text-dim}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "6px"
  button-ghost-hover:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-primary}"

  input-field:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "8px"

  pill-tag:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-dim}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"

  pill-status-recording:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.recording}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"

  pill-status-pro:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.tertiary-container}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"

  insight-section-header:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text-dim}"
    typography: "{typography.label}"
    padding: "6px"

  transcript-row-you:
    backgroundColor: "{colors.background}"
    textColor: "{colors.speaker-you}"
    typography: "{typography.body}"
    padding: "6px"

  transcript-row-remote:
    backgroundColor: "{colors.background}"
    textColor: "{colors.speaker-1}"
    typography: "{typography.body}"
    padding: "6px"

  waveform-bar:
    backgroundColor: "{colors.speaker-you}"
    rounded: "{rounded.xs}"
    width: "2px"

  update-banner:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.info}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "10px"

  limit-banner:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.warning}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "10px"

  meddpicc-metric:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.meddpicc-metrics}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "8px"
  meddpicc-economic-buyer:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.meddpicc-economic-buyer}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "8px"
  meddpicc-decision-criteria:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.meddpicc-decision-criteria}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "8px"
  meddpicc-decision-process:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.meddpicc-decision-process}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "8px"
  meddpicc-paper-process:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.meddpicc-paper-process}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "8px"
  meddpicc-identified-pain:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.meddpicc-identified-pain}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "8px"
  meddpicc-champion:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.meddpicc-champion}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "8px"
  meddpicc-competition:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.meddpicc-competition}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "8px"

  speaker-chip-you:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.speaker-you}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"
  speaker-chip-1:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.speaker-1}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"
  speaker-chip-2:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.speaker-2}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"
  speaker-chip-3:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.speaker-3}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"
  speaker-chip-4:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.speaker-4}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"
  speaker-chip-5:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.speaker-5}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"
  speaker-chip-6:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.speaker-6}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"
  speaker-chip-7:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.speaker-7}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"

  insight-summary:
    backgroundColor: "{colors.background}"
    textColor: "{colors.insight-summary}"
    typography: "{typography.label}"
    padding: "6px"
  insight-discussion:
    backgroundColor: "{colors.background}"
    textColor: "{colors.insight-discussion}"
    typography: "{typography.label}"
    padding: "6px"
  insight-actions:
    backgroundColor: "{colors.background}"
    textColor: "{colors.insight-actions}"
    typography: "{typography.label}"
    padding: "6px"
  insight-topics:
    backgroundColor: "{colors.background}"
    textColor: "{colors.insight-topics}"
    typography: "{typography.label}"
    padding: "6px"
  insight-meddpicc:
    backgroundColor: "{colors.background}"
    textColor: "{colors.insight-meddpicc}"
    typography: "{typography.label}"
    padding: "6px"

  dot-recording:
    backgroundColor: "{colors.recording}"
    rounded: "{rounded.pill}"
    width: "6px"
    height: "6px"
  dot-connected:
    backgroundColor: "{colors.success}"
    rounded: "{rounded.pill}"
    width: "6px"
    height: "6px"
  dot-disconnected:
    backgroundColor: "{colors.text-disabled}"
    rounded: "{rounded.pill}"
    width: "6px"
    height: "6px"

  surface-root:
    backgroundColor: "{colors.background}"
    textColor: "{colors.on-background}"
    typography: "{typography.body}"

  surface-elevated:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body}"

  card-nested:
    backgroundColor: "{colors.surface-tertiary}"
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.md}"
    padding: "8px"

  link-inline:
    backgroundColor: "{colors.background}"
    textColor: "{colors.secondary}"
    typography: "{typography.body}"
  link-inline-hover:
    textColor: "{colors.secondary-container}"
  link-inline-pressed:
    backgroundColor: "{colors.secondary}"
    textColor: "{colors.on-secondary}"
  link-inline-focus:
    backgroundColor: "{colors.secondary-container}"
    textColor: "{colors.on-secondary-container}"

  button-pro-cta:
    backgroundColor: "{colors.tertiary}"
    textColor: "{colors.on-tertiary}"
    typography: "{typography.body-emphasis}"
    rounded: "{rounded.lg}"
    padding: "14px"
  button-pro-cta-pressed:
    backgroundColor: "{colors.tertiary-container}"
    textColor: "{colors.on-tertiary-container}"

  waveform-bar-system:
    backgroundColor: "{colors.secondary-container}"
    rounded: "{rounded.xs}"
    width: "2px"

  divider:
    backgroundColor: "{colors.border}"
    height: "1px"
  divider-subtle:
    backgroundColor: "{colors.border-subtle}"
    height: "1px"

  input-field-hover:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "8px"
  input-field-placeholder:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-dim}"
    typography: "{typography.body}"
    padding: "8px"
  input-field-focused:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "8px"
  input-field-outline:
    backgroundColor: "{colors.border-hover}"
    height: "1px"
  input-field-empty:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-placeholder}"
    typography: "{typography.caption}"
    padding: "8px"

  text-helper:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text-meta}"
    typography: "{typography.caption}"

  text-secondary-body:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text-secondary}"
    typography: "{typography.body}"

  text-empty-state:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text-dim}"
    typography: "{typography.caption}"

  text-divider-label:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text-subtle}"
    typography: "{typography.micro}"

  button-secondary-focused:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-primary}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "7px"

  pill-status-limit-reached:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.limit-reached}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"

  pill-status-no-api-key:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.no-api-key}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "4px"
---

## Overview

miniti is a macOS + iOS meeting assistant. The visual language is intentionally utilitarian: near-black surfaces, highly legible system text, and a small palette of saturated accents that carry semantic weight (recording, connected, action items, MEDDPICC letters, speaker identity). The design keeps its terminal-inspired restraint without sacrificing long-form readability — minimal chrome, no gradients, and no ornamental motion. Current-system material is allowed only on small functional utility surfaces where it improves platform fit without weakening contrast.

The system is **dark-mode only**. iOS forces `.preferredColorScheme(.dark)` app-wide. On Mac, the main, Settings and Debug Log scene roots explicitly prefer dark appearance, so native window controls agree with the dark palette under a Light ambient appearance. Do not force `NSApp.appearance` in production: system-owned menu-bar presentation retains its environment. Light-mode support is explicitly out of scope, so every token is tuned for legibility on a near-black background.

Core principles:

- **Information density over whitespace.** Compact 10–13px system text and small pill tags keep the transcript and insights panel scannable during a live call.
- **Color carries meaning, not decoration.** Green = you/success, red = recording/error, amber = warning/discussion, blue = info/summary, purple = pro/topics. MEDDPICC letters each have a fixed hue.
- **Readability first.** Headings, body copy, labels, and controls use the Apple system font. Only changing numerical readouts use monospaced digits to prevent layout jitter.
- **Motion is optional.** App-authored transitions, pulsing indicators, and scrolling animations stop when Reduce Motion is enabled; state and status must remain understandable without movement.
- **Adapt by platform and space.** macOS windows resize and remember pane choices, iPhone retains bottom tabs, and regular-width iPad uses sidebar navigation. Do not stretch an iPhone layout across iPad.
- **Shape is quiet.** Radii cap at 16px (used only for popup cards). Buttons and inputs use 6–8px. Pills use the radius scale's `pill` token.

## Colors

The palette is derived from `Miniti/Models/ColorPalette.swift` and is the single source of truth for every surface, button, and accent in the app.

**Surfaces** form a tight dark-neutral stack from `background` (`#09090B`, the app shell) up through `surface`, `surface-panel`, `surface-tertiary`, and `surface-card` (`#18181B`, the most elevated card). Steps between surfaces are intentionally small (2–9 points of luminance) to avoid harsh banding on OLED iPhones and to preserve the terminal feel.

**Text** uses a seven-stop ramp from `text-primary` (`#FAFAFA`, near-white) down to `text-subtle` (`#484F58`). Body copy is `text-primary`; helper/meta copy is `text-dim` or `text-meta`; disabled states use `text-disabled`. `text-primary` on `background` clears roughly 19:1, well above WCAG AAA.

**Accents** are GitHub-style saturated hues chosen so every accent also clears WCAG AA against `background`. `primary` is green (`#22C55E`) because the app's identity color doubles as the "you" / success signal. `secondary` blue and `tertiary` purple cover informational and premium surfaces respectively.

**Status** tokens are semantic aliases, not new hues — `recording` and `limit-reached` both resolve to the same GitHub red (`#F85149`); `connected` and `success` both resolve to GitHub green (`#3FB950`). Never hardcode a status hue; always reference the semantic token so a future palette swap stays atomic.

**Speakers** cycle through eight hues (`speaker-you` plus `speaker-1…7`). `speaker-you` is pinned to green so the user's own voice is instantly recognizable in the transcript; remote speakers cycle by index. These are the only tokens that may be selected programmatically (by speaker ID modulo 7).

**MEDDPICC** assigns each letter a fixed hue so the same field reads as the same color in the insights panel, history view, and markdown export. Keep the mapping consistent across platforms — if you need to retune a hue, update `ColorPalette.MEDDPICC` (the source of truth) and mirror it in the `meddpicc-*` tokens here.

**Insight sections** (`insight-summary`, `insight-discussion`, `insight-actions`, `insight-topics`, `insight-meddpicc`) alias back to accents so every section header in the live insights panel has a stable, predictable color cue.

**Coaching metrics** use a separate six-color taxonomy owned by `ColorPalette.Coaching`: fillers gold, pace periwinkle, clarity lavender, questions warm coral, talk ratio cyan, and longest monologue rose. The mapping is identical in live coaching, saved meeting detail, trend sections, history charts, and overview tables. These hues are content labels only and deliberately differ from primary, positive, recording, warning, and trend-status tokens. “You” remains green as speaker identity; question-frequency content never reuses that green.

**Meaningful text contrast.** Explanations, metadata, available actions and empty-field hints use the ordinary-text target of at least 4.5:1 on their actual surface. Placeholder text is meaningful guidance and is not exempt. `text-placeholder` aliases readable `text-dim` (`#A1A1AA`); question context and coaching units use `text-meta`, while copy actions and coaching column headings use `text-dim`. The Mac recording/ending capsule pairs `OnAccent.recording` (near black) with the solid recording red instead of assuming white is readable on every accent.

`text-subtle` (`#484F58`) remains for purely decorative separators which duplicate information available elsewhere. It must not carry unique information, available actions or placeholder guidance. These role-pair checks do not certify all legacy surfaces; remaining legacy literals are tracked by UI3 and their feature owners.

## Typography

Miniti uses the platform's Apple system font for prose, controls, and primary Home / Coaching / History navigation. Its open forms, proportional spacing, native hinting, and accessibility behavior make transcripts and AI insights easier to read at deliberately compact sizes. The `miniti` wordmark retains the original monospaced identity; recording timers and other changing numerical readouts use monospaced digits.

Settings offers three discrete interface scales. At normal system text size, **Compact** preserves the 13-point transcript/insight baseline, **Standard** uses 14 points on Mac and 15 on iOS, and **Large** uses 15 on Mac and 17 on iOS. `ReadingMetrics` resolves Mac prose from InterfaceScale only. iPhone/iPad prose also uses the original system Dynamic Type category and the UIKit body scaling curve, without an accessibility-size cap. System categories below Large intentionally reduce iOS prose below its normal-size baseline; Compact preserves its baseline at the normal system category, rather than imposing a minimum on a smaller user preference. SwiftUI fixed-point fonts and native attributed text consume these final sizes once; attributed text keeps automatic UIKit scaling off. The root `minitiInterfaceScale` modifier preserves that original category separately from semantic controls, which retain their existing one-step Standard/two-step Large adjustment. The shared minitiSheet wrapper forwards the presenting view’s resolved Dynamic Type category through a native Bool sheet; MainTabView uses it for Settings and consent, ThirdPartyAIConsentRow uses it for the separate Settings Privacy presentation, and iOS History filters/Settings Debug Log use it for their Bool sheets. The presented content inherits the separate reading/InterfaceScale values and must not apply the root scaling modifier again. At iOS accessibility categories, the compact Settings list stacks each symbol above its title/subtitle, and the Interface scale control stacks the heading/value and the three captions. Normal iOS and Mac slider layouts keep their horizontal arrangement. Preserve native navigation and slider semantics. Notes preserve their Compact baseline of 12 points on Mac and 14 on iOS, add the same InterfaceScale point increase as transcript prose, then use the same platform scaling rule. Sales/templates resolve their own shared insight metrics. This is not a blanket view transform; the compact insight selector keeps lowercase summary / questions / coaching visible while Sales / Templates / Playbook live in its More menu.

The Coaching overview is a reading-heavy exception to the app's compact desktop chrome: `MinitiDesignSystem.CoachingTypography` adds two points to its fixed macOS type roles while leaving iPhone sizes unchanged. A neutral lowercase `focus` / `stats` / `history` tab strip separates personalized guidance and trends, aggregate comparisons across all six Coaching metrics, and the sortable meeting table. Each segment occupies exactly one third of the strip, including its selection surface and hit target. `MinitiDesignSystem.CoachingLayout` keeps the strip at a 480px compact-column maximum and gives both the stats table and trend sections a 720px maximum on desktop; all become fluid on narrower iPhone/iPad layouts. The stats metric column is deliberately wide enough to keep every metric and unit—including `longest monologue words`—on one line. Each row then uses the remaining width for a visible plain-language explanation beneath the comparisons; stats do not hide this copy behind info icons. Charts do not interrupt those rows: the complete comparison table is followed directly by one card per metric, each using its established content colour, a low-opacity area fade, quiet dashed grid lines, a ringed latest point, and its own value domain. Horizontal positions are categorical meeting-sequence indices, so every meeting receives equal spacing regardless of calendar gaps; unavailable metric values retain their position rather than compressing time. Every chart shows numeric y-axis labels. Its x-axis uses plain numeric ticks below a centred `meeting` label, labels every meeting in very small histories, and selects roughly five to six rounded meeting intervals as histories grow. VoiceOver receives each chart's latest value, date, unit, and eligible meeting count; empty talk-ratio history uses a neutral placeholder instead of inventing data. Comparison arrows use status green/red/neutral only after metric meaning is considered: directional measures use their established better direction, range-based measures use movement toward or away from the broad coaching range, and unavailable or inconclusive comparisons remain neutral. Trend sections sit directly on the page while nested evidence surfaces remain content-sized, without filler gaps or prose truncation. Clickable source examples use an accent wash/border hover state rather than a disclosure chevron; their label and quote remain tightly grouped at left while the right-aligned meeting title appears above a locale-formatted date with no time.

- **Transcript, macOS:** Compact 13px / 2px leading; Standard 14px / 4px; Large 15px / 5px.
- **Transcript, iOS:** Compact 13px / 2px leading; Standard 15px / 5px; Large 17px / 6px.
- **Insight body, macOS:** matches transcript — Compact 13px; Standard 14px; Large 15px.
- **Insight body, iOS:** matches transcript — Compact 13px; Standard 15px; Large 17px.

The supporting scale remains narrow and dense:

- **display (56px/700, monospaced)** — the branded lockup on onboarding and terms; the in-app home lockup uses the same family at its platform layout size.
- **heading (20px/700)** — stopped-session headers, settings section titles.
- **subheading (15px/700)** — onboarding card titles, panel titles.
- **body (13px/400)** — transcript rows, notes, MEDDPICC bullets, insights body copy.
- **body-emphasis (13px/600)** — primary CTA labels, active tab.
- **label (11px/500)** — buttons, tabs, terminal headers, pill text.
- **caption (10px/500)** — chip metadata, keyboard-shortcut hints, speaker chips.
- **micro (10px/500)** — insight-mode tab descriptors, dense status overlays; 10px is the minimum text size.
- **tagline (12px/500, +0.04em)** — the "multi-dimensional meetings" home tagline.

Non-transcript line heights remain compact (1.2–1.5) for information density. Transcript leading is explicitly shared by the live and saved attributed-text renderers so their wrapping and visual rhythm cannot drift. Letter spacing is near-zero, with a small positive tracking on tagline and micro to keep uppercase-ish fragments legible.

## Layout

Spacing uses an even-step scale (`"1"` = 2px through `"12"` = 32px). The 2px base matches the 2px waveform bar width and the 2px inset on small pills. `"3"` (6px) and `"4"` (8px) are the most common — they drive nearly all pill, chip, and terminal-header padding. `"6"` (12px) is the default card / panel padding. `"10"` (24px) separates major home-screen stacks.

Containers follow the same small-step rhythm:

- The meeting view splits horizontally into a transcript + notes column and an insights rail. Both use `surface-panel` for the background and `border` for the 1px divider.
- On macOS, the sidebar collapses to a compact icon rail via `⌘[`; the right pane collapses via `⌘]` (calendar on Home, insights in meetings). Collapsed states share the `sidebar` component tokens.
- macOS history rows keep their locale-formatted start time and duration on one metadata line. Titles use the full row width at rest; hover actions temporarily overlay the trailing title edge without changing layout. Background AI work uses a separate `finishing insights…` status line, so neither state compresses or reflows the metadata.
- On iOS, the recording view keeps share in the native trailing toolbar slot and places the labelled neutral `catch me up` action immediately left of the red Stop action in the bottom control bar. Investigate and Catch me up both use real native `Button` owners with the shared horizontal `MinitiControlLabel` icon/label layout; on macOS, Investigate opens its Web/Codebase chooser from a `Button`-owned popover rather than styling a `Menu` to resemble a button. Catch me up uses the `clock.arrow.circlepath` SF Symbol rather than an emoji. There is no tab bar during recording.

## Elevation & Depth

Miniti uses **surface stacking**, not shadows. An "elevated" card is defined by its `surface-card` background (a step lighter than `surface-panel`) rather than a drop shadow. This keeps OLED blacks intact and avoids the "floating card" look that would clash with the terminal aesthetic.

The only shadow-like affordance is the 1px `border` or `border-light` stroke on panels, cards, and inputs. Hover states darken the border to `border-hover` rather than adding glow.

The Live Activity on iOS (Dynamic Island + Lock Screen) is rendered by the OS and follows ActivityKit's native treatment — app tokens do not apply there except the red `recording` dot and the gray stopped state (`text-disabled`).

## Shapes

Radii step through 2 / 4 / 6 / 8 / 12 / 16 px plus a `pill` sentinel:

- `rounded.xs` (2px) — waveform bars, dense badges.
- `rounded.sm` (4px) — small pills, transcript-row corner highlights.
- `rounded.md` (6px) — default button, input, pill-in-list, tab, panel radius.
- `rounded.lg` (8px) — primary CTA, onboarding card actions, banners.
- `rounded.xl` (12px) — onboarding outer cards.
- `rounded.xxl` (16px) — popup cards (question detail, catch-up sheet on macOS, info popovers).
- `rounded.pill` (999px) — speaker chips, status pills, toggles.

Rectangular (0px) corners are reserved for full-bleed dividers and the app background. Avoid mixing 6px and 7px radii in the same surface — pick one based on which component token applies.

## Components

Component tokens map directly to the SwiftUI views in `Miniti/Views/`:

- **button-primary** — blue navigation and completion CTAs such as Done, Meetings, Save, and Upgrade.
- **button-positive** — green Start and Resume actions plus explicit success affordances.
- **button-recording** — red Stop control while capture is active.
- **button-secondary** — neutral terminal-style utilities such as Settings, Shortcuts, Zoned Out, Update, and Copy.
- **compact-control** — `MinitiControlLabel` renders the shared compact chrome from a semantic `MinitiControlRole`; feature views never provide an arbitrary accent.
- **tab-strip** — persistent neutral navigation for transcript / insights / notes, summary / questions / coaching, and Coaching's focus / stats / history sections. Sales, Templates, and Playbook live under More, and the More label carries the active template's short name. Template sections use `ColorPalette.Templates.sectionColors` in template order (blue, lavender, pink, amber, green, indigo, orange, cyan), never the tab chrome. Product-authored tab labels are lowercased by the component; selection is shown through surface and text contrast, never category color. Equal-width segmented strips use `fillsAvailableWidth` on every label, Button, and Menu so each selected surface and hit target fills its complete divided share of the container.
- **button-destructive** — discard, cancel, "disconnect" in Settings. Error-colored text on a neutral ground until hover, then the red fill flips in.
- **button-ghost** — in-content affordances (e.g. rename speaker), no fill until hover.
- **card / panel** — the live insights panel, history detail panes, onboarding cards. `panel` is slightly darker than `card`.
- **coaching-trend-card** — one-column, content-sized personalized metric card with untruncated copy, a source-meeting title and date, and the stable Coaching metric accent.
- **navigation-swipe-cue** — neutral edge dial driven directly by a macOS two-finger back/forward gesture. Its progress ring reaches full exactly at the commit threshold and only appears when history exists in that direction.

- **terminal-header** — the red-dot + timer strip at the top of the recording view.
- **input-field** — note textarea, search, webhook URL, CRM search. Always system 13px. CRM modal actions use the same semantic compact controls as the rest of the app; Attio orange and Twenty's neutral mark identify integration content, not buttons.
- **pill-tag** — topic tags, language badge, usage pill.
- **pill-status-recording** / **pill-status-pro** — live indicators; color is the only variance.
- **update-banner** / **limit-banner** — home-screen banners; blue for update available, amber for usage warning.
- **meddpicc-***  — one component per MEDDPICC letter, each pinned to its semantic color.
- **speaker-chip-you** / **speaker-chip-1…7** — transcript speaker chips. Index-based, cycle of 8.
- **insight-summary / discussion / actions / topics / meddpicc** — live insights section headers.
- **transcript-row-you** / **transcript-row-remote** — the only two variants; remote rows take their hue from the active `speaker-chip-*` via the speaker cycle.
- **waveform-bar** — 2px wide, green by default (mic). System-audio bars use `speaker-1` (blue).
- **dot-recording / dot-connected / dot-disconnected** — 6×6 circular status dots used in headers, toolbars, and sidebar rows.

### Implementation contract

The design system has three code-level layers: `ColorPalette` owns colors—including the stable Coaching metric palette—`InterfaceScale` owns platform-specific base sizes and `ReadingMetrics` resolves the final prose sizes, and `MinitiDesignSystem` owns shared spacing, radii, control metrics, Coaching's desktop reading scale and overview column bounds, motion, opacity states, semantic control roles, navigation copy, and content accents. `MinitiControlLabel` owns compact action chrome; `MinitiTabLabel` and `MinitiTabStripSurface` own lowercase, neutral mutually-exclusive navigation; `MinitiCardSurface` owns card layout and delegates drawing to `MinitiCardBackground`; `MinitiInsightSection` owns section geometry with explicit desktop/mobile and card variants. These components style content only: the enclosing native `Button` or `Menu` continues to own actions, keyboard shortcuts, focus, disabled state, menus, and accessibility.

Feature views must consume these semantic contracts rather than copy their measurements. Existing native controls are migrated only when their visual contract is being changed; the presence of a design system is not permission for a broad restyle.

Variants follow the `<name>-<state>` convention (`button-primary-hover`, `button-primary-disabled`). Do not create a separate base color token for a one-off hover — reuse an existing color token so the palette stays small.

## Do's and Don'ts

**Do**

- Use semantic tokens over hex. `colors.recording`, not `#F85149`.
- Pin green to "you" / success. If a future feature needs a new positive signal, alias it to `colors.success` rather than introducing a new green.
- Keep category color in content. Tabs, Settings, Shortcuts, and other utilities stay neutral.
- Keep each Coaching metric on its named palette token across live, history, overview, and examples; never substitute a CTA or trend color.
- Keep every text/background pair above WCAG AA (4.5:1). The palette is tuned for this; verify with the linter after any color change.
- Prefer surface stacking (bump to `surface-card`) over shadows to indicate elevation.
- Use the `pill` radius for anything carrying identity (speaker, status, pro); use `rounded.md` for anything carrying an action.
- Respect the 8-step speaker cycle. Never add a ninth without also updating `ColorPalette.Speaker.remote`.

**Don't**

- Don't introduce custom display fonts or switch prose back to monospaced. The system font is the readability baseline; monospaced type is reserved for the existing wordmark and changing numeric readouts.
- Don't ship a light-mode variant of a screen. The product is dark-only; there is no light token set.
- Don't add drop shadows or blurs to simulate depth. Use surface stacking and borders instead.
- Don't pass a Questions, Coaching, Sales, Playbook, speaker, or metric accent into ordinary button chrome.
- Don't apply glass broadly. On current iOS, reserve native material for small functional utility surfaces and keep core transcript and insight panels opaque.
- Don't reassign MEDDPICC letter colors ad-hoc in a view — route through `ColorPalette.MEDDPICC` so a retune stays atomic.
- Don't hardcode a speaker color — always call `ColorPalette.Speaker.color(for:micSpeakerID:)` so the mic speaker stays green.
- Don't mix radii within a single surface (e.g. a 6px button inside an 8px card is fine; a 6px button next to a 7px sibling is not — pick one).
- Use readable body roles for prose. Reserve `text-subtle` for decoration and `text-placeholder` for readable empty-field guidance; disabled text has its own role.

## Optional Home setup

The 3.8.0 setup guide sits directly on Home, using native controls, semantic palette colors and the `MinitiDesignSystem.HomeSetup` width. A vertical checklist shows recording access, calendar, account recovery and Mac-only files/audio choices. Keep all task headings and current-state summaries visible, with one expanded group of direct controls and truthful completion checks. No containing card or horizontal setup navigation. Keep Record ahead of it and scroll Home at constrained sizes, with its utility bar outside the scroll area. Hide/reopen uses the shared short disclosure animation and disables it under Reduce Motion. File setup displays the real destination and binds the folder/export/index choices to the same state as Settings. Email sheet actions stay in the toolbar above the keyboard.


Setup visibility (3.8.0 local): the fixed Home footer uses matching `MinitiHomeActionLabel` controls, setup/progress at left and Feedback at right, on an opaque app background so scrolling text cannot cross their hit targets. Keep the guide expanded by default even when configured; explicit collapse and permanent dismissal remain independent. Task hiding never means completion. General owns per-task and whole-guide restoration. `MinitiDocumentationLink` is a native, accessibly labelled info-circle link backed by `MinitiDocumentationTopic`; keep it separate from Picker/Toggle/Button hit targets and point at the relevant topic rather than the docs home.


Home refinement (2026-11-05): calendar sections precede the setup checklist. Completed task headings use muted text and strikethrough with checks; row hide/docs controls stay visible outside disclosures. Use the shared approximate local-model progress presentation in Home and Settings, plus the compact Models shortcut in Home's status controls. Today/tomorrow/later groups replace abbreviated day labels.


Shared target contract (UI1, 3.9.0): `MinitiControlLabel`, `MinitiTabLabel` and default `MinitiDisclosureStyle` reserve at least 44 points on iOS and 24 on Mac in both dimensions, inside normal layout. Their existing visual chrome heights remain unchanged. The target uses its allocated rectangle, with no negative-padding overlay extending into neighbours. A parent's resulting layout footprint can grow; tight parent rows/toolbars must be checked and adjusted within their UI1 owner before release. A smaller fixed parent can still make the target overflow; this helper is not a clipping boundary. Adjacent compact icon labels retain their narrow chrome inside 44-point slots, so a zero-gap pair can gain a visible gap of about 16 points. Check that spacing on each affected surface. Native grouped Forms can clip row corners; check actionable points inside that system surface instead of treating its rectangular accessibility frame as proof that every corner receives taps. Button/Menu remain responsible for actions, disabled state, selection, focus and accessibility. Native metric-help and overlay-close controls use that same target allocation, with explicit About-metric and Close-metric-help accessibility names. Question and docs-answer copy actions use the shared allocation and remain native Buttons eligible for keyboard focus; no custom tap gesture replaces them. Mac live/saved transcript, notes and insight header Copy actions use the same allocation, identify the copied section for accessibility and keep readable Copy/Copied roles. Their displayed compact chrome stays unchanged. Live and saved insight Update buttons also use the shared target allocation and remain eligible for native focus. Their action closures, generation gates and busy-state labels are unchanged; the larger allocated slot can move adjacent content.

Insight lists (UI2, 3.9.0): `InsightList` renders standard discussion/action/decision lists as one read-only selectable native text surface, with resolved insight font and line spacing. Arrow lists use the same arrow and body column; Mac live and saved discussion retain numbering. Attributed lists measure the actual marker font, align wrapped lines and explicit paragraph continuations with the first word, and align single/double-digit numbers to one column. Inter-item paragraph spacing remains 6 points; saved iOS no longer adds a separate 8-point row gap. Sales/template bullets use the same measured-indent builder, retaining their parsing and colours. Actions have no completion button, local completion state or strikethrough. Preserve content/order, Markdown task-list export and separate CRM task-selection controls. Native selection can span items within a list; VoiceOver per-item navigation and broad layout acceptance remain release gates. Saved Mac discussion/actions now share this renderer and its selectable text, measured indentation and resolved line spacing; their former per-row spacing is replaced by the shared 6-point paragraph spacing.

iOS meeting sections (UI2, 3.9.0): live and saved screens both use `MinitiMeetingSectionPicker`, backed by `MinitiTabLabel` and `MinitiTabStripSurface`. Each screen owns its selection through a binding; no global tab preference is introduced. Preserve transcript / insights / notes order, lowercase labels, selected accessibility traits, equal-width 44-point targets and the 500-point maximum strip width with existing outer padding. Saved meetings adopt the live strip's neutral font, colour, border and radius roles. Content, note bindings, sharing and recording behavior remain screen-owned.

Mac live notes (UI1, 3.9.0): the resizable pane reserves at least 100 points including its 44-point section header and editor insets. Keep the existing 100-point starting height, 500-point upper bound and transcript-space constraint. Shrinking must leave a usable text viewport and preserve editing; the divider remains draggable in both directions. This changes the lower bound only.

Coaching history targets (UI1, 3.9.0): sortable headers use the shared minimum target and expose full sort names, current direction and selected state. iOS keeps the compact metric letters inside separate 44-point columns aligned with their values. Its meeting column reserves 70 points for the heading and sort arrow; the table has a 328-point minimum and scrolls horizontally when the available content width is smaller. This is a bounded layout change: headers grow to 44 points, metric columns widen and less meeting-title text may fit. Data-row height and sorting behavior stay unchanged. The metric help retains touch-and-hold and adds a named accessibility action; its 22-point Close circle sits in a 44-point target centered with the title. Mac headers use the 24-point minimum and native focus eligibility. Keyboard, VoiceOver and iPad runtime acceptance remain separate gates.

3.8.0 compact icon accessibility: setup hide controls and contextual documentation links use `MinitiDesignSystem.Control.minimumIconHitSize`, 44 points on iOS and 24 points on macOS. The symbol remains visually compact; its full rectangular surface accepts input.

Setup and calendar clarity (2026-11-07, source after build 159): use `AudioProcessingComparison` for aligned provider/benefit rows with matching callout type in Home and Settings. Group each heading, comparison and picker with shared comfortable spacing. “Collapse guide” keeps the footer button; “remove guide from Home” removes both until General restoration. Newly hidden tasks also require restoration, not a timed reminder. A calendar snooze inherited from an older version keeps its original expiry. Guide-level collapse/removal buttons share caption sizing; a divider separates the removal footer from task actions. Calendar day disclosures use `UpcomingCalendarDisclosureStyle`: a full-width native button includes label, empty space and chevron, with platform minimum targets, expanded/collapsed accessibility values and Reduce Motion-aware animation.

Build 160 setup polish (approved source, not packaged): guide headings, field labels and actions use lowercase; keep names such as Deepgram, This Mac and Google Calendar intact, and keep explanation sentences in sentence case. Use “speaker separation” throughout the guide and “confirm audio choices” for explicit review. Audio benefits precede their picker in both Home and Settings. Guide removal has one visible explanation, with no duplicate tooltip.


Home layout, 2026-11-09: keep language above the green Start meeting action in the bottom inset. iOS uses three equal-width/equal-height neutral Home utility cells in one row, with captions scaling through xxxLarge, system large-content viewers and platform minimum targets. Guide prose still uses the full requested size; at accessibility sizes, status and chevron precede full-width task text. Mac groups setup, models and feedback at bottom left and has a separate full-height right calendar sidebar, independent of setup. Its bottom-right toggle mirrors the left sidebar, including its shortcut hint. HomeSetup owns its 320pt panel and 360pt minimum main-column tokens; Sidebar owns the shared 52pt collapsed rail and footer measurements. Below the combined width, use an overlay and native dismiss button, not new window constraints. Keep the calendar mounted across collapse/resize and use Reduce Motion-aware disclosure transitions. This supersedes the earlier top-aligned action and separate iOS feedback-row layout.

Mac folder sheets use primary palette backgrounds and full-row `MinitiDisclosureStyle` controls with platform minimum targets. Home Models uses the same labelled neutral footer chrome as setup/feedback; readiness remains visible through its status icon and accessible value.

`MinitiSidebarToggleLabel` is shared by both sidebar footers. Use the secondary background, gradient dividers, mirrored icons and Cmd-[ / Cmd-] hints. Place the right sidebar outside the main-column utility inset so its surface and bottom control reach the window's bottom edge.

Sales section descriptors (UI2, 3.9.0): `SalesInsightField` owns eight distinct named fields, their order, lowercase titles and canonical `ColorPalette.MEDDPICC` accents. `SalesInsightSectionList` renders projected live or saved entries through the existing platform wrapper; the two D fields and two C fields cannot share a letter-based key. Hide nil, blank, null, n/a and none case-insensitively, preserving all meaningful value bytes. Live economic-buyer and competition headings use the same corrected lavender/indigo as saved headings. Template ordering remains owned by `InsightTemplateSectionList`. Section geometry uses the shared variants described below.

Standard section descriptors (UI2, 3.9.0): `StandardInsightSection` carries typed summary, discussion, actions, decisions and topics in that order; `StandardInsightSectionList` supplies their lowercase titles and `ColorPalette.Insights` accents to existing platform wrappers. Every screen supplies only the fields it already displayed. Actual Mac live/saved screens still omit decisions; the legacy shared saved renderer and iOS saved screen keep them. Mac saved and the legacy shared saved renderer retain nonnil empty summaries; other screens omit empty summaries. No trimming, sentinel filtering, sorting or deduplication applies to standard content. Saved Mac headings/topic tags now use the canonical blue, amber, green and purple, and action arrows use the canonical actions green instead of Theme.accent; numbered discussion markers use the muted text role at body size. Summary renderer types, topic chrome dimensions, content ownership, generation and exports stay unchanged.

Insight Update chrome (D10, 3.9.0): the four live/saved Mac/iOS buttons use `MinitiInsightUpdateLabel` over the secondary `MinitiControlLabel`. Keep their compact platform density: Mac 9-point icon, 10-point title, 5/8-point vertical/horizontal padding; iOS 10-point icon, 11-point title, 7/10-point padding. The shared control allocates the existing 24/44-point target. Resting fill/border/text are panel/primary/muted; existing shared hover feedback respects Reduce Motion. The Mac live shortcut now uses readable dim text. Screen owners retain update/regenerate/finishing wording, optional mode suffix, generation actions, disabled/opacity gates, progress siblings and keyboard shortcuts. Mac live and saved fills, Mac live and iOS borders, and saved Mac plus both iOS label colours converge on the neutral role. Copy migration is separate; keyboard/focus, pointer, iPad and largest-text acceptance remain open.

Coaching aggregate values (UI3, 3.9.0): the “all” column uses Text.dim, matching the other aggregate column and its readable heading. Its former 71717A literal failed ordinary-text contrast on the panel surface. Values, calculations, fonts, widths and comparison semantics are unchanged. This closes that specific legacy-value gap; other legacy literals still need inventory and role-based disposition. Success feedback also meets the role contrast threshold on the tertiary hover fill; physical pointer appearance remains a separate gate.

Copy chrome (D10, 3.9.0): `MinitiCopyLabel` uses the secondary `MinitiControlLabel` for question/docs answers and Mac live/saved transcript, notes and insights headers. Keep 9-point icons, 10-point medium copy/copied text, 4-point internal spacing and 3/6-point vertical/horizontal padding, inside the existing 24/44-point target. The compact chrome now shares the 6-point radius, panel fill and primary border with other utilities; normal text is muted, while copied feedback uses Status.success. Saved Mac copied feedback changes from Theme.accent to that shared success colour. Hover uses the existing shared role and respects Reduce Motion; copied text stays success-coloured. Copy feedback keeps one content identity; the shared control’s semantic showsSuccessFeedback flag selects success while normal/hover foreground keeps the existing role behavior. The earlier doubled-chrome concern was unverified; shared chrome was already outside the branch. Screen buttons retain the original clipboard content, accessibility names, 1.5-second feedback and animation timing. No copy action or clipboard ownership moves into the label. Update mode suffixes use dim on both platforms so they remain secondary to the muted title. Keyboard, pointer, VoiceOver, iPad and largest-text checks remain release gates.

Insight section geometry (D11, 3.9.0): `MinitiInsightSection` owns the header, optional accessory slot, body indent and spacing. Plain desktop sections use 10-point semibold headings and mobile sections 12-point semibold; both use a 3×12 accent bar with 1.5-point radius, 6-point header gap, 8-point section gap and 12-point body indent. The Mac live heading changes from bold to semibold and its accent-bar radius from 1 to 1.5 to match saved. Its existing 16-point outer horizontal inset remains in the adapter. Markdown/plain cards keep 12-point bold headings, 8-point header gap, 12-point section gap, 16-point outer padding and 20/0-point body indent; only markdown adds the “##” prefix. `MinitiCardBackground` reuses the existing panel fill/primary border/6-point radius for insight cards, without adopting MinitiCardSurface’s full-width layout. Existing standard/inset/accented card styles keep their 8-point radius, colours and layout. The five old wrapper names remain thin adapters for their existing info types and native help controls; no scroll owner, help content, presentation state, target or field changes. Broader renderer consolidation stays at order 9.

## Source enforcement

The [UI source guard](docs/reference/ui-source-check.md) checks both main-app Swift trees for new raw colour construction. Existing literals are explicit debt, not approved contrast roles. New focus opt-outs, small fixed fonts and local rounded chrome are review cues. Remove obsolete baseline allowances with the source correction; do not regenerate the baseline to accept new debt. Rendered contrast, layout, keyboard and accessibility checks remain required.

The live Mac and shared legacy Coaching card filler-count summaries use `Text.dim` for readable count/rate text. Existing iPhone and saved-meeting renderers retain their readable roles. Counts, grouping, typography and layout are unchanged; the correction does not establish whole-screen contrast acceptance.

Questions and Playbook guidance (UI3, 3.9.0): meaningful empty/setup/error instructions, no-match text and citation snippets use Text.dim. Pending/no-match status icons use Text.meta and the answer disclosure chevron uses Text.dim. Decorative empty-state diamonds retain their existing appearance. This is a colour-only correction; wording, typography, layout and lookup/disclosure actions remain unchanged.

Playbook answer selection (UI3 GUID1): iOS uses the shared native SelectableTextView/SelectableAttributed.body path so answer selection does not intercept the topic header Button. Keep the same reading size, line spacing and secondary text colour; the answer remains read-only and selectable, with the existing explicit Copy action. macOS keeps its SwiftUI selectable Text. Header geometry and target acceptance are separate from this dispatch correction.

Speaker guidance (UI3): SpeakerLegend uses Text.dim for its neutral heading, detection status and count explanations. RenameSpeakerView uses the same role for current-name/automatic-name guidance, attendee email and the split-speaker explanation. Keep speaker identity chip colours, names, grouping and native rename/attendee/self-identification actions unchanged.

Waiting/empty insight guidance (UI3): shared Coaching waiting title and explanation, Mac live insight listening/start instructions, and the no-insights record/generate instructions use Text.dim. Decorative symbols, missing-key warnings, wording, fonts and state/action gates are unchanged. This is bounded contrast work, not new loading or generation behavior.

Coaching/API guidance (UI3): live Mac word counts and average-words units, live and retained legacy clarity explanations, plus API edit headings, disconnected labels and add instructions use Text.dim at full opacity. API connection indicators, connected colours, controls and edit bindings remain unchanged. This does not settle remaining plan-status, notes-placeholder or shortcut contrast debt.

Plan/notes guidance (UI3): checking-plan text on both Apple platforms and the iPhone tier label use Text.dim. The Mac notes placeholder uses Text.placeholder, while section keyboard hints use Text.dim. Mac usage counts draw their existing status accent at full opacity, keeping low-minutes red readable at rest. Existing entitlement/StoreKit state, accent choices, warning thresholds, editing/focus conditions and shortcut registrations remain unchanged.

Consent reading and targets (UI3 CP1/CP2): native Allow and Cancel/Not now buttons reserve the platform minimum outside their chrome. Actions stay outside the disclosure scroll view, with the existing responsive row/stack and native shortcuts. ReadingMetrics preserves Compact normal baselines of 13pt body/actions, 17pt heading and 12pt secondary text; add the transcript InterfaceScale point increase, then apply the unshifted iOS system category once. Mac uses InterfaceScale alone. Action labels keep whole words and use the stacked fallback when they cannot fit side by side. The 18pt monospaced miniti lockup stays fixed. Preserve consent copy, version and decision behavior.

Diagnostic header adaptation (UI3, 3.9.0): iOS Debug Log separates full-width title/count from a native options menu and Close. Use semantic fonts at the resolved size, shared spacing/minimum targets, and a stacked fallback when action labels cannot fit together. Keep the Mac row unchanged. This is a plain native utility surface, not a new compact-chrome variant. Log-row adaptation remains a separate gate.

History folder adaptation (UI3, 3.9.0): iOS accessibility categories stack the native picker and management/Undo controls, with full width available to the picker. Normal iOS and Mac keep the existing horizontal layout and system font sizing. Long custom names and Undo-present geometry need separate evidence.

Presentation inheritance (UI3 SP3): shared item-sheet and iOS full-screen-cover helpers forward the presenting resolved Dynamic Type category unchanged, just like the Bool-sheet helper. Preserve item identity, content detents and native cancellation. Saved History speaker rename and metric help adopt these after reproduced category loss; forwarding does not adapt their existing fixed-point text or certify their layout.

Live/preparation inheritance (UI3 SP4): investigation and catch-up retain their custom dismissal bindings through the Bool-sheet helper; event preparation uses the item overload. Forward the resolved category unchanged. This keeps semantic preparation labels sized consistently; fixed live-helper prose, larger modal layouts and request behavior need separate evidence.

Preparation layout (UI3 SP5): iOS event preparation places its existing content in a vertical ScrollView below the native navigation toolbar. Semantic heading, time and guidance wrap without vertical compression; the notes editor keeps its existing 180pt minimum and fixed 14pt text, and meeting actions keep their native shared 44pt labels. Done stays in the toolbar, medium/large detents stay available, and actions scroll with content. This is reachability, not editing/keyboard or fixed-control text-size acceptance.

Access presentation (UI3 SP6): the first-use access card forwards the resolved category through minitiSheet to its email and recovery-key branches. Keep native sheet dismissal, branch selection, callbacks and empty-field submission gates. This does not change the fixed-point explanatory text or certify sheet layout; Settings account presentations have separate evidence.

Account presentation (UI3 SP7): attach the four Settings restore/move sheets to the persistent first Account Section header, outside enrollment and account-presence branches. The shared helper forwards the resolved category and preserves native bindings, mode content and callbacks. The section keeps its identity when its rows change from fallback to progress or signed-in content. iOS fallback buttons use native borderless style so each action dispatches independently inside the Form. Keep fixed-copy, row wrapping, keyboard and authentication-continuation acceptance separate.

Account recovery row (AL1): iOS attempts whole-label horizontal layout, then stacks title, status and actions at the available width. Show, Replace and Hide use the existing platform minimum target inside their native labels; borderless style isolates their Form dispatch. Mac keeps its horizontal row and original label geometry. Confirmation callbacks and key handling are unchanged. Other Account rows and sign-in prose retain their separate gates.

Account email editing (AL2): iOS gives the draft field its own full-width row. At accessibility categories, the email summary and Send link/Cancel groups use leading vertical layout; ordinary-size groups stay horizontal. Native borderless action dispatch and minimum targets apply to Add/Change, Resend/Remove/Retry and editing actions. Mac retains its previous horizontal structure. Wrapped recovery action labels align leading through the shared local label helper. Preserve state, validation, focus, wording and callbacks; sent/pending/verified/error states need separate evidence.

Recovery sign-in (AL3): shared dialog heading/body roles retain 17/12pt Compact normal baselines; the monospaced key uses the 13pt reading baseline. Error text shares the body role, increasing its Compact baseline from 11 to 12pt. Resolve InterfaceScale and unshifted iOS system text once, with no automatic second scaling. On iPhone, form content scrolls above separate native actions; accessibility categories stack the actions with minimum targets inside their labels. Mac retains horizontal actions. Key normalization, submit eligibility, callbacks and dismissal stay unchanged. On iOS, a returned recovery error scrolls into view without dismissing the keyboard; messages taller than the viewport still require reading by scrolling. Other account dialogs, whole-screen layouts and platform acceptance remain separate gates.
