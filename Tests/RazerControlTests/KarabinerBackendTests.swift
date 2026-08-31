import Foundation
import Testing
@testable import RazerControl

@Suite("Karabiner backend")
struct KarabinerBackendTests {
    @Test("Managed rules are device scoped and preserve existing configuration")
    func writesManagedRuleSafely() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let config = root.appendingPathComponent("karabiner.json")
        let fakeInstall = root.appendingPathComponent("Karabiner-Elements.app", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeInstall, withIntermediateDirectories: true)

        let original: [String: Any] = [
            "global": ["show_in_menu_bar": false],
            "profiles": [[
                "name": "Kris",
                "selected": true,
                "complex_modifications": [
                    "rules": [["description": "Keep me", "manipulators": []]]
                ],
            ]],
        ]
        let originalData = try JSONSerialization.data(withJSONObject: original, options: .prettyPrinted)
        try originalData.write(to: config)

        let backend = KarabinerBackend(configURL: config, installURL: fakeInstall)
        try backend.apply(
            keyMappings: [0x14: .shortcut(modifiers: 0x01, key: 0x06)],
            mouseMappings: [3: .spaceSwitch("next"), 1000: .keystroke(0x04)]
        )

        let data = try Data(contentsOf: config)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["global"] != nil)

        let profiles = try #require(json["profiles"] as? [[String: Any]])
        let complex = try #require(profiles[0]["complex_modifications"] as? [String: Any])
        let rules = try #require(complex["rules"] as? [[String: Any]])
        #expect(rules.count == 2)
        #expect(rules.contains { ($0["description"] as? String) == "Keep me" })

        let managed = try #require(rules.first {
            ($0["description"] as? String) == KarabinerBackend.managedRuleDescription
        })
        let manipulators = try #require(managed["manipulators"] as? [[String: Any]])
        #expect(manipulators.count == 3)

        let keyboardCondition = try #require(
            (manipulators[0]["conditions"] as? [[String: Any]])?.first
        )
        let keyboardIdentifiers = try #require(
            (keyboardCondition["identifiers"] as? [[String: Any]])?.first
        )
        #expect(keyboardIdentifiers["vendor_id"] as? Int == 0x1532)
        #expect(keyboardIdentifiers["product_id"] as? Int == 0x0207)

        let mouseFrom = try #require(manipulators[1]["from"] as? [String: Any])
        #expect(mouseFrom["pointing_button"] as? String == "button4")

        let keyboardMouseFrom = try #require(manipulators[2]["from"] as? [String: Any])
        #expect(keyboardMouseFrom["key_code"] as? String == "left_control")
        let keyboardMouseCondition = try #require(
            (manipulators[2]["conditions"] as? [[String: Any]])?.first
        )
        let keyboardMouseIdentifiers = try #require(
            (keyboardMouseCondition["identifiers"] as? [[String: Any]])?.first
        )
        #expect(keyboardMouseIdentifiers["product_id"] as? Int == 0x007B)
        #expect(keyboardMouseIdentifiers["is_keyboard"] == nil)
        #expect(keyboardMouseIdentifiers["is_pointing_device"] == nil)

        let backup = root.appendingPathComponent("karabiner.json.razercontrol-backup")
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test("Applying twice replaces rather than duplicates the managed rule")
    func replacesManagedRule() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let config = root.appendingPathComponent("karabiner.json")
        let fakeInstall = root.appendingPathComponent("Karabiner-Elements.app", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeInstall, withIntermediateDirectories: true)
        try Data("{\"profiles\":[{\"name\":\"Default\",\"selected\":true}]}".utf8).write(to: config)

        let backend = KarabinerBackend(configURL: config, installURL: fakeInstall)
        try backend.apply(keyMappings: [0x04: .keystroke(0x05)], mouseMappings: [:])
        try backend.apply(keyMappings: [0x04: .disabled], mouseMappings: [:])

        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        )
        let profiles = try #require(json["profiles"] as? [[String: Any]])
        let complex = try #require(profiles[0]["complex_modifications"] as? [String: Any])
        let rules = try #require(complex["rules"] as? [[String: Any]])
        #expect(rules.filter {
            ($0["description"] as? String) == KarabinerBackend.managedRuleDescription
        }.count == 1)
    }

    @Test("Extended function keys are accepted as sources and targets")
    func supportsExtendedFunctionKeys() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let config = root.appendingPathComponent("karabiner.json")
        let fakeInstall = root.appendingPathComponent("Karabiner-Elements.app", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeInstall, withIntermediateDirectories: true)
        try Data("{\"profiles\":[{\"name\":\"Default\",\"selected\":true}]}".utf8).write(to: config)

        let backend = KarabinerBackend(configURL: config, installURL: fakeInstall)
        try backend.apply(keyMappings: [0x68: .keystroke(0x73)], mouseMappings: [:])

        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        )
        let profiles = try #require(json["profiles"] as? [[String: Any]])
        let complex = try #require(profiles[0]["complex_modifications"] as? [String: Any])
        let rules = try #require(complex["rules"] as? [[String: Any]])
        let manipulators = try #require(rules[0]["manipulators"] as? [[String: Any]])
        let from = try #require(manipulators[0]["from"] as? [String: Any])
        let to = try #require((manipulators[0]["to"] as? [[String: Any]])?.first)
        #expect(from["key_code"] as? String == "f13")
        #expect(to["key_code"] as? String == "f24")
    }

    @Test("Print Screen is accepted as a mapping source")
    func supportsPrintScreen() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let config = root.appendingPathComponent("karabiner.json")
        let fakeInstall = root.appendingPathComponent("Karabiner-Elements.app", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeInstall, withIntermediateDirectories: true)
        try Data("{\"profiles\":[{\"name\":\"Default\",\"selected\":true}]}".utf8).write(to: config)

        let backend = KarabinerBackend(configURL: config, installURL: fakeInstall)
        try backend.apply(keyMappings: [0x46: .keystroke(0x68)], mouseMappings: [:])
    }
}
