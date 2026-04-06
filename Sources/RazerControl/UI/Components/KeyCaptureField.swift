import SwiftUI
import AppKit

// MARK: - Key Capture Field
//
// Captures ANY key press including modifier combinations like Ctrl+1, Cmd+Shift+Z.
// Uses performKeyEquivalent which fires BEFORE the system handles shortcuts,
// plus keyDown as fallback for plain keys.
// No Accessibility or Input Monitoring permissions needed.

struct KeyCaptureField: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (UInt16, NSEvent.ModifierFlags, String) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.isActiveCapture = isActive
        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyCaptureNSView: NSView {
    var onCapture: ((UInt16, NSEvent.ModifierFlags, String) -> Void)?
    var isActiveCapture = false

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    // performKeyEquivalent fires BEFORE the system handles Ctrl+1, Cmd+Tab, etc.
    // Return true to consume the event and prevent system handling.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isActiveCapture else { return super.performKeyEquivalent(with: event) }
        captureEvent(event)
        return true // consume — don't let system handle Ctrl+1 etc.
    }

    // keyDown fires for plain keys without modifiers (a, b, F1, etc.)
    override func keyDown(with event: NSEvent) {
        guard isActiveCapture else {
            super.keyDown(with: event)
            return
        }
        captureEvent(event)
    }

    private func captureEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let rawMods = event.modifierFlags

        var parts: [String] = []
        if rawMods.contains(.control) { parts.append("Ctrl") }
        if rawMods.contains(.option) { parts.append("Opt") }
        if rawMods.contains(.shift) { parts.append("Shift") }
        if rawMods.contains(.command) { parts.append("Cmd") }

        let keyName = KeyCodeMap.cgKeyName(keyCode)
        parts.append(keyName)

        let modifiers = rawMods.intersection([.command, .shift, .option, .control])

        print("[KeyCapture] keyCode=\(keyCode) mods=\(parts) name=\(keyName)")
        onCapture?(keyCode, modifiers, parts.joined(separator: " + "))
    }

    override func draw(_ dirtyRect: NSRect) {
        // transparent
    }
}
