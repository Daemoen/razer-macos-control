# RazerControl - macOS App for Razer Devices

## Project Overview
Open source macOS app (Intel + Apple Silicon) for configuring Razer keyboards and mice.
Replaces Razer Synapse which only supports Apple Silicon Macs.
Uses IOKit HID Manager for USB communication (no root, no kext required).

## Tech Stack
- **Language:** Swift 6.2 / SwiftUI (macOS 13+)
- **USB:** IOKit HID Manager (IOHIDDeviceSetReport / IOHIDDeviceGetReport)
- **Build:** Swift Package Manager (SPM) - `swift build` / `swift run RazerControl`
- **No external dependencies** - all Apple frameworks

## Architecture
```
Sources/RazerControl/
├── App/          → Entry point, AppDelegate
├── Core/
│   ├── HID/      → IOKit device discovery + USB communication
│   ├── Protocol/ → Razer 90-byte USB packet format, CRC, commands
│   ├── DeviceDB/ → Static database of ~280 Razer PIDs + capabilities
│   └── Permissions/ → TCC permission checking (Input Monitoring, Accessibility)
├── Features/
│   ├── KeyMapping/ → HID input capture → remap → CGEventPost
│   ├── RGB/        → Lighting effect commands
│   └── Profiles/   → JSON profiles in ~/Library/Application Support/RazerControl/
└── UI/
    ├── Theme/    → Dark theme (Razer green #00FF00, dark grays)
    ├── Keyboard/ → Visual keyboard layout, key mapper, test input
    ├── Mouse/    → Vertical mouse layout, button mapper, DPI
    ├── Lighting/ → Color picker, effect selector, live preview
    └── Setup/    → Permission request wizard
```

## Key Technical Details

### Razer USB Protocol
- 90-byte packets: [status][txid][remaining][proto][size][class][cmd][args...][crc][reserved]
- CRC = XOR of bytes 2..87
- USB Control Transfer: requestType=0x21, request=0x09, value=0x300, index=0x02
- Three protocol generations: Standard (class 0x03), Extended (class 0x0F), Mouse Extended
- Macro key init: class=0x00, id=0x04, args=[0x03, 0x00]
- Device database derived from OpenRazer project (GPLv2)

### Permissions
- **RGB lighting control:** No permissions needed (write-only HID feature reports)
- **Key mapping (read input):** Requires Input Monitoring TCC
- **Synthetic key injection:** Requires Accessibility TCC
- Use IOKit HID Manager (not libusb) to avoid needing root

### Primary test devices
- BlackWidow V4 Pro (PID 0x028D) - QWERTZ ISO layout
- Pro Click V2 Vertical Edition (PID 0x00C7 wired, 0x00C8 wireless)

## Build & Run
```bash
swift build          # Build
swift run RazerControl  # Run
```

## Code Style
- SwiftUI views, MVVM-ish separation
- Theme colors via Color extensions (Color.razerGreen, Color.razerSurface, etc.)
- Card-style UI components via .razerCard() modifier
- Button styles: .razerPrimary, .razerSecondary
