# Distribution

Background / architecture for how Miniti ships. For the hands-on release checklist, see [../RELEASE.md](../../RELEASE.md). For per-lane fastlane detail, see [../fastlane/RUNBOOK.md](../../fastlane/RUNBOOK.md).

## macOS

Direct notarized distribution via DMG (not Mac App Store). The app ships **sandboxed** with `com.apple.security.app-sandbox` + `com.apple.security.device.audio-input` + `com.apple.security.network.client` + `com.apple.security.files.user-selected.read-write`. `AudioHardwareCreateProcessTap` works inside this sandbox given the audio-input entitlement and a valid `NSAudioCaptureUsageDescription`. Meeting data lives at `~/Library/Containers/com.miniti.app/Data/Library/Application Support/default.store`.

From 2.10.0 the app bundle carries the Nemotron-3 diarization model (about 190 MB under `Contents/Resources/NemotronDiarizer`, fetched at build time by `scripts/fetch-nemotron-model.sh`), so DMGs and Sparkle downloads are that much larger. Auto-update is handled by **Sparkle 2.9.5 or newer within the 2.x line** (SPM dep, macOS target only). The app embeds an EdDSA public key (`SUPublicEDKey` in `Info.plist`) and polls `https://api.miniti.app/appcast.xml` once every 24h (`SUScheduledCheckInterval = 86400`) and on launch. On a newer `sparkle:version` in the feed, Sparkle downloads the DMG, verifies the EdDSA signature against the embedded public key, quits the running app, installs in place, and relaunches. Because Miniti is sandboxed, `Info.plist` must include `SUEnableInstallerLauncherService = true`, and `Miniti.entitlements` must allow mach lookup for `com.miniti.app-spks` and `com.miniti.app-spki`. "Check for Updates…" lives under the Miniti menu (`CommandGroup(after: .appInfo)`), guarded by `#if canImport(Sparkle)` so the app still builds if the dep is ever missing.

## iOS (MinitiMobile)

- Bundle ID: `com.miniti.mobile`, deployment target iOS 17.0
- Distribution: App Store; microphone permission and the iOS sandbox/background-audio rules still apply
- In-app purchase: StoreKit 2 auto-renewable subscription product `com.miniti.mobile.pro.monthly` (`$4.99/month`)
- Background audio: `UIBackgroundModes: [audio]` + `AVAudioSession` category `.playAndRecord` enables recording while backgrounded
- Live Activity: `MinitiLiveActivityExtension` widget extension (bundle ID: `com.miniti.mobile.live-activity`), embedded in MinitiMobile via "Embed App Extensions" build phase. Shows recording on Dynamic Island + Lock Screen, redacts transcript text when the user disables it, and returns to the active meeting through the app's `miniti://meeting/<UUID>` URL scheme.
- No system audio capture — iOS sandbox prevents it entirely
- Export compliance: `ITSAppUsesNonExemptEncryption: NO` in Info.plist — the app declares no non-exempt encryption. Preserve the declaration only while it matches the shipped capabilities; device-bound signing also uses system cryptography. This flag is not a substitute for checking changes at release.
- Xcode targets: `Miniti` (macOS app) + `MinitiMobile` (iOS app) + `MinitiLiveActivityExtension` (widget extension) + `MinitiWatch` (embedded watchOS companion) + `MinitiTests` (XCTest, macOS host) + `MinitiMobileTests` (XCTest, iOS host)

## Release scripts

### `scripts/build-dmg.sh`

- Tracked in git (not gitignored) — safe because `scripts/` is not referenced in `project.pbxproj`, so Xcode Cloud ignores it entirely
- Requires `create-dmg` (auto-installed via Homebrew if missing)
- Validates the app's code signature and notarization before packaging
- Creates a drag-to-Applications DMG (miniti.app on the left, Applications symlink on the right)
- Version extracted from the app's `Info.plist` for display. Output defaults to root `miniti.dmg`; an optional second argument selects a separate preview path.
- Background source: `scripts/dmg-background.png`, 1200×800 pixels at 144 dpi for a 600×400-point layout. The builder creates a multi-resolution TIFF with 600×400 / 72 dpi and 1200×800 / 144 dpi representations, checked by `tiffutil -cathidpicheck`, so Finder can render at native 1× or 2× resolution. Keep the two label plates aligned with the icon positions in the script. Volume icon comes from the app's `AppIcon.icns`.
- Leaves DMG notarization and Sparkle signing to Fastlane so the byte-mutating operations stay in the required order.

### Fastlane DMG finalization

- `fastlane mac dmg` and `fastlane mac release` sign the completed DMG with the Developer ID Application identity, submit it to Apple's notary service, staple the returned ticket, and fail unless both `stapler validate` and Gatekeeper's disk-image assessment succeed.
- Only after stapling does Fastlane call Sparkle's `sign_update`, ensuring the appcast signature covers the final published bytes. A missing tool or invalid/empty signature is release-blocking.

### `scripts/release-info.sh`

- Run after `fastlane mac release` succeeds.
- Prints the five appcast values (`sparkle:shortVersionString`, `sparkle:version`, `length`, `sparkle:edSignature`, `enclosure url`) ready to paste to the backend.
- Sanity checks the build before ship:
  - `[ok] app-sandbox entitlement present` — catches the "history wiped" regression. If this fails, the re-sign step stripped entitlements; do not ship.
  - `[ok] nested code signatures valid` — `codesign --deep --strict` covering Sparkle's Updater.app/Autoupdate/XPC services.
  - `[ok] DMG notarization stapled` — a release-blocking failure if the final disk image has no valid stapled ticket.
  - `[ok] URL matches local (N bytes)` — checks `https://miniti.app/dmg/miniti-X.Y.Z.dmg` against the local DMG. If the streamed response omits `Content-Length`, the script downloads it and counts the body instead. Catches upload mismatches before backend deploy.
- If any `[FAIL]` prints, stop the ship and diagnose.

## Sparkle key management (one-time setup + ongoing)

- Private key lives in **macOS Keychain** on the release machine (search "Sparkle" in Keychain Access; entry is `https://sparkle-project.org`, account `ed25519`).
- Public key (base64) is in `Miniti/Info.plist` as `SUPublicEDKey`. Every build ships with this key embedded; changing it means users can't verify updates signed with a different private key.
- **Back up the private key in 1Password** (or equivalent). Lose it → cannot ship Sparkle updates to installed clients anymore, because a new keypair means the `SUPublicEDKey` embedded in already-shipped apps no longer matches your signatures. Only fix would be shipping a new non-Sparkle DMG with a new public key and waiting for all users to migrate.
- Export to PEM once for backup: `generate_keys -x ~/miniti-sparkle-private.pem`. Store securely, delete local copy.
- The Sparkle `generate_keys` / `sign_update` CLI tools ship inside the Sparkle SPM checkout at `~/Library/Developer/Xcode/DerivedData/Miniti-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`. Symlink both onto `/opt/homebrew/bin/` (Apple Silicon) or `/usr/local/bin/` (Intel) so `sign_update` is discoverable by Fastlane's DMG finalization step. DerivedData paths change when Xcode regenerates them — symlink can go stale; redo if `which sign_update` returns nothing.

## Sandboxed Sparkle installer services

Sparkle's sandboxed installation flow is configured in the running app, not the server. Miniti must ship with:

- `Miniti/Info.plist`: `SUEnableInstallerLauncherService = true`
- `Miniti/Miniti.entitlements`: `com.apple.security.temporary-exception.mach-lookup.global-name` containing `com.miniti.app-spks` and `com.miniti.app-spki`

If either piece is missing, Sparkle can still find, download, and verify an update, but installation fails when the running app quits with `Failed copying system domain rights: -60005`. Backend/appcast changes cannot repair the already-installed app because the missing launcher entitlement has to be present in the app that is invoking Sparkle. Recovery is to ship a fixed macOS DMG and have affected users install it manually once; future updates from that fixed build should work through Sparkle again.

Miniti's bundle identifier ends in `.app`. Sparkle 2.9.1 incorrectly used that identifier as the final component of its cache path; on current macOS versions this can be treated as an application bundle and trigger “Miniti was prevented from modifying apps on your computer” on the first update attempt. Sparkle fixed the cache collision in 2.9.3 ([upstream discussion](https://github.com/sparkle-project/Sparkle/discussions/2881), [fix](https://github.com/sparkle-project/Sparkle/pull/2882)); Miniti pins 2.9.5. Do not downgrade below 2.9.3 or change the stable app bundle ID as a workaround. Remember that the installed app supplies the updater: a user moving from a 2.9.1-based Miniti build to the first fixed build may still see the old first-attempt failure once, then succeed on retry. Updates launched after the fixed build is installed use the corrected cache path.

## DMG hosting

Since 2.10.0, current DMGs are GitHub release assets in `12ian34/miniti`. The website's `/dmg/*` and latest-download routes redirect to them through `EXTERNAL_DMG_URLS` and `LATEST_DMG_VERSION` in `../minitidotapp/netlify/functions/_download.mjs`. Sparkle uses the immutable versioned GitHub asset URL. See [RELEASE.md step 4](../../RELEASE.md#4-publish-the-dmg-as-a-github-release-asset) for naming and publication commands.

Legacy smaller DMGs may remain in Netlify Blobs under `downloads`, with versioned keys and a historical `miniti.dmg` latest key. This is not the current upload path: large bundled-model DMGs exceeded the function streaming window. Never overwrite bytes referenced by a published Sparkle signature. Verify both the direct asset and website redirect against the final signed local bytes.

## How `/api/version` coexists with Sparkle

Sparkle is the normal macOS update UI; iOS uses the App Store. Normal updates do not appear as Home banners. `/api/version` retains the per-platform minimum-version gate: below-minimum clients receive the real latest version and show `ForceUpdateView`, while supported clients receive their own version to suppress the removed optional banner.

Backend constants live in `miniti-api/lib/releaseMetadata.ts`. Advance each platform's latest version only when that build is installable. Mac appcast publication and iOS App Store availability are independent; Linux has its own release line. Do not advance minimum versions unless explicitly selecting a forced update. See [release step 5](../../RELEASE.md#5-update-backend).

## Postmortem: v1.24.0 — "my history is wiped" (resolved in v1.24.1)

What happened: v1.24.0 was the first release to bundle the Sparkle framework. Notarization failed because Sparkle's nested binaries (Updater.app, Autoupdate, Downloader.xpc, Installer.xpc) weren't signed with Developer ID + secure timestamp. The fix — a `resign_sparkle_framework` lane that re-signs deepest-first — also re-signed the outer `miniti.app` with `codesign --force --sign` but **without `--entitlements`**. That silently stripped the app's sandbox entitlements, shipping a non-sandboxed build. macOS saw a different "app identity" than v1.23.1 and spun up a fresh non-sandboxed SwiftData store at `~/Library/Application Support/default.store` (empty), while the real 4.4MB history sat untouched in the sandboxed container at `~/Library/Containers/com.miniti.app/Data/...`.

The `Miniti.entitlements` file on disk was correct throughout. `ENABLE_APP_SANDBOX = YES` in pbxproj has been correct since the initial commit. The bug lived entirely inside the release-script re-sign step.

Fixes landed:

- `resign_sparkle_framework` now passes `--entitlements Miniti/Miniti.entitlements` when re-signing the outer app, preserving sandbox + mic + network + user-files entitlements.
- `verify_mac_signing_for_notarization` now fails with a clear message if `com.apple.security.app-sandbox` is missing from the signed app. Runs before `notarize` so a broken build never even reaches Apple.
- `scripts/release-info.sh` re-verifies the sandbox entitlement in the final DMG — belt-and-braces in case the fastlane guard ever drifts.

Takeaway for future Sparkle-adjacent changes: **never call `codesign --force --sign` on a bundle that has entitlements without also passing `--entitlements`**. It silently strips them. And never trust "this bug exists only in my uncommitted changes" — the pbxproj setting was there all along; the signed binary differed from the source-controlled entitlements file because the release script was overriding them at export time.

## Postmortem: v3.2.1 — "miniti forgot my account" (resolved in v3.3.0)

What happened: 3.2.1 moved the managed credential and the device id (`com.miniti.device-auth`, `com.miniti.device-id`) into the data protection keychain (`kSecUseDataProtectionKeychain`) to stop the Keychain permission dialog the Debug test host put up after every release. On macOS that keychain needs the `com.apple.application-identifier` entitlement, which a Developer ID build only gets from an embedded provisioning profile. miniti's release build has none (and neither does the Debug host), so every `SecItemAdd` there failed with `errSecMissingEntitlement` (-34018) while reads answered `errSecItemNotFound`. The device id migration deleted the login-keychain item **before** the new add, so the first launch of 3.2.1 ran on the old id from memory and destroyed its only copy; the second launch found nothing, minted a fresh id, and the server answered every call `device_mismatch` because the saved access token names the old one. From the person's seat: no account, no Pro, no cloud, no calendar, and "join by email" also failing with 401. The credential itself survived in the login keychain (3.2.1 never managed to write it anywhere).

Why tests did not catch it: the storage layer called Security.framework directly, so the unit tests covered only the pure `resolution(afterReadStatus:hasFallback:)` decision; the manual check ran the first launch only, which works.

Fixes landed in 3.3.0:

- `KeychainSlot` (`DeviceIdentifier.swift`) is the one storage policy for both items: data protection keychain first, login keychain on macOS when it refuses, update in place, nothing deleted until the replacement is written. The `KeychainBackend` protocol makes it testable against `FakeKeychain` in `ClientAuthTests`, which models the no-entitlement build.
- `ClientAuthManager.reconcileDeviceIdentity()` runs when the manager loads: the access token is a JWT whose `sub` is the device id the server bound this installation key to, so if the Keychain device id disagrees, `DeviceIdentifier.adopt` restores the token's id before any request goes out. This is what heals every Mac that already ran 3.2.1 twice.
- Updating in place keeps the item's access list, so the Debug host's Always Allow now sticks across token refreshes, which was the original itch.

Takeaways: a Keychain migration must add first and delete only on success; `-34018` on macOS means a missing entitlement, not a locked keychain; and a second-launch check belongs in the manual matrix for anything touching identity storage. Using the data protection keychain for real would need a Developer ID provisioning profile in the release build (and the Debug host), a deliberate change to the signing setup, not a side effect.
