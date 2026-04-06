import Foundation
import IOKit
import IOKit.hid
import Combine

// MARK: - HID Manager

/// Discovers and monitors Razer USB devices using IOKit HID Manager.
/// Publishes device connect/disconnect events via Combine.
@MainActor
final class RazerHIDManager: ObservableObject {
    @Published var connectedDevices: [RazerHIDDevice] = []
    @Published var lastError: String?

    private var hidManager: IOHIDManager?
    private var isRunning = false

    // Callbacks need to be stored as class properties for C function pointer bridging
    private var matchCallback: IOHIDDeviceCallback?
    private var removeCallback: IOHIDDeviceCallback?

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            lastError = "Failed to create HID Manager"
            return
        }

        // Match only Razer devices (vendor ID 0x1532)
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey: RazerUSB.vendorId
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        // Register callbacks using the bridging pattern
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let manager = Unmanaged<RazerHIDManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.deviceConnected(device)
            }
        }, selfPtr)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let manager = Unmanaged<RazerHIDManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.deviceDisconnected(device)
            }
        }, selfPtr)

        // Schedule on the main run loop
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

        // Close all devices
        for device in connectedDevices {
            device.close()
        }
        connectedDevices.removeAll()

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
        isRunning = false
        print("[RazerHID] Manager stopped")
    }

    // MARK: - Device Events

    private func deviceConnected(_ ioDevice: IOHIDDevice) {
        guard let device = RazerHIDDevice(ioDevice: ioDevice) else { return }

        let usagePage = IOHIDDeviceGetProperty(ioDevice, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(ioDevice, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

        // Each Razer device exposes 5-10 USB interfaces. Only some accept control commands.
        // Verified with real hardware:
        //   BlackWidow V4 Pro: UsagePage 0x0001, Usage 0x0000 is the control interface
        //   Pro Click V2 Vertical: UsagePage 0x0001, Usage 0x0002 works
        //
        // Strategy: accept candidate interfaces, and if we already have one for this PID,
        // replace it only if the new one is "better" (Usage 0x0000 is preferred for keyboards).

        let usageScore: Int
        switch (usagePage, usage) {
        case (0x0001, 0x0000): usageScore = 100  // Generic Desktop, undefined — keyboard control (best)
        case (0x0001, 0x0002): usageScore = 80   // Generic Desktop, Mouse — works for mice
        case (0x0001, 0x0006): usageScore = 50   // Generic Desktop, Keyboard — input interface (not for commands)
        default: usageScore = 0                   // Vendor-specific or other — skip
        }

        guard usageScore > 0 else { return }

        // Check if we already have this PID
        if let existingIdx = connectedDevices.firstIndex(where: { $0.productId == device.productId }) {
            let existingIO = connectedDevices[existingIdx].ioDevice
            let existingUsage = IOHIDDeviceGetProperty(existingIO, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
            let existingPage = IOHIDDeviceGetProperty(existingIO, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            let existingScore: Int
            switch (existingPage, existingUsage) {
            case (0x0001, 0x0000): existingScore = 100
            case (0x0001, 0x0002): existingScore = 80
            case (0x0001, 0x0006): existingScore = 50
            default: existingScore = 0
            }

            if usageScore > existingScore {
                // Replace with better interface
                connectedDevices[existingIdx].close()
                connectedDevices[existingIdx] = device
                print("[RazerHID] Upgraded: \(device.debugDescription) [UP:\(String(format: "0x%04X", usagePage)) U:\(String(format: "0x%04X", usage)) score:\(usageScore)]")
            }
            return
        }

        connectedDevices.append(device)
        print("[RazerHID] Connected: \(device.debugDescription) [UP:\(String(format: "0x%04X", usagePage)) U:\(String(format: "0x%04X", usage)) score:\(usageScore)]")
    }

    private func deviceDisconnected(_ ioDevice: IOHIDDevice) {
        // Find and remove the device by matching the IOHIDDevice reference
        guard let vid = IOHIDDeviceGetProperty(ioDevice, kIOHIDVendorIDKey as CFString) as? Int,
              let pid = IOHIDDeviceGetProperty(ioDevice, kIOHIDProductIDKey as CFString) as? Int else {
            return
        }

        if let index = connectedDevices.firstIndex(where: { $0.productId == UInt16(pid) }) {
            let device = connectedDevices.remove(at: index)
            device.close()
            print("[RazerHID] Disconnected: \(device.debugDescription)")
        }
    }

    // MARK: - Device Lookup

    /// Find a connected device by product ID
    func device(withPID pid: UInt16) -> RazerHIDDevice? {
        connectedDevices.first { $0.productId == pid }
    }

    /// Find devices by type (keyboard, mouse, etc) using the device database
    func devices(ofType type: RazerDeviceType) -> [RazerHIDDevice] {
        connectedDevices.filter { device in
            DeviceDatabase.shared.lookup(pid: device.productId)?.type == type
        }
    }

    deinit {
        // Cannot call stop() in deinit because of @MainActor
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
