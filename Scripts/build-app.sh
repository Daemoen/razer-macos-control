#!/bin/bash
set -e

# Build RazerControl.app bundle from SPM project
# Usage: ./Scripts/build-app.sh [release|debug]

CONFIG="${1:-release}"
APP_NAME="RazerControl"
BUNDLE_ID="com.razercontrol.app"
VERSION="0.1.0"
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

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/${APP_NAME}"

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
    <string>1</string>
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

# Ad-hoc sign
echo "=== Signing ==="
codesign --force --deep --sign - "$APP_DIR"

echo "=== Done ==="
echo "App bundle: $APP_DIR"
echo "Size: $(du -sh "$APP_DIR" | cut -f1)"
