---
name: changelog
description: >-
  Update the changelog in CLAUDE.md and release notes in fastlane/metadata after
  code changes. Use after completing any task that changes user-facing behaviour,
  or when the user asks to update the changelog or release notes.
---

# Changelog

Update the changelog after every task that changes user-facing behaviour. There are two places to update:

1. **`CLAUDE.md`** — the canonical changelog under `## Changelog`
2. **`fastlane/metadata/{en-US,en-GB}/release_notes.txt`** — App Store "What's New"

## CLAUDE.md changelog

Entries live under the current version heading (`### YYYY-MM-DD - vX.Y.Z`).

### Format

```
- prefix: short description
```

Prefixes: `new`, `improvement`, `fix`.

### Tone

- **User-facing only.** Write what changed from the user's perspective.
- **Concise.** One line per change. No filler words.
- **No implementation details.** No code references, function names, file paths, class names, or technical architecture.
- **Lowercase prefixes.** `- new:` not `- New:`.
- **No period at end** unless the entry has multiple sentences.

### Good

```
- new: home screen redesign
- improvement: training stats include questions asked
- improvement: iOS native toolbar items
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

- Never modify older changelog entries. Add corrections as new entries at the top.
- Group related changes into one entry when possible (e.g. "iOS native toolbar items" covers home + recording + history).
- Add entries immediately after making changes, not at the end of a session.

## Release notes (`fastlane/metadata`)

These are iOS App Store "What's New" text. Update both `en-US` and `en-GB` locales.

### Scope

**iOS only.** Only include changes that affect the iOS app. Skip macOS-only changes entirely.

For shared views/services that affect both platforms, include the change only if it's visible to iOS users. When in doubt, check whether the changed file is compiled into the `MinitiMobile` target or is iOS-guarded (`#if os(iOS)`). Shared model/service changes that have no user-visible iOS impact should be skipped.

### Tone

- Written for end users who don't know what SwiftUI or toolbars are.
- Slightly more descriptive than CLAUDE.md entries — one sentence per bullet.
- Start each line with `- `.
- No version numbers or dates in the body.

### Example

```
- Training stats now include questions asked, alongside fillers, pace, and clarity.
- Share button is now context-aware: sharing from transcript shares the transcript; sharing from insights shares all insights, MEDDPICC, and notes.
- Filler words info popup now links to Settings so you can add or edit your own filler words.
```

### Rules

- Keep total length reasonable (Apple truncates after ~4000 chars).
- `en-GB` should match `en-US` but use British spelling where it differs naturally (e.g. "centred" not "centered").
- Release notes are fully replaced each version — no append-only rule here.
