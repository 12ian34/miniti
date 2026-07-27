# Release Process

Authoritative 10-step runbook for shipping Miniti. For repo context, start with [AGENTS.md](AGENTS.md). For distribution detail, see [docs/distribution.md](docs/distribution.md). For per-lane detail, see [fastlane/RUNBOOK.md](fastlane/RUNBOOK.md).

## Before you start

- Clean `git status` (or only the release-related bumps are staged).
- `security find-identity -v -p codesigning` shows `Developer ID Application: ... (9AUR5U5KTF)`.
- `which sign_update` returns a path. If not, symlink the Sparkle tool:
  ```sh
  ln -sf ~/Library/Developer/Xcode/DerivedData/Miniti-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update /opt/homebrew/bin/sign_update
  ln -sf ~/Library/Developer/Xcode/DerivedData/Miniti-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys /opt/homebrew/bin/generate_keys
  ```
- `.env` at repo root has `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY`.

## The 10 steps

### 1. Bump version everywhere

Pick a new semver (`X.Y.Z`) and a monotonically-increasing build number (`N`). Every ship needs a new build number, even hotfixes — both Sparkle and App Store Connect compare build numbers, not semver.

Edit:

- `Miniti/Info.plist` — `CFBundleShortVersionString` → `X.Y.Z`, `CFBundleVersion` → `N`.
- `MinitiMobile/Info.plist` — `CFBundleShortVersionString` → `X.Y.Z`.
- `Miniti.xcodeproj/project.pbxproj` — `MARKETING_VERSION = X.Y.Z;` (6 places) and `CURRENT_PROJECT_VERSION = N;` (10 places). `CURRENT_PROJECT_VERSION` wins over `Info.plist` at build time; keep them in sync.
- `fastlane/metadata/en-US/release_notes.txt` — user-facing release notes for iOS. Also mirror to `en-GB/release_notes.txt`.
- `CHANGELOG.md` — prepend a new `### YYYY-MM-DD - vX.Y.Z` changelog entry.
- `fastlane/metadata/en-US/description.txt` + `en-GB/description.txt` — only if there's a literal `vX.Y.Z` footer; bump it.

Quick bulk update for MARKETING_VERSION and CURRENT_PROJECT_VERSION (adjust old→new):

```sh
sed -i '' 's/MARKETING_VERSION = OLD_VERSION;/MARKETING_VERSION = NEW_VERSION;/g' Miniti.xcodeproj/project.pbxproj
sed -i '' 's/CURRENT_PROJECT_VERSION = OLD_BUILD;/CURRENT_PROJECT_VERSION = NEW_BUILD;/g' Miniti.xcodeproj/project.pbxproj
```

### 2. Build, sign, notarize, package

```sh
fastlane mac release
```

This runs build → re-sign Sparkle framework (preserving entitlements) → verify entitlements → notarize → staple → DMG. Takes ~3–5 minutes.

If it aborts with "app-sandbox entitlement MISSING", the re-sign step stripped entitlements. Do not work around this — investigate. See the v1.24.0 postmortem in `docs/distribution.md`.

### 3. Verify and collect appcast values

```sh
bash scripts/release-info.sh
```

Confirm all sanity checks are `[ok]` (DMG stapling is an expected `[warn]`, tolerated). Copy the five appcast values for step 5.

### 4. Upload DMG to Netlify blobs

From the website repo (`../minitidotapp`):

```sh
netlify blobs:set downloads miniti-X.Y.Z.dmg --input ../miniti/miniti.dmg --force
netlify blobs:set downloads miniti.dmg --input ../miniti/miniti.dmg --force
```

For v1.25.0, run:

```sh
netlify blobs:set downloads miniti-1.25.0.dmg --input ../miniti/miniti.dmg --force; netlify blobs:set downloads miniti.dmg --input ../miniti/miniti.dmg --force
```

Both keys matter: `miniti.dmg` is the "latest" for the marketing site's download button; `miniti-X.Y.Z.dmg` is what Sparkle's appcast enclosure URL points to forever for this version.

### 5. Update backend

Tell the backend agent (or edit `miniti-api` directly):

```
- public/appcast.xml: add new <item> at the top with:
    sparkle:shortVersionString → X.Y.Z
    sparkle:version            → N
    length                     → <bytes from release-info.sh>
    sparkle:edSignature        → <base64 from release-info.sh>
    enclosure url              → https://miniti.app/dmg/miniti-X.Y.Z.dmg
  Keep prior <item>s (Sparkle renders "what's changed since your version" from them).

- app/api/version/route.ts:
    MACOS_LATEST_VERSION → X.Y.Z
    IOS_LATEST_VERSION   → X.Y.Z
    MACOS_RELEASE_NOTES  → (copy from fastlane/metadata/en-US/release_notes.txt)
    IOS_RELEASE_NOTES    → same
  Do not touch MACOS_MIN_VERSION / IOS_MIN_VERSION unless you're intentionally force-updating.

Deploy.
```

Only bump a platform's `*_LATEST_VERSION` once that platform's build is actually installable. The two ship independently — macOS goes live the moment the appcast is deployed, while iOS waits on App Review — so if only one platform shipped, leave the other on its previous version or you'll advertise an update nobody can install.

`app/api/version/route.test.ts` asserts the version strings and release notes as literals, so it fails until you update it alongside the constants. That's deliberate: it catches a half-finished bump. Run `npm test` in `miniti-api` before pushing, since a push to `main` is a production deploy.

Sanity-check once deployed:

```sh
curl -s https://api.miniti.app/appcast.xml | grep -E "shortVersionString|sparkle:version"
```

### 6. Re-verify the live URL matches local bytes

```sh
bash scripts/release-info.sh
```

The `URL matches local` line should now be `[ok]`, not `[warn]`.

### 7. Smoke-test Sparkle end-to-end

On a Mac running the previous version:

1. Launch Miniti.
2. **Miniti menu → Check for Updates…**
3. Expect: "A new version of Miniti is available!" dialog with release notes for X.Y.Z.
4. Click **Install Update** → download → verify → quit → install → relaunch.
5. About window shows X.Y.Z (build N). Meeting history and settings intact.

If Sparkle says "up to date" incorrectly: check `sparkle:version` in the appcast is strictly greater than the installed build number.

If Sparkle says "signature error": the public key in the installed app's `Info.plist` doesn't match the key that signed the DMG. Investigate; do not ship.

If Sparkle downloads the update but fails when quitting/installing with `Failed copying system domain rights: -60005`, the installed app is missing Sparkle's sandboxed installer-launcher setup. This cannot be fixed server-side for that already-installed build. Ship a fixed macOS DMG that includes `SUEnableInstallerLauncherService = true` plus the `com.miniti.app-spks` / `com.miniti.app-spki` mach lookup exceptions; affected users must install that DMG manually once, then Sparkle should work going forward.

### 8. iOS: upload + submit

```sh
fastlane ios release version:X.Y.Z
```

Uploads to App Store Connect with metadata. Then manually in App Store Connect:

1. Create/select the X.Y.Z version.
2. Attach the uploaded build.
3. Complete review info + screenshots (screenshots are managed manually in ASC, not via Fastlane).
4. Submit for review.

### 9. Commit + tag + push

```sh
git add -A
git commit -m "Release vX.Y.Z"
git tag vX.Y.Z
git push origin main vX.Y.Z
```

### 10. Cleanup (not blocking)

- Delete stale/broken blobs if any: `netlify blobs:delete downloads miniti-OLD.dmg`.
- If any release-process behavior changed during this ship, update [AGENTS.md](AGENTS.md), [docs/distribution.md](docs/distribution.md), and [fastlane/RUNBOOK.md](fastlane/RUNBOOK.md) if their guidance would otherwise go stale.

## Common failures and fixes

| Symptom | Fix |
|---|---|
| `fastlane mac release` aborts with "app-sandbox entitlement MISSING" | The Sparkle re-sign step stripped entitlements. Do NOT ship. See the v1.24.0 postmortem in `docs/distribution.md` — the `resign_sparkle_framework` lane must pass `--entitlements` when re-signing the outer app. |
| Notarization rejects Sparkle nested binaries | Sparkle framework's Updater.app / Autoupdate / XPC services weren't signed with Developer ID + timestamp. The `resign_sparkle_framework` lane handles this; confirm it ran. |
| Sparkle says "update improperly signed" | Public key in `Info.plist` doesn't match the signature on the DMG. Re-run `sign_update miniti.dmg`, redeploy appcast. |
| Sparkle says "up to date" when it shouldn't | `sparkle:version` in appcast ≤ installed build's `CFBundleVersion`. Bump and redeploy. |
| Sparkle downloads but fails install with `Failed copying system domain rights: -60005` | The installed sandboxed app lacks Sparkle's installer-launcher service setup. Server/appcast changes cannot repair that installed build. Ship a fixed DMG with `SUEnableInstallerLauncherService = true` and `com.miniti.app-spks` / `com.miniti.app-spki` mach lookup exceptions; affected users install it manually once. |
| "My history is wiped" after update | Sandbox entitlement was stripped → app points at a fresh non-sandboxed SwiftData store. Users' data is still at `~/Library/Containers/com.miniti.app/Data/...` — intact. Ship a hotfix that preserves entitlements. |
| `which sign_update` returns nothing | Symlink the Sparkle SPM tools — see "Before you start" above. |
| iOS `exportArchive No Accounts` / `No signing certificate "iOS Distribution" found` | The machine has no Apple Distribution certificate or Xcode account (both are lost in a Migration Assistant transfer). Sign into Xcode → Settings → Accounts and let it create the certificate. See `fastlane/RUNBOOK.md` § `fastlane ios release`. macOS releases are unaffected. |
| iOS build number ends up one ahead of the shipped macOS DMG | Both targets share `CURRENT_PROJECT_VERSION`, and the iOS lanes auto-increment it unless `build:N` is passed. Pass it explicitly when macOS shipped first. |
| DMG URL returns 404 | Netlify blob upload didn't happen, or the marketing site's `/dmg/*` route is misconfigured. |
| Build number in built app differs from `Info.plist` | `CURRENT_PROJECT_VERSION` in pbxproj wins. Update both in sync. |

## Key management

Do not lose the Sparkle private key. It lives in macOS Keychain (search "Sparkle", account `ed25519`) on the release machine. Back up to 1Password:

```sh
generate_keys -x ~/miniti-sparkle-private.pem
# store the .pem in 1Password, then delete the local file
```

Losing the key means you cannot ship Sparkle updates to already-installed clients — because the public key baked into those installations would no longer match your signatures. Recovery would require shipping a new non-Sparkle DMG with a new public key and waiting for every user to migrate manually. Don't let it come to that.
