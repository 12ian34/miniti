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

1. **`CHANGELOG.md`** at repo root — the canonical release history (moved out of the old monolithic `claude.md` during the 1.24.1 doc split).
2. **`fastlane/metadata/{en-US,en-GB}/release_notes.txt`** — App Store "What's New" for iOS.

Neither lives in `CLAUDE.md` / `AGENTS.md` any more — those are the slim dev-facing index. Don't put changelog entries there.

## CHANGELOG.md

Entries live under the current version heading (`### YYYY-MM-DD - vX.Y.Z`) under the `## Releases` section.

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
- **Platform scoping**: prefix with `(macOS)`, `(iOS)`, or `(macOS and iOS)` when relevant, especially for platform-specific bugs or new features.

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

- Never modify older changelog entries. Add corrections as new entries at the top.
- Group related changes into one entry when possible (e.g. "iOS native toolbar items" covers home + recording + history).
- Add entries immediately after making changes, not at the end of a session.

## Release notes (`fastlane/metadata`)

These are iOS App Store "What's New" text. Update both `en-US` and `en-GB` locales. `CHANGELOG.md` is the source of truth — these files are mirrored from it at release time, filtered to iOS-relevant bullets.

### Scope

**iOS only.** Only include changes that affect the iOS app. Skip macOS-only changes entirely (e.g. Sparkle auto-updater is macOS-only and must not appear in iOS release notes).

For shared views/services that affect both platforms, include the change only if it's visible to iOS users. When in doubt, check whether the changed file is compiled into the `MinitiMobile` target or is iOS-guarded (`#if os(iOS)`). Shared model/service changes that have no user-visible iOS impact should be skipped.

### Tone

- Written for end users who don't know what SwiftUI or toolbars are.
- Slightly more descriptive than `CHANGELOG.md` entries — one sentence per bullet.
- Start each line with `- `.
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
