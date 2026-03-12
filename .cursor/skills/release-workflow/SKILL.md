---
name: release-workflow
description: >-
  Build, notarize, and release macOS and iOS apps via Fastlane. Use when the
  user asks to release, build, submit to TestFlight, upload to App Store,
  create a DMG, or prepare a release.
---

# Release Workflow

## Prerequisites (both platforms)

- Xcode signed into team `9AUR5U5KTF` with automatic signing on all targets
- Repo root `.env` contains: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY`
- Version already bumped (use the `version-bump` skill)
- Changelog and release notes already updated (use the `changelog` skill)

## macOS

### Quick path

```bash
fastlane mac release
```

Runs build → notarize → DMG in sequence.

### Step-by-step

1. `fastlane mac build` — archives with Developer ID signing, outputs `build/macos/miniti.app`
2. `fastlane mac notarize_app` — submits to Apple notarization, staples ticket, copies to repo root
3. `fastlane mac dmg` — runs `scripts/build-dmg.sh`, creates `miniti.dmg` in repo root
4. Upload DMG to Netlify Blobs (key: `downloads/miniti.dmg`)

### Xcode fallback

Product → Archive → Distribute App → Developer ID → Upload (notarizes), then:

```bash
./scripts/build-dmg.sh miniti.app
```

## iOS

### TestFlight

```bash
fastlane ios beta version:X.Y.Z changelog:"release notes here"
```

- Auto-increments build number (override with `build:N`)
- Uploads to TestFlight but does not add testers or submit external review

### App Store

```bash
fastlane ios release version:X.Y.Z
```

- Auto-increments build number (override with `build:N`)
- Uploads binary + metadata from `fastlane/metadata/` (screenshots skipped — manage in App Store Connect)
- Includes `fastlane/metadata/app_review_notes.txt` when present
- Does not submit for review automatically

### After upload

1. Wait ~5–15 min for Apple to process
2. TestFlight: add build to external testing group, submit for TestFlight review
3. App Store: create/select version in ASC, attach build, submit for App Review

### Xcode fallback

Product → Archive → Distribute App → App Store Connect → Upload

## After both platforms

Update the backend version endpoint in `miniti-api`:

```
app/api/version/route.ts → set latest_version + release_notes
```

macOS `download_url` is signed at request time (no per-release paste needed).

## Pre-release checklist

- [ ] Version bumped everywhere (use `version-bump` skill)
- [ ] CLAUDE.md changelog updated
- [ ] `fastlane/metadata/en-US/release_notes.txt` updated (iOS-only changes)
- [ ] `fastlane/metadata/en-GB/release_notes.txt` mirrored
- [ ] `fastlane/metadata/copyright.txt` has current year
- [ ] `fastlane/metadata/en-US/description.txt` version footer updated
- [ ] `fastlane/RUNBOOK.md` example commands updated

## Reference

- `fastlane/RUNBOOK.md` — detailed lane behaviour and parameters
- `scripts/build-dmg.sh` — requires `create-dmg` (auto-installed via Homebrew)
- StoreKit product: `com.miniti.mobile.pro.monthly` ($4.99/month)
- Export compliance: `ITSAppUsesNonExemptEncryption: NO` (HTTPS only, exempt)
