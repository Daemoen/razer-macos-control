import Foundation
import IOKit.hid
import RazerControlIPC
import SystemConfiguration
import Security
import Darwin

final class InputService: NSObject, NSXPCListenerDelegate, RazerInputHelperProtocol {
    private var manager: IOHIDManager?
    private var client: RazerInputClientProtocol?
    private var serviceConnection: NSXPCConnection?

    func run() -> Never {
        let listener = NSXPCListener(machServiceName: razerInputMachServiceName)
        guard let requirement = containingAppRequirement() else {
            NSLog("[RazerInputHelper] Unable to derive the containing app's signing requirement")
            exit(EX_CONFIG)
        }
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = self
        listener.activate()
        dispatchMain()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // This protocol exposes no privileged mutation: a client can only
        // register a callback that receives keypad input. Still, constrain it
        // to the active console user rather than accepting cross-user clients.
        guard connection.effectiveUserIdentifier == consoleUserID() else { return false }
        let helperInterface = NSXPCInterface(with: RazerInputHelperProtocol.self)
        helperInterface.setInterface(
            NSXPCInterface(with: RazerInputClientProtocol.self),
            for: #selector(RazerInputHelperProtocol.registerClient(_:withReply:)),
            argumentIndex: 0,
            ofReply: false
        )
        connection.exportedInterface = helperInterface
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in self?.shutdown() }
        serviceConnection = connection
        connection.activate()
        return true
    }

    func registerClient(_ client: RazerInputClientProtocol,
                        withReply reply: @escaping (Bool, String?) -> Void) {
        self.client = client

        if manager == nil, let failure = openOrbweaver() {
            client.helperError(failure)
            reply(false, failure)
            return
        }
        client.helperReady()
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
        service.client?.inputEvent(usage: Int(usage),
                                   pressed: IOHIDValueGetIntegerValue(value) != 0)
    }

    private func consoleUserID() -> uid_t {
        var uid: uid_t = 0
        var gid: gid_t = 0
        _ = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid)
        return uid
    }

    private func shutdown() {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(),
                                              CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        client = nil
        serviceConnection = nil
        exit(EXIT_SUCCESS)
    }

    private func containingAppRequirement() -> String? {
        var pathSize: UInt32 = 0
        _NSGetExecutablePath(nil, &pathSize)
        var path = [CChar](repeating: 0, count: Int(pathSize))
        guard _NSGetExecutablePath(&path, &pathSize) == 0 else {
            NSLog("[RazerInputHelper] _NSGetExecutablePath failed")
            return nil
        }
        var appURL = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
        for _ in 0..<4 { appURL.deleteLastPathComponent() }
        NSLog("[RazerInputHelper] Validating containing app at %@", appURL.path)
        return designatedRequirement(at: appURL)
    }

    private func designatedRequirement(at url: URL) -> String? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            NSLog("[RazerInputHelper] SecStaticCodeCreateWithPath failed: %d", createStatus)
            return nil
        }
        var requirement: SecRequirement?
        let requirementStatus = SecCodeCopyDesignatedRequirement(staticCode, [], &requirement)
        guard requirementStatus == errSecSuccess, let requirement else {
            NSLog("[RazerInputHelper] SecCodeCopyDesignatedRequirement failed: %d", requirementStatus)
            return nil
        }
        var text: CFString?
        let stringStatus = SecRequirementCopyString(requirement, [], &text)
        guard stringStatus == errSecSuccess else {
            NSLog("[RazerInputHelper] SecRequirementCopyString failed: %d", stringStatus)
            return nil
        }
        return text as String?
    }
}

private let service = InputService()
service.run()
