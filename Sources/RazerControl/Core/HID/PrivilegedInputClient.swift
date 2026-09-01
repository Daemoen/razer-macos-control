import Foundation
import AppKit
import RazerControlIPC
import Darwin

/// Controller-side half of the privileged input channel.
///
/// The daemon is a classic root LaunchDaemon installed by `Scripts/install-daemon.sh`,
/// not an `SMAppService` job. That is deliberate. `SMAppService.daemon` registers a
/// job whose executable lives inside the application bundle, which means a root
/// process executing from a user-writable path, and it keys approval on
/// Background Task Management state that an app cannot inspect or repair when it
/// desynchronises. Karabiner-Elements and RustDesk both avoid it for the same
/// reasons. Consequently this type never registers, unregisters, or approves
/// anything — installation is an explicit privileged action, and the controller's
/// only job is to connect, authenticate, and report.
@MainActor
final class PrivilegedInputClient: ObservableObject {
    enum State: Equatable {
        case notInstalled
        case connecting
        case active
        case failed(String)
    }

    @Published private(set) var isActive = false
    @Published private(set) var state: State = .notInstalled
    @Published private(set) var error: String?

    var onKeyboardUsage: ((UInt8, Bool) -> Void)?

    private let ioQueue = DispatchQueue(label: "com.razercontrol.input-client.socket")
    private var socketFD: Int32 = -1
    /// Invalidates in-flight socket work when a newer connect supersedes it.
    private var generation = UUID()
    private var activationObserver: NSObjectProtocol?

    /// True when the daemon plist is present. Absence is a distinct, actionable
    /// state from "installed but not reachable" and must not be collapsed into it.
    var isDaemonInstalled: Bool {
        FileManager.default.fileExists(atPath: razerInputDaemonPlistPath)
    }

    /// The `--native-input-self-test` entry point drives its own connection.
    /// SwiftUI still constructs the whole object graph in that mode, so without
    /// this guard the UI layer would open a second connection from the same
    /// process, take the daemon's single exclusive-owner slot, and leave the
    /// self-test's own connection waiting until it timed out. The failure
    /// presented as a hung daemon; it was the app competing with itself.
    private static let isSelfTestProcess =
        CommandLine.arguments.contains("--native-input-self-test")

    init() {
        guard !Self.isSelfTestProcess else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isActive else { return }
                self.connect()
            }
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func start() {
        guard !Self.isSelfTestProcess else { return }
        connect()
    }

    /// Explicit user-driven retry.
    func reconnect() { connect() }

    func stop() {
        generation = UUID()
        let fd = socketFD
        socketFD = -1
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd) }
        isActive = false
    }

    private func connect() {
        stop()

        guard isDaemonInstalled else {
            state = .notInstalled
            error = "Input daemon is not installed. Run Scripts/install-daemon.sh."
            return
        }

        state = .connecting
        error = nil
        let currentGeneration = generation

        ioQueue.async { [weak self] in
            guard let self else { return }
            // The daemon waits for a console user before binding, so a cold boot
            // can legitimately take a few seconds. 40 x 250ms = 10s.
            for _ in 0..<40 {
                guard let fd = Self.openSocket() else { usleep(250_000); continue }
                Task { @MainActor in
                    guard self.generation == currentGeneration else { close(fd); return }
                    self.socketFD = fd
                }
                do {
                    try Self.write(.init(kind: .hello), to: fd)
                    self.readLoop(fd: fd, generation: currentGeneration)
                    return
                } catch {
                    close(fd)
                }
                usleep(250_000)
            }
            Task { @MainActor in
                guard self.generation == currentGeneration else { return }
                self.socketFD = -1
                self.isActive = false
                self.state = .failed("Input daemon is installed but not responding.")
                self.error = "Input daemon is installed but not responding. Check: sudo launchctl print system/\(razerInputDaemonLabel)"
            }
        }
    }

    nonisolated private func readLoop(fd: Int32, generation: UUID) {
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &bytes, bytes.count)
            if count <= 0 { break }
            buffer.append(bytes, count: count)
            if buffer.count > 65_536 { break }
            while let newline = buffer.firstIndex(of: 0x0a) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let message = try? RazerInputWire.decode(Data(line)),
                      message.version == razerInputProtocolVersion else { continue }
                Task { @MainActor [weak self] in self?.receive(message, generation: generation) }
            }
        }
        Task { @MainActor [weak self] in
            guard let self, self.generation == generation else { return }
            self.socketFD = -1
            self.isActive = false
            if case .failed = self.state {} else {
                self.state = .failed("Input daemon disconnected.")
                self.error = "Input daemon disconnected."
            }
        }
    }

    private func receive(_ message: RazerInputMessage, generation: UUID) {
        guard self.generation == generation else { return }
        switch message.kind {
        case .ready:
            isActive = true
            state = .active
            error = nil

        case .event:
            guard let usage = message.usage.flatMap(UInt8.init(exactly:)),
                  let pressed = message.pressed else { return }
            onKeyboardUsage?(usage, pressed)

        case .error:
            isActive = false
            let text = Self.remediation(for: message)
            state = .failed(text)
            error = text

        default:
            break
        }
    }

    /// The daemon sends a stable code alongside prose so the controller can give
    /// the user the one instruction that actually resolves their case.
    private static func remediation(for message: RazerInputMessage) -> String {
        let detail = message.message ?? "Input daemon error"
        switch message.code {
        case RazerInputErrorCode.inputMonitoringDenied:
            return detail + " (the daemon runs as root and cannot raise this prompt itself)"
        case RazerInputErrorCode.deviceAbsent:
            return detail + " Connect the keypad, then press Reconnect."
        case RazerInputErrorCode.protocolMismatch:
            return detail
        default:
            return detail
        }
    }

    // MARK: - Socket primitives

    nonisolated private static func openSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                       socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(razerInputSocketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            path.withUnsafeBytes { source in destination.copyBytes(from: source) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { close(fd); return nil }
        return fd
    }

    nonisolated private static func write(_ message: RazerInputMessage, to fd: Int32) throws {
        let data = try RazerInputWire.encode(message)
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                guard count > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += count
            }
        }
    }
}
