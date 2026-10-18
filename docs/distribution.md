# Distribution

Background / architecture for how Miniti ships. For the hands-on release checklist, see [../RELEASE.md](../RELEASE.md). For per-lane fastlane detail, see [../fastlane/RUNBOOK.md](../fastlane/RUNBOOK.md).

## macOS

Direct notarized distribution via DMG (not Mac App Store). The app ships **sandboxed** with `com.apple.security.app-sandbox` + `com.apple.security.device.audio-input` + `com.apple.security.network.client` + `com.apple.security.files.user-selected.read-write`. `AudioHardwareCreateProcessTap` works inside this sandbox given the audio-input entitlement and a valid `NSAudioCaptureUsageDescription`. Meeting data lives at `~/Library/Containers/com.miniti.app/Data/Library/Application Support/default.store`.

From 2.10.0 the app bundle carries the Nemotron-3 diarization model (about 190 MB under `Contents/Resources/NemotronDiarizer`, fetched at build time by `scripts/fetch-nemotron-model.sh`), so DMGs and Sparkle downloads are that much larger. Auto-update is handled by **Sparkle 2.9.5 or newer within the 2.x line** (SPM dep, macOS target only). The app embeds an EdDSA public key (`SUPublicEDKey` in `Info.plist`) and polls `https://api.miniti.app/appcast.xml` once every 24h (`SUScheduledCheckInterval = 86400`) and on launch. On a newer `sparkle:version` in the feed, Sparkle downloads the DMG, verifies the EdDSA signature against the embedded public key, quits the running app, installs in place, and relaunches. Because Miniti is sandboxed, `Info.plist` must include `SUEnableInstallerLauncherService = true`, and `Miniti.entitlements` must allow mach lookup for `com.miniti.app-spks` and `com.miniti.app-spki`. "Check for Updates…" lives under the Miniti menu (`CommandGroup(after: .appInfo)`), guarded by `#if canImport(Sparkle)` so the app still builds if the dep is ever missing.

## iOS (MinitiMobile)

- Bundle ID: `com.miniti.mobile`, deployment target iOS 17.0
- Distribution: App Store (no sandbox restrictions for mic-only recording)
- In-app purchase: StoreKit 2 auto-renewable subscription product `com.miniti.mobile.pro.monthly` (`$4.99/month`)
- Background audio: `UIBackgroundModes: [audio]` + `AVAudioSession` category `.playAndRecord` enables recording while backgrounded
- Live Activity: `MinitiLiveActivityExtension` widget extension (bundle ID: `com.miniti.mobile.live-activity`), embedded in MinitiMobile via "Embed App Extensions" build phase. Shows recording on Dynamic Island + Lock Screen, redacts transcript text when the user disables it, and returns to the active meeting through the app's `miniti://meeting/<UUID>` URL scheme.
- No system audio capture — iOS sandbox prevents it entirely
- Export compliance: `ITSAppUsesNonExemptEncryption: NO` in Info.plist — app only uses HTTPS (OS-provided TLS), which is exempt. This key bypasses the App Store Connect encryption compliance dialog and unblocks TestFlight distribution.
- Xcode targets: `Miniti` (macOS app) + `MinitiMobile` (iOS app) + `MinitiLiveActivityExtension` (widget extension) + `MinitiTests` (XCTest, macOS host) + `MinitiMobileTests` (XCTest, iOS host)

## Release scripts

### `scripts/build-dmg.sh`

- Tracked in git (not gitignored) — safe because `scripts/` is not referenced in `project.pbxproj`, so Xcode Cloud ignores it entirely
- Requires `create-dmg` (auto-installed via Homebrew if missing)
- Validates the app's code signature and notarization before packaging
- Creates a drag-to-Applications DMG (miniti.app on the left, Applications symlink on the right)
- Version extracted from the app's `Info.plist` (for display only — output filename is always `miniti.dmg`)
- Background image: `scripts/dmg-background.png`; volume icon pulled from app's `AppIcon.icns`
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

macOS DMGs are stored in Netlify Blobs under the `downloads` store, two keys per release:

- `miniti.dmg` — the "latest" DMG for the marketing site's download-now button.
- `miniti-X.Y.Z.dmg` — the versioned DMG. Sparkle's appcast `<enclosure url>` points at `https://miniti.app/dmg/miniti-X.Y.Z.dmg` for each release. Pinned forever for that version, because Sparkle verifies the signature against the exact bytes at that URL.

The marketing site's `/dmg/*` route resolves to the versioned blob. Never overwrite a versioned blob post-release — once an appcast `<item>` is live, that URL must return the exact bytes that were signed.

All website functions that serve DMGs use Netlify's modern `Request`/`Response` API with a Blob-backed stream. Keep them streamed: classic function responses base64-encode binary data, making Netlify's 6 MB buffered limit effectively about 4.5 MB and returning 502 for larger release artifacts.

Upload pattern (from the website repo, `../minitidotapp`):

```sh
netlify blobs:set downloads miniti-X.Y.Z.dmg --input ../miniti/miniti.dmg --force
netlify blobs:set downloads miniti.dmg --input ../miniti/miniti.dmg --force
```

For v1.25.0 specifically: `netlify blobs:set downloads miniti-1.25.0.dmg --input ../miniti/miniti.dmg --force; netlify blobs:set downloads miniti.dmg --input ../miniti/miniti.dmg --force`

## How `/api/version` coexists with Sparkle

Sparkle is the primary update UX on macOS. `/api/version` stays around because:

- **iOS has no Sparkle** — the blue home-screen banner reads from `/api/version` and deep-links to the App Store.
- **Force-update gate** — setting `MACOS_MIN_VERSION` / `IOS_MIN_VERSION` hard-blocks older clients via `ForceUpdateView`. Sparkle can only offer updates, not force them.
- **Belt-and-braces for macOS** — even on macOS the blue banner fires from `/api/version` as a fallback if Sparkle ever fails silently for a user (stale appcast, network issue, signature mismatch).

Every release bumps `/api/version` constants AND appends to `public/appcast.xml`. They're kept in lockstep.

## Postmortem: v1.24.0 — "my history is wiped" (resolved in v1.24.1)

What happened: v1.24.0 was the first release to bundle the Sparkle framework. Notarization failed because Sparkle's nested binaries (Updater.app, Autoupdate, Downloader.xpc, Installer.xpc) weren't signed with Developer ID + secure timestamp. The fix — a `resign_sparkle_framework` lane that re-signs deepest-first — also re-signed the outer `miniti.app` with `codesign --force --sign` but **without `--entitlements`**. That silently stripped the app's sandbox entitlements, shipping a non-sandboxed build. macOS saw a different "app identity" than v1.23.1 and spun up a fresh non-sandboxed SwiftData store at `~/Library/Application Support/default.store` (empty), while the real 4.4MB history sat untouched in the sandboxed container at `~/Library/Containers/com.miniti.app/Data/...`.

The `Miniti.entitlements` file on disk was correct throughout. `ENABLE_APP_SANDBOX = YES` in pbxproj has been correct since the initial commit. The bug lived entirely inside the release-script re-sign step.

Fixes landed:

- `resign_sparkle_framework` now passes `--entitlements Miniti/Miniti.entitlements` when re-signing the outer app, preserving sandbox + mic + network + user-files entitlements.
- `verify_mac_signing_for_notarization` now fails with a clear message if `com.apple.security.app-sandbox` is missing from the signed app. Runs before `notarize` so a broken build never even reaches Apple.
- `scripts/release-info.sh` re-verifies the sandbox entitlement in the final DMG — belt-and-braces in case the fastlane guard ever drifts.

Takeaway for future Sparkle-adjacent changes: **never call `codesign --force --sign` on a bundle that has entitlements without also passing `--entitlements`**. It silently strips them. And never trust "this bug exists only in my uncommitted changes" — the pbxproj setting was there all along; the signed binary differed from the source-controlled entitlements file because the release script was overriding them at export time.
