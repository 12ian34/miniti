fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios test

```sh
[bundle exec] fastlane ios test
```

Run MinitiMobileTests unit tests on iOS Simulator

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the current iOS release archive locally

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Bump build/version if needed, build, and upload to TestFlight

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload metadata only (no screenshots, no binary).

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Upload screenshots only (no metadata, no binary). Reads from fastlane/screenshots.

### ios release

```sh
[bundle exec] fastlane ios release
```

Bump build/version if needed, build, and upload to App Store Connect with metadata/screenshots without auto-submitting

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Attach an uploaded build and submit it for App Review with automatic release

----


## Mac

### mac test

```sh
[bundle exec] fastlane mac test
```

Run MinitiTests unit tests

### mac build

```sh
[bundle exec] fastlane mac build
```

Build the current macOS Developer ID export locally

### mac notarize_app

```sh
[bundle exec] fastlane mac notarize_app
```

Notarize the exported macOS app in build/macos/miniti.app

### mac dmg

```sh
[bundle exec] fastlane mac dmg
```

Build, notarize, staple, and Sparkle-sign a DMG from a notarized macOS app

### mac release

```sh
[bundle exec] fastlane mac release
```

Build and notarize the macOS app, then package, notarize, and Sparkle-sign miniti.dmg

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
