import Foundation

// MARK: - Razer USB Packet (90 bytes)
//
// Offset  Size  Field
// 0x00    1     status (0x00=new, 0x02=success, 0x03=fail)
// 0x01    1     transaction_id
// 0x02    2     remaining_packets (big-endian)
// 0x04    1     protocol_type (always 0x00)
// 0x05    1     data_size (payload length, max 80)
// 0x06    1     command_class
// 0x07    1     command_id
// 0x08    80    arguments (payload)
// 0x58    1     crc (XOR of bytes [2..87])
// 0x59    1     reserved (0x00)

struct RazerPacket {
    static let packetSize = 90
    static let headerSize = 8
    static let maxPayloadSize = 80
    static let crcIndex = 88
    static let reservedIndex = 89

    var data: [UInt8]

    // MARK: - Computed Properties

    var status: RazerStatus {
        get { RazerStatus(rawValue: data[0]) ?? .new }
        set { data[0] = newValue.rawValue }
    }

    var transactionId: UInt8 {
        get { data[1] }
        set { data[1] = newValue }
    }

    var remainingPackets: UInt16 {
        get { UInt16(data[2]) << 8 | UInt16(data[3]) }
        set { data[2] = UInt8(newValue >> 8); data[3] = UInt8(newValue & 0xFF) }
    }

    var dataSize: UInt8 {
        get { data[5] }
        set { data[5] = newValue }
    }

    var commandClass: UInt8 {
        get { data[6] }
        set { data[6] = newValue }
    }

    var commandId: UInt8 {
        get { data[7] }
        set { data[7] = newValue }
    }

    var arguments: ArraySlice<UInt8> {
        data[8..<88]
    }

    var crc: UInt8 {
        get { data[Self.crcIndex] }
        set { data[Self.crcIndex] = newValue }
    }

    var isSuccess: Bool { status == .successful }

    // MARK: - Init

    init() {
        data = [UInt8](repeating: 0, count: Self.packetSize)
    }

    init(transactionId: UInt8, commandClass: RazerCommandClass, commandId: UInt8, args: [UInt8] = []) {
        data = [UInt8](repeating: 0, count: Self.packetSize)
        self.transactionId = transactionId
        self.commandClass = commandClass.rawValue
        self.commandId = commandId
        self.dataSize = UInt8(args.count)
        for (i, arg) in args.enumerated() where i < Self.maxPayloadSize {
            data[8 + i] = arg
        }
        updateCRC()
    }

    // MARK: - CRC

    /// XOR all bytes from index 2 through 87 inclusive
    func calculateCRC() -> UInt8 {
        var crc: UInt8 = 0
        for i in 2...87 {
            crc ^= data[i]
        }
        return crc
    }

    mutating func updateCRC() {
        data[Self.crcIndex] = calculateCRC()
    }

    // MARK: - Raw Bytes

    var bytes: [UInt8] { data }

    var nsData: Data { Data(data) }
}

// MARK: - Command Builders

extension RazerPacket {

    // MARK: Device Commands

    /// Initialize macro keys by switching to driver mode
    /// This makes M1-M5 emit F13-F17 keycodes
    static func setDriverMode(transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .device,
            commandId: RazerCmd.deviceMode,
            args: [RazerDeviceMode.driver.rawValue, 0x00]
        )
    }

    /// Get current device mode (normal or driver)
    static func getDeviceMode(transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .device,
            commandId: RazerCmd.deviceMode,
            args: [0x00, 0x00]
        )
    }

    /// Get firmware version string
    static func getFirmwareVersion(transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .device,
            commandId: RazerCmd.firmwareVersion,
            args: []
        )
    }

    /// Get device serial number
    static func getSerialNumber(transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .device,
            commandId: RazerCmd.serialNumber,
            args: [0x00] + [UInt8](repeating: 0, count: 22)
        )
    }

    // MARK: Standard Effects (class 0x03)

    static func standardStatic(r: UInt8, g: UInt8, b: UInt8, transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .standard,
            commandId: RazerCmd.stdEffect,
            args: [RazerStandardEffect.static.rawValue, r, g, b]
        )
    }

    static func standardWave(direction: RazerWaveDirection, transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .standard,
            commandId: RazerCmd.stdEffect,
            args: [RazerStandardEffect.wave.rawValue, direction.rawValue]
        )
    }

    static func standardBreathing(r: UInt8, g: UInt8, b: UInt8, transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .standard,
            commandId: RazerCmd.stdEffect,
            args: [RazerStandardEffect.breathing.rawValue, 0x01, r, g, b, 0, 0, 0]
        )
    }

    static func standardSpectrum(transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .standard,
            commandId: RazerCmd.stdEffect,
            args: [RazerStandardEffect.spectrum.rawValue]
        )
    }

    static func standardOff(transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .standard,
            commandId: RazerCmd.stdEffect,
            args: [RazerStandardEffect.off.rawValue]
        )
    }

    // MARK: Extended Effects (class 0x0F)

    static func extendedStatic(
        led: RazerLED = .backlight,
        storage: RazerLEDStorage = .variableStore,
        r: UInt8, g: UInt8, b: UInt8,
        transactionId: UInt8 = RazerTransactionID.standard.rawValue
    ) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .extended,
            commandId: RazerCmd.extEffect,
            args: [storage.rawValue, led.rawValue, RazerExtendedEffect.static.rawValue, 0x00, 0x00, 0x01, r, g, b]
        )
    }

    static func extendedBreathing(
        led: RazerLED = .backlight,
        r: UInt8, g: UInt8, b: UInt8,
        transactionId: UInt8 = RazerTransactionID.standard.rawValue
    ) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .extended,
            commandId: RazerCmd.extEffect,
            args: [RazerLEDStorage.variableStore.rawValue, led.rawValue, RazerExtendedEffect.breathing.rawValue, 0x01, 0x00, 0x01, r, g, b]
        )
    }

    static func extendedWave(
        led: RazerLED = .backlight,
        direction: RazerWaveDirection = .leftToRight,
        transactionId: UInt8 = RazerTransactionID.standard.rawValue
    ) -> RazerPacket {
        // V4 Pro uses short format: [storage, led, effect, direction]
        // Speed parameter is NOT supported on newer devices
        RazerPacket(
            transactionId: transactionId,
            commandClass: .extended,
            commandId: RazerCmd.extEffect,
            args: [RazerLEDStorage.variableStore.rawValue, led.rawValue, RazerExtendedEffect.wave.rawValue, direction.rawValue]
        )
    }

    static func extendedSpectrum(
        led: RazerLED = .backlight,
        transactionId: UInt8 = RazerTransactionID.standard.rawValue
    ) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .extended,
            commandId: RazerCmd.extEffect,
            args: [RazerLEDStorage.variableStore.rawValue, led.rawValue, RazerExtendedEffect.spectrum.rawValue]
        )
    }

    static func extendedOff(
        led: RazerLED = .backlight,
        transactionId: UInt8 = RazerTransactionID.standard.rawValue
    ) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .extended,
            commandId: RazerCmd.extEffect,
            args: [RazerLEDStorage.variableStore.rawValue, led.rawValue, RazerExtendedEffect.off.rawValue]
        )
    }

    // MARK: Brightness

    static func setBrightness(
        led: RazerLED = .backlight,
        value: UInt8,   // 0-255
        transactionId: UInt8 = RazerTransactionID.standard.rawValue
    ) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .extended,
            commandId: RazerCmd.extBrightness,
            args: [RazerLEDStorage.variableStore.rawValue, led.rawValue, value]
        )
    }

    // MARK: Per-Key Matrix (standard protocol)

    /// Send a row of RGB data for per-key lighting
    /// row: 0-5, startCol/stopCol define the range, colors is [R,G,B,R,G,B,...]
    static func setCustomFrame(
        row: UInt8, startCol: UInt8, stopCol: UInt8, colors: [UInt8],
        transactionId: UInt8 = RazerTransactionID.standard.rawValue
    ) -> RazerPacket {
        var args: [UInt8] = [0xFF, row, startCol, stopCol]
        args.append(contentsOf: colors)
        return RazerPacket(
            transactionId: transactionId,
            commandClass: .standard,
            commandId: RazerCmd.stdCustomFrame,
            args: args
        )
    }

    /// Activate custom (per-key) mode after sending frames
    static func activateCustomMode(transactionId: UInt8 = RazerTransactionID.standard.rawValue) -> RazerPacket {
        RazerPacket(
            transactionId: transactionId,
            commandClass: .standard,
            commandId: RazerCmd.stdEffect,
            args: [RazerStandardEffect.custom.rawValue, 0x01]
        )
    }
}
