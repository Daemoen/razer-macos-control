import Foundation
import IOKit
import IOKit.hid

// MARK: - HID Device Wrapper

/// Wraps one or more IOHIDDevice interfaces for a single Razer device.
/// Each physical Razer device exposes 5-10 USB interfaces. Commands may
/// only work on specific interfaces, so we try all of them and cache
/// the working one.
final class RazerHIDDevice {
    let vendorId: UInt16
    let productId: UInt16
    let productName: String
    let serialNumber: String

    /// All IOHIDDevice interfaces for this physical device
    var interfaces: [IOHIDDevice] = []

    /// The interface that last successfully sent a command (cached)
    private var workingInterface: IOHIDDevice?

    // MARK: - Init

    init?(ioDevice: IOHIDDevice) {
        guard let vid = IOHIDDeviceGetProperty(ioDevice, kIOHIDVendorIDKey as CFString) as? Int,
              let pid = IOHIDDeviceGetProperty(ioDevice, kIOHIDProductIDKey as CFString) as? Int else {
            return nil
        }

        self.vendorId = UInt16(vid)
        self.productId = UInt16(pid)
        self.productName = IOHIDDeviceGetProperty(ioDevice, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        self.serialNumber = IOHIDDeviceGetProperty(ioDevice, kIOHIDSerialNumberKey as CFString) as? String ?? ""
        self.interfaces = [ioDevice]
    }

    /// Add another interface for this same physical device
    func addInterface(_ ioDevice: IOHIDDevice) {
        interfaces.append(ioDevice)
        // Reset cache so next send retries all interfaces
        workingInterface = nil
    }

    // MARK: - Close

    func close() {
        for iface in interfaces {
            IOHIDDeviceClose(iface, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        interfaces.removeAll()
        workingInterface = nil
    }

    // MARK: - Send Packet (tries all interfaces)

    /// Send a RazerPacket as a HID feature report.
    /// Tries the cached working interface first, then all others.
    /// Returns the response packet, or nil on failure.
    @discardableResult
    func sendPacket(_ packet: RazerPacket) -> RazerPacket? {
        // Try cached interface first
        if let working = workingInterface {
            if let response = trySendOnInterface(working, packet: packet) {
                return response
            }
            workingInterface = nil // cache invalidated
        }

        // Try all interfaces
        for iface in interfaces {
            if let response = trySendOnInterface(iface, packet: packet) {
                workingInterface = iface // cache for next time
                let usage = IOHIDDeviceGetProperty(iface, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
                let usagePage = IOHIDDeviceGetProperty(iface, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                print("[RazerHID] Working interface found: [UP:\(String(format: "0x%04X", usagePage)) U:\(String(format: "0x%04X", usage))]")
                return response
            }
        }

        print("[RazerHID] All \(interfaces.count) interfaces failed for \(productName)")
        return nil
    }

    private func trySendOnInterface(_ iface: IOHIDDevice, packet: RazerPacket) -> RazerPacket? {
        // Ensure open
        let openResult = IOHIDDeviceOpen(iface, IOOptionBits(kIOHIDOptionsTypeNone))
        // kIOReturnSuccess or already-open is fine
        guard openResult == kIOReturnSuccess || openResult == kIOReturnExclusiveAccess else {
            return nil
        }

        let sendData = packet.bytes
        let sendResult = IOHIDDeviceSetReport(
            iface,
            kIOHIDReportTypeFeature,
            CFIndex(0x00),
            sendData,
            sendData.count
        )

        guard sendResult == kIOReturnSuccess else {
            return nil
        }

        // Wait for the device to process
        usleep(RazerUSB.postWriteDelay)

        // Read response
        var response = [UInt8](repeating: 0, count: RazerPacket.packetSize)
        var reportLength = RazerPacket.packetSize

        let readResult = IOHIDDeviceGetReport(
            iface,
            kIOHIDReportTypeFeature,
            CFIndex(0x00),
            &response,
            &reportLength
        )

        guard readResult == kIOReturnSuccess else {
            return nil
        }

        var responsePacket = RazerPacket()
        responsePacket.data = response

        // Only count as success if device acknowledged (status 0x02)
        // or at least didn't explicitly fail
        if responsePacket.status == .failure {
            return nil
        }

        return responsePacket
    }

    // MARK: - Convenience Commands

    func initMacroKeys(transactionId: UInt8) -> Bool {
        let packet = RazerPacket.setDriverMode(transactionId: transactionId)
        let response = sendPacket(packet)
        return response?.isSuccess ?? false
    }

    func setStaticColor(r: UInt8, g: UInt8, b: UInt8, led: RazerLED = .backlight,
                        protocol proto: RazerProtocolVersion, transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardStatic(r: r, g: g, b: b, transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedStatic(led: led, r: r, g: g, b: b, transactionId: transactionId)
        }
        return sendPacket(packet) != nil
    }

    func setWaveEffect(direction: RazerWaveDirection = .leftToRight, speed: UInt8 = 0x60,
                       led: RazerLED = .backlight,
                       protocol proto: RazerProtocolVersion, transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardWave(direction: direction, transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedWave(led: led, direction: direction, speed: speed, transactionId: transactionId)
        }
        return sendPacket(packet) != nil
    }

    func setSpectrumEffect(led: RazerLED = .backlight, protocol proto: RazerProtocolVersion,
                           transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardSpectrum(transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedSpectrum(led: led, transactionId: transactionId)
        }
        return sendPacket(packet) != nil
    }

    func setBreathingEffect(r: UInt8, g: UInt8, b: UInt8, led: RazerLED = .backlight,
                            protocol proto: RazerProtocolVersion, transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardBreathing(r: r, g: g, b: b, transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedBreathing(led: led, r: r, g: g, b: b, transactionId: transactionId)
        }
        return sendPacket(packet) != nil
    }

    func setOff(led: RazerLED = .backlight, protocol proto: RazerProtocolVersion,
                transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardOff(transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedOff(led: led, transactionId: transactionId)
        }
        return sendPacket(packet) != nil
    }

    func setBrightness(_ value: UInt8, led: RazerLED = .backlight, transactionId: UInt8) -> Bool {
        let packet = RazerPacket.setBrightness(led: led, value: value, transactionId: transactionId)
        return sendPacket(packet) != nil
    }

    func getFirmwareVersion(transactionId: UInt8) -> String? {
        let packet = RazerPacket.getFirmwareVersion(transactionId: transactionId)
        guard let response = sendPacket(packet), response.isSuccess else { return nil }
        let major = response.data[9]
        let minor = response.data[10]
        return "v\(major).\(minor)"
    }

    // MARK: - Debug

    var debugDescription: String {
        "RazerHIDDevice(\(productName), PID:\(String(format: "0x%04X", productId)), \(interfaces.count) interfaces)"
    }
}
