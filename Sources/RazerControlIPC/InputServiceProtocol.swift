import Foundation

public let razerInputMachServiceName = "com.razercontrol.input-helper"

@objc public protocol RazerInputHelperProtocol {
    func registerClient(_ client: RazerInputClientProtocol,
                        withReply reply: @escaping (Bool, String?) -> Void)
}

@objc public protocol RazerInputClientProtocol {
    func helperReady()
    func inputEvent(usage: Int, pressed: Bool)
    func helperError(_ message: String)
}
