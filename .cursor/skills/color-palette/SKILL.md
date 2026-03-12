---
name: color-palette
description: >-
  Use the centralized ColorPalette for all colors in UI code. Use when adding
  or editing SwiftUI views, styling components, or working with colors.
---

# Color Palette

All colors must use `ColorPalette` from `Miniti/Models/ColorPalette.swift`. Never hardcode hex values in views.

## Available namespaces

| Namespace | Keys | Example |
|---|---|---|
| `Background` | `primary`, `secondary`, `tertiary`, `panel`, `card` | `ColorPalette.Background.primary` |
| `Border` | `primary`, `light`, `hover`, `subtle` | `ColorPalette.Border.subtle` |
| `Text` | `primary`, `secondary`, `muted`, `dim`, `disabled`, `placeholder`, `subtle`, `meta` | `ColorPalette.Text.muted` |
| `Accent` | `green`, `blue`, `purple`, `red`, `amber`, `yellow`, `pink`, `cyan`, `orange` | `ColorPalette.Accent.green` |
| `Status` | `success`, `error`, `warning`, `info`, `recording`, `connected`, `disconnected`, `limitReached`, `noApiKey` | `ColorPalette.Status.recording` |
| `Speaker` | `mic` (green, "You"), `remote` (array, blue/purple) | `ColorPalette.Speaker.mic` |
| `MEDDPICC` | `metrics`, `economicBuyer`, `decisionCriteria`, etc. + `color(for:)` | `ColorPalette.MEDDPICC.metrics` |
| `Insights` | `summary`, `discussion`, `actions`, `topics`, `meddpicc` | `ColorPalette.Insights.summary` |

## Rules

- **Always use `ColorPalette.*`** — no `Color(hex: "...")` in view files unless defining a new palette entry.
- `Color(hex:)` extension is defined in `ColorPalette.swift` for creating colors from hex strings within the palette.
- `Theme` struct in `MainWindow.swift` provides macOS-only shorthand aliases (`Theme.bg`, `Theme.text`). These reference `ColorPalette` underneath.
- When adding a new color, add it to `ColorPalette.swift` first, then reference it.
- GitHub-style dark theme: backgrounds are near-black, text is light gray, accents are saturated.

## Common mappings

| Use case | Color |
|---|---|
| Page background | `Background.primary` |
| Panel/card/toolbar background | `Background.secondary` |
| Primary text | `Text.primary` |
| Secondary/label text | `Text.secondary` |
| Dimmed/hint text | `Text.muted` |
| Disabled text | `Text.disabled` |
| Success/active/go | `Accent.green` |
| Links/info | `Accent.blue` |
| Pro/subscription | `Accent.purple` |
| Error/danger/stop | `Accent.red` / `Status.error` |
| Warning | `Accent.amber` / `Status.warning` |
| Recording dot | `Status.recording` (red) |
| Mic speaker ("You") | `Speaker.mic` (green) |
| Remote speakers | `Speaker.remote[index]` |
| Subtle borders | `Border.subtle` |
