import Foundation
import AppKit
import ServiceManagement
import RazerControlIPC
import Darwin

@MainActor
final class PrivilegedInputClient: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var serviceStatus: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    var onKeyboardUsage: ((UInt8, Bool) -> Void)?

    private let service = SMAppService.daemon(plistName: "com.razercontrol.input-helper.plist")
    private let registeredBuildKey = "RazerControlInputServiceRegisteredBuild"
    private let ioQueue = DispatchQueue(label: "com.razercontrol.input-client.socket")
    private var socketFD: Int32 = -1
    private var generation = UUID()
    private var activationObserver: NSObjectProtocol?

    init() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshStatus()
                if self.serviceStatus == .enabled, !self.isActive { self.connect() }
            }
        }
    }

    func start() { refreshStatus(); if serviceStatus == .enabled { connect() } }

    func stop() {
        generation = UUID()
        let fd = socketFD
        socketFD = -1
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd) }
        isActive = false
    }

    func install() {
        refreshStatus()
        do {
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let registeredBuild = UserDefaults.standard.string(forKey: registeredBuildKey)
            if serviceStatus == .enabled, registeredBuild == build {
                error = nil
                connect()
                return
            }
            if serviceStatus == .enabled {
                // launchd snapshots the plist at registration. Refresh it when
                // a new signed bundle changes the daemon definition.
                try service.unregister()
                refreshStatus()
            }
            try service.register()
            UserDefaults.standard.set(build, forKey: registeredBuildKey)
            error = nil
        } catch { self.error = "Native input registration failed: \(error.localizedDescription)" }
        refreshStatus()
        if serviceStatus == .enabled { connect() }
        else if serviceStatus == .requiresApproval {
            error = "Approve RazerControl under Login Items, then reopen the app"
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func uninstall() {
        stop()
        do {
            try service.unregister()
            UserDefaults.standard.removeObject(forKey: registeredBuildKey)
            error = nil
        }
        catch { self.error = "Native input removal failed: \(error.localizedDescription)" }
        refreshStatus()
    }

    func refreshStatus() { serviceStatus = service.status }

    private func connect() {
        stop()
        error = "Waiting for RazerControl Input Service"
        let currentGeneration = generation
        ioQueue.async { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                guard let fd = Self.openSocket() else { usleep(250_000); continue }
                Task { @MainActor in
                    guard self.generation == currentGeneration else { close(fd); return }
                    self.socketFD = fd
                    self.error = nil
                }
                do {
                    try Self.write(.init(kind: .hello), to: fd)
                    self.readLoop(fd: fd, generation: currentGeneration)
                    return
                } catch { close(fd) }
                usleep(250_000)
            }
            Task { @MainActor in
                guard self.generation == currentGeneration else { return }
                self.error = "Native input connection failed: input service socket unavailable"
                self.isActive = false
                self.socketFD = -1
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
            if self.error == nil { self.error = "RazerControl Input Service disconnected" }
        }
    }

    private func receive(_ message: RazerInputMessage, generation: UUID) {
        guard self.generation == generation else { return }
        switch message.kind {
        case .ready: isActive = true; error = nil
        case .event:
            guard let usage = message.usage.flatMap(UInt8.init(exactly:)),
                  let pressed = message.pressed else { return }
            onKeyboardUsage?(usage, pressed)
        case .error: isActive = false; error = message.message ?? "Input service error"
        default: break
        }
    }

    nonisolated private static func openSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                       socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(razerInputSocketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return nil }
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
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
    }
}
