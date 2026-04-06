import Testing
@testable import RazerControl

@Suite("KeyCodeMap")
struct KeyCodeTests {

    @Test("All letters A-Z have HID to CG mappings")
    func allLettersMapped() {
        for hid: UInt8 in 0x04...0x1D {
            #expect(KeyCodeMap.hidToCG[hid] != nil, "HID 0x\(String(format: "%02X", hid)) not mapped")
        }
    }

    @Test("All numbers 1-0 have HID to CG mappings")
    func allNumbersMapped() {
        for hid: UInt8 in 0x1E...0x27 {
            #expect(KeyCodeMap.hidToCG[hid] != nil, "HID 0x\(String(format: "%02X", hid)) not mapped")
        }
    }

    @Test("F1-F12 are mapped")
    func functionKeysMapped() {
        for hid: UInt8 in 0x3A...0x45 {
            #expect(KeyCodeMap.hidToCG[hid] != nil, "F\(hid - 0x39) not mapped")
        }
    }

    @Test("F13-F20 are mapped (for macro keys)")
    func macroFKeysMapped() {
        for hid: UInt8 in 0x68...0x6F {
            #expect(KeyCodeMap.hidToCG[hid] != nil, "F\(hid - 0x68 + 13) (HID 0x\(String(format: "%02X", hid))) not mapped")
        }
    }

    @Test("Modifiers are mapped")
    func modifiersMapped() {
        #expect(KeyCodeMap.hidToCG[0xE0] != nil) // Left Ctrl
        #expect(KeyCodeMap.hidToCG[0xE1] != nil) // Left Shift
        #expect(KeyCodeMap.hidToCG[0xE2] != nil) // Left Alt
        #expect(KeyCodeMap.hidToCG[0xE3] != nil) // Left Cmd
        #expect(KeyCodeMap.hidToCG[0xE4] != nil) // Right Ctrl
        #expect(KeyCodeMap.hidToCG[0xE5] != nil) // Right Shift
        #expect(KeyCodeMap.hidToCG[0xE6] != nil) // Right Alt (AltGr)
        #expect(KeyCodeMap.hidToCG[0xE7] != nil) // Right Cmd
    }

    @Test("Arrow keys are mapped")
    func arrowsMapped() {
        #expect(KeyCodeMap.hidToCG[0x4F] != nil) // Right
        #expect(KeyCodeMap.hidToCG[0x50] != nil) // Left
        #expect(KeyCodeMap.hidToCG[0x51] != nil) // Down
        #expect(KeyCodeMap.hidToCG[0x52] != nil) // Up
    }

    @Test("Numpad keys are mapped")
    func numpadMapped() {
        for hid: UInt8 in 0x53...0x63 {
            #expect(KeyCodeMap.hidToCG[hid] != nil, "Numpad HID 0x\(String(format: "%02X", hid)) not mapped")
        }
    }

    @Test("Special keys are mapped")
    func specialKeysMapped() {
        #expect(KeyCodeMap.hidToCG[0x28] != nil) // Return
        #expect(KeyCodeMap.hidToCG[0x29] != nil) // Escape
        #expect(KeyCodeMap.hidToCG[0x2A] != nil) // Backspace
        #expect(KeyCodeMap.hidToCG[0x2B] != nil) // Tab
        #expect(KeyCodeMap.hidToCG[0x2C] != nil) // Space
        #expect(KeyCodeMap.hidToCG[0x39] != nil) // Caps Lock
    }

    @Test("CG key names are human readable")
    func cgKeyNames() {
        #expect(KeyCodeMap.cgKeyName(0x24) == "Return")
        #expect(KeyCodeMap.cgKeyName(0x35) == "Esc")
        #expect(KeyCodeMap.cgKeyName(0x31) == "Space")
        #expect(KeyCodeMap.cgKeyName(0x7A) == "F1")
        #expect(KeyCodeMap.cgKeyName(0x00) == "A")
    }

    @Test("HID key names resolve through CG mapping")
    func hidKeyNames() {
        #expect(KeyCodeMap.hidKeyName(0x04) == "A")
        #expect(KeyCodeMap.hidKeyName(0x28) == "Return")
        #expect(KeyCodeMap.hidKeyName(0x29) == "Esc")
    }

    @Test("No duplicate CG keycodes for different HID codes")
    func noDuplicateCGCodes() {
        var seen: [UInt16: UInt8] = [:]
        for (hid, cg) in KeyCodeMap.hidToCG {
            if let existing = seen[cg] {
                // Some duplicates are intentional (Print Screen maps to F13, etc.)
                let allowedDuplicates: Set<UInt16> = [0x69, 0x6B, 0x71] // F13, F14, F15
                if !allowedDuplicates.contains(cg) {
                    Issue.record("CG keycode 0x\(String(format: "%02X", cg)) mapped from both HID 0x\(String(format: "%02X", existing)) and 0x\(String(format: "%02X", hid))")
                }
            }
            seen[cg] = hid
        }
    }
}
