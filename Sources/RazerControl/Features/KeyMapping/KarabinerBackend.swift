import Foundation

// MARK: - Karabiner Remapping Backend

/// Writes one device-scoped rule into the selected Karabiner profile.
/// All unrelated Karabiner settings are preserved byte-for-byte at the JSON
/// object level, and the previous configuration is backed up before writing.
final class KarabinerBackend {
    static let managedRuleDescription = "RazerControl — managed device mappings"

    enum BackendError: LocalizedError {
        case karabinerNotInstalled
        case missingConfiguration
        case invalidConfiguration
        case noSelectedProfile
        case unsupportedKey(UInt8)
        case unsupportedAction

        var errorDescription: String? {
            switch self {
            case .karabinerNotInstalled:
                return "Karabiner-Elements is not installed"
            case .missingConfiguration:
                return "Open Karabiner-Elements once to create its configuration"
            case .invalidConfiguration:
                return "Karabiner's configuration is not valid JSON"
            case .noSelectedProfile:
                return "Karabiner has no selected profile"
            case .unsupportedKey(let code):
                return "Key 0x\(String(format: "%02X", code)) is not supported"
            case .unsupportedAction:
                return "That action cannot yet be represented in Karabiner"
            }
        }
    }

    private let fileManager: FileManager
    private let configURL: URL
    private let installURL: URL

    init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/karabiner/karabiner.json"),
        installURL: URL = URL(fileURLWithPath: "/Applications/Karabiner-Elements.app"),
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL
        self.installURL = installURL
        self.fileManager = fileManager
    }

    var isInstalled: Bool { fileManager.fileExists(atPath: installURL.path) }
    var isConfigured: Bool { isInstalled && fileManager.fileExists(atPath: configURL.path) }

    /// Replace only RazerControl's managed rule in the selected profile.
    func apply(keyMappings: [UInt8: KeyAction], mouseMappings: [Int: KeyAction]) throws {
        guard isInstalled else { throw BackendError.karabinerNotInstalled }
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw BackendError.missingConfiguration
        }

        let originalData = try Data(contentsOf: configURL)
        guard var root = try JSONSerialization.jsonObject(with: originalData) as? [String: Any],
              var profiles = root["profiles"] as? [[String: Any]] else {
            throw BackendError.invalidConfiguration
        }

        guard let profileIndex = profiles.firstIndex(where: { ($0["selected"] as? Bool) == true })
                ?? profiles.indices.first else {
            throw BackendError.noSelectedProfile
        }

        var profile = profiles[profileIndex]
        var complex = profile["complex_modifications"] as? [String: Any] ?? [:]
        var rules = complex["rules"] as? [[String: Any]] ?? []
        rules.removeAll { ($0["description"] as? String) == Self.managedRuleDescription }

        let manipulators = try makeManipulators(
            keyMappings: keyMappings,
            mouseMappings: mouseMappings
        )
        if !manipulators.isEmpty {
            rules.append([
                "description": Self.managedRuleDescription,
                "manipulators": manipulators,
            ])
        }

        complex["rules"] = rules
        profile["complex_modifications"] = complex
        profiles[profileIndex] = profile
        root["profiles"] = profiles

        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let backupURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("karabiner.json.razercontrol-backup")
        let originalAttributes = try? fileManager.attributesOfItem(atPath: configURL.path)
        let originalPermissions = originalAttributes?[.posixPermissions]
        try originalData.write(to: backupURL, options: .atomic)
        try output.write(to: configURL, options: .atomic)
        if let originalPermissions {
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: originalPermissions]
            try fileManager.setAttributes(attributes, ofItemAtPath: configURL.path)
            try fileManager.setAttributes(attributes, ofItemAtPath: backupURL.path)
        }
    }

    private func makeManipulators(
        keyMappings: [UInt8: KeyAction],
        mouseMappings: [Int: KeyAction]
    ) throws -> [[String: Any]] {
        var result: [[String: Any]] = []

        for (source, action) in keyMappings.sorted(by: { $0.key < $1.key }) {
            guard let sourceName = Self.karabinerKeyNames[source] else {
                throw BackendError.unsupportedKey(source)
            }
            result.append([
                "type": "basic",
                "from": [
                    "key_code": sourceName,
                    "modifiers": ["optional": ["any"]],
                ],
                "to": try karabinerOutput(for: action),
                "conditions": [Self.deviceCondition(pid: 0x0207)],
            ])
        }

        for (source, action) in mouseMappings.sorted(by: { $0.key < $1.key }) {
            let from: [String: Any]
            switch source {
            case 1000:
                from = ["key_code": "left_control", "modifiers": ["optional": ["any"]]]
            case 1001:
                from = ["key_code": "left_option", "modifiers": ["optional": ["any"]]]
            default:
                from = ["pointing_button": "button\(source + 1)"]
            }
            result.append([
                "type": "basic",
                "from": from,
                "to": try karabinerOutput(for: action),
                "conditions": [Self.deviceCondition(pid: 0x007B)],
            ])
        }

        return result
    }

    private static func deviceCondition(pid: UInt16) -> [String: Any] {
        [
            "type": "device_if",
            "identifiers": [[
                "vendor_id": 0x1532,
                "product_id": Int(pid),
            ]],
        ]
    }

    private func karabinerOutput(for action: KeyAction) throws -> [[String: Any]] {
        switch action {
        case .keystroke(let key):
            guard let name = Self.karabinerKeyNames[key] else {
                throw BackendError.unsupportedKey(key)
            }
            return [["key_code": name]]

        case .shortcut(let modifiers, let key):
            guard let name = Self.karabinerKeyNames[key] else {
                throw BackendError.unsupportedKey(key)
            }
            return [[
                "key_code": name,
                "modifiers": Self.modifierNames(modifiers),
            ]]

        case .spaceSwitch(let direction):
            if direction == "next" {
                return [["key_code": "right_arrow", "modifiers": ["left_control"]]]
            }
            if direction == "previous" {
                return [["key_code": "left_arrow", "modifiers": ["left_control"]]]
            }
            if let number = Int(direction), (1...9).contains(number) {
                return [["key_code": String(number), "modifiers": ["left_control"]]]
            }
            throw BackendError.unsupportedAction

        case .launchApp(let bundleId):
            return [[
                "software_function": [
                    "open_application": ["bundle_identifier": bundleId]
                ]
            ]]

        case .mediaControl(let control):
            let names = [
                "play": "play_or_pause", "pause": "play_or_pause",
                "next": "fast_forward", "prev": "rewind", "mute": "mute",
            ]
            guard let name = names[control] else { throw BackendError.unsupportedAction }
            return [["consumer_key_code": name]]

        case .disabled:
            return [["key_code": "vk_none"]]

        case .macroSequence:
            throw BackendError.unsupportedAction
        }
    }

    private static func modifierNames(_ value: UInt8) -> [String] {
        var result: [String] = []
        if value & 0x01 != 0 { result.append("left_command") }
        if value & 0x02 != 0 { result.append("left_shift") }
        if value & 0x04 != 0 { result.append("left_option") }
        if value & 0x08 != 0 { result.append("left_control") }
        return result
    }

    private static let karabinerKeyNames: [UInt8: String] = [
        0x04: "a", 0x05: "b", 0x06: "c", 0x07: "d", 0x08: "e", 0x09: "f",
        0x0A: "g", 0x0B: "h", 0x0C: "i", 0x0D: "j", 0x0E: "k", 0x0F: "l",
        0x10: "m", 0x11: "n", 0x12: "o", 0x13: "p", 0x14: "q", 0x15: "r",
        0x16: "s", 0x17: "t", 0x18: "u", 0x19: "v", 0x1A: "w", 0x1B: "x",
        0x1C: "y", 0x1D: "z",
        0x1E: "1", 0x1F: "2", 0x20: "3", 0x21: "4", 0x22: "5",
        0x23: "6", 0x24: "7", 0x25: "8", 0x26: "9", 0x27: "0",
        0x28: "return_or_enter", 0x29: "escape", 0x2A: "delete_or_backspace",
        0x2B: "tab", 0x2C: "spacebar", 0x2D: "hyphen", 0x2E: "equal_sign",
        0x2F: "open_bracket", 0x30: "close_bracket", 0x31: "backslash",
        0x33: "semicolon", 0x34: "quote", 0x35: "grave_accent_and_tilde",
        0x36: "comma", 0x37: "period", 0x38: "slash", 0x39: "caps_lock",
        0x3A: "f1", 0x3B: "f2", 0x3C: "f3", 0x3D: "f4", 0x3E: "f5",
        0x3F: "f6", 0x40: "f7", 0x41: "f8", 0x42: "f9", 0x43: "f10",
        0x44: "f11", 0x45: "f12",
        0x46: "print_screen", 0x47: "scroll_lock", 0x48: "pause",
        0x68: "f13", 0x69: "f14", 0x6A: "f15", 0x6B: "f16",
        0x6C: "f17", 0x6D: "f18", 0x6E: "f19", 0x6F: "f20",
        0x70: "f21", 0x71: "f22", 0x72: "f23", 0x73: "f24",
        0x49: "insert", 0x4A: "home",
        0x4B: "page_up", 0x4C: "delete_forward", 0x4D: "end", 0x4E: "page_down",
        0x4F: "right_arrow", 0x50: "left_arrow", 0x51: "down_arrow", 0x52: "up_arrow",
        0x53: "keypad_num_lock", 0x54: "keypad_slash", 0x55: "keypad_asterisk",
        0x56: "keypad_hyphen", 0x57: "keypad_plus", 0x58: "keypad_enter",
        0x59: "keypad_1", 0x5A: "keypad_2", 0x5B: "keypad_3", 0x5C: "keypad_4",
        0x5D: "keypad_5", 0x5E: "keypad_6", 0x5F: "keypad_7", 0x60: "keypad_8",
        0x61: "keypad_9", 0x62: "keypad_0", 0x63: "keypad_period",
        0x64: "non_us_backslash", 0x65: "application",
        0xE0: "left_control", 0xE1: "left_shift", 0xE2: "left_option",
        0xE3: "left_command", 0xE4: "right_control", 0xE5: "right_shift",
        0xE6: "right_option", 0xE7: "right_command",
    ]
}
