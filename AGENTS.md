# AGENTS.md

## Project
- `RazerControl` is a macOS 13+ SwiftUI app for configuring Razer keyboards and mice.
- The project uses Swift Package Manager and ships as a single executable target.
- There are no external dependencies; prefer Apple frameworks and existing project code.

## Build And Run
- Build with `swift build`.
- Run with `swift run RazerControl`.
- Prefer targeted validation for touched code before suggesting broader checks.

## Repository Structure
- `Sources/RazerControl/App/` contains the app entry point and app lifecycle code.
- `Sources/RazerControl/Core/` contains HID, protocol, permissions, and device database code.
- `Sources/RazerControl/Features/` contains user-facing feature logic like key mapping, RGB, and profiles.
- `Sources/RazerControl/UI/` contains SwiftUI views, theme helpers, and reusable UI components.

## Editing Guidelines
- Use SwiftUI for UI work and keep styling consistent with the existing Razer theme system.
- Keep USB protocol details in `Core/Protocol/` and device-specific definitions in `Core/DeviceDB/`.
- Prefer small, surgical changes that match the existing architecture and naming.
- Do not add external dependencies unless the user explicitly asks for them.
- Update documentation when behavior, setup, or supported devices materially change.

## Validation
- For code changes, start with the smallest relevant build or test command.
- If hardware-specific behavior changes, call out what still needs manual verification on a real device.
- Avoid claiming device behavior was verified unless you actually ran it against hardware.

## Notes
- Key remapping features may require Input Monitoring and Accessibility permissions.
- RGB/device detection paths generally do not require elevated privileges.
