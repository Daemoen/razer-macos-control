import Testing
import Foundation
@testable import RazerControl

@Suite("Profile")
struct ProfileTests {

    @Test("Default profile has correct initial values")
    func defaultProfile() {
        let profile = DeviceProfile(name: "Test", devicePID: 0x028D)

        #expect(profile.name == "Test")
        #expect(profile.devicePID == 0x028D)
        #expect(profile.lighting.effect == "static")
        #expect(profile.lighting.brightness == 1.0)
        #expect(profile.lighting.primaryColor.r == 0)
        #expect(profile.lighting.primaryColor.g == 255) // Razer green
        #expect(profile.lighting.primaryColor.b == 0)
        #expect(profile.keyMappings.isEmpty)
        #expect(profile.dpiStages == [400, 800, 1600, 3200, 6400])
        #expect(profile.activeDPIStage == 2)
    }

    @Test("Profile serializes to and from JSON")
    func jsonRoundTrip() throws {
        var profile = DeviceProfile(name: "Round Trip", devicePID: 0x00C7, deviceSerial: "SN12345")
        profile.lighting.effect = "wave"
        profile.lighting.brightness = 0.75
        profile.lighting.primaryColor = CodableColor(r: 255, g: 0, b: 128)
        profile.keyMappings[0x68] = .keystroke(0x04) // F13 → A
        profile.keyMappings[0x69] = .disabled
        profile.dpiStages = [800, 1600, 3200]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DeviceProfile.self, from: data)

        #expect(decoded.name == "Round Trip")
        #expect(decoded.devicePID == 0x00C7)
        #expect(decoded.deviceSerial == "SN12345")
        #expect(decoded.lighting.effect == "wave")
        #expect(decoded.lighting.brightness == 0.75)
        #expect(decoded.lighting.primaryColor.r == 255)
        #expect(decoded.lighting.primaryColor.g == 0)
        #expect(decoded.lighting.primaryColor.b == 128)
        #expect(decoded.dpiStages == [800, 1600, 3200])

        // Check key mappings survived
        if case .keystroke(let key) = decoded.keyMappings[0x68] {
            #expect(key == 0x04)
        } else {
            Issue.record("keyMappings[0x68] should be .keystroke(0x04)")
        }

        if case .disabled = decoded.keyMappings[0x69] {
            // ok
        } else {
            Issue.record("keyMappings[0x69] should be .disabled")
        }
    }

    @Test("KeyAction.shortcut serializes correctly")
    func shortcutSerialization() throws {
        let action = KeyAction.shortcut(modifiers: 0x03, key: 0x06) // Cmd+Shift+Z
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(KeyAction.self, from: data)

        if case .shortcut(let mods, let key) = decoded {
            #expect(mods == 0x03)
            #expect(key == 0x06)
        } else {
            Issue.record("Expected .shortcut, got \(decoded)")
        }
    }

    @Test("KeyAction.macroSequence serializes correctly")
    func macroSerialization() throws {
        let steps = [
            MacroStep(keyCode: 0x04, isPress: true, delayMs: 50),
            MacroStep(keyCode: 0x04, isPress: false, delayMs: 0),
        ]
        let action = KeyAction.macroSequence(steps)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(KeyAction.self, from: data)

        if case .macroSequence(let decodedSteps) = decoded {
            #expect(decodedSteps.count == 2)
            #expect(decodedSteps[0].keyCode == 0x04)
            #expect(decodedSteps[0].isPress == true)
            #expect(decodedSteps[0].delayMs == 50)
        } else {
            Issue.record("Expected .macroSequence")
        }
    }

    @Test("KeyAction.launchApp serializes correctly")
    func launchAppSerialization() throws {
        let action = KeyAction.launchApp(bundleId: "com.apple.Terminal")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(KeyAction.self, from: data)

        if case .launchApp(let bid) = decoded {
            #expect(bid == "com.apple.Terminal")
        } else {
            Issue.record("Expected .launchApp")
        }
    }

    @Test("CodableColor converts to SwiftUI Color")
    func codableColor() {
        let cc = CodableColor(r: 0, g: 255, b: 0)
        let color = cc.swiftUIColor
        // Can't easily test SwiftUI Color equality, but we can test CodableColor roundtrip
        let cc2 = CodableColor(from: color)
        #expect(cc2.r == 0)
        #expect(cc2.g == 255)
        #expect(cc2.b == 0)
    }

    @Test("LightingConfig has sane defaults")
    func lightingDefaults() {
        let config = LightingConfig()
        #expect(config.effect == "static")
        #expect(config.brightness >= 0 && config.brightness <= 1)
        #expect(config.speed >= 0 && config.speed <= 1)
        #expect(config.waveDirection == 0 || config.waveDirection == 1)
    }
}
