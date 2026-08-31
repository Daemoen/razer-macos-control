#!/bin/bash
set -euo pipefail

SIGNING_IDENTITY="RazerControl Development"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

if ! security find-identity -v -p codesigning | grep -Fq "\"${SIGNING_IDENTITY}\""; then
    echo "Signing identity not found: ${SIGNING_IDENTITY}" >&2
    echo "Open Keychain Access and confirm it appears under login > My Certificates." >&2
    exit 1
fi

echo "=== Building and signing with ${SIGNING_IDENTITY} ==="
CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" ./Scripts/build-app.sh debug

APP_PATH="$PROJECT_DIR/dist/RazerControl.app"
HELPER_PATH="$APP_PATH/Contents/Library/LaunchServices/RazerControl Input Service.app"

echo "=== Verifying nested input service ==="
codesign --verify --strict --verbose=2 "$HELPER_PATH"

echo "=== Verifying RazerControl bundle ==="
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "=== Signed build ready ==="
echo "$APP_PATH"
