# Contributing to RazerControl

## Adding Support for a New Device

1. Find the device's USB PID in the [OpenRazer source](https://github.com/openrazer/openrazer)
2. Add a `DeviceInfo` entry in the appropriate file under `Sources/RazerControl/Core/DeviceDB/`
3. Specify capabilities: RGB zones, macro keys, matrix dimensions, protocol version
4. Test with a real device if possible
5. Submit a PR with the device name in the title

## Development Setup

```bash
# Clone
git clone https://github.com/YOUR_USERNAME/RazerControl.git
cd RazerControl

# Build
swift build

# Run
swift run RazerControl
```

Requires: macOS 13+, Xcode 15+ (for Swift 5.9+), no external dependencies.

## Code Guidelines

- Use SwiftUI for all new views
- Follow existing theme system (Color.razer*, RazerFont.*, .razerCard())
- Keep USB protocol code in Core/Protocol/
- Device-specific logic goes in Core/DeviceDB/
- No external dependencies unless absolutely necessary

## Testing

- Test RGB commands with a real device before submitting
- Use the Test Input field in the Keyboard tab to verify key mappings
- Check that the app builds on both Intel and Apple Silicon

## License

By contributing, you agree that your contributions will be licensed under GPLv2.
