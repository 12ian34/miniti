# Fastlane for Miniti iOS

This Fastlane setup is only for the iOS target `MinitiMobile`.

It uses:
- the project root `.env`
- your existing Xcode Apple account / automatic signing setup
- App Store Connect API key credentials already stored in the root `.env`

## Required root `.env` keys

```sh
APP_STORE_CONNECT_KEY_ID=...
APP_STORE_CONNECT_ISSUER_ID=...
APP_STORE_CONNECT_API_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
```

The inline private key is expected to use escaped `\n`. Fastlane converts that into real newlines automatically.

## Before using Fastlane

Check this once in Xcode:
- Xcode -> Settings -> Accounts: signed into the Apple account that owns team `9AUR5U5KTF`
- target `MinitiMobile`: automatic signing enabled, team `9AUR5U5KTF`
- target `MinitiLiveActivityExtension`: automatic signing enabled, team `9AUR5U5KTF`
- if Xcode shows **Fix Issue**, resolve that first

If Xcode Organizer can archive/upload this iOS app on this Mac, Fastlane should be able to use that same signing state.

## Commands

### `fastlane lanes`

Lists the available lanes.

### `fastlane ios build`

Purpose:
- validate the local archive/export flow without uploading anything

What it does:
- loads the root `.env`
- builds project `Miniti.xcodeproj`
- uses scheme `MinitiMobile`
- uses configuration `Release`
- enables Xcode-managed signing with `-allowProvisioningUpdates`
- writes derived data to `DerivedDataLocal/`
- exports `build/ios/MinitiMobile.ipa`

What it does not do:
- does not change marketing version
- does not change build number
- does not upload anything

### `fastlane ios beta`

Purpose:
- build and upload to TestFlight

Examples:

```sh
fastlane ios beta version:1.12.4
fastlane ios beta version:1.12.4 build:3
fastlane ios beta version:1.12.4 changelog:"fixes recording resume bug"
```

What it does:
- sets `MARKETING_VERSION` if `version:` is provided
- increments `CURRENT_PROJECT_VERSION` by 1 unless `build:` is provided
- builds the archive and exports the IPA
- uploads the IPA to TestFlight
- sends TestFlight release notes if `changelog:` is provided

What it does not do:
- does not add testers to groups
- does not submit external TestFlight review
- does not upload screenshots
- does not upload App Store metadata

### `fastlane ios release`

Purpose:
- build and upload the binary to App Store Connect for App Store release prep

Examples:

```sh
fastlane ios release version:1.12.4
fastlane ios release version:1.12.4 build:3
```

What it does:
- sets `MARKETING_VERSION` if `version:` is provided
- increments `CURRENT_PROJECT_VERSION` by 1 unless `build:` is provided
- builds the archive and exports the IPA
- uploads the IPA to App Store Connect

What it does not do:
- does not upload metadata
- does not upload screenshots
- does not submit for App Review
- does not auto-release the app

After `fastlane ios release`, finish manually in App Store Connect:
- create/select the app version
- attach the uploaded build
- complete review information and screenshots if needed
- submit for review

## Recommended flows

### TestFlight release flow

```sh
fastlane ios build
fastlane ios beta version:1.12.4 changelog:"release notes here"
```

Then in App Store Connect:
- wait for processing
- add the build to the right testing group
- submit for external TestFlight review if needed

### App Store upload flow

```sh
fastlane ios build
fastlane ios release version:1.12.4
```

Then in App Store Connect:
- wait for processing
- create/select the app version
- attach the build
- complete metadata / review info
- submit for App Review

## Not set up here

These Fastlane areas are intentionally not configured in this repo:
- `match`
- certificate/profile management
- screenshot automation
- metadata sync
- automatic App Review submission
- automatic App Store release

This setup is intentionally narrow: it wraps the existing Xcode-managed signing and App Store upload process instead of replacing it.
