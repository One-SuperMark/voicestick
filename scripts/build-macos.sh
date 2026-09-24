#!/bin/bash
# Build VoiceStick for macOS as an Apple Silicon app bundle.
#
# Produces:
#   build/VoiceStick-<version>.app
#   build/VoiceStick-<version>.zip
#   build/VoiceStick-<version>.signature  (when Sparkle sign_update is available)
#
# Optional environment:
#   VOICESTICK_APPCAST_URL=https://78.github.io/voicestick/appcast.xml
#   SPARKLE_PUBLIC_ED_KEY=<public key from Sparkle generate_keys>
#   SPARKLE_PRIVATE_ED_KEY=<private key exported by Sparkle generate_keys -x>
#   SPARKLE_KEY_ACCOUNT=voicestick

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
DESKTOP_DIR="$ROOT_DIR/desktop/macos"
BUILD_DIR="$ROOT_DIR/build"
PLIST="$DESKTOP_DIR/Sources/VoiceStickApp/Info.plist"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
CONFIG="${1:---release}"
TARGET_ARCH="arm64"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-voicestick}"

case "$CONFIG" in
    --release)
        SWIFT_CONFIG="release"
        ;;
    --debug)
        SWIFT_CONFIG="debug"
        ;;
    *)
        echo "Usage: $0 [--release|--debug]"
        exit 1
        ;;
esac

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: VERSION must contain exactly three numeric components."
    exit 1
fi

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [ "$SHORT_VERSION" != "$VERSION" ] || [ "$BUNDLE_VERSION" != "$VERSION" ]; then
    echo "Error: VERSION and both macOS bundle version fields must match."
    exit 1
fi

mkdir -p "$BUILD_DIR"

echo "===================================="
echo " VoiceStick macOS Build v$VERSION"
echo " Architecture: $TARGET_ARCH"
echo "===================================="

if [ -n "${VOICESTICK_APPCAST_URL:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $VOICESTICK_APPCAST_URL" "$PLIST"
fi

if [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$PLIST"
elif /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" | grep -q "REPLACE_WITH"; then
    echo "WARNING: SUPublicEDKey is still a placeholder."
    echo "         Generate Sparkle keys before shipping a public release."
fi

echo ""
echo "Building VoiceStickApp for $TARGET_ARCH..."
SCRATCH="$DESKTOP_DIR/.build-$TARGET_ARCH"
rm -rf "$SCRATCH"
swift build \
    --package-path "$DESKTOP_DIR" \
    -c "$SWIFT_CONFIG" \
    --arch "$TARGET_ARCH" \
    --scratch-path "$SCRATCH"

APP_DIR="$BUILD_DIR/VoiceStick-${VERSION}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

ARM_BUILD="$DESKTOP_DIR/.build-arm64/arm64-apple-macosx/$SWIFT_CONFIG"
if [ "$SWIFT_CONFIG" = "release" ]; then
    PRODUCT_CONFIG="Release"
else
    PRODUCT_CONFIG="Debug"
fi
if [ ! -f "$ARM_BUILD/VoiceStickApp" ]; then
    ARM_BUILD="$DESKTOP_DIR/.build-arm64/out/Products/$PRODUCT_CONFIG"
fi
if [ ! -f "$ARM_BUILD/VoiceStickApp" ]; then
    echo "Error: ARM64 build output was not found."
    exit 1
fi

echo ""
echo "Copying ARM64 executable..."
cp "$ARM_BUILD/VoiceStickApp" "$APP_DIR/Contents/MacOS/VoiceStickApp"
if [ "$(lipo -archs "$APP_DIR/Contents/MacOS/VoiceStickApp")" != "$TARGET_ARCH" ]; then
    echo "Error: packaged executable is not ARM64-only."
    exit 1
fi

cp "$PLIST" "$APP_DIR/Contents/Info.plist"

ICON_PATH="$DESKTOP_DIR/Resources/AppIcon.icns"
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "WARNING: App icon was not found: $ICON_PATH"
fi

SPARKLE_FRAMEWORK="$ARM_BUILD/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK="$(find -L "$DESKTOP_DIR/.build-arm64/artifacts" -name Sparkle.framework -type d 2>/dev/null | head -1 || true)"
fi
if [ -z "$SPARKLE_FRAMEWORK" ] || [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Error: required Sparkle.framework was not found in SwiftPM artifacts."
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
if [ ! -f "$APP_DIR/Contents/Frameworks/Sparkle.framework/Sparkle" ]; then
    echo "Error: packaged Sparkle executable is missing."
    exit 1
fi

EXECUTABLE="$APP_DIR/Contents/MacOS/VoiceStickApp"
RPATH_LIST="$(otool -l "$EXECUTABLE")"
if [[ "$RPATH_LIST" != *'path @loader_path/../Frameworks ('* ]]; then
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$EXECUTABLE"
    RPATH_LIST="$(otool -l "$EXECUTABLE")"
fi
if [[ "$RPATH_LIST" != *'path @loader_path/../Frameworks ('* ]]; then
    echo "Error: packaged executable cannot locate its embedded frameworks."
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

echo ""
echo "Signing app..."
xattr -cr "$APP_DIR" 2>/dev/null || true
if [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "Using: $CODESIGN_IDENTITY"
    if [ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --deep --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
    fi
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR/Contents/MacOS/VoiceStickApp"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
    echo "Using ad-hoc signature."
    codesign --force --sign - "$APP_DIR/Contents/MacOS/VoiceStickApp"
    codesign --force --sign - "$APP_DIR"
fi

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ZIP_PATH="$BUILD_DIR/VoiceStick-${VERSION}.zip"
SIGNATURE_PATH="${ZIP_PATH%.zip}.signature"
STAGING_DIR="$BUILD_DIR/.sparkle-staging"
rm -rf "$STAGING_DIR" "$ZIP_PATH" "$SIGNATURE_PATH"
mkdir -p "$STAGING_DIR"
ditto --norsrc --noextattr "$APP_DIR" "$STAGING_DIR/VoiceStick.app"

echo ""
echo "Creating Sparkle ZIP..."
ditto -c -k --norsrc --noextattr --keepParent "$STAGING_DIR/VoiceStick.app" "$ZIP_PATH"
rm -rf "$STAGING_DIR"

SIGN_TOOL="$(find -L "$DESKTOP_DIR/.build-arm64/artifacts" -name sign_update -type f 2>/dev/null | head -1 || true)"
if [ -n "$SIGN_TOOL" ] && [ -x "$SIGN_TOOL" ]; then
    echo "Signing Sparkle ZIP..."
    if [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
        SIGN_OUTPUT="$(printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$SIGN_TOOL" --ed-key-file - "$ZIP_PATH" 2>&1 || true)"
    else
        SIGN_OUTPUT="$("$SIGN_TOOL" --account "$SPARKLE_KEY_ACCOUNT" "$ZIP_PATH" 2>&1 || true)"
    fi
    echo "$SIGN_OUTPUT"
    ED_SIGNATURE="$(printf '%s\n' "$SIGN_OUTPUT" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' | head -1)"
    if [ -n "$ED_SIGNATURE" ]; then
        printf '%s\n' "$ED_SIGNATURE" > "$SIGNATURE_PATH"
    elif [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
        echo "Error: Sparkle ZIP signing failed."
        exit 1
    else
        echo "No Sparkle signing key was available; skipping ZIP signature."
    fi
else
    echo "WARNING: Sparkle sign_update tool was not found."
fi

echo ""
echo "Build complete:"
echo "  App: $APP_DIR"
echo "  ZIP: $ZIP_PATH"
if [ -f "$SIGNATURE_PATH" ]; then
    echo "  Sig: $SIGNATURE_PATH"
fi
echo ""
echo "Next: $SCRIPT_DIR/make-dmg.sh $APP_DIR"
