import Foundation

/// Sends exactly one button assignment and prints what the device answered.
///
/// The assignment command was derived from captured Synapse traffic and has
/// never been sent by this application. Two things are unverified and this is
/// the smallest thing that can settle both: whether the device accepts the
/// command on the interface the app already uses, and whether the resulting
/// assignment survives a reconnect or evaporates with the session.
///
///     RazerControl --assign-button 007b 06 kb 68
///     RazerControl --assign-button 007b 06 mouse 04
///
/// Slots are physical positions: 04 left-back, 05 left-front, 06 right-back,
/// 07 right-front. Unlike the other self-tests this one *does* write to
/// hardware, which is why it is a separate flag and not folded into any of them.
enum ButtonAssignmentProbe {
    @MainActor
    static func run(_ args: [String]) -> (passed: Bool, report: String) {
        let usage = """
        usage: --assign-button <pid-hex> <slot-hex> <kb|mouse> <value-hex>
          slot:  04 left-back  05 left-front  06 right-back  07 right-front
          kb:    HID keyboard usage, e.g. 68 for F13, 27 for '0'
          mouse: button number, e.g. 04 or 05
        """

        guard args.count >= 4,
              let pid = UInt16(args[0], radix: 16),
              let slotRaw = UInt8(args[1], radix: 16),
              let slot = RazerButtonSlot(rawValue: slotRaw),
              let value = UInt8(args[3], radix: 16)
        else { return (false, usage) }

        let action: RazerButtonAction
        switch args[2].lowercased() {
        case "kb": action = .keyboardKey(value)
        case "mouse": action = .mouseButton(value)
        default: return (false, usage)
        }

        let manager = RazerHIDManager()
        manager.start()
        guard let device = manager.device(withPID: pid) else {
            return (false, String(format: "no Razer device with PID %04X is attached", Int(pid)))
        }

        let packet = RazerPacket.setButtonAssignment(
            slot: slot, action: action,
            transactionId: RazerTransactionID.mouse.rawValue
        )
        let sent = packet.bytes[0..<12].map { String(format: "%02x", $0) }.joined(separator: " ")

        guard let response = device.sendPacket(packet) else {
            return (false, "sent:     \(sent)\nresponse: none -- the device did not answer")
        }
        let status = String(format: "0x%02x", response.status.rawValue)
        let verdict = response.isSuccess
            ? "ACCEPTED -- press the button and see what it now emits"
            : "REJECTED -- status \(status); likely the wrong interface"
        return (response.isSuccess, "sent:     \(sent)\nresponse: status \(status)\n\(verdict)")
    }
}
