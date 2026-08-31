#!/bin/bash
set -u

APP="${1:-/Applications/RazerControl.app}"
PLIST="$APP/Contents/Library/LaunchDaemons/com.razercontrol.input-helper.plist"
HELPER="$APP/Contents/Library/LaunchServices/RazerControl Input Service.app"
EXECUTABLE="$APP/Contents/MacOS/RazerControl"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

[ -x "$EXECUTABLE" ] || fail "RazerControl executable not found at $APP"
codesign --verify --deep --strict "$APP" 2>/dev/null || fail "app signature validation"
pass "app signature validation"
codesign --verify --strict "$HELPER" 2>/dev/null || fail "input-service signature validation"
pass "input-service signature validation"
plutil -lint "$PLIST" >/dev/null || fail "launch-daemon property list"
pass "launch-daemon property list"

APP_REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
[ -n "$APP_REQUIREMENT" ] || fail "could not read app designated requirement"
echo "INFO: app requirement: $APP_REQUIREMENT"

if launchctl print system/com.razercontrol.input-helper >/dev/null 2>&1; then
    pass "input service is registered with launchd"
else
    fail "input service is not registered; open RazerControl and choose Enable Native Input"
fi

echo "INFO: running authenticated helper/HID handshake"
# The service intentionally permits one exclusive input owner. Close the GUI
# client before launching the same signed executable in diagnostic mode.
osascript -e 'tell application id "com.razercontrol.app" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x RazerControl >/dev/null 2>&1 || break
    sleep 0.2
done
"$EXECUTABLE" --native-input-self-test
