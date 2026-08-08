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
  text-placeholder: "#52525B"
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
    note: "Native Button and Menu own interaction semantics; the label owns shared chrome."

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

The system is **dark-mode only**. iOS forces `.preferredColorScheme(.dark)` app-wide; macOS inherits the same palette regardless of the user's system appearance. Light-mode support is explicitly out of scope, so every token is tuned for legibility on a near-black background.

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

**Coaching metrics** use a separate six-color taxonomy owned by `ColorPalette.Coaching`: fillers gold, pace periwinkle, clarity lavender, questions warm coral, talk ratio cyan, and longest monologue rose. The mapping is identical in live coaching, saved meeting detail, trend cards, and overview tables. These hues are content labels only and deliberately differ from primary, positive, recording, warning, and trend-status tokens. “You” remains green as speaker identity; question-frequency content never reuses that green.

**Known WCAG AA exceptions.** Two component pairings ship below the 4.5:1 threshold and are called out explicitly rather than papered over:

- `input-field-empty` — `text-placeholder` (`#52525B`) on `surface-panel`. Placeholders are intentionally dim so they read as ghosted rather than as real content; WCAG AA explicitly exempts inactive/placeholder text.
- `text-divider-label` — `text-subtle` (`#484F58`) on the app background. Used only for non-essential divider labels (e.g. section separators in Settings) that duplicate information available elsewhere.

Any *new* component must clear 4.5:1. These two are pinned to the in-code palette (they serve the "ghosted" and "decorative" roles by design) and a fix belongs in `ColorPalette.swift` first, then here.

## Typography

Miniti uses the platform's Apple system font for prose, controls, and primary Home / Coaching / History navigation. Its open forms, proportional spacing, native hinting, and accessibility behavior make transcripts and AI insights easier to read at deliberately compact sizes. The `miniti` wordmark retains the original monospaced identity; recording timers and other changing numerical readouts use monospaced digits.

Settings offers three discrete interface scales. **Compact** exactly preserves the original type metrics and the user's system Dynamic Type setting. **Standard** is the default restrained readability pass and adds one Dynamic Type step. **Large** adds two steps and roomier prose metrics. This is not a blanket view transform: important prose uses platform-specific metrics, existing accessibility sizes are never reduced, and the compact insight selector keeps lowercase summary / questions / coaching visible while Sales / Playbook live in its More menu.

The Coaching overview is a reading-heavy exception to the app's compact desktop chrome: `MinitiDesignSystem.CoachingTypography` adds two points to its fixed macOS type roles while leaving iPhone sizes unchanged. A neutral lowercase `focus` / `stats` / `history` tab strip separates personalized guidance and trends, aggregate comparisons across all six Coaching metrics, and the sortable meeting table. Each segment occupies exactly one third of the strip, including its selection surface and hit target. `MinitiDesignSystem.CoachingLayout` keeps the strip at a 480px compact-column maximum and gives both the stats table and trend cards a 720px maximum on desktop; all become fluid on narrower iPhone/iPad layouts. The stats metric column is deliberately wide enough to keep every metric and unit—including `longest monologue words`—on one line. Each row then uses the remaining width for a visible plain-language explanation beneath the comparisons; stats do not hide this copy behind info icons. Charts do not interrupt those rows: the complete comparison table is followed directly by an always-visible card for each metric, with no extra section heading or disclosure. Each chart uses the metric's established content colour, a low-opacity area fade, quiet dashed grid lines, and a ringed latest point. Horizontal positions are categorical meeting-sequence indices, so every meeting receives equal spacing regardless of calendar gaps; unavailable metric values retain their position rather than compressing time. Axes stay visually hidden because the aligned all/recent/latest values already provide the numerical frame; VoiceOver receives the latest value, date, unit, and eligible meeting count. Empty talk-ratio history uses a neutral placeholder instead of inventing data. Comparison arrows use status green/red/neutral only after metric meaning is considered: directional measures use their established better direction, range-based measures use movement toward or away from the broad coaching range, and unavailable or inconclusive comparisons remain neutral. Cards and nested evidence surfaces size to their content, without filler gaps or prose truncation. Source-example labels wrap, and every source shows its meeting title with a locale-formatted date but no time.

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
- On macOS, the sidebar collapses to a compact icon rail via `⌘[`; the insights pane collapses via `⌘]`. Collapsed states share the `sidebar` component tokens.
- On iOS, the recording view keeps share in the native trailing toolbar slot and places the labelled neutral `catch me up` action immediately left of the red Stop action in the bottom control bar. The catch-up action uses an SF Symbol rather than an emoji. There is no tab bar during recording.

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
- **tab-strip** — persistent neutral navigation for transcript / insights / notes, summary / questions / coaching, and Coaching's focus / stats / history sections. Sales and Playbook live under More. Product-authored tab labels are lowercased by the component; selection is shown through surface and text contrast, never category color. Equal-width segmented strips use `fillsAvailableWidth` on every label, Button, and Menu so each selected surface and hit target fills its complete divided share of the container.
- **button-destructive** — discard, cancel, "disconnect" in Settings. Error-colored text on a neutral ground until hover, then the red fill flips in.
- **button-ghost** — in-content affordances (e.g. rename speaker), no fill until hover.
- **card / panel** — the live insights panel, history detail panes, onboarding cards. `panel` is slightly darker than `card`.
- **coaching-trend-card** — one-column, content-sized personalized metric card with untruncated copy, a source-meeting title and date, and the stable Coaching metric accent.
- **navigation-swipe-cue** — neutral edge dial driven directly by a macOS two-finger back/forward gesture. Its progress ring reaches full exactly at the commit threshold and only appears when history exists in that direction.

- **terminal-header** — the red-dot + timer strip at the top of the recording view.
- **input-field** — note textarea, search, webhook URL, Attio search. Always system 13px. Attio modal actions use the same semantic compact controls as the rest of the app; Attio orange identifies the integration, not its buttons.
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

The design system has three code-level layers: `ColorPalette` owns colors—including the stable Coaching metric palette—`InterfaceScale` owns platform-specific readable typography, and `MinitiDesignSystem` owns shared spacing, radii, control metrics, Coaching's desktop reading scale and overview column bounds, motion, opacity states, semantic control roles, navigation copy, and content accents. `MinitiControlLabel` owns compact action chrome; `MinitiTabLabel` and `MinitiTabStripSurface` own lowercase, neutral mutually-exclusive navigation; `MinitiCardSurface` owns card chrome. These components style content only: the enclosing native `Button` or `Menu` continues to own actions, keyboard shortcuts, focus, disabled state, menus, and accessibility.

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

- Don't introduce custom display fonts or switch prose back to monospaced. The system font is the readability baseline; monospaced type is reserved for the existing wordmark, primary navigation identity, and changing numeric readouts.
- Don't ship a light-mode variant of a screen. The product is dark-only; there is no light token set.
- Don't add drop shadows or blurs to simulate depth. Use surface stacking and borders instead.
- Don't pass a Questions, Coaching, Sales, Playbook, speaker, or metric accent into ordinary button chrome.
- Don't apply glass broadly. On current iOS, reserve native material for small functional utility surfaces and keep core transcript and insight panels opaque.
- Don't reassign MEDDPICC letter colors ad-hoc in a view — route through `ColorPalette.MEDDPICC` so a retune stays atomic.
- Don't hardcode a speaker color — always call `ColorPalette.Speaker.color(for:micSpeakerID:)` so the mic speaker stays green.
- Don't mix radii within a single surface (e.g. a 6px button inside an 8px card is fine; a 6px button next to a 7px sibling is not — pick one).
- Don't use `text-subtle` or `text-placeholder` for body copy. They exist only for disabled/empty states.
