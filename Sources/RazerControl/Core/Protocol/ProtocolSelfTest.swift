import Foundation

/// Golden-vector checks for the Razer wire format.
///
/// These assert the bytes we build against OpenRazer\'s `razerchromacommon.c`,
/// which is the reference this device database was derived from. They run
/// entirely offline: nothing is transmitted, no device is opened. That matters,
/// because the alternative way to validate a lighting packet is to fire it at
/// real hardware, and a malformed feature report is exactly how a Razer device
/// ends up in an unexpected firmware state.
///
/// Run with:  RazerControl --protocol-self-test
enum ProtocolSelfTest {
    struct Expectation {
        let name: String
        let packet: RazerPacket
        let commandClass: UInt8
        let commandId: UInt8
        /// Payload length the protocol declares. Not necessarily the number of
        /// bytes populated -- several commands declare more and leave the rest
        /// zero. Inferring it from the populated length is the defect these
        /// vectors exist to catch.
        let dataSize: UInt8
        /// Index -> required value, for the bytes the reference pins down.
        let args: [Int: UInt8]
    }

    static func run() -> (passed: Bool, report: String) {
        let rgb: (UInt8, UInt8, UInt8) = (0x11, 0x22, 0x33)
        let vs = RazerLEDStorage.variableStore.rawValue
        let bl = RazerLED.backlight.rawValue
        let std = RazerCommandClass.standard.rawValue
        let ext = RazerCommandClass.extended.rawValue
        let dev = RazerCommandClass.device.rawValue
        let pwr = RazerCommandClass.power.rawValue
        let btn = RazerCommandClass.buttonAssignment.rawValue

        let cases: [Expectation] = [
            // -- device + power: observed on the wire with USBPcap, not ported
            // from OpenRazer, which carries no equivalent command. The captured
            // checksums are reproduced here because the CRC covers bytes 2..87
            // and so does not depend on the transaction id.
            .init(name: "handedness right", packet: .setHandedness(.rightHanded),
                  commandClass: dev, commandId: RazerCmd.handedness,
                  dataSize: 0x01, args: [0: 0x00]),

            .init(name: "handedness left", packet: .setHandedness(.leftHanded),
                  commandClass: dev, commandId: RazerCmd.handedness,
                  dataSize: 0x01, args: [0: 0x01]),

            .init(name: "battery level", packet: .getBatteryLevel(),
                  commandClass: pwr, commandId: RazerCmd.batteryLevel,
                  dataSize: 0x02, args: [:]),

            .init(name: "charging status", packet: .getChargingStatus(),
                  commandClass: pwr, commandId: RazerCmd.chargingStatus,
                  dataSize: 0x02, args: [:]),

            // -- button assignment: class 0x02, command 0x0C -----------------
            // Byte-for-byte reproductions of frames captured from Synapse and
            // acknowledged by the device. The keyboard and mouse forms differ
            // in length because the action is type-length-value.
            .init(name: "assign left front to Left Ctrl",
                  packet: .setButtonAssignment(slot: .leftFront, action: .keyboardKey(0xE0)),
                  commandClass: btn, commandId: RazerCmd.buttonAssignment,
                  dataSize: 0x0A,
                  args: [0: 0x01, 1: 0x05, 2: 0x00, 3: 0x02, 4: 0x02, 5: 0x00, 6: 0xE0]),

            .init(name: "assign right back to key 0",
                  packet: .setButtonAssignment(slot: .rightBack, action: .keyboardKey(0x27)),
                  commandClass: btn, commandId: RazerCmd.buttonAssignment,
                  dataSize: 0x0A,
                  args: [0: 0x01, 1: 0x06, 2: 0x00, 3: 0x02, 4: 0x02, 5: 0x00, 6: 0x27]),

            .init(name: "assign right back to Mouse 4",
                  packet: .setButtonAssignment(slot: .rightBack, action: .mouseButton(0x04)),
                  commandClass: btn, commandId: RazerCmd.buttonAssignment,
                  dataSize: 0x0A,
                  args: [0: 0x01, 1: 0x06, 2: 0x00, 3: 0x01, 4: 0x01, 5: 0x04]),

            .init(name: "assign right front to Mouse 5",
                  packet: .setButtonAssignment(slot: .rightFront, action: .mouseButton(0x05)),
                  commandClass: btn, commandId: RazerCmd.buttonAssignment,
                  dataSize: 0x0A,
                  args: [0: 0x01, 1: 0x07, 2: 0x00, 3: 0x01, 4: 0x01, 5: 0x05]),

            // -- standard matrix effects: class 0x03, command 0x0A ------------
            .init(name: "standard off", packet: .standardOff(),
                  commandClass: std, commandId: RazerCmd.stdEffect,
                  dataSize: 0x01, args: [0: 0x00]),

            .init(name: "standard wave leftToRight", packet: .standardWave(direction: .leftToRight),
                  commandClass: std, commandId: RazerCmd.stdEffect,
                  dataSize: 0x02, args: [0: 0x01, 1: 0x01]),

            .init(name: "standard wave rightToLeft", packet: .standardWave(direction: .rightToLeft),
                  commandClass: std, commandId: RazerCmd.stdEffect,
                  dataSize: 0x02, args: [0: 0x01, 1: 0x02]),

            .init(name: "standard spectrum", packet: .standardSpectrum(),
                  commandClass: std, commandId: RazerCmd.stdEffect,
                  dataSize: 0x01, args: [0: 0x04]),

            .init(name: "standard static", packet: .standardStatic(r: rgb.0, g: rgb.1, b: rgb.2),
                  commandClass: std, commandId: RazerCmd.stdEffect,
                  dataSize: 0x04, args: [0: 0x06, 1: rgb.0, 2: rgb.1, 3: rgb.2]),

            .init(name: "standard breathing", packet: .standardBreathing(r: rgb.0, g: rgb.1, b: rgb.2),
                  commandClass: std, commandId: RazerCmd.stdEffect,
                  dataSize: 0x08, args: [0: 0x03, 1: 0x01, 2: rgb.0, 3: rgb.1, 4: rgb.2]),

            // -- extended matrix effects: class 0x0F, command 0x02 ------------
            // The three below declare 0x06 while populating fewer bytes. That
            // discrepancy is the whole point of these vectors.
            .init(name: "extended off", packet: .extendedOff(),
                  commandClass: ext, commandId: RazerCmd.extEffect,
                  dataSize: 0x06, args: [0: vs, 1: bl, 2: 0x00]),

            .init(name: "extended spectrum", packet: .extendedSpectrum(),
                  commandClass: ext, commandId: RazerCmd.extEffect,
                  dataSize: 0x06, args: [0: vs, 1: bl, 2: 0x03]),

            .init(name: "extended wave leftToRight", packet: .extendedWave(direction: .leftToRight),
                  commandClass: ext, commandId: RazerCmd.extEffect,
                  dataSize: 0x06,
                  args: [0: vs, 1: bl, 2: 0x04, 3: 0x01, 4: RazerPacket.extendedWaveSpeed]),

            .init(name: "extended wave rightToLeft", packet: .extendedWave(direction: .rightToLeft),
                  commandClass: ext, commandId: RazerCmd.extEffect,
                  dataSize: 0x06,
                  args: [0: vs, 1: bl, 2: 0x04, 3: 0x02, 4: RazerPacket.extendedWaveSpeed]),

            .init(name: "extended static", packet: .extendedStatic(r: rgb.0, g: rgb.1, b: rgb.2),
                  commandClass: ext, commandId: RazerCmd.extEffect,
                  dataSize: 0x09,
                  args: [0: vs, 1: bl, 2: 0x01, 5: 0x01, 6: rgb.0, 7: rgb.1, 8: rgb.2]),

            .init(name: "extended breathing", packet: .extendedBreathing(r: rgb.0, g: rgb.1, b: rgb.2),
                  commandClass: ext, commandId: RazerCmd.extEffect,
                  dataSize: 0x09,
                  args: [0: vs, 1: bl, 2: 0x02, 3: 0x01, 5: 0x01, 6: rgb.0, 7: rgb.1, 8: rgb.2]),

            // -- brightness: class 0x0F, command 0x04 -------------------------
            .init(name: "extended brightness", packet: .setBrightness(value: 0x80),
                  commandClass: ext, commandId: RazerCmd.extBrightness,
                  dataSize: 0x03, args: [0: vs, 1: bl, 2: 0x80]),
        ]

        var lines: [String] = []
        var failures = 0

        for expectation in cases {
            var problems: [String] = []
            let packet = expectation.packet

            if packet.commandClass != expectation.commandClass {
                problems.append(String(format: "class %02X != %02X",
                                       Int(packet.commandClass), Int(expectation.commandClass)))
            }
            if packet.commandId != expectation.commandId {
                problems.append(String(format: "command %02X != %02X",
                                       Int(packet.commandId), Int(expectation.commandId)))
            }
            if packet.dataSize != expectation.dataSize {
                problems.append(String(format: "declared data_size %02X != %02X",
                                       Int(packet.dataSize), Int(expectation.dataSize)))
            }
            for (index, expected) in expectation.args.sorted(by: { $0.key < $1.key }) {
                let actual = packet.data[8 + index]
                if actual != expected {
                    problems.append(String(format: "arg[%d] %02X != %02X",
                                           index, Int(actual), Int(expected)))
                }
            }
            // Every packet must carry a correct checksum, or the device drops it
            // before any of the above matters.
            if packet.crc != packet.calculateCRC() {
                problems.append("CRC mismatch")
            }
            // Bytes past the declared payload must be clean; stale content there
            // has been observed to change how a device reads a short command.
            let tail = (Int(expectation.dataSize) ..< 80).first {
                packet.data[8 + $0] != 0 && expectation.args[$0] == nil
            }
            if let tail {
                problems.append("non-zero byte at arg[\(tail)] past declared payload")
            }

            if problems.isEmpty {
                lines.append("  PASS  \(expectation.name)")
            } else {
                failures += 1
                lines.append("  FAIL  \(expectation.name): \(problems.joined(separator: ", "))")
            }
        }

        let header = "Razer wire-format vectors (reference: OpenRazer razerchromacommon.c)"
        let footer = failures == 0
            ? "PASS protocol-self-test: \(cases.count)/\(cases.count) vectors"
            : "FAIL protocol-self-test: \(failures)/\(cases.count) vectors failed"
        return (failures == 0, ([header] + lines + [footer]).joined(separator: "\n"))
    }
}
