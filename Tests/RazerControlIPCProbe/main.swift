import Foundation
import RazerControlIPC

// Executable probe rather than an XCTest/swift-testing target: this toolchain
// has no `Testing` module, so the package's test target cannot build. This
// binary is runnable from any script and returns a real exit code.

enum ProbeError: Error, CustomStringConvertible {
    case missingFrameDelimiter(String)
    case roundTripMismatch(String)
    case acceptedMalformedPayload
    case versionMismatchNotDetected
    case framingLost(String)
    case constantInvalid(String)

    var description: String {
        switch self {
        case .missingFrameDelimiter(let k): return "frame for \(k) lacked newline delimiter"
        case .roundTripMismatch(let k):     return "round trip altered \(k)"
        case .acceptedMalformedPayload:     return "decoder accepted non-JSON payload"
        case .versionMismatchNotDetected:   return "version mismatch was not observable to the reader"
        case .framingLost(let d):           return "stream framing lost: \(d)"
        case .constantInvalid(let d):       return "deployment constant invalid: \(d)"
        }
    }
}

func check(_ condition: Bool, _ error: ProbeError) throws {
    if !condition { throw error }
}

/// Every message shape that actually crosses the socket, including the `code`
/// field added for structured error reporting.
let messages: [RazerInputMessage] = [
    .init(kind: .hello),
    .init(kind: .ready),
    .init(kind: .event, usage: 0x1e, pressed: true),
    .init(kind: .event, usage: 0xff, pressed: false),
    .init(kind: .error, message: "denied", code: RazerInputErrorCode.inputMonitoringDenied),
    .init(kind: .error, message: "no device", code: RazerInputErrorCode.deviceAbsent),
    .init(kind: .error, message: "seize failed", code: RazerInputErrorCode.hidOpenFailed),
    .init(kind: .error, message: "bad version", code: RazerInputErrorCode.protocolMismatch),
    .init(kind: .ping),
    .init(kind: .pong),
    .init(kind: .status, message: "ok"),
]

do {
    // 1. Round trip preserves every field, delimiter included.
    for expected in messages {
        let framed = try RazerInputWire.encode(expected)
        try check(framed.last == 0x0a, .missingFrameDelimiter(expected.kind.rawValue))
        let decoded = try RazerInputWire.decode(framed.dropLast())
        try check(decoded.kind == expected.kind
                  && decoded.version == razerInputProtocolVersion
                  && decoded.usage == expected.usage
                  && decoded.pressed == expected.pressed
                  && decoded.message == expected.message
                  && decoded.code == expected.code,
                  .roundTripMismatch(expected.kind.rawValue))
    }

    // 2. Malformed input is rejected rather than silently coerced.
    do {
        _ = try RazerInputWire.decode(Data("not-json".utf8))
        throw ProbeError.acceptedMalformedPayload
    } catch is DecodingError {
        // Expected.
    }

    // 3. A foreign protocol version still decodes structurally, so both sides
    //    can *see* the mismatch and report it. If this stopped decoding, the
    //    peer would get "malformed frame" instead of "wrong version".
    let foreign = #"{"kind":"hello","version":99}"#
    let decodedForeign = try RazerInputWire.decode(Data(foreign.utf8))
    try check(decodedForeign.version == 99 && decodedForeign.version != razerInputProtocolVersion,
              .versionMismatchNotDetected)

    // 4. Newline framing survives concatenation. Both peers append to a buffer
    //    and split on 0x0a, so a burst of key events arriving in one read must
    //    decompose exactly.
    var stream = Data()
    for message in messages { stream.append(try RazerInputWire.encode(message)) }
    var recovered: [RazerInputMessage] = []
    var buffer = stream
    while let newline = buffer.firstIndex(of: 0x0a) {
        let line = buffer[..<newline]
        buffer.removeSubrange(...newline)
        recovered.append(try RazerInputWire.decode(Data(line)))
    }
    try check(buffer.isEmpty, .framingLost("residual bytes after split"))
    try check(recovered.count == messages.count,
              .framingLost("expected \(messages.count) frames, recovered \(recovered.count)"))
    for (a, b) in zip(recovered, messages) {
        try check(a.kind == b.kind && a.usage == b.usage && a.code == b.code,
                  .framingLost("frame \(b.kind.rawValue) corrupted in stream"))
    }

    // 5. No encoded frame may contain an interior newline, or framing breaks.
    for message in messages {
        let framed = try RazerInputWire.encode(message)
        let interior = framed.dropLast().firstIndex(of: 0x0a)
        try check(interior == nil, .framingLost("interior newline in \(message.kind.rawValue)"))
    }

    // 6. Deployment constants must be absolute and must not point inside a
    //    user-writable application bundle. This is the invariant the whole
    //    daemon relocation exists to establish; assert it mechanically.
    try check(razerInputDaemonPath.hasPrefix("/Library/"),
              .constantInvalid("daemon path not under /Library: \(razerInputDaemonPath)"))
    try check(!razerInputDaemonPath.contains(".app/"),
              .constantInvalid("daemon path is inside an app bundle: \(razerInputDaemonPath)"))
    try check(razerInputDaemonPlistPath.hasPrefix("/Library/LaunchDaemons/"),
              .constantInvalid("plist not in /Library/LaunchDaemons: \(razerInputDaemonPlistPath)"))
    try check(razerInputDaemonLabel != "com.razercontrol.input-helper",
              .constantInvalid("label collides with the retired SMAppService label"))
    try check(razerInputDaemonPlistPath.hasSuffix("/\(razerInputDaemonLabel).plist"),
              .constantInvalid("plist filename does not match the launchd label"))
    try check(razerControllerAppPath.hasSuffix(".app"),
              .constantInvalid("controller path is not a bundle: \(razerControllerAppPath)"))
    try check(razerInputSocketPath.hasPrefix("/var/run/"),
              .constantInvalid("socket outside /var/run: \(razerInputSocketPath)"))

    print("PASS: wire round-trip, malformed rejection, version visibility, stream framing, deployment constants (\(messages.count) shapes)")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
