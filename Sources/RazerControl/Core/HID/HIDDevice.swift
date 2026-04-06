import Foundation
import IOKit
import IOKit.hid

// MARK: - HID Device Wrapper

/// Wraps an IOHIDDevice for sending/receiving Razer USB packets.
/// Uses IOKit HID Manager (not libusb) — no root required on macOS.
final class RazerHIDDevice {
    let ioDevice: IOHIDDevice
    let vendorId: UInt16
    let productId: UInt16
    let productName: String
    let serialNumber: String

    private(set) var isOpen = false

    // MARK: - Init

    init?(ioDevice: IOHIDDevice) {
        self.ioDevice = ioDevice

        guard let vid = IOHIDDeviceGetProperty(ioDevice, kIOHIDVendorIDKey as CFString) as? Int,
              let pid = IOHIDDeviceGetProperty(ioDevice, kIOHIDProductIDKey as CFString) as? Int else {
            return nil
        }

        self.vendorId = UInt16(vid)
        self.productId = UInt16(pid)
        self.productName = IOHIDDeviceGetProperty(ioDevice, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        self.serialNumber = IOHIDDeviceGetProperty(ioDevice, kIOHIDSerialNumberKey as CFString) as? String ?? ""
    }

    // MARK: - Open / Close

    func open() -> Bool {
        guard !isOpen else { return true }
        let result = IOHIDDeviceOpen(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = (result == kIOReturnSuccess)
        if !isOpen {
            print("[RazerHID] Failed to open device \(productName): \(String(format: "0x%08X", result))")
        }
        return isOpen
    }

    func close() {
        guard isOpen else { return }
        IOHIDDeviceClose(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
    }

    // MARK: - Send Packet (Feature Report)

    /// Send a RazerPacket as a HID feature report.
    /// This is the primary way to communicate with Razer devices.
    /// Returns the response packet, or nil on failure.
    @discardableResult
    func sendPacket(_ packet: RazerPacket) -> RazerPacket? {
        guard isOpen || open() else { return nil }

        // Send the feature report
        let sendData = packet.bytes
        let sendResult = IOHIDDeviceSetReport(
            ioDevice,
            kIOHIDReportTypeFeature,
            CFIndex(0x00),  // Report ID
            sendData,
            sendData.count
        )

        guard sendResult == kIOReturnSuccess else {
            print("[RazerHID] SetReport failed for \(productName): \(String(format: "0x%08X", sendResult))")
            return nil
        }

        // Wait for the device to process (important for USB timing)
        usleep(RazerUSB.postWriteDelay)

        // Read response
        var response = [UInt8](repeating: 0, count: RazerPacket.packetSize)
        var reportLength = RazerPacket.packetSize

        let readResult = IOHIDDeviceGetReport(
            ioDevice,
            kIOHIDReportTypeFeature,
            CFIndex(0x00),
            &response,
            &reportLength
        )

        guard readResult == kIOReturnSuccess else {
            print("[RazerHID] GetReport failed for \(productName): \(String(format: "0x%08X", readResult))")
            return nil
        }

        var responsePacket = RazerPacket()
        responsePacket.data = response
        return responsePacket
    }

    // MARK: - Convenience Commands

    /// Initialize macro keys (switch to driver mode)
    func initMacroKeys(transactionId: UInt8) -> Bool {
        let packet = RazerPacket.setDriverMode(transactionId: transactionId)
        let response = sendPacket(packet)
        return response?.isSuccess ?? false
    }

    /// Set static color on a specific LED zone
    func setStaticColor(r: UInt8, g: UInt8, b: UInt8, led: RazerLED = .backlight,
                        protocol proto: RazerProtocolVersion, transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardStatic(r: r, g: g, b: b, transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedStatic(led: led, r: r, g: g, b: b, transactionId: transactionId)
        }
        let response = sendPacket(packet)
        return response?.isSuccess ?? false
    }

    /// Set wave effect
    func setWaveEffect(direction: RazerWaveDirection = .leftToRight, led: RazerLED = .backlight,
                       protocol proto: RazerProtocolVersion, transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardWave(direction: direction, transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedWave(led: led, direction: direction, transactionId: transactionId)
        }
        return sendPacket(packet)?.isSuccess ?? false
    }

    /// Set spectrum cycling effect
    func setSpectrumEffect(led: RazerLED = .backlight, protocol proto: RazerProtocolVersion,
                           transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardSpectrum(transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedSpectrum(led: led, transactionId: transactionId)
        }
        return sendPacket(packet)?.isSuccess ?? false
    }

    /// Set breathing effect
    func setBreathingEffect(r: UInt8, g: UInt8, b: UInt8, led: RazerLED = .backlight,
                            protocol proto: RazerProtocolVersion, transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardBreathing(r: r, g: g, b: b, transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedBreathing(led: led, r: r, g: g, b: b, transactionId: transactionId)
        }
        return sendPacket(packet)?.isSuccess ?? false
    }

    /// Turn off lighting
    func setOff(led: RazerLED = .backlight, protocol proto: RazerProtocolVersion,
                transactionId: UInt8) -> Bool {
        let packet: RazerPacket
        switch proto {
        case .standard:
            packet = .standardOff(transactionId: transactionId)
        case .extended, .mouseExtended:
            packet = .extendedOff(led: led, transactionId: transactionId)
        }
        return sendPacket(packet)?.isSuccess ?? false
    }

    /// Set brightness (0-255)
    func setBrightness(_ value: UInt8, led: RazerLED = .backlight, transactionId: UInt8) -> Bool {
        let packet = RazerPacket.setBrightness(led: led, value: value, transactionId: transactionId)
        return sendPacket(packet)?.isSuccess ?? false
    }

    /// Get firmware version string
    func getFirmwareVersion(transactionId: UInt8) -> String? {
        let packet = RazerPacket.getFirmwareVersion(transactionId: transactionId)
        guard let response = sendPacket(packet), response.isSuccess else { return nil }
        let major = response.data[9]
        let minor = response.data[10]
        return "v\(major).\(minor)"
    }

    // MARK: - Debug

    var debugDescription: String {
        "RazerHIDDevice(\(productName), VID:\(String(format: "0x%04X", vendorId)), PID:\(String(format: "0x%04X", productId)), SN:\(serialNumber))"
    }
}
