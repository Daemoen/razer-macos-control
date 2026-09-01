import Foundation

/// Filesystem endpoint the privileged input daemon listens on. The daemon runs
/// as root and re-owns this path to the active console user, so the controller
/// connects as an ordinary user process.
public let razerInputSocketPath = "/var/run/razercontrol-input.sock"

/// launchd label for the privileged daemon. This deliberately differs from the
/// retired `com.razercontrol.input-helper` SMAppService label: that identifier
/// still has an orphaned Background Task Management record on machines that ran
/// the old installer, and reusing it would mean reconciling with BTM state we
/// cannot inspect or repair. A fresh label sidesteps that entirely.
public let razerInputDaemonLabel = "com.razercontrol.inputd"

/// Absolute install location of the daemon executable. It lives outside the
/// application bundle because a root job must not execute code from a path an
/// unprivileged user can rewrite, and because TCC keys Input Monitoring on this
/// exact path.
public let razerInputDaemonPath =
    "/Library/Application Support/RazerControl/RazerControlInputHelper"

public let razerInputDaemonPlistPath =
    "/Library/LaunchDaemons/com.razercontrol.inputd.plist"

/// Absolute path of the controller the daemon authenticates against. Fixed
/// rather than derived: the daemon no longer lives inside the app bundle, so
/// there is no containing bundle to walk up to.
public let razerControllerAppPath = "/Applications/RazerControl.app"

public let razerControllerBundleIdentifier = "com.razercontrol.app"

/// Bumped only for wire-incompatible changes. Both sides refuse a mismatch.
public let razerInputProtocolVersion = 3

public struct RazerInputMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello, ready, event, error, ping, pong, status
    }

    public let kind: Kind
    public let version: Int
    public let usage: Int?
    public let pressed: Bool?
    /// USB product ID of the device that produced this event.
    ///
    /// Without it the controller cannot tell a keypad's Left arrow from a
    /// mouse side button reporting the same usage, and one device's bindings
    /// fire on another's input. Usage alone is not an identity.
    public let productId: Int?
    public let message: String?
    /// Set on `error` so the controller can branch on cause rather than parse prose.
    public let code: String?

    public init(kind: Kind, version: Int = razerInputProtocolVersion,
                usage: Int? = nil, pressed: Bool? = nil, productId: Int? = nil,
                message: String? = nil, code: String? = nil) {
        self.kind = kind
        self.version = version
        self.usage = usage
        self.pressed = pressed
        self.productId = productId
        self.message = message
        self.code = code
    }
}

/// Stable error codes crossing the trust boundary. The controller maps these to
/// specific remediation text; prose is for humans only.
public enum RazerInputErrorCode {
    public static let inputMonitoringDenied = "input-monitoring-denied"
    public static let hidOpenFailed = "hid-open-failed"
    public static let deviceAbsent = "device-absent"
    public static let protocolMismatch = "protocol-mismatch"
}

public enum RazerInputWire {
    /// Newline-delimited JSON. Frames are bounded by the reader, not here.
    public static func encode(_ message: RazerInputMessage) throws -> Data {
        var data = try JSONEncoder().encode(message)
        data.append(0x0a)
        return data
    }

    public static func decode(_ line: Data) throws -> RazerInputMessage {
        try JSONDecoder().decode(RazerInputMessage.self, from: line)
    }
}
