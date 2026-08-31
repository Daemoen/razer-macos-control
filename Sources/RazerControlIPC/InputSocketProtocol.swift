import Foundation

public let razerInputSocketPath = "/var/run/razercontrol-input.sock"
public let razerInputProtocolVersion = 1

public struct RazerInputMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello, ready, event, error, ping, pong
    }

    public let kind: Kind
    public let version: Int
    public let usage: Int?
    public let pressed: Bool?
    public let message: String?

    public init(kind: Kind, version: Int = razerInputProtocolVersion,
                usage: Int? = nil, pressed: Bool? = nil, message: String? = nil) {
        self.kind = kind
        self.version = version
        self.usage = usage
        self.pressed = pressed
        self.message = message
    }
}

public enum RazerInputWire {
    public static func encode(_ message: RazerInputMessage) throws -> Data {
        var data = try JSONEncoder().encode(message)
        data.append(0x0a)
        return data
    }

    public static func decode(_ line: Data) throws -> RazerInputMessage {
        try JSONDecoder().decode(RazerInputMessage.self, from: line)
    }
}
