import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Check Accessibility (needed for key remapping, not for RGB)
        let ax = AXIsProcessTrusted()
        NSLog("[RazerControl] AXIsProcessTrusted: %@", ax ? "YES" : "NO")
        let debug = "AX=\(ax) bundle=\(Bundle.main.bundleIdentifier ?? "nil") pid=\(ProcessInfo.processInfo.processIdentifier)\n"
        try? debug.write(toFile: "/tmp/razercontrol_debug.txt", atomically: true, encoding: .utf8)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
