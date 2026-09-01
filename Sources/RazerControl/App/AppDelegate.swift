import AppKit
import ApplicationServices
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-device-art") {
            // Offline rasterisation of the device views. Discovery is
            // IORegistry-only; no HID device is opened and no feature report is
            // written, so this cannot alter hardware state.
            let outputDirectory = flagIndex + 1 < CommandLine.arguments.count
                ? CommandLine.arguments[flagIndex + 1]
                : NSHomeDirectory() + "/razercontrol-renders"
            let result = DeviceArtRenderer.run(outputDirectory: outputDirectory)
            FileHandle.standardOutput.write(Data((result.report + "\n").utf8))
            Darwin.exit(result.passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        if CommandLine.arguments.contains("--protocol-self-test") {
            // Pure byte-layout verification. Opens no device and transmits
            // nothing, so it is safe to run against attached hardware.
            let result = ProtocolSelfTest.run()
            FileHandle.standardOutput.write(Data((result.report + "\n").utf8))
            Darwin.exit(result.passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }

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

    /// Closing the window must NOT quit the app.
    ///
    /// The controller owns the connection that keeps the input daemon's seize
    /// alive. Quitting drops that connection, the daemon releases the keypad,
    /// and every mapping silently reverts to factory behaviour. Returning true
    /// here meant closing the window mid-game disabled remapping. Quit with
    /// Command-Q when you actually want the keypad back to stock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
