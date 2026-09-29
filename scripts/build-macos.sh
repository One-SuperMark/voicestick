#!/bin/bash
# Build VoiceStick for macOS as an Apple Silicon app bundle.
#
# Produces:
#   build/VoiceStick-<version>.app
#   build/VoiceStick-<version>.zip
#   build/VoiceStick-<version>.signature  (when Sparkle sign_update is available)
#   --development: local four-part artifact/display version; Apple versions stay three-part
#
# Optional environment:
#   VOICESTICK_APPCAST_URL=<HTTPS appcast URL override for this build>
#   SPARKLE_PUBLIC_ED_KEY=<public key from Sparkle generate_keys>
#   SPARKLE_PRIVATE_ED_KEY=<private key exported by Sparkle generate_keys -x>
#   SPARKLE_KEY_ACCOUNT=one-supermark-voicestick

set -euo pipefail

# BEGIN LOCAL DEVELOPMENT VERSION HELPERS
# The state belongs to ignored build output, not to the source version files.
next_development_revision() {
    local baseline_version="$1"
    local state_path="$2"
    local previous_state previous_version previous_revision state_bytes

    if [ -e "$state_path" ] || [ -L "$state_path" ]; then
        if [ ! -f "$state_path" ] || [ -L "$state_path" ]; then
            echo "Error: local development version state must be a regular file." >&2
            return 1
        fi
        state_bytes="$(wc -c < "$state_path")"
        if [ "$state_bytes" -gt 128 ]; then
            echo "Error: local development version state is malformed." >&2
            return 1
        fi
        previous_state="$(< "$state_path")"
        if [ "$state_bytes" -ne "$((${#previous_state} + 1))" ]; then
            echo "Error: local development version state is malformed." >&2
            return 1
        fi
        if [[ ! "$previous_state" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\ ([1-9][0-9]{0,8})$ ]]; then
            echo "Error: local development version state is malformed." >&2
            return 1
        fi
        previous_version="${BASH_REMATCH[1]}"
        previous_revision="${BASH_REMATCH[2]}"
        if [ "$previous_version" = "$baseline_version" ]; then
            if [ "$previous_revision" -ge 999999999 ]; then
                echo "Error: local development revision counter is exhausted." >&2
                return 1
            fi
            printf '%s\n' "$((previous_revision + 1))"
            return 0
        fi
    fi

    printf '1\n'
}

save_development_revision() {
    local baseline_version="$1"
    local revision="$2"
    local state_path="$3"
    local temporary_state

    temporary_state="$(mktemp "${state_path}.XXXXXX")" || return 1
    if ! printf '%s %s\n' "$baseline_version" "$revision" > "$temporary_state" \
        || ! mv -f "$temporary_state" "$state_path"; then
        rm -f "$temporary_state"
        echo "Error: unable to save the local development version state." >&2
        return 1
    fi
}

release_development_lock() {
    if [ "${DEVELOPMENT_LOCK_ACQUIRED:-0}" = "1" ]; then
        rmdir "$DEVELOPMENT_LOCK_DIR" || true
    fi
}
# END LOCAL DEVELOPMENT VERSION HELPERS

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
DESKTOP_DIR="$ROOT_DIR/desktop/macos"
BUILD_DIR="$ROOT_DIR/build"
PLIST="$DESKTOP_DIR/Sources/VoiceStickApp/Info.plist"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
CONFIG="${1:---release}"
TARGET_ARCH="arm64"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-one-supermark-voicestick}"
DEVELOPMENT_BUILD=0
ARTIFACT_VERSION="$VERSION"

case "$CONFIG" in
    --release)
        SWIFT_CONFIG="release"
        ;;
    --debug)
        SWIFT_CONFIG="debug"
        ;;
    --development)
        SWIFT_CONFIG="release"
        DEVELOPMENT_BUILD=1
        ;;
    *)
        echo "Usage: $0 [--release|--debug|--development]"
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

if [ "$DEVELOPMENT_BUILD" = "1" ]; then
    DEVELOPMENT_STATE_PATH="$BUILD_DIR/.development-version-state"
    DEVELOPMENT_LOCK_DIR="$BUILD_DIR/.development-version.lock"
    if ! mkdir "$DEVELOPMENT_LOCK_DIR" 2>/dev/null; then
        echo "Error: unable to acquire the local development build lock at $DEVELOPMENT_LOCK_DIR." >&2
        echo "Another local development build may still be running." >&2
        echo "If a previous build was interrupted, confirm it has stopped before removing that lock directory." >&2
        exit 1
    fi
    DEVELOPMENT_LOCK_ACQUIRED=1
    trap release_development_lock EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    DEVELOPMENT_REVISION="$(next_development_revision "$VERSION" "$DEVELOPMENT_STATE_PATH")"
    ARTIFACT_VERSION="${VERSION}.${DEVELOPMENT_REVISION}"
fi

echo "===================================="
if [ "$DEVELOPMENT_BUILD" = "1" ]; then
    echo " VoiceStick Local Development Build $ARTIFACT_VERSION"
    echo " Apple bundle versions: $VERSION (unchanged)"
else
    echo " VoiceStick macOS Build v$VERSION"
fi
echo " Architecture: $TARGET_ARCH"
echo "===================================="

if /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" | grep -q "REPLACE_WITH" && [ -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
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

APP_DIR="$BUILD_DIR/VoiceStick-${ARTIFACT_VERSION}.app"
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
if /usr/libexec/PlistBuddy -c 'Print :VoiceStickDevelopmentVersion' "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Delete :VoiceStickDevelopmentVersion' "$APP_DIR/Contents/Info.plist"
fi
if [ "$DEVELOPMENT_BUILD" = "1" ]; then
    /usr/libexec/PlistBuddy -c "Add :VoiceStickDevelopmentVersion string $ARTIFACT_VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [ -n "${VOICESTICK_APPCAST_URL:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $VOICESTICK_APPCAST_URL" "$APP_DIR/Contents/Info.plist"
fi
if [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$APP_DIR/Contents/Info.plist"
fi

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
if { [ "${REQUIRE_DEVELOPER_ID:-0}" = "1" ] || [ "$DEVELOPMENT_BUILD" = "1" ]; } && [ "$CODESIGN_IDENTITY" = "-" ]; then
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

ZIP_PATH="$BUILD_DIR/VoiceStick-${ARTIFACT_VERSION}.zip"
SIGNATURE_PATH="${ZIP_PATH%.zip}.signature"
STAGING_DIR="$BUILD_DIR/.sparkle-staging"
rm -rf "$STAGING_DIR" "$ZIP_PATH" "$SIGNATURE_PATH"
mkdir -p "$STAGING_DIR"
ditto --norsrc --noextattr "$APP_DIR" "$STAGING_DIR/VoiceStick.app"

echo ""
if [ "$DEVELOPMENT_BUILD" = "1" ]; then
    echo "Creating local development ZIP (not an update release)..."
else
    echo "Creating Sparkle ZIP..."
fi
ditto -c -k --norsrc --noextattr --keepParent "$STAGING_DIR/VoiceStick.app" "$ZIP_PATH"
rm -rf "$STAGING_DIR"

if [ "$DEVELOPMENT_BUILD" = "1" ]; then
    echo "Local development package: skipping Sparkle private key access and update signing."
    save_development_revision "$VERSION" "$DEVELOPMENT_REVISION" "$DEVELOPMENT_STATE_PATH"
else
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
fi

echo ""
echo "Build complete:"
echo "  App: $APP_DIR"
echo "  ZIP: $ZIP_PATH"
if [ -f "$SIGNATURE_PATH" ]; then
    echo "  Sig: $SIGNATURE_PATH"
fi
echo ""
if [ "$DEVELOPMENT_BUILD" = "1" ]; then
    echo "Local development only: not notarized or published by this build."
else
    echo "Next: $SCRIPT_DIR/make-dmg.sh $APP_DIR"
fi
