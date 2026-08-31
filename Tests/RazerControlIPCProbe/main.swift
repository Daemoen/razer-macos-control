import Foundation
import RazerControlIPC

let messages: [RazerInputMessage] = [
    .init(kind: .hello),
    .init(kind: .ready),
    .init(kind: .event, usage: 0x1e, pressed: true),
    .init(kind: .error, message: "denied"),
    .init(kind: .ping),
    .init(kind: .pong),
]

do {
    for expected in messages {
        let framed = try RazerInputWire.encode(expected)
        guard framed.last == 0x0a else { throw ProbeError.missingFrameDelimiter }
        let decoded = try RazerInputWire.decode(framed.dropLast())
        guard decoded.kind == expected.kind,
              decoded.version == razerInputProtocolVersion,
              decoded.usage == expected.usage,
              decoded.pressed == expected.pressed,
              decoded.message == expected.message else { throw ProbeError.roundTripMismatch }
    }
    do {
        _ = try RazerInputWire.decode(Data("not-json".utf8))
        throw ProbeError.acceptedMalformedPayload
    } catch is DecodingError {
        // Expected.
    }
    print("PASS: Razer input wire protocol round-trip and malformed-input rejection")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

enum ProbeError: Error {
    case missingFrameDelimiter
    case roundTripMismatch
    case acceptedMalformedPayload
}
