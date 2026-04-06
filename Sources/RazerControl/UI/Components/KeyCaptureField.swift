import SwiftUI
import AppKit

// MARK: - Key Capture Field
//
// A SwiftUI wrapper around an NSView that captures keyDown events.
// This works WITHOUT Accessibility or Input Monitoring permissions
// because it uses the normal NSView responder chain — any focused
// view receives keyDown events natively.
//
// Usage: KeyCaptureField(onCapture: { keyCode, modifiers, name in ... })

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
            // Ensure this view becomes first responder to receive key events
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

// MARK: - NSView that captures keys

class KeyCaptureNSView: NSView {
    var onCapture: ((UInt16, NSEvent.ModifierFlags, String) -> Void)?
    var isActiveCapture = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isActiveCapture else {
            super.keyDown(with: event)
            return
        }

        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Build display name
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(KeyCodeMap.cgKeyName(keyCode))

        let displayName = parts.joined(separator: " + ")

        onCapture?(keyCode, modifiers, displayName)
    }

    // Capture modifier-only presses (e.g., just Ctrl)
    override func flagsChanged(with event: NSEvent) {
        // Don't capture modifier-only events — wait for a real key
        super.flagsChanged(with: event)
    }

    // Visual feedback
    override func draw(_ dirtyRect: NSRect) {
        // Transparent — the SwiftUI overlay handles visuals
    }

    override func becomeFirstResponder() -> Bool {
        true
    }
}
