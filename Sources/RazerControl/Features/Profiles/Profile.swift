import Foundation
import SwiftUI

// MARK: - Profile

struct DeviceProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var devicePID: UInt16
    var deviceSerial: String
    var createdAt: Date
    var updatedAt: Date

    // Lighting
    var lighting: LightingConfig

    // Key mappings (HID code → action)
    var keyMappings: [UInt8: KeyAction]

    // Mouse DPI
    var dpiStages: [Int]
    var activeDPIStage: Int

    init(name: String = "Default", devicePID: UInt16, deviceSerial: String = "") {
        self.id = UUID()
        self.name = name
        self.devicePID = devicePID
        self.deviceSerial = deviceSerial
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lighting = LightingConfig()
        self.keyMappings = [:]
        self.dpiStages = [400, 800, 1600, 3200, 6400]
        self.activeDPIStage = 2  // 1600
    }
}

// MARK: - Lighting Config

struct LightingConfig: Codable {
    var effect: String   // "static", "breathing", "wave", "spectrum", "off"
    var primaryColor: CodableColor
    var secondaryColor: CodableColor
    var brightness: Double
    var speed: Double
    var waveDirection: Int  // 0=left-to-right, 1=right-to-left
    var zone: String       // "all", "backlight", "logo", "underglow"

    init() {
        self.effect = "static"
        self.primaryColor = CodableColor(r: 0, g: 255, b: 0) // Razer green
        self.secondaryColor = CodableColor(r: 0, g: 0, b: 255)
        self.brightness = 1.0
        self.speed = 0.5
        self.waveDirection = 0
        self.zone = "all"
    }
}

// MARK: - Codable Color (SwiftUI Color isn't Codable)

struct CodableColor: Codable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    var swiftUIColor: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    init(from color: Color) {
        let (r, g, b) = color.rgbBytes
        self.r = r; self.g = g; self.b = b
    }
}

// MARK: - Key Action

enum KeyAction: Codable {
    case keystroke(UInt8)                    // Single key (virtual keycode)
    case shortcut(modifiers: UInt8, key: UInt8) // Modifier + key
    case launchApp(bundleId: String)         // Open application
    case mediaControl(String)                // play, pause, next, prev, mute
    case macroSequence([MacroStep])          // Sequence of key events
    case disabled                            // Key does nothing
}

struct MacroStep: Codable {
    var keyCode: UInt8
    var isPress: Bool    // true = press, false = release
    var delayMs: UInt16  // delay after this step
}
