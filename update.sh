#!/usr/bin/env bash
# Transactional build + install for RazerControl and its privileged input daemon.
#
# The previous version ran `sudo rm -rf /Applications/RazerControl.app` while the
# daemon was still registered against that bundle. That destroyed the provider
# app out from under an active registration and orphaned it, which is the state
# this codebase spent a long time failing to recover from. Nothing here deletes
# the installed app until a verified replacement is in place, and the old copy
# is retained until the new one proves itself.
set -Eeuo pipefail

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-RazerControl Development}"
APP_NAME='RazerControl.app'
BUILD_APP="dist/$APP_NAME"
INSTALLED_APP="/Applications/$APP_NAME"
ROLLBACK_APP="/Applications/.${APP_NAME}.rollback"
HELPER_BUILD="dist/RazerControlInputHelper"
LABEL="com.razercontrol.inputd"

cd -- "$(dirname -- "$0")"

step() { echo; echo "==> $*"; }
die()  { echo "error: $*" >&2; exit 1; }

restore() {
    if [ -d "$ROLLBACK_APP" ]; then
        echo "!! restoring previous installation"
        sudo rm -rf "$INSTALLED_APP"
        sudo mv "$ROLLBACK_APP" "$INSTALLED_APP"
    fi
}
trap 'restore' ERR

step "Building and signing"
CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" ./Scripts/build-app.sh "${1:-debug}"

[ -d "$BUILD_APP" ]    || die "no app bundle produced"
[ -f "$HELPER_BUILD" ] || die "no daemon binary produced"

step "Verifying the new bundle before touching the installation"
codesign --verify --deep --strict --verbose=2 "$BUILD_APP"
codesign --verify --strict --verbose=2 "$HELPER_BUILD"
plutil -lint "$BUILD_APP/Contents/Info.plist" >/dev/null
plutil -lint "Scripts/${LABEL}.plist" >/dev/null

step "Stopping the daemon so it releases any seized device"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true

step "Quitting the running controller"
osascript -e 'tell application id "com.razercontrol.app" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do pgrep -x RazerControl >/dev/null 2>&1 || break; sleep 0.25; done
pkill -x RazerControl 2>/dev/null || true

step "Installing the controller"
sudo rm -rf "$ROLLBACK_APP"
if [ -d "$INSTALLED_APP" ]; then
    sudo mv "$INSTALLED_APP" "$ROLLBACK_APP"
fi
sudo ditto "$BUILD_APP" "$INSTALLED_APP"

# ditto run under sudo preserves the SOURCE ownership, so without this the
# installed bundle stays owned by the building user. The daemon derives its
# trust anchor from this bundle; it must not be user-writable.
sudo chown -R root:wheel "$INSTALLED_APP"
sudo chmod -R go-w "$INSTALLED_APP"

step "Verifying the installed copy"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP" || die "installed app failed verification"

step "Installing and starting the privileged input daemon"
sudo ./Scripts/install-daemon.sh "$PWD/$HELPER_BUILD"

trap - ERR
step "Discarding rollback copy"
sudo rm -rf "$ROLLBACK_APP"

echo
echo "Update complete."
echo "Run ./Scripts/verify-native-input.sh to confirm end to end."
