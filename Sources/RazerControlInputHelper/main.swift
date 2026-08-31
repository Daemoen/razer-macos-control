import Foundation
import IOKit.hid
import Darwin

private let socketPath = "/tmp/com.razercontrol.input.sock"

final class InputHelper {
    private var manager: IOHIDManager?
    private let socketFD = socket(AF_UNIX, SOCK_DGRAM, 0)
    private let queue = DispatchQueue(label: "com.razercontrol.input-helper")
    private var heartbeat: DispatchSourceTimer?

    func run() -> Never {
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
            send("error \(String(format: "%08X", result))")
            fputs("RazerControlInputHelper: HID open failed \(String(format: "0x%08X", result))\n", stderr)
            exit(1)
        }
        self.manager = manager
        send("ready")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.send("ready") }
        timer.resume()
        heartbeat = timer
        CFRunLoopRun()
        fatalError("unreachable")
    }

    private static let inputCallback: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess, let context else { return }
        let helper = Unmanaged<InputHelper>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard page == 0x07, usage > 0x03, usage <= UInt32(UInt8.max) else { return }
        helper.send("key \(usage) \(IOHIDValueGetIntegerValue(value) == 0 ? 0 : 1)")
    }

    private func send(_ message: String) {
        guard socketFD >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return }
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            _ = socketPath.utf8.withContiguousStorageIfAvailable { source in
                bytes.copyBytes(from: source)
            }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1)
        message.withCString { pointer in
            withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(socketFD, pointer, strlen(pointer), 0, $0, length)
                }
            }
        }
    }
}

InputHelper().run()
