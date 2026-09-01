#!/bin/bash
# Builds RazerControl.app plus the standalone privileged input daemon binary.
#
# The daemon is NOT packaged inside the app bundle. It is deployed to
# /Library/Application Support/RazerControl by Scripts/install-daemon.sh, because
# a root launchd job must not execute code from a user-writable path.
set -Eeuo pipefail

CONFIG="${1:-release}"
APP_NAME="RazerControl"
HELPER_NAME="RazerControlInputHelper"
BUNDLE_ID="com.razercontrol.app"
HELPER_ID="com.razercontrol.input-helper"
VERSION="0.1.0"

# Deterministic by default. The previous script used a wall-clock timestamp
# whenever the tree was dirty, which meant every single build produced a new
# CFBundleVersion. Registration logic keyed on that value, so each rebuild
# invalidated the daemon's approval. Nothing keys on it any more, but a stable
# value still makes "did the installed copy change?" answerable.
if [ -z "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
    if ! git diff --quiet --ignore-submodules -- 2>/dev/null \
       || [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
        BUILD_NUMBER="${BUILD_NUMBER}.dirty"
    fi
fi

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-RazerControl Development}"
APP_DIR="dist/${APP_NAME}.app"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/razercontrol-clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${TMPDIR:-/tmp}/razercontrol-swift-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

# codesign reaches the signing key through the login keychain, which is only
# available inside a GUI login session. A build driven over SSH therefore fails
# with errSecInternalComponent. Retry inside the console user's launchd session,
# which does have keychain access. Direct signing is attempted first so an
# ordinary local build never needs privilege.
rc_codesign() {
    local output
    if output="$(codesign "$@" 2>&1)"; then
        [ -n "$output" ] && echo "$output"
        return 0
    fi
    case "$output" in
        *errSecInternalComponent*|*"User interaction is not allowed"*) ;;
        *) echo "$output" >&2; return 1 ;;
    esac
    local console_uid
    console_uid="$(stat -f%u /dev/console 2>/dev/null || echo 0)"
    if [ "$console_uid" = "0" ] || [ -z "$console_uid" ]; then
        echo "$output" >&2
        echo "error: no GUI session available to reach the signing keychain" >&2
        return 1
    fi
    echo "    (no keychain in this session; signing via console session $console_uid)"
    sudo launchctl asuser "$console_uid" sudo -u "#$console_uid" /usr/bin/codesign "$@"
}

echo "=== Building RazerControl ($CONFIG, build $BUILD_NUMBER) ==="

if [ "${SKIP_BUILD:-0}" != "1" ]; then
    if [ "$CONFIG" = "release" ]; then
        swift build --disable-sandbox -c release
    else
        swift build --disable-sandbox
    fi
fi

ARCH="$(uname -m)"
BIN_DIR=".build/${ARCH}-apple-macosx/${CONFIG}"
[ -d "$BIN_DIR" ] || BIN_DIR=".build/${CONFIG}"

APP_BINARY="${BIN_DIR}/${APP_NAME}"
HELPER_BINARY="${BIN_DIR}/${HELPER_NAME}"
[ -f "$APP_BINARY" ]    || { echo "missing app binary: $APP_BINARY" >&2; exit 1; }
[ -f "$HELPER_BINARY" ] || { echo "missing helper binary: $HELPER_BINARY" >&2; exit 1; }

echo "=== Creating app bundle ==="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$APP_BINARY" "$APP_DIR/Contents/MacOS/${APP_NAME}"

RESOURCE_BUNDLE="${BIN_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2024 RazerControl Contributors. GPLv2.</string>
</dict>
</plist>
PLIST

echo "=== Staging privileged daemon binary ==="
cp "$HELPER_BINARY" "dist/${HELPER_NAME}"

echo "=== Signing ==="
# The daemon derives its trust anchor from the app's designated requirement, so
# both must carry the same signing identity. Sign the daemon first: it is an
# independent deployment artifact, not nested code.
rc_codesign --force --sign "$SIGN_IDENTITY" --identifier "$HELPER_ID" "dist/${HELPER_NAME}"
rc_codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"

echo "=== Verifying signatures ==="
codesign --verify --strict --verbose=2 "dist/${HELPER_NAME}"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# The app bundle must not ship a privileged job definition any more. Assert it,
# so a future edit that reintroduces one fails the build instead of shipping.
if [ -e "$APP_DIR/Contents/Library" ]; then
    echo "error: app bundle still contains Contents/Library (privileged code must not ship in-bundle)" >&2
    exit 1
fi

echo "=== Done ==="
echo "App:    $APP_DIR"
echo "Daemon: dist/${HELPER_NAME}"
