---
name: changelog
description: >-
  Update the canonical changelog in CHANGELOG.md and the iOS App Store "What's
  New" text in fastlane/metadata after code changes. Use after completing any
  task that changes user-facing behaviour, or when the user asks to update
  the changelog or release notes.
---

# Changelog

Update the changelog after every task that changes user-facing behaviour. There are two places to update:

1. **`CHANGELOG.md`** at repo root — the canonical release history.
2. **`fastlane/metadata/{en-US,en-GB}/release_notes.txt`** — App Store "What's New" for iOS.

Neither lives in `AGENTS.md` — that is the slim dev-facing index. Don't put changelog entries there.

`CHANGELOG.md` also feeds the website: run `../minitidotapp/scripts/build-changelog.mjs` using that repo's runbook rather than hand-editing its generated `changelog/index.html`. Use the Mac bullets for Sparkle and the current backend release-metadata contract. Do not restore obsolete release-note constants. Publication still requires release authorization.

## CHANGELOG.md

Prepare new work under an explicit Unreleased heading. At publication use `### YYYY-MM-DD - vX.Y.Z` under `## Releases`. Keep dates and versions accurate; historical entries stay unchanged unless Ian explicitly requests a correction.

### Format

```
- prefix: short description
```

Prefixes: `new`, `improvement`, `fix`.

### Tone

- **User-facing only.** Write what changed from the user's perspective.
- **Concise.** One line per change. No filler words. Product name is lowercase miniti; no em dashes, bold or exclamation marks.
- **No implementation details.** No code references, function names, file paths, class names, or technical architecture.
- **Lowercase prefixes.** `- new:` not `- New:`.
- **No period at end** unless the entry has multiple sentences.
- **Platform scoping**: put `(macOS)`, `(iOS)`, `(macOS and iOS)`, or `(Linux)` immediately after the prefix. The website uses these tags to split platform tabs. Availability never belongs in the header.
- One flat list per release; no feature/fix subheadings in CHANGELOG.md. Keep the file to release entries only.
- Use short sentences, plain verbs and specific supported numbers. Avoid "seamless", "enhances", "leverages", "not X, it's Y" framing and forced excitement. Put detailed tradeoffs in the docs. Do not label Jev or Nemotron as beta.
- Name settings using their current visible labels, checking the app rather than copying an old tab list. These public rules are sufficient without the private personal voice guide.

### Good

```
- new: (macOS) in-app auto-updater
- new: (macOS and iOS) home-screen card helps discover Google Calendar
- improvement: (macOS) audio capture reliability improved when switching to or from bluetooth headphones
- fix: transcript losing last sentence on stop
```

### Bad

```
- improvement: iOS recording screen home and share buttons are now native toolbar items (visible during recording and when stopped), matching the history view's native rendering.
- improvement: Moved settings gear NavigationLink from custom ZStack into .toolbar ToolbarItem(.topBarTrailing) for native iOS circle background.
- fix: Fixed `TranscriptSegment.speakerLabel` for `micSpeakerID` in saved meetings.
```

The bad examples are too long, include implementation details, or reference code constructs.

### Ordering

Within a version, entries are sorted by prefix: all `new` first, then `improvement`, then `fix`.

### Rules

- Describe the final release relative to the previous publicly released version, not relative to the last commit, review or development iteration. Check the released tag when uncertain.
- A feature first shipping in this release is `new`, even if it was redesigned several times during development. Fold its final behavior into that feature bullet.
- Do not publish fixes for regressions introduced and repaired entirely within the unreleased candidate. Keep those in the internal release record. Deduplicate and rewrite the candidate entry as its final scope changes.
- Never modify older changelog entries unless Ian explicitly requests a historical correction. Add ordinary corrections to the unreleased entry.
- Group related changes into one entry when possible (e.g. "iOS native toolbar items" covers home + recording + history).
- Add entries immediately after making changes, not at the end of a session.

## Release notes (`fastlane/metadata`)

These are iOS App Store "What's New" text. Update both `en-US` and `en-GB` locales. `CHANGELOG.md` is the source of truth — these files are mirrored from it at release time, filtered to iOS-relevant bullets.

Keep metadata for the currently selected release until release preparation selects the next version; docs-only changes do not replace live release notes.

### Scope

**iOS only.** Only include changes that affect the iOS app. Skip macOS-only changes entirely (e.g. Sparkle auto-updater is macOS-only and must not appear in iOS release notes).

For shared views/services that affect both platforms, include the change only if it's visible to iOS users. When in doubt, check whether the changed file is compiled into the `MinitiMobile` target or is iOS-guarded (`#if os(iOS)`). Shared model/service changes that have no user-visible iOS impact should be skipped.

### Tone

- Written for end users who don't know what SwiftUI or toolbars are.
- Slightly more descriptive than `CHANGELOG.md` entries — one sentence per bullet.
- Group iOS notes under the existing `NEW`, `IMPROVED`, `FIXED` headings as applicable; start each item with `- ` and end it with a full stop. These store-note headings do not apply to CHANGELOG.md.
- No version numbers or dates in the body.

### Example

```
- Home-screen card helps discover Google Calendar.
- Audio capture reliability improved when switching to or from bluetooth headphones.
```

### Rules

- Keep total length reasonable (Apple truncates after ~4000 chars).
- `en-GB` should match `en-US` but use British spelling where it differs naturally (e.g. "centred" not "centered").
- Release notes are fully replaced each version — no append-only rule here.
