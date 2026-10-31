#!/usr/bin/env bash
#
# build-dmg.sh — Package a notarized miniti.app into a DMG ready for notarization.
#
# Usage:
#   ./scripts/build-dmg.sh /path/to/notarized/miniti.app [output.dmg]
#
# Prerequisites:
#   - Homebrew installed
#   - create-dmg (installed automatically if missing)
#   - The .app must already be signed and notarized
#
# Output:
#   miniti.dmg in the repo root, or the optional output path for a local preview

set -euo pipefail

# ─── Resolve paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
    echo "Usage: $0 /path/to/notarized/miniti.app [output.dmg]"
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
ARTWORK_DIR=$(mktemp -d)
trap "rm -rf '$STAGING_DIR' '$ARTWORK_DIR'" EXIT

echo ""
echo "Preparing staging directory..."
cp -R "$APP_PATH" "$STAGING_DIR/miniti.app"

# ─── Resolve assets ─────────────────────────────────────────────────────────
ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ ! -f "$ICON_PATH" ]]; then
    echo "Warning: AppIcon.icns not found at $ICON_PATH"
    ICON_PATH=""
fi

# The source is 1200x800 at 144 dpi: a 600x400-point Retina background.
# A multi-resolution TIFF lets Finder pick 1x or 2x without changing its layout.
BACKGROUND_SOURCE="$SCRIPT_DIR/dmg-background.png"
BACKGROUND_PATH=""
if [[ -f "$BACKGROUND_SOURCE" ]]; then
    sips --resampleHeightWidth 400 600 --setProperty dpiWidth 72 --setProperty dpiHeight 72 \
        --setProperty format tiff "$BACKGROUND_SOURCE" --out "$ARTWORK_DIR/background.tiff" >/dev/null
    sips --setProperty format tiff "$BACKGROUND_SOURCE" --out "$ARTWORK_DIR/background@2x.tiff" >/dev/null
    BACKGROUND_PATH="$ARTWORK_DIR/dmg-background.tiff"
    tiffutil -cathidpicheck "$ARTWORK_DIR/background.tiff" "$ARTWORK_DIR/background@2x.tiff" \
        -out "$BACKGROUND_PATH"
else
    echo "Warning: dmg-background.png not found at $BACKGROUND_SOURCE"
fi

# ─── Build the DMG ──────────────────────────────────────────────────────────
DMG_PATH="${2:-$REPO_ROOT/miniti.dmg}"
DMG_NAME="$(basename "$DMG_PATH")"

# Remove existing DMG if present (create-dmg won't overwrite)
rm -f "$DMG_PATH"

echo ""
echo "Creating $DMG_NAME..."

# The background has light label plates centered at (205, 286) and (395, 286).
# Finder draws black labels below the 128pt icons even on dark image backgrounds.
CREATE_DMG_ARGS=(
    --volname "miniti"
    --window-pos 200 120
    --window-size 600 480
    --icon-size 128
    --icon "miniti.app" 205 201
    --app-drop-link 395 201
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
echo "  Next: notarize and staple this DMG, then generate its Sparkle signature"
echo "================================================"
