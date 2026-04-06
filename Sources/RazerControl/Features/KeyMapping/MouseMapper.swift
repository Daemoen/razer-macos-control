import Foundation
import CoreGraphics
import AppKit

// MARK: - Mouse Button Mapper
//
// Intercepts mouse button events (specifically side buttons 4 and 5)
// and remaps them to custom actions. Uses CGEventTap like KeyMapper.
// Side buttons on Pro Click V2 Vertical send standard HID button 4/5
// without needing any initialization.

@MainActor
final class MouseMapper: ObservableObject {
    @Published var isActive = false
    @Published var error: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Button number (CGMouseButton raw value) → action
    private var mappings: [Int64: KeyAction] = [:]

    private static var sharedInstance: MouseMapper?

    // MARK: - Start / Stop

    func start(with mappings: [Int: KeyAction]) {
        guard !isActive else { return }

        self.mappings = [:]
        for (button, action) in mappings {
            self.mappings[Int64(button)] = action
        }

        MouseMapper.sharedInstance = self

        // Listen for other mouse button events (side buttons are "otherMouse")
        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: MouseMapper.eventTapCallback,
            userInfo: nil
        ) else {
            error = "Failed to create mouse event tap. Grant Accessibility permission."
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
        print("[MouseMapper] Started with \(self.mappings.count) mappings")
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
        MouseMapper.sharedInstance = nil
        print("[MouseMapper] Stopped")
    }

    func updateMappings(_ mappings: [Int: KeyAction]) {
        self.mappings = [:]
        for (button, action) in mappings {
            self.mappings[Int64(button)] = action
        }
    }

    // MARK: - Event Tap Callback

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, _ in
        guard let mapper = MouseMapper.sharedInstance else {
            return Unmanaged.passRetained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = mapper.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Get button number: 0=left, 1=right, 2=middle, 3=button4(back), 4=button5(forward)
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        NSLog("[MouseMapper] Event type=%d btn=%d mappings=%@", type.rawValue, buttonNumber,
              mapper.mappings.keys.map { String($0) }.joined(separator: ","))

        guard let action = mapper.mappings[buttonNumber] else {
            return Unmanaged.passRetained(event) // no mapping, pass through
        }

        NSLog("[MouseMapper] Matched btn=%d → action", buttonNumber)

        let isDown = (type == .otherMouseDown)

        switch action {
        case .keystroke(let key):
            if let cgKey = KeyCodeMap.hidToCG[key] {
                if let keyEvent = CGEvent(keyboardEventSource: nil, virtualKey: cgKey, keyDown: isDown) {
                    keyEvent.post(tap: .cghidEventTap)
                }
            }
            return nil // suppress original mouse button

        case .shortcut(let modifiers, let key):
            if isDown, let cgKey = KeyCodeMap.hidToCG[key] {
                var flags = CGEventFlags()
                if modifiers & 0x01 != 0 { flags.insert(.maskCommand) }
                if modifiers & 0x02 != 0 { flags.insert(.maskShift) }
                if modifiers & 0x04 != 0 { flags.insert(.maskAlternate) }
                if modifiers & 0x08 != 0 { flags.insert(.maskControl) }

                if let down = CGEvent(keyboardEventSource: nil, virtualKey: cgKey, keyDown: true) {
                    down.flags = flags
                    down.post(tap: .cghidEventTap)
                }
                if let up = CGEvent(keyboardEventSource: nil, virtualKey: cgKey, keyDown: false) {
                    up.flags = flags
                    up.post(tap: .cghidEventTap)
                }
            }
            return nil

        case .launchApp(let bundleId):
            if isDown {
                Task { @MainActor in
                    NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleId,
                                                        options: [], additionalEventParamDescriptor: nil,
                                                        launchIdentifier: nil)
                }
            }
            return nil

        case .mediaControl(let control):
            if isDown {
                mapper.sendMediaKey(control)
            }
            return nil

        case .macroSequence(let steps):
            if isDown {
                DispatchQueue.global(qos: .userInteractive).async {
                    for step in steps {
                        guard let cgKey = KeyCodeMap.hidToCG[step.keyCode] else { continue }
                        if let event = CGEvent(keyboardEventSource: nil, virtualKey: cgKey, keyDown: step.isPress) {
                            event.post(tap: .cghidEventTap)
                        }
                        if step.delayMs > 0 { usleep(UInt32(step.delayMs) * 1000) }
                    }
                }
            }
            return nil

        case .disabled:
            return nil
        }
    }

    private func sendMediaKey(_ control: String) {
        let keyCode: Int32
        switch control {
        case "play", "pause": keyCode = 16
        case "next":          keyCode = 17
        case "prev":          keyCode = 18
        case "mute":          keyCode = 7
        default: return
        }

        let down = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                       modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       subtype: 8, data1: Int((keyCode << 16) | (0xa << 8)), data2: -1)
        let up = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                     modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     subtype: 8, data1: Int((keyCode << 16) | (0xb << 8)), data2: -1)
        down?.cgEvent?.post(tap: .cghidEventTap)
        up?.cgEvent?.post(tap: .cghidEventTap)
    }
}
