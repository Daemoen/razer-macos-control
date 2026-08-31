import Foundation
import IOKit.hid
import Combine

/// Device-scoped raw input observation used to identify the real controls
/// before enabling exclusive capture. This does not suppress or remap input.
final class RazerHIDInputMonitor: ObservableObject {
    @Published private(set) var pressedKeyboardUsages: Set<UInt8> = []
    @Published private(set) var lastUsage: UInt8?
    @Published private(set) var error: String?

    private var manager: IOHIDManager?
    private var activeProductId: UInt16?
    private let traceURL = URL(fileURLWithPath: "/tmp/razercontrol_input_trace.log")

    func start(productId: UInt16) {
        guard activeProductId != productId else { return }
        stop()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let keyboardMatch: [String: Any] = [
            kIOHIDVendorIDKey as String: Int(RazerUSB.vendorId),
            kIOHIDProductIDKey as String: Int(productId),
            kIOHIDDeviceUsagePageKey as String: 0x01,
            kIOHIDDeviceUsageKey as String: 0x06,
        ]
        let pointerMatch: [String: Any] = [
            kIOHIDVendorIDKey as String: Int(RazerUSB.vendorId),
            kIOHIDProductIDKey as String: Int(productId),
            kIOHIDDeviceUsagePageKey as String: 0x01,
            kIOHIDDeviceUsageKey as String: 0x02,
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [keyboardMatch, pointerMatch] as CFArray)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            Self.inputValueCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            error = "Raw input open failed: \(String(format: "0x%08X", result))"
            return
        }

        self.manager = manager
        activeProductId = productId
        try? "RazerControl raw input trace — PID \(String(format: "%04X", productId))\n"
            .write(to: traceURL, atomically: true, encoding: .utf8)
        error = nil
        print("[RazerInput] Observing VID 1532 PID \(String(format: "%04X", productId))")
    }

    func stop() {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        activeProductId = nil
        pressedKeyboardUsages.removeAll()
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess, let context else { return }
        let monitor = Unmanaged<RazerHIDInputMonitor>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)
        let type = IOHIDElementGetType(element)
        let isArray = IOHIDElementIsArray(element)

        // Limit the trace to keyboard, button, and directional pointer data.
        if page == 0x07 || page == 0x09 || (page == 0x01 && [0x30, 0x31, 0x38].contains(usage)) {
            monitor.trace(
                "page=\(String(format: "%04X", page)) usage=\(String(format: "%04X", usage)) " +
                "value=\(integerValue) type=\(type.rawValue) array=\(isArray ? 1 : 0) " +
                "cookie=\(IOHIDElementGetCookie(element))"
            )
        }

        guard page == 0x07,
              usage != UInt32.max,
              usage > 0x03,
              usage <= UInt32(UInt8.max)
        else { return }

        // IOHID publishes boot-keyboard array reports twice: once as a generic
        // selector (usage FFFFFFFF, value = key usage), then as the concrete
        // key element (usage = key usage, value = pressed state). Consuming the
        // selector value shifts ordinary keys because its release value is 0.
        monitor.record(usage: UInt8(usage), isPressed: integerValue != 0)
    }

    private func record(usage: UInt8, isPressed: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isPressed {
                self.pressedKeyboardUsages.insert(usage)
                self.lastUsage = usage
            } else {
                self.pressedKeyboardUsages.remove(usage)
            }
            print("[RazerInput] usage=\(String(format: "0x%02X", usage)) \(isPressed ? "down" : "up")")
        }
    }

    private func trace(_ line: String) {
        let text = line + "\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: traceURL) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                print("[RazerInput] Trace write failed: \(error.localizedDescription)")
            }
        }
        print("[RazerInput] \(line)")
    }
}
