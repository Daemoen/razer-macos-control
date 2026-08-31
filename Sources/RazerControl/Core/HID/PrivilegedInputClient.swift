import Foundation
import AppKit
import ServiceManagement
import RazerControlIPC

@MainActor
final class PrivilegedInputClient: NSObject, ObservableObject, NSXPCListenerDelegate, RazerInputClientProtocol {
    @Published private(set) var isActive = false
    @Published private(set) var serviceStatus: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    var onKeyboardUsage: ((UInt8, Bool) -> Void)?

    private let service = SMAppService.daemon(plistName: "com.razercontrol.input-helper.plist")
    private var connection: NSXPCConnection?
    private var callbackListener: NSXPCListener?

    func start() {
        refreshStatus()
        guard serviceStatus == .enabled else { return }
        connect()
    }

    func stop() {
        connection?.invalidate()
        connection = nil
        callbackListener?.invalidate()
        callbackListener = nil
        isActive = false
    }

    func install() {
        do {
            try service.register()
            error = nil
        } catch {
            self.error = "Native input registration failed: \(error.localizedDescription)"
        }
        refreshStatus()
        if serviceStatus == .enabled {
            connect()
        } else if serviceStatus == .requiresApproval {
            error = "Approve RazerControl under Login Items, then reopen the app"
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func refreshStatus() {
        serviceStatus = service.status
    }

    private func connect() {
        stop()

        let callback = NSXPCListener.anonymous()
        callback.delegate = self
        callback.resume()
        callbackListener = callback

        let connection = NSXPCConnection(machServiceName: razerInputMachServiceName,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: RazerInputHelperProtocol.self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.isActive = false }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.isActive = false }
        }
        connection.resume()
        self.connection = connection

        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] failure in
            Task { @MainActor in
                self?.error = "Native input connection failed: \(failure.localizedDescription)"
                self?.isActive = false
            }
        } as? RazerInputHelperProtocol
        proxy?.registerClient(callback.endpoint) { [weak self] success, message in
            Task { @MainActor in
                self?.isActive = success
                self?.error = message
            }
        }
    }

    nonisolated func listener(_ listener: NSXPCListener,
                              shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RazerInputClientProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    nonisolated func helperReady() {
        Task { @MainActor in
            isActive = true
            error = nil
        }
    }

    nonisolated func inputEvent(usage: Int, pressed: Bool) {
        guard let usage = UInt8(exactly: usage) else { return }
        Task { @MainActor in onKeyboardUsage?(usage, pressed) }
    }

    nonisolated func helperError(_ message: String) {
        Task { @MainActor in
            error = message
            isActive = false
        }
    }
}
