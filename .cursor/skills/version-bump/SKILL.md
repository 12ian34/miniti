---
name: version-bump
description: >-
  Bump the app version number across all required files. Use when the user asks
  to bump the version, prepare a release, or change the version number. Covers
  both CFBundleShortVersionString (semver) and CFBundleVersion / CURRENT_PROJECT_VERSION
  (build number, strictly-increasing — required for Sparkle + App Store Connect).
---

# Version Bump

All targets share the same version string. When bumping, update every location listed below.

**Two distinct numbers:**

- **`CFBundleShortVersionString`** — user-facing semver, e.g. `1.24.1`. Called `MARKETING_VERSION` in pbxproj.
- **`CFBundleVersion`** — monotonically-increasing build number integer, e.g. `92`. Called `CURRENT_PROJECT_VERSION` in pbxproj. **Bump this on every release, even hotfixes.** It's what Sparkle compares via `sparkle:version` in the appcast AND what App Store Connect enforces as strictly-increasing across submissions.

## Locations (all required)

### 1. Info.plist files — semver + build number

- `Miniti/Info.plist`:
  - `CFBundleShortVersionString` → new semver (e.g. `1.24.1`)
  - `CFBundleVersion` → new build number (e.g. `92`)
- `MinitiMobile/Info.plist`:
  - `CFBundleShortVersionString` → new semver

### 2. Xcode project (`Miniti.xcodeproj/project.pbxproj`)

Two build settings, each in multiple places:

- `MARKETING_VERSION` — 6 occurrences (2 per target × 3 targets, Debug + Release). Must match the new semver.
- `CURRENT_PROJECT_VERSION` — 10 occurrences. Must match the new build number.

**`CURRENT_PROJECT_VERSION` wins over `CFBundleVersion` in Info.plist at build time** — always keep both in sync, or the built binary will have a different build number than the source-controlled Info.plist claims.

Bulk update with sed (replace X.Y.Z / N as appropriate):

```sh
sed -i '' 's/MARKETING_VERSION = OLD_VER;/MARKETING_VERSION = NEW_VER;/g' Miniti.xcodeproj/project.pbxproj
sed -i '' 's/CURRENT_PROJECT_VERSION = OLD_N;/CURRENT_PROJECT_VERSION = NEW_N;/g' Miniti.xcodeproj/project.pbxproj
```

### 3. CHANGELOG.md heading

- Prepend a new version section at the top: `### YYYY-MM-DD - vX.Y.Z`
- Use today's date.
- Entries follow the `changelog` skill's rules (user-facing, no code refs, ordered new → improvement → fix).

### 4. Fastlane release notes

- `fastlane/metadata/en-US/release_notes.txt` — iOS App Store "What's New". Mirror from the new `CHANGELOG.md` entry, filtered to iOS-relevant bullets only.
- `fastlane/metadata/en-GB/release_notes.txt` — same, with British spelling where it differs.

### 5. Fastlane description version footer (optional)

Only if the footer exists at the bottom of `description.txt`:

- `fastlane/metadata/en-US/description.txt` — `vX.Y.Z` footer
- `fastlane/metadata/en-GB/description.txt` — same

Check with: `grep -n "v[0-9]\." fastlane/metadata/en-US/description.txt` before and after.

### 6. Fastlane RUNBOOK example commands

- `fastlane/RUNBOOK.md` — update version in example commands:
  - `fastlane ios beta version:X.Y.Z`
  - `fastlane ios release version:X.Y.Z`
  - Appears in both the reference section and the quick-start examples.

## Procedure

1. Read the current semver from `Miniti/Info.plist` (`CFBundleShortVersionString`) and the current build number from `CFBundleVersion` to confirm the old values.
2. Update all locations above, old → new. Remember BOTH numbers — semver + build number.
3. Verify with grep: `rg "OLD_SEMVER"` should return zero hits outside `CHANGELOG.md` history. `rg "CURRENT_PROJECT_VERSION = OLD_N"` should return zero hits.

## Not updated here

- **`fastlane/metadata/copyright.txt`** — only needs the current year, not the version.
- **Backend `miniti-api` version endpoint + appcast** — updated during the release workflow (see `release-workflow` skill), lives in a different repo.
- **DMG filename** — always `miniti.dmg` (unversioned); the versioned upload to Netlify Blobs happens in the release step using the semver read from Info.plist.

## Common mistake

Only bumping `MARKETING_VERSION` (semver) without bumping `CURRENT_PROJECT_VERSION` (build number). The built binary will then have a stale build number, and:

- Sparkle will see the new version as "same or older" than what's already installed → no update offered.
- App Store Connect will reject the upload with "this build number is not higher than the previous submission".

Always bump both.
