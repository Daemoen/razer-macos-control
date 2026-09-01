#!/bin/bash
# Non-mutating end-to-end check of the native input path.
# Reports every boundary separately so a failure names its own layer.
set -u

APP="${1:-/Applications/RazerControl.app}"
LABEL="com.razercontrol.inputd"
HELPER="/Library/Application Support/RazerControl/RazerControlInputHelper"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
SOCKET="/var/run/razercontrol-input.sock"
EXECUTABLE="$APP/Contents/MacOS/RazerControl"

fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails+1)); }
info() { echo "INFO: $1"; }

echo "=== Controller ==="
[ -x "$EXECUTABLE" ] && pass "controller present at $APP" || fail "controller missing at $APP"
codesign --verify --deep --strict "$APP" 2>/dev/null \
    && pass "controller signature" || fail "controller signature"
owner="$(stat -f '%Su:%Sg' "$APP" 2>/dev/null)"
[ "$owner" = "root:wheel" ] \
    && pass "controller owned root:wheel" \
    || fail "controller owned $owner (must be root:wheel; the daemon trusts this bundle)"
info "designated requirement: $(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"

echo
echo "=== Daemon ==="
[ -f "$HELPER" ] && pass "daemon binary installed" || fail "daemon binary missing at $HELPER"
codesign --verify --strict "$HELPER" 2>/dev/null \
    && pass "daemon signature" || fail "daemon signature"
howner="$(stat -f '%Su:%Sg %Lp' "$HELPER" 2>/dev/null)"
[ "${howner%% *}" = "root:wheel" ] \
    && pass "daemon owned root:wheel ($howner)" || fail "daemon ownership: $howner"
[ -f "$PLIST" ] && plutil -lint "$PLIST" >/dev/null 2>&1 \
    && pass "launchd plist valid" || fail "launchd plist missing or invalid"

if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    pass "daemon registered with launchd"
    info "pid/last exit: $(launchctl print "system/$LABEL" 2>/dev/null | awk '/^\tpid = |^\tlast exit code = /{print}' | tr -d '\t' | paste -sd'; ' -)"
else
    fail "daemon not registered — run: sudo ./Scripts/install-daemon.sh"
fi

echo
echo "=== IPC ==="
if [ -S "$SOCKET" ]; then
    pass "socket present ($(stat -f '%Su:%Sg %Lp' "$SOCKET"))"
else
    fail "socket absent at $SOCKET"
fi

echo
echo "=== Permissions ==="
sysdb="/Library/Application Support/com.apple.TCC/TCC.db"
if im="$(sudo -n sqlite3 "$sysdb" \
        "select auth_value from access where service='kTCCServiceListenEvent' and client like '%RazerControlInputHelper%';" 2>/dev/null)"; then
    case "$im" in
        2) pass "Input Monitoring granted to the daemon" ;;
        "") fail "Input Monitoring not granted. Add manually: System Settings > Privacy & Security > Input Monitoring, click +, Shift-Cmd-G, enter: $HELPER" ;;
        *)  fail "Input Monitoring present but not granted (auth_value=$im)" ;;
    esac
else
    info "Input Monitoring state needs sudo to read; skipping"
fi

echo
echo "=== End-to-end handshake ==="
# The daemon permits exactly one exclusive owner, so the GUI must not hold the
# connection while the self-test claims it.
osascript -e 'tell application id "com.razercontrol.app" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x RazerControl >/dev/null 2>&1 || break; sleep 0.2; done
if [ -x "$EXECUTABLE" ]; then
    out="$("$EXECUTABLE" --native-input-self-test 2>&1)"
    echo "$out"
    case "$out" in
        PASS*) pass "authenticated IPC + HID seize" ;;
        *)     fail "handshake: $out" ;;
    esac
fi

echo
if [ "$fails" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
else
    echo "$fails CHECK(S) FAILED"
fi
exit "$fails"
