import Foundation
import IOKit
import Combine

// MARK: - Device Discovery

/// Passively discovers Razer USB devices through the IORegistry.
///
/// This intentionally does not create or open an IOHIDManager. Karabiner's
/// grabber must remain the sole owner of keyboard and pointing interfaces for
/// device-specific remapping to work reliably.
@MainActor
final class RazerHIDManager: ObservableObject {
    @Published var connectedDevices: [RazerHIDDevice] = []
    @Published var lastError: String?

    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
    }

    func stop() {
        connectedDevices.removeAll()
        isRunning = false
    }

    /// Refresh is passive and is also used by the UI's Rescan command.
    private func refresh() {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOUSBHostDevice"),
            &iterator
        )

        guard result == KERN_SUCCESS else {
            lastError = "Failed to read the USB device registry"
            return
        }
        defer { IOObjectRelease(iterator) }

        var discovered: [RazerHIDDevice] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard propertyInt(service, "idVendor") == Int(RazerUSB.vendorId),
                  let productId = propertyInt(service, "idProduct") else {
                continue
            }

            let name = propertyString(service, "USB Product Name")
                ?? propertyString(service, "kUSBProductString")
                ?? "Razer Device"
            let serial = propertyString(service, "USB Serial Number") ?? ""

            discovered.append(RazerHIDDevice(
                vendorId: RazerUSB.vendorId,
                productId: UInt16(productId),
                productName: name,
                serialNumber: serial
            ))
        }

        connectedDevices = discovered
        lastError = nil
        print("[RazerUSB] Passively discovered \(discovered.count) Razer device(s)")
    }

    private func propertyInt(_ service: io_registry_entry_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private func propertyString(_ service: io_registry_entry_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String
    }

    func device(withPID pid: UInt16) -> RazerHIDDevice? {
        connectedDevices.first { $0.productId == pid }
    }

    func devices(ofType type: RazerDeviceType) -> [RazerHIDDevice] {
        connectedDevices.filter { device in
            DeviceDatabase.shared.lookup(pid: device.productId)?.type == type
        }
    }
}
