#!/bin/bash
# Package VoiceStick.app into a signed and optionally notarized DMG.
#
# Usage:
#   scripts/make-dmg.sh
#   scripts/make-dmg.sh build/VoiceStick-<version>.app
#   scripts/make-dmg.sh build/VoiceStick-<version>.app build/VoiceStick-<version>.dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$ROOT_DIR/build"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_PATH="${1:-$BUILD_DIR/VoiceStick-${VERSION}.app}"
OUTPUT="${2:-$BUILD_DIR/VoiceStick-${VERSION}.dmg}"
STAGING_DIR="$BUILD_DIR/.dmg-staging"
VOLUME_NAME="VoiceStick"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Application bundle not found: $APP_PATH"
    exit 1
fi

CODESIGN_IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    CODESIGN_IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')"
fi
if [ "${REQUIRE_DEVELOPER_ID:-0}" = "1" ] && [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "Error: a Developer ID Application signing identity is required."
    exit 1
fi

echo "Verifying the previously signed app..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf "$STAGING_DIR" "$OUTPUT"
mkdir -p "$STAGING_DIR"
ditto --norsrc --noextattr "$APP_PATH" "$STAGING_DIR/VoiceStick.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating DMG..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT"
rm -rf "$STAGING_DIR"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "Signing DMG with Developer ID..."
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$OUTPUT"
    codesign --verify --verbose=2 "$OUTPUT"
fi

NOTARY_OPTIONS=(--keychain-profile "AC_PASSWORD")
if [ -n "${NOTARY_KEYCHAIN_PATH:-}" ]; then
    NOTARY_OPTIONS+=(--keychain "$NOTARY_KEYCHAIN_PATH")
fi
if xcrun notarytool history "${NOTARY_OPTIONS[@]}" >/dev/null 2>&1; then
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "$OUTPUT" "${NOTARY_OPTIONS[@]}" --wait
    xcrun stapler staple "$OUTPUT"
else
    if [ "${REQUIRE_NOTARIZATION:-0}" = "1" ]; then
        echo "Error: notarization profile AC_PASSWORD is required."
        exit 1
    fi
    echo "Skipping notarization: keychain profile AC_PASSWORD was not found."
fi

echo "DMG complete: $OUTPUT"
