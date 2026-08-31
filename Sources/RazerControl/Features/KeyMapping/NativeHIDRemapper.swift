import AppKit
import CoreGraphics

/// Executes mappings for a device already seized by RazerHIDInputMonitor.
/// The physical report is suppressed at IOHID, so emitted events cannot loop
/// back into this backend and other keyboards remain completely unaffected.
@MainActor
final class NativeHIDRemapper {
    private var mappings: [UInt8: KeyAction] = [:]
    private var activeActions: [UInt8: KeyAction] = [:]

    func updateMappings(_ mappings: [UInt8: KeyAction]) {
        self.mappings = mappings
    }

    func handle(source: UInt8, isPressed: Bool) {
        if isPressed {
            guard activeActions[source] == nil else { return }
            // A seized device must replay unmapped controls so it behaves like
            // the factory device until the user assigns an override.
            let action = mappings[source] ?? .keystroke(source)
            activeActions[source] = action
            execute(action, isPressed: true)
        } else if let action = activeActions.removeValue(forKey: source) {
            execute(action, isPressed: false)
        }
    }

    func releaseAll() {
        for action in activeActions.values { execute(action, isPressed: false) }
        activeActions.removeAll()
    }

    private func execute(_ action: KeyAction, isPressed: Bool) {
        switch action {
        case .keystroke(let usage):
            postKey(usage, isPressed: isPressed)

        case .shortcut(let modifiers, let usage):
            if isPressed {
                postModifiers(modifiers, isPressed: true)
                postKey(usage, isPressed: true)
            } else {
                postKey(usage, isPressed: false)
                postModifiers(modifiers, isPressed: false)
            }

        case .disabled:
            break

        case .launchApp(let bundleId):
            guard isPressed else { return }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }

        case .mediaControl(let control):
            guard isPressed else { return }
            postMediaKey(control)

        case .macroSequence(let steps):
            guard isPressed else { return }
            DispatchQueue.global(qos: .userInteractive).async {
                for step in steps {
                    Self.postKeyFromBackground(step.keyCode, isPressed: step.isPress)
                    if step.delayMs > 0 { usleep(UInt32(step.delayMs) * 1_000) }
                }
            }

        case .spaceSwitch(let direction):
            guard isPressed else { return }
            if direction == "next" { SpaceSwitcher.shared.switchToNextSpace() }
            else if direction == "previous" { SpaceSwitcher.shared.switchToPreviousSpace() }
            else if let index = Int(direction) { SpaceSwitcher.shared.switchToSpace(index: index - 1) }
        }
    }

    private func postKey(_ usage: UInt8, isPressed: Bool) {
        Self.postKeyFromBackground(usage, isPressed: isPressed)
    }

    nonisolated private static func postKeyFromBackground(_ usage: UInt8, isPressed: Bool) {
        guard let keyCode = KeyCodeMap.hidToCG[usage],
              let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isPressed)
        else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postModifiers(_ bits: UInt8, isPressed: Bool) {
        let usages: [UInt8] = [
            bits & 0x01 != 0 ? 0xE3 : 0,
            bits & 0x02 != 0 ? 0xE1 : 0,
            bits & 0x04 != 0 ? 0xE2 : 0,
            bits & 0x08 != 0 ? 0xE0 : 0,
        ].filter { $0 != 0 }
        for usage in isPressed ? usages : usages.reversed() { postKey(usage, isPressed: isPressed) }
    }

    private func postMediaKey(_ control: String) {
        let codes = ["play": 16, "pause": 16, "next": 17, "prev": 18, "mute": 7,
                     "volumeUp": 0, "volumeDown": 1]
        guard let code = codes[control] else { return }
        for (flags, state) in [(0xa00, 0xa), (0xb00, 0xb)] {
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (code << 16) | (state << 8), data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
