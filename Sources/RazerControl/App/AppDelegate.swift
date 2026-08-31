import AppKit
import ApplicationServices
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--native-input-self-test") {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = NativeInputSelfTest.run()
                FileHandle.standardOutput.write(Data((result.message + "\n").utf8))
                Darwin.exit(result.succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
            }
            return
        }

        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Check Accessibility (needed for key remapping, not for RGB)
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let ax = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        NSLog("[RazerControl] AXIsProcessTrusted: %@", ax ? "YES" : "NO")
        let debug = "AX=\(ax) bundle=\(Bundle.main.bundleIdentifier ?? "nil") pid=\(ProcessInfo.processInfo.processIdentifier)\n"
        try? debug.write(toFile: "/tmp/razercontrol_debug.txt", atomically: true, encoding: .utf8)

        // Raw, device-scoped HID observation requires Input Monitoring. Ask
        // under RazerControl's own signed identity so the TCC entry belongs to
        // the app rather than Terminal or the development environment.
        if #available(macOS 10.15, *), !CGPreflightListenEventAccess() {
            let requested = CGRequestListenEventAccess()
            NSLog("[RazerControl] Requested Input Monitoring: %@", requested ? "granted" : "pending")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
