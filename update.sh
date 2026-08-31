#!/usr/bin/env bash
set -Eeuo pipefail

readonly SIGNING_IDENTITY='RazerControl Development'
readonly APP_NAME='RazerControl.app'
readonly BUILD_APP="dist/$APP_NAME"
readonly INSTALLED_APP="/Applications/$APP_NAME"

cd -- "$(dirname -- "$0")"

echo "Building and signing RazerControl…"
CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    ./Scripts/build-app.sh debug

test -d "$BUILD_APP"

echo "Verifying the new bundle…"
codesign --verify --deep --strict --verbose=2 "$BUILD_APP"
plutil -lint \
    "$BUILD_APP/Contents/Info.plist" \
    "$BUILD_APP/Contents/Library/LaunchDaemons/com.razercontrol.input-helper.plist"

echo "Closing the installed application…"
osascript -e 'tell application id "com.razercontrol.app" to quit' \
    >/dev/null 2>&1 || true

echo "Installing RazerControl…"
sudo rm -rf "$INSTALLED_APP"
sudo ditto "$BUILD_APP" "$INSTALLED_APP"

echo "Verifying the installed copy…"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"

echo
echo "Update installed successfully."
echo "Open RazerControl and choose Enable Native Input to refresh its input service."
echo "Then run: ./Scripts/verify-native-input.sh"
