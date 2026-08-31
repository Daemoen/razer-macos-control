import Foundation
import IOKit.hid
import RazerControlIPC
import SystemConfiguration

final class InputService: NSObject, NSXPCListenerDelegate, RazerInputHelperProtocol {
    private var manager: IOHIDManager?
    private var clientConnection: NSXPCConnection?

    func run() -> Never {
        let listener = NSXPCListener(machServiceName: razerInputMachServiceName)
        listener.delegate = self
        listener.resume()
        dispatchMain()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // This protocol exposes no privileged mutation: a client can only
        // register a callback that receives keypad input. Still, constrain it
        // to the active console user rather than accepting cross-user clients.
        guard connection.effectiveUserIdentifier == consoleUserID() else { return false }
        connection.exportedInterface = NSXPCInterface(with: RazerInputHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func registerClient(_ endpoint: NSXPCListenerEndpoint,
                        withReply reply: @escaping (Bool, String?) -> Void) {
        clientConnection?.invalidate()
        let client = NSXPCConnection(listenerEndpoint: endpoint)
        client.remoteObjectInterface = NSXPCInterface(with: RazerInputClientProtocol.self)
        client.invalidationHandler = { [weak self] in self?.clientConnection = nil }
        client.resume()
        clientConnection = client

        if manager == nil, let failure = openOrbweaver() {
            remoteClient()?.helperError(failure)
            reply(false, failure)
            return
        }
        remoteClient()?.helperReady()
        reply(true, nil)
    }

    private func openOrbweaver() -> String? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x1532,
            kIOHIDProductIDKey as String: 0x0207,
            kIOHIDDeviceUsagePageKey as String: 0x01,
            kIOHIDDeviceUsageKey as String: 0x06,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputCallback,
                                                Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(),
                                        CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(),
                                              CFRunLoopMode.commonModes.rawValue)
            return "HID open failed: \(String(format: "0x%08X", result))"
        }
        self.manager = manager
        return nil
    }

    private static let inputCallback: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess, let context else { return }
        let service = Unmanaged<InputService>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let usage = IOHIDElementGetUsage(element)
        guard IOHIDElementGetUsagePage(element) == 0x07,
              usage > 0x03, usage <= UInt32(UInt8.max) else { return }
        service.remoteClient()?.inputEvent(usage: Int(usage),
                                           pressed: IOHIDValueGetIntegerValue(value) != 0)
    }

    private func remoteClient() -> RazerInputClientProtocol? {
        clientConnection?.remoteObjectProxyWithErrorHandler { error in
            NSLog("[RazerInputHelper] Client XPC error: %@", error.localizedDescription)
        } as? RazerInputClientProtocol
    }

    private func consoleUserID() -> uid_t {
        var uid: uid_t = 0
        var gid: gid_t = 0
        _ = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid)
        return uid
    }
}

private let service = InputService()
service.run()
