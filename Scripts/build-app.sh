#!/bin/bash
set -e

# Build RazerControl.app bundle from SPM project
# Usage: ./Scripts/build-app.sh [release|debug]

CONFIG="${1:-release}"
APP_NAME="RazerControl"
BUNDLE_ID="com.razercontrol.app"
VERSION="0.1.0"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || date +%s)}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-RazerControl Development}"
BUILD_DIR=".build/${CONFIG}"
APP_DIR="dist/${APP_NAME}.app"

echo "=== Building RazerControl ($CONFIG) ==="

# Build (SKIP_BUILD=1 repackages an already-built binary.)
if [ "$CONFIG" = "release" ]; then
    if [ "${SKIP_BUILD:-0}" != "1" ]; then
        swift build --disable-sandbox -c release 2>&1
    fi
    BINARY=".build/release/${APP_NAME}"
else
    if [ "${SKIP_BUILD:-0}" != "1" ]; then
        swift build --disable-sandbox 2>&1
    fi
    BINARY=".build/debug/${APP_NAME}"
fi

# Determine architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    BINARY=".build/${ARCH}-apple-macosx/${CONFIG}/${APP_NAME}"
fi

echo "Binary: $BINARY"

# Create app bundle structure
echo "=== Creating app bundle ==="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
HELPER_APP="$APP_DIR/Contents/Library/LaunchServices/RazerControl Input Service.app"
mkdir -p "$HELPER_APP/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Library/LaunchDaemons"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/${APP_NAME}"

HELPER_BINARY=".build/${ARCH}-apple-macosx/${CONFIG}/RazerControlInputHelper"
if [ ! -f "$HELPER_BINARY" ]; then
    HELPER_BINARY=".build/${CONFIG}/RazerControlInputHelper"
fi
cp "$HELPER_BINARY" "$HELPER_APP/Contents/MacOS/RazerControlInputHelper"
cat > "$HELPER_APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>RazerControlInputHelper</string>
    <key>CFBundleIdentifier</key><string>com.razercontrol.input-helper</string>
    <key>CFBundleName</key><string>RazerControl Input Service</string>
    <key>CFBundleDisplayName</key><string>RazerControl Input Service</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSBackgroundOnly</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
cp "Sources/RazerControl/Resources/com.razercontrol.input-helper.plist" "$APP_DIR/Contents/Library/LaunchDaemons/"

# Keep resources in the standard signed-app location. During local development,
# SwiftPM's generated accessor can also fall back to the bundle in .build.
RESOURCE_BUNDLE=".build/${ARCH}-apple-macosx/${CONFIG}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 RazerControl Contributors. GPLv2.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# Sign the nested helper first, then seal the containing app.
echo "=== Signing ==="
codesign --force --sign "$SIGN_IDENTITY" --identifier com.razercontrol.input-helper "$HELPER_APP"
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"

echo "=== Done ==="
echo "App bundle: $APP_DIR"
echo "Size: $(du -sh "$APP_DIR" | cut -f1)"
