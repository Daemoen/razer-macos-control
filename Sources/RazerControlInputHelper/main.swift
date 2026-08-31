import Foundation
import IOKit.hid
import RazerControlIPC
import Security
import SystemConfiguration
import Darwin

final class InputService {
    private let queue = DispatchQueue(label: "com.razercontrol.input-helper.socket")
    private let clientLock = NSLock()
    private var listenerFD: Int32 = -1
    private var clientFD: Int32 = -1
    private var manager: IOHIDManager?
    private var expectedRequirement: SecRequirement?
    private var receiveBuffer = Data()

    func run() -> Never {
        guard let requirement = containingAppRequirement() else {
            NSLog("[RazerInputHelper] Could not derive app signing requirement")
            exit(EX_CONFIG)
        }
        expectedRequirement = requirement
        do {
            try createListener()
        } catch {
            NSLog("[RazerInputHelper] Socket setup failed: %@", error.localizedDescription)
            exit(EX_OSERR)
        }
        queue.async { [weak self] in self?.acceptLoop() }
        dispatchMain()
    }

    private func createListener() throws {
        // LaunchDaemons can start at the login window. Wait for a real console
        // user before creating a user-owned socket instead of crash-looping.
        var identity = consoleUserIdentity()
        while identity.0 == 0 || identity.0 == uid_t.max {
            sleep(1)
            identity = consoleUserIdentity()
        }
        listenerFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenerFD >= 0 else { throw POSIXError(.ENOTSOCK) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(razerInputSocketPath.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { source in destination.copyBytes(from: source) }
        }

        _ = unlink(razerInputSocketPath)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenerFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw currentPOSIXError() }
        let (uid, gid) = identity
        guard uid != 0,
              chmod(razerInputSocketPath, 0o600) == 0,
              chown(razerInputSocketPath, uid, gid) == 0,
              listen(listenerFD, 4) == 0 else { throw currentPOSIXError() }
        NSLog("[RazerInputHelper] Listening at %@ for uid %u", razerInputSocketPath, uid)
    }

    private func acceptLoop() {
        while true {
            let fd = accept(listenerFD, nil, nil)
            guard fd >= 0 else {
                if errno != EINTR { NSLog("[RazerInputHelper] accept failed: %d", errno) }
                continue
            }
            handleClient(fd)
        }
    }

    private func handleClient(_ fd: Int32) {
        closeClient()
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                       socklen_t(MemoryLayout<Int32>.size))
        guard authenticate(fd) else {
            NSLog("[RazerInputHelper] Rejected unauthenticated client")
            close(fd)
            return
        }
        clientLock.lock()
        clientFD = fd
        clientLock.unlock()
        receiveBuffer.removeAll(keepingCapacity: true)
        NSLog("[RazerInputHelper] Accepted authenticated client")

        var bytes = [UInt8](repeating: 0, count: 4096)
        while currentClientFD() == fd {
            let count = read(fd, &bytes, bytes.count)
            if count <= 0 { break }
            receiveBuffer.append(bytes, count: count)
            if receiveBuffer.count > 65_536 {
                NSLog("[RazerInputHelper] Closing client with oversized frame")
                break
            }
            consumeMessages()
        }
        closeClient()
    }

    private func authenticate(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0,
              uid == consoleUserIdentity().0 else { return false }

        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0,
              pid > 0, let expectedRequirement else { return false }

        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        return SecCodeCheckValidity(code, [], expectedRequirement) == errSecSuccess
    }

    private func consumeMessages() {
        while let newline = receiveBuffer.firstIndex(of: 0x0a) {
            let line = receiveBuffer[..<newline]
            receiveBuffer.removeSubrange(...newline)
            guard let message = try? RazerInputWire.decode(Data(line)),
                  message.version == razerInputProtocolVersion else {
                send(.init(kind: .error, message: "Protocol mismatch"))
                continue
            }
            switch message.kind {
            case .hello:
                if let failure = openOrbweaver() { send(.init(kind: .error, message: failure)) }
                else { send(.init(kind: .ready)) }
            case .ping:
                send(.init(kind: .pong))
            default:
                break
            }
        }
    }

    private func openOrbweaver() -> String? {
        if manager != nil { return nil }
        var access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeUnknown {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        }
        guard access == kIOHIDAccessTypeGranted else {
            return "Input Monitoring required for RazerControl Input Service"
        }

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
        service.send(.init(kind: .event, usage: Int(usage),
                           pressed: IOHIDValueGetIntegerValue(value) != 0))
    }

    private func send(_ message: RazerInputMessage) {
        guard let data = try? RazerInputWire.encode(message) else { return }
        clientLock.lock()
        defer { clientLock.unlock() }
        guard clientFD >= 0 else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(clientFD, base.advanced(by: offset), buffer.count - offset)
                if count <= 0 { break }
                offset += count
            }
        }
    }

    private func closeClient() {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(),
                                              CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        clientLock.lock()
        if clientFD >= 0 { close(clientFD) }
        clientFD = -1
        clientLock.unlock()
    }

    private func currentClientFD() -> Int32 {
        clientLock.lock()
        defer { clientLock.unlock() }
        return clientFD
    }

    private func consoleUserIdentity() -> (uid_t, gid_t) {
        var uid: uid_t = 0
        var gid: gid_t = 0
        _ = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid)
        return (uid, gid)
    }

    private func containingAppRequirement() -> SecRequirement? {
        // SMAppService's BundleProgram is relative to the containing app. A
        // launchd-started daemon can consequently receive a relative value
        // from _NSGetExecutablePath. Bundle.main.bundleURL is already resolved
        // to the installed helper bundle and is the reliable traversal anchor.
        var candidate = Bundle.main.bundleURL.resolvingSymlinksInPath()
        while candidate.path != "/" {
            if candidate.pathExtension == "app",
               Bundle(url: candidate)?.bundleIdentifier == "com.razercontrol.app" {
                var code: SecStaticCode?
                let createStatus = SecStaticCodeCreateWithPath(candidate as CFURL, [], &code)
                guard createStatus == errSecSuccess, let code else {
                    NSLog("[RazerInputHelper] SecStaticCodeCreateWithPath(%@) failed: %d",
                          candidate.path, createStatus)
                    return nil
                }
                var requirement: SecRequirement?
                let requirementStatus = SecCodeCopyDesignatedRequirement(code, [], &requirement)
                guard requirementStatus == errSecSuccess else {
                    NSLog("[RazerInputHelper] SecCodeCopyDesignatedRequirement failed: %d",
                          requirementStatus)
                    return nil
                }
                NSLog("[RazerInputHelper] Authenticating clients against %@", candidate.path)
                return requirement
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

InputService().run()
