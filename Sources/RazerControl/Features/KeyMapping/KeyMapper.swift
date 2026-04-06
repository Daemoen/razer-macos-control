import Foundation
import CoreGraphics
import Combine
import AppKit

// MARK: - Key Mapper
//
// Intercepts keyboard events via CGEventTap and remaps them based on
// the active profile's key mappings. Requires Accessibility permission.
//
// Flow: physical key press → CGEventTap callback → lookup mapping →
//       suppress original + inject remapped key via CGEventPost

@MainActor
final class KeyMapper: ObservableObject {
    @Published var isActive = false
    @Published var lastCapturedKey: CapturedKey?
    @Published var error: String?

    /// When true, next key press is captured for assignment (not remapped)
    @Published var isCapturing = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mappings: [UInt16: KeyAction] = [:]  // CGKeyCode → action

    // Callback needs a static context pointer
    private static var sharedInstance: KeyMapper?

    // MARK: - Start / Stop

    func start(with mappings: [UInt8: KeyAction]) {
        guard !isActive else { return }

        // Convert HID keycodes to CGKeyCodes for the event tap
        self.mappings = [:]
        for (hidCode, action) in mappings {
            if let cgKey = KeyCodeMap.hidToCG[hidCode] {
                self.mappings[cgKey] = action
            }
        }

        // Store instance for C callback
        KeyMapper.sharedInstance = self

        // Create event tap
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: KeyMapper.eventTapCallback,
            userInfo: nil
        ) else {
            error = "Failed to create event tap. Grant Accessibility permission."
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        error = nil
        print("[KeyMapper] Started with \(self.mappings.count) mappings")
    }

    func stop() {
        guard isActive else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isActive = false
        KeyMapper.sharedInstance = nil
        print("[KeyMapper] Stopped")
    }

    func updateMappings(_ mappings: [UInt8: KeyAction]) {
        self.mappings = [:]
        for (hidCode, action) in mappings {
            if let cgKey = KeyCodeMap.hidToCG[hidCode] {
                self.mappings[cgKey] = action
            }
        }
    }

    // MARK: - Capture Mode

    /// Start capturing: next key press will be recorded, not remapped
    func startCapture() {
        isCapturing = true
        lastCapturedKey = nil
    }

    func stopCapture() {
        isCapturing = false
    }

    // MARK: - Event Tap Callback (C function)

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, _ in
        guard let mapper = KeyMapper.sharedInstance else {
            return Unmanaged.passRetained(event)
        }

        // Handle tap disabled (system disables taps if they're too slow)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = mapper.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Capture mode: record the key and suppress
        if mapper.isCapturing {
            let isKeyDown = type == .keyDown
            if isKeyDown {
                let flags = event.flags
                Task { @MainActor in
                    mapper.lastCapturedKey = CapturedKey(
                        cgKeyCode: keyCode,
                        modifiers: flags,
                        name: KeyCodeMap.cgKeyName(keyCode)
                    )
                    mapper.isCapturing = false
                }
            }
            return nil // suppress
        }

        // Remap mode: check if this key has a mapping
        guard let action = mapper.mappings[keyCode] else {
            return Unmanaged.passRetained(event) // no mapping, pass through
        }

        let isKeyDown = (type == .keyDown)

        // Execute the action
        switch action {
        case .keystroke(let targetKey):
            return mapper.remapToKey(targetKey, isDown: isKeyDown, originalEvent: event)

        case .shortcut(let modifiers, let key):
            return mapper.remapToShortcut(modifiers: modifiers, key: key, isDown: isKeyDown, originalEvent: event)

        case .launchApp(let bundleId):
            if isKeyDown {
                Task { @MainActor in
                    NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleId,
                                                        options: [], additionalEventParamDescriptor: nil,
                                                        launchIdentifier: nil)
                }
            }
            return nil // suppress original

        case .mediaControl(let control):
            if isKeyDown {
                mapper.sendMediaKey(control)
            }
            return nil

        case .macroSequence(let steps):
            if isKeyDown {
                mapper.executeMacro(steps)
            }
            return nil

        case .disabled:
            return nil // suppress
        }
    }

    // MARK: - Remap Helpers

    private func remapToKey(_ targetKey: UInt8, isDown: Bool, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard let cgKey = KeyCodeMap.hidToCG[targetKey] else {
            return Unmanaged.passRetained(originalEvent)
        }

        let eventType: CGEventType = isDown ? .keyDown : .keyUp
        if let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: cgKey, keyDown: isDown) {
            newEvent.flags = originalEvent.flags
            return Unmanaged.passRetained(newEvent)
        }
        return Unmanaged.passRetained(originalEvent)
    }

    private func remapToShortcut(modifiers: UInt8, key: UInt8, isDown: Bool, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard let cgKey = KeyCodeMap.hidToCG[key] else { return nil }

        if let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: cgKey, keyDown: isDown) {
            var flags = CGEventFlags()
            if modifiers & 0x01 != 0 { flags.insert(.maskCommand) }
            if modifiers & 0x02 != 0 { flags.insert(.maskShift) }
            if modifiers & 0x04 != 0 { flags.insert(.maskAlternate) }
            if modifiers & 0x08 != 0 { flags.insert(.maskControl) }
            newEvent.flags = flags
            return Unmanaged.passRetained(newEvent)
        }
        return nil
    }

    private func sendMediaKey(_ control: String) {
        let keyCode: Int32
        switch control {
        case "play", "pause": keyCode = 16 // NX_KEYTYPE_PLAY
        case "next":          keyCode = 17 // NX_KEYTYPE_NEXT
        case "prev":          keyCode = 18 // NX_KEYTYPE_PREVIOUS
        case "mute":          keyCode = 7  // NX_KEYTYPE_MUTE
        case "volumeUp":      keyCode = 0  // NX_KEYTYPE_SOUND_UP
        case "volumeDown":    keyCode = 1  // NX_KEYTYPE_SOUND_DOWN
        default: return
        }

        // Media keys use NSEvent system-defined events
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((keyCode << 16) | (0xa << 8)),
            data2: -1
        )
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((keyCode << 16) | (0xb << 8)),
            data2: -1
        )

        keyDown?.cgEvent?.post(tap: .cghidEventTap)
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func executeMacro(_ steps: [MacroStep]) {
        // Run macro on background thread to not block the event tap
        DispatchQueue.global(qos: .userInteractive).async {
            for step in steps {
                guard let cgKey = KeyCodeMap.hidToCG[step.keyCode] else { continue }
                if let event = CGEvent(keyboardEventSource: nil, virtualKey: cgKey, keyDown: step.isPress) {
                    event.post(tap: .cghidEventTap)
                }
                if step.delayMs > 0 {
                    usleep(UInt32(step.delayMs) * 1000)
                }
            }
        }
    }
}

// MARK: - Captured Key

struct CapturedKey {
    let cgKeyCode: UInt16
    let modifiers: CGEventFlags
    let name: String

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.maskCommand) { parts.append("Cmd") }
        if modifiers.contains(.maskShift) { parts.append("Shift") }
        if modifiers.contains(.maskAlternate) { parts.append("Opt") }
        if modifiers.contains(.maskControl) { parts.append("Ctrl") }
        parts.append(name)
        return parts.joined(separator: " + ")
    }
}
