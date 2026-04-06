#!/bin/bash
set -e

# Create a DMG installer for RazerControl
# Requires: build-app.sh to have been run first

APP_NAME="RazerControl"
VERSION="0.1.0"
APP_DIR="dist/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR="dist/dmg"

if [ ! -d "$APP_DIR" ]; then
    echo "Error: $APP_DIR not found. Run ./Scripts/build-app.sh first."
    exit 1
fi

echo "=== Creating DMG ==="

# Clean
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app to staging
cp -R "$APP_DIR" "$DMG_DIR/"

# Create Applications symlink
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "dist/$DMG_NAME"

# Clean staging
rm -rf "$DMG_DIR"

echo "=== Done ==="
echo "DMG: dist/$DMG_NAME"
echo "Size: $(du -sh "dist/$DMG_NAME" | cut -f1)"
echo ""
echo "To install: open dist/$DMG_NAME and drag RazerControl to Applications"
