import SwiftUI
import AppKit

// MARK: - Key Capture Field
//
// Captures key presses including modifier combos (Ctrl+1, Cmd+Shift+Z).
// Uses TWO mechanisms:
// 1. NSView.performKeyEquivalent — captures shortcuts before system
// 2. Local NSEvent monitor — catches anything the view misses
//
// The local monitor works because the APP window has focus (even if
// the system would normally handle the shortcut globally).

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
        if isActive && !nsView.isActiveCapture {
            nsView.startCapture()
        } else if !isActive && nsView.isActiveCapture {
            nsView.stopCapture()
        }
    }

    static func dismantleNSView(_ nsView: KeyCaptureNSView, coordinator: ()) {
        nsView.stopCapture()
    }
}

class KeyCaptureNSView: NSView {
    var onCapture: ((UInt16, NSEvent.ModifierFlags, String) -> Void)?
    var isActiveCapture = false
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    func startCapture() {
        isActiveCapture = true

        // Make ourselves first responder
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }

        // Local event monitor — catches keys delivered to THIS app
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isActiveCapture else { return event }
            self.handleCapture(event)
            return nil // consume
        }
    }

    func stopCapture() {
        isActiveCapture = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // performKeyEquivalent catches Cmd+X, Ctrl+X etc before system
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isActiveCapture else { return super.performKeyEquivalent(with: event) }
        handleCapture(event)
        return true
    }

    // keyDown catches plain keys
    override func keyDown(with event: NSEvent) {
        guard isActiveCapture else { super.keyDown(with: event); return }
        handleCapture(event)
    }

    private func handleCapture(_ event: NSEvent) {
        let keyCode = event.keyCode
        let rawMods = event.modifierFlags

        var parts: [String] = []
        if rawMods.contains(.control) { parts.append("Ctrl") }
        if rawMods.contains(.option) { parts.append("Opt") }
        if rawMods.contains(.shift) { parts.append("Shift") }
        if rawMods.contains(.command) { parts.append("Cmd") }
        parts.append(KeyCodeMap.cgKeyName(keyCode))

        let mods = rawMods.intersection([.command, .shift, .option, .control])

        print("[KeyCapture] code=\(keyCode) → \(parts.joined(separator: "+"))")
        onCapture?(keyCode, mods, parts.joined(separator: " + "))

        // Stop after capture
        stopCapture()
    }

    override func draw(_ dirtyRect: NSRect) {}

    deinit {
        stopCapture()
    }
}
