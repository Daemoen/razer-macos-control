import Foundation
import IOKit
import IOKit.hid
import Combine

// MARK: - HID Manager

/// Discovers and monitors Razer USB devices using IOKit HID Manager.
/// Collects ALL USB interfaces per physical device. The HIDDevice then
/// tries each interface when sending commands.
@MainActor
final class RazerHIDManager: ObservableObject {
    @Published var connectedDevices: [RazerHIDDevice] = []
    @Published var lastError: String?

    private var hidManager: IOHIDManager?
    private var isRunning = false

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            lastError = "Failed to create HID Manager"
            return
        }

        // Match only Razer devices (vendor ID 0x1532)
        let matchDict: [String: Any] = [kIOHIDVendorIDKey: RazerUSB.vendorId]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let mgr = Unmanaged<RazerHIDManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in mgr.deviceConnected(device) }
        }, selfPtr)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let mgr = Unmanaged<RazerHIDManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in mgr.deviceDisconnected(device) }
        }, selfPtr)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            lastError = "Failed to open HID Manager: \(String(format: "0x%08X", openResult))"
            return
        }

        isRunning = true
        print("[RazerHID] Manager started, scanning for devices...")
    }

    func stop() {
        guard isRunning, let manager = hidManager else { return }
        for device in connectedDevices { device.close() }
        connectedDevices.removeAll()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
        isRunning = false
        print("[RazerHID] Manager stopped")
    }

    // MARK: - Device Events

    private func deviceConnected(_ ioDevice: IOHIDDevice) {
        guard let pid = IOHIDDeviceGetProperty(ioDevice, kIOHIDProductIDKey as CFString) as? Int else { return }
        let usagePage = IOHIDDeviceGetProperty(ioDevice, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(ioDevice, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

        // Skip vendor-specific interfaces (UsagePage 0x0059) — they don't accept feature reports
        // Keep all Generic Desktop (0x0001) interfaces — we'll try them all when sending
        guard usagePage == 0x0001 else { return }

        // If we already have this PID, add the interface to existing device
        if let existing = connectedDevices.first(where: { $0.productId == UInt16(pid) }) {
            existing.addInterface(ioDevice)
            let count = existing.interfaces.count
            print("[RazerHID] +interface for \(existing.productName) [UP:\(String(format: "0x%04X", usagePage)) U:\(String(format: "0x%04X", usage))] (total: \(count))")
            return
        }

        // New device
        guard let device = RazerHIDDevice(ioDevice: ioDevice) else { return }
        connectedDevices.append(device)
        print("[RazerHID] Connected: \(device.productName) [UP:\(String(format: "0x%04X", usagePage)) U:\(String(format: "0x%04X", usage))]")
    }

    private func deviceDisconnected(_ ioDevice: IOHIDDevice) {
        guard let pid = IOHIDDeviceGetProperty(ioDevice, kIOHIDProductIDKey as CFString) as? Int else { return }

        // Remove the interface from the device
        if let device = connectedDevices.first(where: { $0.productId == UInt16(pid) }) {
            device.interfaces.removeAll { $0 === ioDevice }

            // If no interfaces left, remove the device entirely
            if device.interfaces.isEmpty {
                connectedDevices.removeAll { $0.productId == UInt16(pid) }
                print("[RazerHID] Disconnected: \(device.productName)")
            }
        }
    }

    // MARK: - Lookup

    func device(withPID pid: UInt16) -> RazerHIDDevice? {
        connectedDevices.first { $0.productId == pid }
    }

    func devices(ofType type: RazerDeviceType) -> [RazerHIDDevice] {
        connectedDevices.filter { device in
            DeviceDatabase.shared.lookup(pid: device.productId)?.type == type
        }
    }

    deinit {
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
