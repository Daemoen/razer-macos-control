#!/bin/bash
# Installs the RazerControl privileged input daemon as a classic root
# LaunchDaemon.
#
# Why not SMAppService: that API registers a job whose executable lives inside
# the application bundle, which puts a root process's code on a path an
# unprivileged user can rewrite, and it gates activation on Background Task
# Management state an app cannot inspect or repair once it desynchronises.
# Karabiner-Elements and RustDesk both install privileged components this way
# instead, for the same reasons.
#
# Idempotent: safe to re-run over an existing install.
set -Eeuo pipefail

LABEL="com.razercontrol.inputd"
LEGACY_LABEL="com.razercontrol.input-helper"
INSTALL_DIR="/Library/Application Support/RazerControl"
HELPER_DEST="$INSTALL_DIR/RazerControlInputHelper"
PLIST_DEST="/Library/LaunchDaemons/${LABEL}.plist"
SOCKET="/var/run/razercontrol-input.sock"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
HELPER_SRC="${1:-$PROJECT_DIR/dist/RazerControlInputHelper}"
PLIST_SRC="$SCRIPT_DIR/${LABEL}.plist"

die() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }

[ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"
[ -f "$HELPER_SRC" ] || die "helper binary not found at $HELPER_SRC — run Scripts/build-app.sh first"
[ -f "$PLIST_SRC" ] || die "plist not found at $PLIST_SRC"

step "Validating helper signature"
codesign --verify --strict "$HELPER_SRC" || die "helper signature invalid; rebuild and re-sign"

step "Validating plist syntax"
plutil -lint "$PLIST_SRC" >/dev/null || die "plist failed lint"

# Retire the SMAppService-era job if this machine ever ran it. Its Background
# Task Management record may be orphaned; booting it out is best-effort and a
# failure here is expected and harmless.
step "Retiring legacy job (best effort)"
launchctl bootout "system/$LEGACY_LABEL" 2>/dev/null || true

# Stop the current job before replacing the binary on disk. Replacing a running
# executable in place is how you get a daemon holding a seized HID device with
# no way to release it.
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    step "Stopping running daemon"
    launchctl bootout "system/$LABEL" || die "could not stop existing daemon"
    for _ in $(seq 1 20); do
        launchctl print "system/$LABEL" >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

step "Installing helper to $HELPER_DEST"
install -d -o root -g wheel -m 0755 "$INSTALL_DIR"
install -o root -g wheel -m 0755 "$HELPER_SRC" "$HELPER_DEST"

step "Installing launchd plist to $PLIST_DEST"
install -o root -g wheel -m 0644 "$PLIST_SRC" "$PLIST_DEST"

# A stale socket from a previous generation would let the controller connect to
# nothing.
rm -f "$SOCKET"

step "Bootstrapping daemon"
launchctl bootstrap system "$PLIST_DEST" || die "launchctl bootstrap failed"
launchctl enable "system/$LABEL" 2>/dev/null || true

step "Verifying"
launchctl print "system/$LABEL" >/dev/null 2>&1 || die "daemon did not register"

# The daemon binds only after a console user exists; give it a moment.
for _ in $(seq 1 20); do
    [ -S "$SOCKET" ] && break
    sleep 0.25
done

echo
if [ -S "$SOCKET" ]; then
    echo "PASS  daemon registered and listening at $SOCKET"
    ls -l "$SOCKET"
else
    echo "WARN  daemon registered but socket not yet present at $SOCKET"
    echo "      (expected if no console user is logged in)"
fi
echo
echo "Next: grant Input Monitoring to the daemon."
echo "  System Settings > Privacy & Security > Input Monitoring"
echo "  Add or enable: $HELPER_DEST"
echo "  The daemon runs as root and cannot raise that prompt itself."
