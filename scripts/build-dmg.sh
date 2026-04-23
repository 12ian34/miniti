#!/usr/bin/env bash
#
# build-dmg.sh — Package a notarized miniti.app into a distributable DMG.
#
# Usage:
#   ./scripts/build-dmg.sh /path/to/notarized/miniti.app
#
# Prerequisites:
#   - Homebrew installed
#   - create-dmg (installed automatically if missing)
#   - The .app must already be signed & notarized via Xcode
#
# Output:
#   miniti.dmg in the repo root

set -euo pipefail

# ─── Resolve paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
    echo "Usage: $0 /path/to/notarized/miniti.app"
    exit 1
fi

# Resolve to absolute path
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: $APP_PATH does not exist or is not a directory."
    exit 1
fi

APP_NAME="$(basename "$APP_PATH" .app)"

# ─── Extract version from the app's Info.plist ──────────────────────────────
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
echo "App: ${APP_NAME}.app  Version: $VERSION"

# ─── Validate code signing ──────────────────────────────────────────────────
echo ""
echo "Validating code signature..."
if ! codesign --verify --deep --strict "$APP_PATH" 2>&1; then
    echo "Error: Code signature verification failed."
    echo "Make sure the app is properly signed before creating the DMG."
    exit 1
fi
echo "  Code signature: OK"

echo "Checking notarization..."
if spctl --assess --type execute "$APP_PATH" 2>&1; then
    echo "  Notarization: OK"
else
    echo "  Warning: spctl assessment failed. The app may not be notarized."
    echo "  The DMG will still be created, but users may see Gatekeeper warnings."
    read -p "  Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ─── Ensure create-dmg is installed ─────────────────────────────────────────
if ! command -v create-dmg &>/dev/null; then
    echo ""
    echo "Installing create-dmg via Homebrew..."
    brew install create-dmg
fi

# ─── Prepare staging directory ──────────────────────────────────────────────
# create-dmg works best with a source folder (not a bare .app).
STAGING_DIR=$(mktemp -d)
trap "rm -rf '$STAGING_DIR'" EXIT

echo ""
echo "Preparing staging directory..."
cp -R "$APP_PATH" "$STAGING_DIR/miniti.app"

# ─── Resolve assets ─────────────────────────────────────────────────────────
ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ ! -f "$ICON_PATH" ]]; then
    echo "Warning: AppIcon.icns not found at $ICON_PATH"
    ICON_PATH=""
fi

BACKGROUND_PATH="$SCRIPT_DIR/dmg-background.png"
if [[ ! -f "$BACKGROUND_PATH" ]]; then
    echo "Warning: dmg-background.png not found at $BACKGROUND_PATH"
    BACKGROUND_PATH=""
fi

# ─── Build the DMG ──────────────────────────────────────────────────────────
DMG_NAME="miniti.dmg"
DMG_PATH="$REPO_ROOT/$DMG_NAME"

# Remove existing DMG if present (create-dmg won't overwrite)
rm -f "$DMG_PATH"

echo ""
echo "Creating $DMG_NAME..."

CREATE_DMG_ARGS=(
    --volname "miniti"
    --window-pos 200 120
    --window-size 600 400
    --icon-size 128
    --icon "miniti.app" 180 190
    --app-drop-link 420 190
    --hide-extension "miniti.app"
    --no-internet-enable
)

if [[ -n "$ICON_PATH" ]]; then
    CREATE_DMG_ARGS+=(--volicon "$ICON_PATH")
fi

if [[ -n "$BACKGROUND_PATH" ]]; then
    CREATE_DMG_ARGS+=(--background "$BACKGROUND_PATH")
fi

create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$STAGING_DIR"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: DMG creation failed — $DMG_PATH not found."
    exit 1
fi

# ─── Staple the notarization ticket to the DMG ──────────────────────────────
echo ""
echo "Stapling notarization ticket to DMG..."
if xcrun stapler staple "$DMG_PATH" 2>&1; then
    echo "  Staple: OK"
else
    echo "  Warning: Stapling failed. This is expected if the app was not notarized."
fi

# ─── Final verification ─────────────────────────────────────────────────────
echo ""
echo "Verifying DMG..."
if spctl --assess --type open --context context:primary-signature "$DMG_PATH" 2>&1; then
    echo "  DMG verification: OK"
else
    echo "  Warning: DMG verification returned non-zero (may be fine for non-notarized builds)."
fi

# ─── Sparkle EdDSA signature (for appcast) ──────────────────────────────────
# If Sparkle's `sign_update` is on PATH, emit the EdDSA signature + byte length
# needed for the appcast enclosure. The private key must be in Keychain (set up
# once via `generate_keys`).
echo ""
if command -v sign_update &>/dev/null; then
    echo "Generating Sparkle signature..."
    SIGN_OUTPUT=$(sign_update "$DMG_PATH" 2>&1 || true)
    if [[ -n "$SIGN_OUTPUT" ]]; then
        echo "  $SIGN_OUTPUT"
        echo ""
        echo "  Paste the above attributes into the appcast enclosure, e.g.:"
        echo "    <enclosure url=\"https://miniti.app/dmg/miniti-${VERSION}.dmg\""
        echo "               $SIGN_OUTPUT"
        echo "               type=\"application/octet-stream\" />"
    else
        echo "  Warning: sign_update produced no output — skipping Sparkle signature."
    fi
else
    echo "Note: Sparkle's sign_update not on PATH — skipping appcast signature generation."
    echo "      Install with: brew install --cask sparkle  (or use the SPM-vendored binary)"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | xargs)
DMG_SIZE_BYTES=$(stat -f%z "$DMG_PATH" 2>/dev/null || wc -c < "$DMG_PATH" | xargs)
echo ""
echo "================================================"
echo "  DMG created successfully!"
echo "  File: $DMG_PATH"
echo "  Size: $DMG_SIZE ($DMG_SIZE_BYTES bytes)"
echo "  Version: $VERSION"
echo "  Contents: miniti.app"
echo "================================================"
