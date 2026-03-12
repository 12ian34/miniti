---
name: version-bump
description: >-
  Bump the app version number across all required files. Use when the user asks
  to bump the version, prepare a release, or change the version number.
---

# Version Bump

All targets share the same version string. When bumping, update every location listed below.

## Locations (all required)

### 1. Info.plist files (2 files)

- `Miniti/Info.plist` — `CFBundleShortVersionString`
- `MinitiMobile/Info.plist` — `CFBundleShortVersionString`

### 2. Xcode project (6 occurrences)

- `Miniti.xcodeproj/project.pbxproj` — `MARKETING_VERSION`
- 6 places: 2 per target (Debug + Release) × 3 targets (Miniti, MinitiMobile, MinitiLiveActivityExtension)
- Use `replace_all` to update all 6 at once.

### 3. CLAUDE.md changelog heading

- Update the current version heading: `### YYYY-MM-DD - vX.Y.Z`
- Use today's date if starting a new version section.

### 4. Fastlane description version footer (2 files)

- `fastlane/metadata/en-US/description.txt` — version footer at the bottom (e.g. `v1.15.0`)
- `fastlane/metadata/en-GB/description.txt` — same footer, keep in sync

### 5. Fastlane RUNBOOK example commands (4 occurrences)

- `fastlane/RUNBOOK.md` — update version in example commands:
  - `fastlane ios beta version:X.Y.Z`
  - `fastlane ios release version:X.Y.Z`
  - Appears in both the reference section and the quick-start examples.

## Procedure

1. Read the current version from `Miniti/Info.plist` to confirm the old value.
2. Update all locations above, old → new.
3. Verify with a quick grep: `rg "OLD_VERSION"` should return zero hits (except changelog history).

## Not updated here

- **`fastlane/metadata/copyright.txt`** — only needs the current year, not the version.
- **Backend `miniti-api` version endpoint** — updated separately after release, lives in a different repo.
- **Build number** — Fastlane auto-increments this; don't touch it manually.
