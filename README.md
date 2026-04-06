# RazerControl

Open source macOS app for configuring Razer keyboards and mice on **Intel and Apple Silicon** Macs.

Razer Synapse for Mac only supports Apple Silicon. This app fills the gap using the USB protocol documented by the [OpenRazer](https://github.com/openrazer/openrazer) project.

## Features

- **Key Remapping** — Remap any key including macro keys (M1-M8), media keys, and the Command Dial
- **RGB Lighting** — Static, breathing, wave, spectrum, reactive, starlight effects with per-key support
- **Mouse Button Mapping** — Remap side buttons, DPI stages, and scroll behavior
- **Multiple Layouts** — QWERTY (US), QWERTZ (DE/CH), AZERTY (FR) keyboard layouts
- **No Root Required** — Uses IOKit HID Manager, no kernel extensions or sudo needed
- **280+ Devices** — Device database derived from OpenRazer

## Supported Devices

Primary test devices:
- Razer BlackWidow V4 Pro
- Razer Pro Click V2 Vertical Edition

See [device database](Sources/RazerControl/Core/DeviceDB/) for full list.

## Requirements

- macOS 13 (Ventura) or later
- Intel or Apple Silicon Mac
- Razer USB device

## Install

Download the latest DMG from [Releases](../../releases), or build from source:

```bash
git clone https://github.com/YOUR_USERNAME/RazerControl.git
cd RazerControl
swift build
swift run RazerControl
```

## Permissions

| Feature | Permission Required |
|---------|-------------------|
| RGB Lighting | None |
| Device Detection | None |
| Key Remapping | Input Monitoring + Accessibility |

The app will guide you through granting permissions on first launch.

## License

GPLv2 — Compatible with [OpenRazer](https://github.com/openrazer/openrazer) from which the device database and protocol documentation are derived.

## Acknowledgments

- [OpenRazer](https://github.com/openrazer/openrazer) — USB protocol documentation and device database
- [razer-macos](https://github.com/1kc/razer-macos) — macOS RGB control reference
