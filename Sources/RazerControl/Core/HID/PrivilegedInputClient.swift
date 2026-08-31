import Foundation
import AppKit
import Darwin

@MainActor
final class PrivilegedInputClient: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var error: String?
    var onKeyboardUsage: ((UInt8, Bool) -> Void)?

    private let socketPath = "/tmp/com.razercontrol.input.sock"
    private let queue = DispatchQueue(label: "com.razercontrol.input-client")
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var expiry: DispatchWorkItem?

    func start() {
        stop()
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { error = "Unable to create input service socket"; return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd); error = "Input service socket path is too long"; return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            _ = socketPath.utf8.withContiguousStorageIfAvailable { bytes.copyBytes(from: $0) }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bindResult == 0 else {
            close(fd); error = "Unable to bind input service socket (\(errno))"; return
        }
        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Self.readAvailableMessages(from: fd, client: self)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        readSource = source
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        socketFD = -1
        expiry?.cancel()
        expiry = nil
        isActive = false
        unlink(socketPath)
    }

    func install() {
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "RazerControlInputHelper"),
              let plist = Bundle.module.url(forResource: "com.razercontrol.input-helper", withExtension: "plist")
        else {
            error = "Input service is missing from this build"
            return
        }

        let destination = "/Library/PrivilegedHelperTools/com.razercontrol.input-helper"
        let launchPlist = "/Library/LaunchDaemons/com.razercontrol.input-helper.plist"
        let command = [
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/cp \(helper.path.shellQuoted) \(destination.shellQuoted)",
            "/usr/sbin/chown root:wheel \(destination.shellQuoted)",
            "/bin/chmod 755 \(destination.shellQuoted)",
            "/bin/cp \(plist.path.shellQuoted) \(launchPlist.shellQuoted)",
            "/usr/sbin/chown root:wheel \(launchPlist.shellQuoted)",
            "/bin/chmod 644 \(launchPlist.shellQuoted)",
            "/bin/launchctl bootout system/com.razercontrol.input-helper 2>/dev/null || true",
            "/bin/launchctl bootstrap system \(launchPlist.shellQuoted)",
            "/bin/launchctl enable system/com.razercontrol.input-helper",
            "/bin/launchctl kickstart -k system/com.razercontrol.input-helper",
        ].joined(separator: "; ")
        let script = "do shell script \"\(command.appleScriptEscaped)\" with administrator privileges"
        var scriptError: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&scriptError)
        if let scriptError {
            error = scriptError[NSAppleScript.errorMessage] as? String ?? "Input service installation failed"
        } else {
            error = nil
        }
    }

    private nonisolated static func readAvailableMessages(from fd: Int32, client: PrivilegedInputClient) {
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = recv(fd, &buffer, buffer.count, 0)
        guard count > 0, let message = String(bytes: buffer.prefix(count), encoding: .utf8) else { return }
        Task { @MainActor in client.handle(message) }
    }

    private func handle(_ message: String) {
        if message == "ready" {
            isActive = true
            error = nil
            expiry?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.isActive = false }
            expiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            return
        }
        if message.hasPrefix("error ") {
            error = "Input service HID failure: \(message.dropFirst(6))"
            isActive = false
            return
        }
        let parts = message.split(separator: " ")
        guard parts.count == 3, parts[0] == "key", let usage = UInt8(parts[1]) else { return }
        onKeyboardUsage?(usage, parts[2] == "1")
    }
}

private extension String {
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
