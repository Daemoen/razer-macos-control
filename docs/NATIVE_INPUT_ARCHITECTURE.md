# Native Input Architecture and Lifecycle

## Status

This document is the design contract for RazerControl native input. Runtime or
installer changes must not be shipped unless they preserve every lifecycle
invariant and pass the test matrix below.

## Goals

- Capture only explicitly supported Razer HID interfaces.
- Suppress captured physical events and replay either the factory action or the
  configured mapping.
- Keep RGB feature-report access independent from input capture.
- Require no Karabiner installation or service juggling.
- Survive app relaunch, logout/login, sleep/wake, device reconnect, routine
  upgrades, rollback, and reboot.
- Install, upgrade, disable, and uninstall without orphaning launchd or
  Background Task Management state.
- Produce a precise diagnostic at every boundary.

## Process model

### RazerControl UI / console-user controller

Runs as the logged-in user and owns:

- SwiftUI and device/profile configuration.
- RGB feature-report traffic.
- Accessibility permission and synthetic keyboard/mouse event injection.
- Selection of devices and mappings sent to the capture service.
- Registration UI and health reporting.
- Console-session lifecycle while the app is active.

It must never require root privileges. It must not open a keyboard exclusively
while the privileged service owns that interface.

### RazerControl Input Service

Runs as a root LaunchDaemon and owns:

- Exclusive opening of only configured Razer input interfaces.
- Reading raw HID reports and suppressing the original physical events.
- Releasing every seized interface immediately when the controller disconnects,
  asks it to stop, the active console user changes, or the service terminates.
- A versioned, authenticated IPC endpoint.

It does not launch applications, read user configuration files directly, or
inject CoreGraphics events into a user session. The console-user controller
performs those operations.

### Optional login controller

If mappings must work before the main window is opened, add a dedicated
LaunchAgent/controller in a later milestone. It must use a separate
`SMAppService.agent` manager and status display. Do not combine agent and daemon
approval state into one ambiguous toggle. Until that component exists, native
mapping is explicitly active only while RazerControl is running.

## IPC and trust boundary

Use a Unix-domain socket with explicit framing and protocol versioning.

The service must authenticate every connection with all of:

1. `getpeereid` and the active console-user UID.
2. Peer PID obtained from the connected socket.
3. Dynamic code validation using Security.framework.
4. A requirement anchored to the expected signing team/certificate and the
   RazerControl controller signing identifier.

The service must not trust a path, process name, UID alone, or data supplied in
the first message. Production builds must use one stable Apple-issued signing
team across all components. A locally trusted self-signed certificate is a
development fallback, not a production/distribution identity.

The wire protocol must include:

- Protocol version and message type.
- App build and helper build.
- Capability negotiation.
- `hello`, `ready`, `health`, `event`, `configure`, `releaseDevices`,
  `prepareForUpdate`, `shutdown`, and structured `error` messages.
- Bounded frame sizes, timeouts, full-write handling, reconnect backoff, and
  broken-pipe protection.

Only one active controller may own exclusive capture. Additional diagnostic
connections may receive health state but must not change capture ownership.

## Console-user and session handling

The socket cannot be permanently assigned to the user present at daemon boot.
The service must observe console-session changes and recreate or re-own its
endpoint for the current console user. On a user transition it must:

1. Stop capture and release all devices.
2. Disconnect the former controller.
3. Update endpoint ownership/authorization.
4. Wait for an authenticated controller belonging to the new console user.

Fast User Switching, loginwindow, remote sessions, logout, and wake must be
explicitly tested. The service must remain idle at loginwindow rather than
crash-looping.

## Permissions and identities

Permissions belong to the executable/code identity that performs the protected
operation:

- The Input Service needs Input Monitoring authorization for HID capture.
- The console-user controller needs Accessibility authorization for event
  injection and any UI-context inspection.
- RGB feature reports should not be coupled to either permission.

The UI must show these as separate checks with the responsible executable named.
It must preflight without prompting at ordinary launch and prompt only after an
explicit user action. A root daemon must not attempt to present UI.

Changing the signing team, certificate requirement, bundle identifier, or
responsible executable is a permission migration, not a routine upgrade. It may
require user reapproval and must be declared before installation.

## Service registration state machine

Registration is durable lifecycle state. It is not tied to `CFBundleVersion`.
Never unregister/re-register merely because an app or helper build changed.

Interpret `SMAppService.Status` as follows:

### `.notRegistered`

- On explicit Enable/Register: call `register()` once.
- Report the full error domain, code, failure reason, and recovery suggestion.
- Do not retry in a tight loop.

### `.requiresApproval`

- Explain that the daemon is registered but disabled by macOS.
- Open Login Items settings only after user action.
- Poll status with bounded backoff while the UI is visible.

### `.enabled`

- Test the IPC health endpoint.
- If healthy, do nothing to registration.
- If registration is enabled but the service is not running, make one bounded
  registration/start attempt as recommended by Karabiner's documented macOS
  workaround, then report the resulting state. Do not unregister first.

### `.notFound`

- This is a recovery state, not normal installation.
- The documented Karabiner workaround is one `unregister` followed by one
  `register`, with complete errors recorded.
- Never use `sfltool resetbtm` automatically.

The controller must expose signed management commands equivalent to Apple's
sample: `service status`, `service register`, `service unregister`, and
`service test`. Add `service diagnose` for the combined state report.

## First installation

1. Build every executable for supported architectures.
2. Sign nested code first and the containing app last with the same stable team.
3. Validate nested and deep signatures, designated requirements, hardened
   runtime settings, identifiers, versions, and plists.
4. Stage the complete app on the destination volume.
5. Validate the staged copy again.
6. Atomically install it at a stable path.
7. Launch the signed installed application, never the build-tree copy.
8. On explicit user action, register the daemon.
9. Guide approval of the background daemon.
10. Guide Input Monitoring for the service identity and Accessibility for the
    controller identity.
11. Run the installed binary's end-to-end service test.
12. Mark setup complete only after authenticated IPC and HID open both succeed.

For distribution, use a signed/notarized package or equivalent transactional
installer. A local script is acceptable only as a development installer and
must implement the same validation and rollback boundaries.

## Routine upgrade

Routine upgrades assume an unchanged service label, plist semantics, signing
team, identifiers, and compatible wire protocol.

1. Build, sign, and validate the new app before touching the installation.
2. Ask the running controller/service for versions and health.
3. Send `prepareForUpdate`; the service releases HID interfaces and exits
   cleanly after acknowledging.
4. Quit the old controller.
5. Stage and validate the new app on the `/Applications` volume.
6. Rename the old app to a rollback location and atomically rename the staged
   app into place.
7. Do not call `SMAppService.unregister` or `register` for an ordinary upgrade.
8. Let launchd restart the durable service from the stable installed path. If
   needed, use a bounded, documented kickstart/restart mechanism rather than
   altering registration state.
9. Launch the new controller and verify helper build, protocol, signature,
   authenticated IPC, permissions, and HID open.
10. On failure, release devices, restore the old app atomically, restart it, and
    verify rollback before reporting failure.
11. Delete the rollback copy only after success.

The daemon/client version handshake decides whether an old running helper is
compatible. Never infer helper freshness from a preference or app build number.

## Service-definition or identity migration

Changes to the service label, plist behavior, signing team, bundle identifiers,
or incompatible protocol are migrations, not routine upgrades.

Prefer a side-by-side generation:

1. Ship a new service label and manager identity.
2. Register and approve the new service while the old service and manager still
   exist.
3. Verify the new service end to end without both services seizing devices.
4. Transfer ownership.
5. Unregister the old service using the old signed manager.
6. Remove the old generation only after its registration and process are gone.

If side-by-side migration is impossible, the old installed signed application
must unregister its service before replacement, and the new installed signed
application must register afterward. This may require renewed approval and must
have rollback behavior.

## Disable, uninstall, and teardown

### Disable native input

- Stop capture and verify every device was released.
- Disconnect the controller.
- Leave registration intact unless the user explicitly chooses Disable Service.

### Disable service

- Call `unregister` from the installed signed controller.
- Wait for asynchronous completion.
- Verify status, process absence, socket removal, and device release.
- Keep the app installed so recovery remains possible.

### Complete uninstall

1. Run the signed uninstaller/management command while the app still exists.
2. Stop capture and release devices.
3. Unregister the daemon and verify completion.
4. Stop user components and remove sockets/runtime files.
5. Preserve or remove profiles according to an explicit user choice.
6. Remove the app only after service teardown succeeds.
7. Explain that macOS privacy entries may remain visible and can be removed by
   the user in System Settings.

Deleting the app bundle first is never a supported uninstall or upgrade path.
`sfltool resetbtm` is a destructive developer recovery tool affecting unrelated
apps and is prohibited from product scripts and normal support instructions.

## Orphan recovery

If registration exists but the provider app or launchd job is missing:

1. Reinstall a controller at the same stable path with the same trusted signing
   identity and identifiers.
2. Run `service diagnose` and retain full error domains/codes.
3. Use the signed controller to unregister the orphan.
4. Verify registration and job removal.
5. Register again only after the state is clean and only with explicit consent.

If the signing identity was lost or changed, treat this as an identity migration
and explain that administrative/manual recovery may be required. Do not hide it
behind repeated retries.

## Diagnostics

One command must report, without mutating state:

- Installed app/helper paths, builds, architectures, identifiers, signing team,
  designated requirements, and signature validation results.
- `SMAppService.status` raw and named value.
- launchd job presence, PID, last exit status, and throttle state.
- Socket existence, owner, group, mode, and connect result.
- Peer-authentication result.
- App/helper protocol versions and negotiated capabilities.
- Console UID and connected peer UID/PID.
- Input Monitoring and Accessibility preflight state for the correct identities.
- Device enumeration and exact HID-open result.
- Whether another process owns exclusive HID access.

Every error crossing a subsystem boundary must retain its domain/facility,
numeric code, symbolic interpretation where available, and underlying error.

## Required test matrix

Automated unit/integration tests:

- Wire framing, malformed input, frame bounds, partial reads/writes.
- Authentication accepts the intended signed controller and rejects wrong UID,
  PID, identifier, certificate/team, and modified code.
- Registration-state transitions are pure and exhaustively tested.
- Version negotiation across current/previous compatible and incompatible builds.
- Device release on disconnect, timeout, crash, shutdown, and update.
- Update rollback after failures at every transaction boundary.

Installed-system tests on supported Intel and Apple-silicon macOS versions:

- Fresh install and first approval.
- Approval denied, revoked, and restored.
- App quit/relaunch and controller crash.
- Daemon crash and launchd restart with bounded behavior.
- Reboot, logout/login, Fast User Switching, sleep/wake.
- USB disconnect/reconnect and hub reconnect.
- Karabiner or another process holding HID interfaces.
- Routine upgrade while healthy, while disabled, and while the daemon is down.
- Incompatible service migration and rollback.
- Disable service, uninstall, reinstall, and same-identity orphan recovery.
- Deliberately invalid signatures and deliberate signing-identity change.

No manual acceptance test begins until build, signature, state-machine, protocol,
and scripted installed-health gates pass.

## Current RazerControl gaps

- Registration is incorrectly refreshed from `CFBundleVersion` preferences.
- `update.sh` deletes the registered provider bundle before service teardown or
  replacement validation and has no rollback transaction.
- Management commands cover only a socket self-test, not register/unregister/
  status/diagnose/update preparation.
- Error reporting drops domain and numeric Service Management details.
- Helper/client protocol does not negotiate app/helper builds or capabilities.
- The helper currently captures only a hard-coded Orbweaver interface.
- Socket ownership is fixed to the console user seen during listener creation.
- No explicit console-session transition handling exists.
- No health-only secondary diagnostic connection exists.
- Permission ownership between the app and helper is not represented clearly.
- The development self-signed identity lacks the guarantees expected from a
  stable Apple team identity for distribution and permission continuity.
- No transactional updater, rollback, signed uninstaller, orphan-recovery
  command, or installed lifecycle integration suite exists.

## Primary references

- Apple: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- Apple: [Updating your app package installer to use the new Service Management API](https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api)
- Apple: [Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- Apple: [Applying Code Requirements](https://developer.apple.com/documentation/security/applying-code-requirements)
- Apple: [SecCodeCheckValidity](https://developer.apple.com/documentation/security/seccodecheckvalidity(_:_:_:))
- Karabiner-Elements: [Development architecture and Service Management notes](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md)
- Karabiner-Elements: [Uninstall lifecycle](https://github.com/pqrs-org/Karabiner-Elements/blob/main/src/scripts/uninstall.sh)
- RustDesk: [macOS service management entry points](https://github.com/rustdesk/rustdesk/blob/master/src/core_main.rs)
- RustDesk: [macOS uninstall script](https://github.com/rustdesk/rustdesk/blob/master/src/platform/privileges_scripts/uninstall.scpt)
