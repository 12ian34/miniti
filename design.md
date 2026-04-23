---
version: alpha
name: miniti
description: Terminal-styled, dark-mode-only design system for the miniti macOS + iOS meeting assistant. Monospaced typography, near-black surfaces, and GitHub-accent status colors.
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

typography:
  display:
    fontFamily: "SF Mono, Menlo, monospace"
    fontSize: "56px"
    fontWeight: "700"
    lineHeight: "1.05"
    letterSpacing: "-0.01em"
  heading:
    fontFamily: "SF Mono, Menlo, monospace"
    fontSize: "20px"
    fontWeight: "700"
    lineHeight: "1.2"
    letterSpacing: "0em"
  subheading:
    fontFamily: "SF Mono, Menlo, monospace"
    fontSize: "15px"
    fontWeight: "700"
    lineHeight: "1.3"
    letterSpacing: "0em"
  body:
    fontFamily: "SF Mono, Menlo, monospace"
    fontSize: "13px"
    fontWeight: "400"
    lineHeight: "1.5"
    letterSpacing: "0em"
  body-emphasis:
    fontFamily: "SF Mono, Menlo, monospace"
    fontSize: "13px"
    fontWeight: "600"
    lineHeight: "1.5"
    letterSpacing: "0em"
  label:
    fontFamily: "SF Mono, Menlo, monospace"
    fontSize: "11px"
    fontWeight: "500"
    lineHeight: "1.3"
    letterSpacing: "0em"
  caption:
    fontFamily: "SF Mono, Menlo, monospace"
    fontSize: "10px"
    fontWeight: "500"
    lineHeight: "1.3"
    letterSpacing: "0em"
  micro:
    fontFamily: "SF Mono, Menlo, monospace"
    fontSize: "8px"
    fontWeight: "500"
    lineHeight: "1.2"
    letterSpacing: "0.02em"
  tagline:
    fontFamily: "SF Mono, Menlo, monospace"
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

  terminal-header:
    backgroundColor: "{colors.surface-panel}"
    textColor: "{colors.text-muted}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "6px"

  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.body-emphasis}"
    rounded: "{rounded.lg}"
    padding: "14px"
  button-primary-hover:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.on-primary-container}"
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

miniti is a macOS + iOS meeting assistant. The visual language is intentionally utilitarian: near-black surfaces, high-contrast monospaced text, and a small palette of saturated accents that carry semantic weight (recording, connected, action items, MEDDPICC letters, speaker identity). The design reads as a terminal-native tool, not a "productivity SaaS" — minimal chrome, no glass, no gradients, no ornamental motion.

The system is **dark-mode only**. iOS forces `.preferredColorScheme(.dark)` app-wide; macOS inherits the same palette regardless of the user's system appearance. Light-mode support is explicitly out of scope, so every token is tuned for legibility on a near-black background.

Core principles:

- **Information density over whitespace.** Tight line heights, 10–13px monospaced body, small pill tags. The transcript and insights panel must stay scannable during a live call.
- **Color carries meaning, not decoration.** Green = you/success, red = recording/error, amber = warning/discussion, blue = info/summary, purple = pro/topics. MEDDPICC letters each have a fixed hue.
- **Monospaced everywhere.** Headings, body, labels, numbers — all SF Mono / Menlo. Variable-width fonts are not used in the product.
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

**Known WCAG AA exceptions.** Two component pairings ship below the 4.5:1 threshold and are called out explicitly rather than papered over:

- `input-field-empty` — `text-placeholder` (`#52525B`) on `surface-panel`. Placeholders are intentionally dim so they read as ghosted rather than as real content; WCAG AA explicitly exempts inactive/placeholder text.
- `text-divider-label` — `text-subtle` (`#484F58`) on the app background. Used only for non-essential divider labels (e.g. section separators in Settings) that duplicate information available elsewhere.

Any *new* component must clear 4.5:1. These two are pinned to the in-code palette (they serve the "ghosted" and "decorative" roles by design) and a fix belongs in `ColorPalette.swift` first, then here.

## Typography

Miniti is monospaced end to end. Every text token resolves to `SF Mono, Menlo, monospace` — a deliberate choice that reinforces the terminal aesthetic and aligns numerals (critical for the recording timer, usage counters, and training metrics).

The scale is narrow and dense:

- **display (56px/700)** — the lockup on the home screen (`miniti`).
- **heading (20px/700)** — stopped-session headers, settings section titles.
- **subheading (15px/700)** — onboarding card titles, panel titles.
- **body (13px/400)** — transcript rows, notes, MEDDPICC bullets, insights body copy.
- **body-emphasis (13px/600)** — primary CTA labels, active tab.
- **label (11px/500)** — buttons, tabs, terminal headers, pill text.
- **caption (10px/500)** — chip metadata, keyboard-shortcut hints, speaker chips.
- **micro (8px/500)** — insight-mode tab descriptors, dense status overlays.
- **tagline (12px/500, +0.04em)** — the "multi-dimensional meetings" home tagline.

Line heights skew tight (1.2–1.5) because monospaced fonts already read airy. Letter spacing is near-zero, with a small positive tracking on tagline and micro to keep uppercase-ish fragments legible.

## Layout

Spacing uses an even-step scale (`"1"` = 2px through `"12"` = 32px). The 2px base matches the 2px waveform bar width and the 2px inset on small pills. `"3"` (6px) and `"4"` (8px) are the most common — they drive nearly all pill, chip, and terminal-header padding. `"6"` (12px) is the default card / panel padding. `"10"` (24px) separates major home-screen stacks.

Containers follow the same small-step rhythm:

- The meeting view splits horizontally into a transcript + notes column and an insights rail. Both use `surface-panel` for the background and `border` for the 1px divider.
- On macOS, the sidebar collapses to a compact icon rail via `⌘[`; the insights pane collapses via `⌘]`. Collapsed states share the `sidebar` component tokens.
- On iOS, the recording view places the primary button bottom-center and uses native toolbar slots for home / timer / share. There is no tab bar during recording.

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

- **button-primary** — the "start", "save", and "upgrade to pro" CTAs. Green fill, 8px radius, 14px padding.
- **button-secondary** — neutral terminal-style buttons (tabs, "update", "copy").
- **button-destructive** — discard, cancel, "disconnect" in Settings. Error-colored text on a neutral ground until hover, then the red fill flips in.
- **button-ghost** — in-content affordances (e.g. rename speaker), no fill until hover.
- **card / panel** — the live insights panel, history detail panes, onboarding cards. `panel` is slightly darker than `card`.
- **terminal-header** — the red-dot + timer strip at the top of the recording view.
- **input-field** — note textarea, search, webhook URL, Attio search. Always monospaced 13px.
- **pill-tag** — topic tags, language badge, usage pill.
- **pill-status-recording** / **pill-status-pro** — live indicators; color is the only variance.
- **update-banner** / **limit-banner** — home-screen banners; blue for update available, amber for usage warning.
- **meddpicc-***  — one component per MEDDPICC letter, each pinned to its semantic color.
- **speaker-chip-you** / **speaker-chip-1…7** — transcript speaker chips. Index-based, cycle of 8.
- **insight-summary / discussion / actions / topics / meddpicc** — live insights section headers.
- **transcript-row-you** / **transcript-row-remote** — the only two variants; remote rows take their hue from the active `speaker-chip-*` via the speaker cycle.
- **waveform-bar** — 2px wide, green by default (mic). System-audio bars use `speaker-1` (blue).
- **dot-recording / dot-connected / dot-disconnected** — 6×6 circular status dots used in headers, toolbars, and sidebar rows.

Variants follow the `<name>-<state>` convention (`button-primary-hover`, `button-primary-disabled`). Do not create a separate base color token for a one-off hover — reuse an existing color token so the palette stays small.

## Do's and Don'ts

**Do**

- Use semantic tokens over hex. `colors.recording`, not `#F85149`.
- Pin green to "you" / success. If a future feature needs a new positive signal, alias it to `colors.success` rather than introducing a new green.
- Keep every text/background pair above WCAG AA (4.5:1). The palette is tuned for this; verify with the linter after any color change.
- Prefer surface stacking (bump to `surface-card`) over shadows to indicate elevation.
- Use the `pill` radius for anything carrying identity (speaker, status, pro); use `rounded.md` for anything carrying an action.
- Respect the 8-step speaker cycle. Never add a ninth without also updating `ColorPalette.Speaker.remote`.

**Don't**

- Don't introduce variable-width fonts. The terminal aesthetic breaks immediately.
- Don't ship a light-mode variant of a screen. The product is dark-only; there is no light token set.
- Don't add drop shadows or blurs to simulate depth. Use surface stacking and borders instead.
- Don't reassign MEDDPICC letter colors ad-hoc in a view — route through `ColorPalette.MEDDPICC` so a retune stays atomic.
- Don't hardcode a speaker color — always call `ColorPalette.Speaker.color(for:micSpeakerID:)` so the mic speaker stays green.
- Don't mix radii within a single surface (e.g. a 6px button inside an 8px card is fine; a 6px button next to a 7px sibling is not — pick one).
- Don't use `text-subtle` or `text-placeholder` for body copy. They exist only for disabled/empty states.
