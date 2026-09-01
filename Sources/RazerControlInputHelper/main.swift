import Foundation
import IOKit.hid
import RazerControlIPC
import Security
import SystemConfiguration
import Darwin

// Razer Orbweaver Chroma. The daemon deliberately captures exactly one device
// class: seizing an interface is a destructive act for every other consumer of
// that device, so the match is narrow and explicit rather than discovered.
private let razerVendorID = 0x1532
private let orbweaverProductID = 0x0207
private let hidUsagePageGenericDesktop = 0x01
private let hidUsageKeyboard = 0x06
private let hidUsagePageKeyboard: UInt32 = 0x07

final class InputService {
    private let queue = DispatchQueue(label: "com.razercontrol.inputd.socket")
    /// Each accepted connection is serviced on its own thread. A connected
    /// session blocks in read() for its entire lifetime, so servicing inline
    /// would leave every later connection stranded in the listen backlog until
    /// the current one closed — which, from the client side, is indistinguishable
    /// from a hung daemon. That is exactly the symptom this replaced.
    private let clientPool = DispatchQueue(label: "com.razercontrol.inputd.clients",
                                           attributes: .concurrent)
    private let clientLock = NSLock()
    private var listenerFD: Int32 = -1
    private var clientFD: Int32 = -1
    private var manager: IOHIDManager?
    private var expectedRequirement: SecRequirement?

    func run() -> Never {
        expectedRequirement = awaitControllerRequirement()
        do {
            try createListener()
        } catch {
            NSLog("[razer-inputd] Socket setup failed: %@", String(describing: error))
            exit(EX_OSERR)
        }
        queue.async { [weak self] in self?.acceptLoop() }

        // IOHIDManager callbacks are delivered by a CFRunLoop, not by libdispatch.
        // The previous build called dispatchMain() here, which drains the main
        // queue but never runs the main run loop, so scheduled HID sources could
        // never fire. Every HID interaction below is marshalled onto this thread.
        CFRunLoopRun()
        exit(EX_SOFTWARE)
    }

    // MARK: - Trust anchor

    /// The daemon authenticates clients against the installed controller's
    /// designated requirement. The controller is at a fixed absolute path
    /// because the daemon no longer lives inside the app bundle and therefore
    /// has no containing bundle to walk up to.
    ///
    /// Missing controller is a wait state, not a fatal one: exiting here would
    /// make launchd restart-throttle the job during an app reinstall.
    private func awaitControllerRequirement() -> SecRequirement {
        var loggedWait = false
        while true {
            if FileManager.default.fileExists(atPath: razerControllerAppPath),
               let requirement = controllerRequirement() {
                return requirement
            }
            if !loggedWait {
                NSLog("[razer-inputd] Waiting for controller at %@", razerControllerAppPath)
                loggedWait = true
            }
            sleep(5)
        }
    }

    private func controllerRequirement() -> SecRequirement? {
        let url = URL(fileURLWithPath: razerControllerAppPath) as CFURL
        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, [], &code)
        guard createStatus == errSecSuccess, let code else {
            NSLog("[razer-inputd] SecStaticCodeCreateWithPath failed: %d", createStatus)
            return nil
        }
        // Reject a controller whose signature no longer validates before we
        // derive a requirement from it.
        let validity = SecStaticCodeCheckValidity(code, [], nil)
        guard validity == errSecSuccess else {
            NSLog("[razer-inputd] Controller signature invalid: %d", validity)
            return nil
        }
        var requirement: SecRequirement?
        let status = SecCodeCopyDesignatedRequirement(code, [], &requirement)
        guard status == errSecSuccess, let requirement else {
            NSLog("[razer-inputd] SecCodeCopyDesignatedRequirement failed: %d", status)
            return nil
        }
        NSLog("[razer-inputd] Authenticating clients against %@", razerControllerAppPath)
        return requirement
    }

    // MARK: - Listener

    private func createListener() throws {
        // A LaunchDaemon starts at the login window, before any console user
        // exists. Wait for one rather than creating a root-owned socket the
        // controller could never open.
        var identity = consoleUserIdentity()
        while identity.0 == 0 || identity.0 == uid_t.max {
            sleep(1)
            identity = consoleUserIdentity()
        }

        listenerFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenerFD >= 0 else { throw currentPOSIXError() }

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
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenerFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw currentPOSIXError() }

        let (uid, gid) = identity
        guard uid != 0 else { throw POSIXError(.EPERM) }
        guard chmod(razerInputSocketPath, 0o600) == 0,
              chown(razerInputSocketPath, uid, gid) == 0,
              listen(listenerFD, 4) == 0 else { throw currentPOSIXError() }

        NSLog("[razer-inputd] Listening at %@ for uid %u", razerInputSocketPath, uid)
    }

    private func acceptLoop() {
        while true {
            let fd = accept(listenerFD, nil, nil)
            guard fd >= 0 else {
                if errno != EINTR { NSLog("[razer-inputd] accept failed: %d", errno) }
                continue
            }
            clientPool.async { [weak self] in self?.handleClient(fd) }
        }
    }

    private func handleClient(_ fd: Int32) {
        // Exactly one connection may own exclusive capture. A new authenticated
        // controller displaces the previous one rather than being refused, so a
        // relaunched app is never locked out by its own dead predecessor.
        displaceCurrentClient()
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                       socklen_t(MemoryLayout<Int32>.size))
        guard authenticate(fd) else {
            NSLog("[razer-inputd] Rejected unauthenticated client")
            close(fd)
            return
        }
        clientLock.lock()
        clientFD = fd
        clientLock.unlock()
        NSLog("[razer-inputd] Accepted authenticated client (fd %d)", fd)

        // Buffer is per-connection. Sharing one across concurrently serviced
        // clients would interleave partial frames from different peers.
        var receiveBuffer = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while currentClientFD() == fd {
            let count = read(fd, &bytes, bytes.count)
            if count <= 0 { break }
            receiveBuffer.append(bytes, count: count)
            if receiveBuffer.count > 65_536 {
                NSLog("[razer-inputd] Closing client with oversized frame")
                break
            }
            consumeMessages(&receiveBuffer)
        }
        releaseClient(fd)
    }

    /// Four independent checks, all required: the peer is the console user, the
    /// peer PID is resolvable, that PID maps to a running code object, and that
    /// code object satisfies the controller's designated requirement. UID or
    /// path alone would be trivially forgeable.
    private func authenticate(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == consoleUserIdentity().0 else {
            NSLog("[razer-inputd] Auth reject: peer uid mismatch")
            return false
        }

        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else {
            NSLog("[razer-inputd] Auth reject: peer pid unavailable")
            return false
        }
        guard let expectedRequirement else {
            NSLog("[razer-inputd] Auth reject: no controller requirement")
            return false
        }

        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            NSLog("[razer-inputd] Auth reject: no code object for pid %d", pid)
            return false
        }
        let status = SecCodeCheckValidity(code, [], expectedRequirement)
        if status != errSecSuccess {
            NSLog("[razer-inputd] Auth reject: requirement check failed: %d", status)
            return false
        }
        return true
    }

    private func consumeMessages(_ receiveBuffer: inout Data) {
        while let newline = receiveBuffer.firstIndex(of: 0x0a) {
            let line = receiveBuffer[..<newline]
            receiveBuffer.removeSubrange(...newline)
            guard let message = try? RazerInputWire.decode(Data(line)) else {
                send(.init(kind: .error, message: "Malformed frame",
                           code: RazerInputErrorCode.protocolMismatch))
                continue
            }
            guard message.version == razerInputProtocolVersion else {
                send(.init(kind: .error,
                           message: "Protocol \(message.version) unsupported; daemon speaks \(razerInputProtocolVersion). Reinstall so app and daemon match.",
                           code: RazerInputErrorCode.protocolMismatch))
                continue
            }
            switch message.kind {
            case .hello:
                if let failure = openDevice() {
                    NSLog("[razer-inputd] hello -> error [%@] %@", failure.1, failure.0)
                    send(.init(kind: .error, message: failure.0, code: failure.1))
                } else {
                    send(.init(kind: .ready))
                }
            case .ping:
                send(.init(kind: .pong))
            default:
                break
            }
        }
    }

    // MARK: - HID capture (main-thread only)

    /// Returns nil on success, or (human message, stable code) on failure.
    private func openDevice() -> (String, String)? {
        var result: (String, String)?
        // Safe against deadlock: the main thread is inside CFRunLoopRun, which
        // drains the main dispatch queue.
        DispatchQueue.main.sync { result = self.openDeviceOnMain() }
        return result
    }

    private func openDeviceOnMain() -> (String, String)? {
        if manager != nil { return nil }

        // ADVISORY ONLY -- deliberately not a gate.
        //
        // IOHIDCheckAccess reports the TCC Input Monitoring state that applies
        // to user-session processes. A root LaunchDaemon is not necessarily
        // subject to it: Karabiner-Elements' root grabber seizes HID interfaces
        // on this machine while holding no kTCCServiceListenEvent entry at all.
        // Refusing here because this check says "not granted" would deny an
        // operation the kernel may well permit, and would demand a permission
        // grant the user might not actually need.
        //
        // The access-request API is deliberately not called either: it blocks
        // until the user answers a prompt, and a root daemon has no session in
        // which such a prompt can ever appear.
        //
        // So: attempt the seize, and let the returned IOKit code decide.
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let accessName: String
        switch access {
        case kIOHIDAccessTypeGranted: accessName = "granted"
        case kIOHIDAccessTypeDenied:  accessName = "denied"
        default:                      accessName = "unknown"
        }
        NSLog("[razer-inputd] Input Monitoring advisory state: %@", accessName)

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: razerVendorID,
            kIOHIDProductIDKey as String: orbweaverProductID,
            kIOHIDDeviceUsagePageKey as String: hidUsagePageGenericDesktop,
            kIOHIDDeviceUsageKey as String: hidUsageKeyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)

        // IOHIDManagerOpen succeeds with zero matched devices, so absence has to
        // be detected separately or the controller would sit waiting for events
        // that can never arrive.
        let matched = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0
        guard matched > 0 else {
            return ("Razer Orbweaver Chroma is not connected.",
                    RazerInputErrorCode.deviceAbsent)
        }

        IOHIDManagerRegisterInputValueCallback(manager, Self.inputCallback,
                                               Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(),
                                        CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(),
                                              CFRunLoopMode.commonModes.rawValue)
            let hex = String(format: "0x%08X", result)
            // Empirically, a seize refused for want of Input Monitoring comes
            // back as kIOReturnNotPermitted (0xE00002E2), not the more obvious
            // kIOReturnNotPrivileged. Both are mapped so the user is told to
            // fix the permission rather than shown a bare hex code.
            let detail: String
            let code: String
            switch result {
            case kIOReturnNotPermitted, kIOReturnNotPrivileged:
                detail = "Input Monitoring is not granted to the input daemon (\(hex)). "
                    + "Open System Settings > Privacy & Security > Input Monitoring, click +, "
                    + "press Shift-Command-G, and enter this exact path: \(razerInputDaemonPath)"
                code = RazerInputErrorCode.inputMonitoringDenied
            case kIOReturnExclusiveAccess:
                detail = "Another process already owns this device exclusively (\(hex)). Quit Karabiner-Elements or Razer Synapse."
                code = RazerInputErrorCode.hidOpenFailed
            default:
                detail = "HID seize failed (\(hex))."
                code = RazerInputErrorCode.hidOpenFailed
            }
            return (detail, code)
        }

        self.manager = manager
        NSLog("[razer-inputd] Seized Orbweaver (%d interface(s))", matched)
        return nil
    }

    private static let inputCallback: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess, let context else { return }
        let service = Unmanaged<InputService>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let usage = IOHIDElementGetUsage(element)
        // Boot-keyboard array reports publish each keypress twice: once as a
        // generic selector element (usage 0xFFFFFFFF carrying the key usage as
        // its value) and once as the concrete key element. Only the latter
        // carries a correct pressed/released state.
        guard IOHIDElementGetUsagePage(element) == hidUsagePageKeyboard,
              usage > 0x03, usage <= UInt32(UInt8.max) else { return }
        service.send(.init(kind: .event, usage: Int(usage),
                           pressed: IOHIDValueGetIntegerValue(value) != 0))
    }

    // MARK: - Teardown

    private func send(_ message: RazerInputMessage) {
        guard let data = try? RazerInputWire.encode(message) else { return }
        clientLock.lock()
        defer { clientLock.unlock() }
        guard clientFD >= 0 else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(clientFD, base.advanced(by: offset),
                                         buffer.count - offset)
                if count <= 0 { break }
                offset += count
            }
        }
    }

    /// Releasing the seized interface is the single most important teardown
    /// step: a seized device that is never released leaves the keypad dead for
    /// every other process until the daemon is restarted.
    private func releaseHID() {
        DispatchQueue.main.sync {
            if let manager = self.manager {
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(),
                                                  CFRunLoopMode.commonModes.rawValue)
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                NSLog("[razer-inputd] Released seized device")
            }
            self.manager = nil
        }
    }

    /// Evict the current owner without touching its descriptor. Shutting the
    /// socket down wakes that owner's blocked read() so it tears itself down;
    /// closing another thread's fd here would risk closing a descriptor that
    /// had already been recycled for a different connection.
    private func displaceCurrentClient() {
        clientLock.lock()
        let previous = clientFD
        clientFD = -1
        clientLock.unlock()
        if previous >= 0 {
            NSLog("[razer-inputd] Displacing previous client (fd %d)", previous)
            shutdown(previous, SHUT_RDWR)
        }
        releaseHID()
    }

    /// Called by a connection handler for its own descriptor only.
    private func releaseClient(_ fd: Int32) {
        clientLock.lock()
        let wasOwner = (clientFD == fd)
        if wasOwner { clientFD = -1 }
        clientLock.unlock()
        if wasOwner { releaseHID() }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        NSLog("[razer-inputd] Client fd %d closed%@", fd,
              wasOwner ? "; devices released" : " (already displaced)")
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

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

// Release seized devices on SIGTERM so a launchd stop or a reinstall does not
// leave the keypad captured by a dying process.
private func installSignalHandlers(_ service: InputService) {
    for signalNumber in [SIGTERM, SIGINT] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler {
            NSLog("[razer-inputd] Received signal %d; exiting", signalNumber)
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
}

private var signalSources: [DispatchSourceSignal] = []

let service = InputService()
installSignalHandlers(service)
service.run()
