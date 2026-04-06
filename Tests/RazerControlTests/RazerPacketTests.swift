import Testing
@testable import RazerControl

@Suite("RazerPacket")
struct RazerPacketTests {

    @Test("Empty packet is 90 bytes of zeros")
    func emptyPacket() {
        let packet = RazerPacket()
        #expect(packet.data.count == 90)
        #expect(packet.data.allSatisfy { $0 == 0 })
    }

    @Test("Packet fields are at correct offsets")
    func fieldOffsets() {
        var packet = RazerPacket()
        packet.data[0] = 0x02
        packet.data[1] = 0x1F
        packet.data[5] = 0x03
        packet.data[6] = 0x0F
        packet.data[7] = 0x02

        #expect(packet.status == .successful)
        #expect(packet.transactionId == 0x1F)
        #expect(packet.dataSize == 0x03)
        #expect(packet.commandClass == 0x0F)
        #expect(packet.commandId == 0x02)
    }

    @Test("CRC is XOR of bytes 2 through 87")
    func crcCalculation() {
        var packet = RazerPacket()
        // Set some bytes in the CRC range
        packet.data[2] = 0xAA
        packet.data[3] = 0x55
        packet.data[6] = 0x03
        packet.data[7] = 0x0A

        let expectedCRC = UInt8(0xAA ^ 0x55 ^ 0x03 ^ 0x0A) // all other bytes are 0
        #expect(packet.calculateCRC() == expectedCRC)
    }

    @Test("updateCRC writes to byte 88")
    func updateCRC() {
        var packet = RazerPacket()
        packet.data[6] = 0xFF
        packet.updateCRC()
        #expect(packet.data[88] == 0xFF) // only byte 6 is non-zero in CRC range
        #expect(packet.crc == 0xFF)
    }

    @Test("setDriverMode packet has correct structure")
    func driverModePacket() {
        let packet = RazerPacket.setDriverMode(transactionId: 0x1F)

        #expect(packet.transactionId == 0x1F)
        #expect(packet.commandClass == RazerCommandClass.device.rawValue) // 0x00
        #expect(packet.commandId == RazerCmd.deviceMode) // 0x04
        #expect(packet.dataSize == 2)
        #expect(packet.data[8] == RazerDeviceMode.driver.rawValue) // 0x03
        #expect(packet.data[9] == 0x00)

        // CRC should be valid
        #expect(packet.crc == packet.calculateCRC())
    }

    @Test("standardStatic packet has RGB in correct positions")
    func standardStaticPacket() {
        let packet = RazerPacket.standardStatic(r: 255, g: 0, b: 128, transactionId: 0xFF)

        #expect(packet.commandClass == RazerCommandClass.standard.rawValue) // 0x03
        #expect(packet.commandId == RazerCmd.stdEffect) // 0x0A
        #expect(packet.data[8] == RazerStandardEffect.static.rawValue) // 0x06
        #expect(packet.data[9] == 255)  // R
        #expect(packet.data[10] == 0)   // G
        #expect(packet.data[11] == 128) // B
        #expect(packet.crc == packet.calculateCRC())
    }

    @Test("extendedStatic packet has LED and RGB in correct positions")
    func extendedStaticPacket() {
        let packet = RazerPacket.extendedStatic(
            led: .backlight, storage: .variableStore,
            r: 0, g: 255, b: 0, transactionId: 0x1F
        )

        #expect(packet.commandClass == RazerCommandClass.extended.rawValue) // 0x0F
        #expect(packet.commandId == RazerCmd.extEffect) // 0x02
        #expect(packet.data[8] == RazerLEDStorage.variableStore.rawValue) // 0x01
        #expect(packet.data[9] == RazerLED.backlight.rawValue) // 0x05
        #expect(packet.data[10] == RazerExtendedEffect.static.rawValue) // 0x01
        // RGB at offset 14, 15, 16
        #expect(packet.data[14] == 0)   // R
        #expect(packet.data[15] == 255) // G
        #expect(packet.data[16] == 0)   // B
        #expect(packet.crc == packet.calculateCRC())
    }

    @Test("Wave packet includes direction")
    func wavePacket() {
        let packet = RazerPacket.standardWave(direction: .rightToLeft)
        #expect(packet.data[8] == RazerStandardEffect.wave.rawValue)
        #expect(packet.data[9] == RazerWaveDirection.rightToLeft.rawValue) // 0x02
    }

    @Test("Breathing packet includes single color mode byte")
    func breathingPacket() {
        let packet = RazerPacket.standardBreathing(r: 100, g: 200, b: 50)
        #expect(packet.data[8] == RazerStandardEffect.breathing.rawValue) // 0x03
        #expect(packet.data[9] == 0x01)  // single color mode
        #expect(packet.data[10] == 100)  // R
        #expect(packet.data[11] == 200)  // G
        #expect(packet.data[12] == 50)   // B
    }

    @Test("Spectrum packet has no arguments beyond effect ID")
    func spectrumPacket() {
        let packet = RazerPacket.standardSpectrum()
        #expect(packet.data[8] == RazerStandardEffect.spectrum.rawValue)
        #expect(packet.dataSize == 1)
    }

    @Test("Brightness packet has correct value range")
    func brightnessPacket() {
        let packet = RazerPacket.setBrightness(led: .backlight, value: 128, transactionId: 0x1F)
        #expect(packet.commandClass == RazerCommandClass.extended.rawValue)
        #expect(packet.commandId == RazerCmd.extBrightness)
        #expect(packet.data[8] == RazerLEDStorage.variableStore.rawValue)
        #expect(packet.data[9] == RazerLED.backlight.rawValue)
        #expect(packet.data[10] == 128)
    }

    @Test("Per-key custom frame has row and column data")
    func customFramePacket() {
        let colors: [UInt8] = [255, 0, 0, 0, 255, 0, 0, 0, 255] // 3 keys: R, G, B
        let packet = RazerPacket.setCustomFrame(row: 2, startCol: 0, stopCol: 2, colors: colors)
        #expect(packet.data[8] == 0xFF)  // flag
        #expect(packet.data[9] == 2)     // row
        #expect(packet.data[10] == 0)    // start col
        #expect(packet.data[11] == 2)    // stop col
        #expect(packet.data[12] == 255)  // R of first key
        #expect(packet.data[13] == 0)    // G of first key
        #expect(packet.data[14] == 0)    // B of first key
    }

    @Test("Remaining packets field is big-endian")
    func remainingPackets() {
        var packet = RazerPacket()
        packet.remainingPackets = 0x0102
        #expect(packet.data[2] == 0x01)
        #expect(packet.data[3] == 0x02)
        #expect(packet.remainingPackets == 0x0102)
    }

    @Test("Packet nsData returns correct Data object")
    func nsDataConversion() {
        let packet = RazerPacket.standardSpectrum()
        let data = packet.nsData
        #expect(data.count == 90)
        #expect(data[6] == RazerCommandClass.standard.rawValue)
    }
}
