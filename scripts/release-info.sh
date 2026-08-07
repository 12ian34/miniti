#!/usr/bin/env bash
# Run from repo root after `fastlane mac release` succeeds.
# Prints appcast values + sanity checks for the newly built DMG.

set -u

APP="$PWD/miniti.app"
DMG="$PWD/miniti.dmg"

if [[ ! -d "$APP" ]]; then
    echo "ERROR: $APP not found. Run 'fastlane mac release' first."
    exit 1
fi
if [[ ! -f "$DMG" ]]; then
    echo "ERROR: $DMG not found. Run 'fastlane mac release' first."
    exit 1
fi

SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
BYTES=$(stat -f%z "$DMG")
SIG=$(sign_update "$DMG" 2>/dev/null | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')

echo ""
echo "-------- appcast values for v$SHORT --------"
echo "  sparkle:shortVersionString -> $SHORT"
echo "  sparkle:version            -> $BUILD"
echo "  length                     -> $BYTES"
echo "  sparkle:edSignature        -> $SIG"
echo "  enclosure url              -> https://miniti.app/dmg/miniti-$SHORT.dmg"
echo ""
echo "-------- sanity checks --------"

if codesign -d --entitlements :- "$APP" 2>&1 | grep -q "com.apple.security.app-sandbox"; then
    echo "  [ok] app-sandbox entitlement present"
else
    echo "  [FAIL] app-sandbox entitlement MISSING - DO NOT SHIP, would wipe history"
fi

if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    echo "  [ok] nested code signatures valid"
else
    echo "  [FAIL] nested signature verification failed"
fi

if xcrun stapler validate "$DMG" 2>&1 | grep -Eq "validates|validate action worked"; then
    echo "  [ok] DMG notarization stapled"
else
    echo "  [FAIL] DMG notarization not stapled - DO NOT SHIP"
fi

URL="https://miniti.app/dmg/miniti-$SHORT.dmg"
HEADERS=$(curl -sILo /dev/null -D - -w "%{http_code}" "$URL" 2>/dev/null)
HTTP_CODE=$(echo "$HEADERS" | tail -1)
REMOTE_LEN=$(echo "$HEADERS" | awk -F': ' 'tolower($1)=="content-length"{print $2}' | tr -d '\r' | tail -1)

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "  [FAIL] $URL returned HTTP $HTTP_CODE - upload DMG and add redirect"
elif [[ -n "$REMOTE_LEN" ]] && [[ "$REMOTE_LEN" == "$BYTES" ]]; then
    echo "  [ok] URL matches local ($REMOTE_LEN bytes)"
elif [[ -n "$REMOTE_LEN" ]]; then
    echo "  [FAIL] URL has $REMOTE_LEN bytes, local has $BYTES - upload mismatch"
else
    # Server didn't return content-length (chunked transfer). Verify by fetching
    # the full body and counting bytes locally.
    ACTUAL=$(curl -sL "$URL" 2>/dev/null | wc -c | tr -d ' ')
    if [[ "$ACTUAL" == "$BYTES" ]]; then
        echo "  [ok] URL serves $ACTUAL bytes (matches local, no content-length header)"
    else
        echo "  [FAIL] URL serves $ACTUAL bytes, local is $BYTES"
    fi
fi

echo ""
