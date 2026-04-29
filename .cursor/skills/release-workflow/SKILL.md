---
name: release-workflow
description: >-
  Build, sign, notarize, Sparkle-sign, publish, and release macOS and iOS apps
  via Fastlane. Use when the user asks to release, build, submit to TestFlight,
  upload to App Store, create a DMG, or prepare a release.
---

# Release Workflow

The authoritative runbook is [`RELEASE.md`](../../../RELEASE.md) at the repo root. This skill is a quick reference for the most common flows.

For deeper context:

- Per-lane detail → [`fastlane/RUNBOOK.md`](../../../fastlane/RUNBOOK.md)
- Sparkle / notarization / postmortems → [`docs/distribution.md`](../../../docs/distribution.md)

## Prerequisites (both platforms)

- Xcode signed into team `9AUR5U5KTF` with automatic signing on all targets.
- Repo root `.env` contains: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY`.
- Version already bumped (use the `version-bump` skill — touches `Info.plist` x2, pbxproj `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`, `CHANGELOG.md`, `release_notes.txt`).
- Changelog and release notes already updated (use the `changelog` skill — `CHANGELOG.md` + `fastlane/metadata`).
- macOS only: `which sign_update` returns a path. If not, symlink the Sparkle tool from the SPM checkout:

  ```sh
  ln -sf ~/Library/Developer/Xcode/DerivedData/Miniti-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update /opt/homebrew/bin/sign_update
  ```

## macOS

### Quick path

```bash
fastlane mac release
bash scripts/release-info.sh
```

`fastlane mac release` runs build → **Sparkle framework re-sign (preserving entitlements)** → **verify entitlements survived** → notarize → staple → DMG with `sign_update`.

`scripts/release-info.sh` prints the five appcast values + sanity checks. **All `[ok]` required before ship.** In particular:

- `[ok] app-sandbox entitlement present` — catches the regression that shipped in v1.24.0 and silently wiped history. If this fails, do NOT ship; investigate the `resign_sparkle_framework` lane.
- `[ok] URL matches local` — catches upload mismatches.

### Step-by-step (if you need it)

1. `fastlane mac build` — archives with Developer ID signing, outputs `build/macos/miniti.app`.
2. `fastlane mac notarize_app` — re-signs Sparkle nested binaries, preserves entitlements, verifies, submits to notarytool, staples, copies to repo root.
3. `fastlane mac dmg` — runs `scripts/build-dmg.sh`, creates `miniti.dmg`, runs `sign_update` for the appcast signature.
4. `bash scripts/release-info.sh` — sanity-check + print appcast values.
5. Upload DMG to Netlify Blobs (both keys, from the website repo `../minitidotapp`):

   ```bash
   netlify blobs:set downloads miniti-X.Y.Z.dmg --input ../miniti/miniti.dmg --force
   netlify blobs:set downloads miniti.dmg --input ../miniti/miniti.dmg --force
   ```

   For v1.25.0 specifically: `netlify blobs:set downloads miniti-1.25.0.dmg --input ../miniti/miniti.dmg --force; netlify blobs:set downloads miniti.dmg --input ../miniti/miniti.dmg --force`

   Versioned key is what Sparkle's appcast enclosure URL points at — never overwrite post-release.
6. Update backend (`miniti-api`):
   - `public/appcast.xml` — add new `<item>` at top with the five values from step 4. Keep prior `<item>`s for release-note history.
   - `app/api/version/route.ts` — bump `MACOS_LATEST_VERSION` + `MACOS_RELEASE_NOTES`.
   - Deploy.
7. Smoke-test Sparkle on a machine running the previous version: Miniti menu → Check for Updates… → one-click install should work end-to-end.

### Xcode fallback

Product → Archive → Distribute App → Developer ID → Upload (notarizes), then:

```bash
./scripts/build-dmg.sh miniti.app
sign_update miniti.dmg   # manual signature for the appcast
```

## iOS

### TestFlight

```bash
fastlane ios beta version:X.Y.Z changelog:"release notes here"
```

- Auto-increments build number (override with `build:N`).
- Uploads to TestFlight but does not add testers or submit external review.

### App Store

```bash
fastlane ios release version:X.Y.Z
```

- Auto-increments build number (override with `build:N`).
- Uploads binary + metadata from `fastlane/metadata/` (screenshots skipped — manage in App Store Connect).
- Includes `fastlane/metadata/app_review_notes.txt` when present.
- Does not submit for review automatically.

### After upload

1. Wait ~5–15 min for Apple to process.
2. TestFlight: add build to external testing group, submit for TestFlight review.
3. App Store: create/select version in ASC, attach build, submit for App Review.

### Xcode fallback

Product → Archive → Distribute App → App Store Connect → Upload.

## After both platforms

1. Backend already updated in macOS step 6. Sanity-check:

   ```bash
   curl -s https://api.miniti.app/appcast.xml | grep -E "shortVersionString|sparkle:version"
   ```

2. Commit + tag:

   ```bash
   git add -A
   git commit -m "Release vX.Y.Z"
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

## Pre-release checklist

- [ ] Version bumped everywhere (use `version-bump` skill): Info.plists, pbxproj `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`, `release_notes.txt`, `CHANGELOG.md`.
- [ ] `CHANGELOG.md` entry added (use `changelog` skill).
- [ ] `fastlane/metadata/en-US/release_notes.txt` + `en-GB` mirrored, iOS-scoped.
- [ ] `fastlane/metadata/copyright.txt` has current year.
- [ ] `fastlane/metadata/en-US/description.txt` version footer updated (+ `en-GB`).
- [ ] `fastlane/RUNBOOK.md` example commands updated.

## Key safety rules

- **Never ship if `release-info.sh` shows `[FAIL] app-sandbox entitlement MISSING`.** That's the v1.24.0 regression that wiped history for every user — see postmortem in [`docs/distribution.md`](../../../docs/distribution.md).
- **Never overwrite a versioned Netlify blob** (`miniti-X.Y.Z.dmg`) after release. Sparkle pins the signature to the exact bytes at that URL.
- **Never call `codesign --force --sign` on a bundle with entitlements without passing `--entitlements`** — silently strips them.

## Reference

- `RELEASE.md` — full 10-step checklist
- `docs/distribution.md` — Sparkle internals, key management, postmortems
- `fastlane/RUNBOOK.md` — detailed lane behaviour and parameters
- `scripts/build-dmg.sh` — requires `create-dmg` (auto-installed via Homebrew)
- `scripts/release-info.sh` — post-build sanity checks + appcast values
- StoreKit product: `com.miniti.mobile.pro.monthly` ($4.99/month)
- Export compliance: `ITSAppUsesNonExemptEncryption: NO` (HTTPS only, exempt)
