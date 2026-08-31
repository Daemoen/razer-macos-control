import Foundation
import RazerControlIPC
import Darwin

/// Runs inside the signed RazerControl executable so the helper validates the
/// exact same code identity used by the GUI, rather than a shell-side proxy.
enum NativeInputSelfTest {
    struct Result {
        let succeeded: Bool
        let message: String
    }

    static func run() -> Result {
        let deadline = Date().addingTimeInterval(8)
        var lastError = "socket unavailable"
        while Date() < deadline {
            switch connectOnce() {
            case .success(let fd):
                defer { close(fd) }
                do {
                    try write(.init(kind: .hello), to: fd)
                    return readResponse(from: fd)
                } catch {
                    return .init(succeeded: false, message: "FAIL transport-write: \(error)")
                }
            case .failure(let error):
                lastError = error.localizedDescription
                usleep(250_000)
            }
        }
        return .init(succeeded: false, message: "FAIL socket-connect: \(lastError)")
    }

    private static func connectOnce() -> Swift.Result<Int32, Error> {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(posixError()) }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                       socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(razerInputSocketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return .failure(POSIXError(.ENAMETOOLONG))
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            path.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard status == 0 else {
            let error = posixError()
            close(fd)
            return .failure(error)
        }
        return .success(fd)
    }

    private static func readResponse(from fd: Int32) -> Result {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 10_000) > 0 else {
            return .init(succeeded: false, message: "FAIL helper-response-timeout")
        }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else {
            return .init(succeeded: false, message: "FAIL helper-closed-connection")
        }
        let data = Data(buffer.prefix(count))
        guard let newline = data.firstIndex(of: 0x0a),
              let message = try? RazerInputWire.decode(Data(data[..<newline])) else {
            return .init(succeeded: false, message: "FAIL malformed-helper-response")
        }
        switch message.kind {
        case .ready:
            return .init(succeeded: true, message: "PASS native-input: authenticated, HID opened, helper ready")
        case .error:
            return .init(succeeded: false, message: "FAIL helper: \(message.message ?? "unknown error")")
        default:
            return .init(succeeded: false, message: "FAIL unexpected-response: \(message.kind.rawValue)")
        }
    }

    private static func write(_ message: RazerInputMessage, to fd: Int32) throws {
        let data = try RazerInputWire.encode(message)
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
