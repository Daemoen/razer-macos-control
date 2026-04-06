import Foundation

// MARK: - Device Type

enum RazerDeviceType: String, Codable {
    case keyboard
    case mouse
    case accessory
    case headset
}

// MARK: - Device Features

struct RazerDeviceFeatures: OptionSet, Codable {
    let rawValue: UInt32

    static let matrixRGB       = RazerDeviceFeatures(rawValue: 1 << 0)
    static let macroKeys       = RazerDeviceFeatures(rawValue: 1 << 1)
    static let dial            = RazerDeviceFeatures(rawValue: 1 << 2)
    static let roller          = RazerDeviceFeatures(rawValue: 1 << 3)
    static let staticEffect    = RazerDeviceFeatures(rawValue: 1 << 4)
    static let breathingEffect = RazerDeviceFeatures(rawValue: 1 << 5)
    static let waveEffect      = RazerDeviceFeatures(rawValue: 1 << 6)
    static let spectrumEffect  = RazerDeviceFeatures(rawValue: 1 << 7)
    static let reactiveEffect  = RazerDeviceFeatures(rawValue: 1 << 8)
    static let starlightEffect = RazerDeviceFeatures(rawValue: 1 << 9)
    static let brightnessCtrl  = RazerDeviceFeatures(rawValue: 1 << 10)
    static let dpiControl      = RazerDeviceFeatures(rawValue: 1 << 11)
    static let pollRateCtrl    = RazerDeviceFeatures(rawValue: 1 << 12)
    static let onboardMemory   = RazerDeviceFeatures(rawValue: 1 << 13)
    static let wireless        = RazerDeviceFeatures(rawValue: 1 << 14)
    static let bluetooth       = RazerDeviceFeatures(rawValue: 1 << 15)
    static let underglow       = RazerDeviceFeatures(rawValue: 1 << 16)

    static let allEffects: RazerDeviceFeatures = [.staticEffect, .breathingEffect, .waveEffect, .spectrumEffect, .reactiveEffect, .starlightEffect]
    static let keyboardFull: RazerDeviceFeatures = [.allEffects, .matrixRGB, .brightnessCtrl, .onboardMemory]
}

// MARK: - Device LED Zone

struct RazerDeviceZone: Codable {
    let led: RazerLED
    let label: String

    // Codable conformance for RazerLED
    enum CodingKeys: String, CodingKey { case ledRaw, label }
    init(led: RazerLED, label: String) { self.led = led; self.label = label }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        led = RazerLED(rawValue: try c.decode(UInt8.self, forKey: .ledRaw)) ?? .none
        label = try c.decode(String.self, forKey: .label)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(led.rawValue, forKey: .ledRaw)
        try c.encode(label, forKey: .label)
    }
}

// MARK: - Device Info

struct RazerDeviceInfo {
    let pid: UInt16
    let name: String
    let type: RazerDeviceType
    let features: RazerDeviceFeatures
    let protocolVersion: RazerProtocolVersion
    let transactionId: UInt8
    let zones: [RazerDeviceZone]

    // Keyboard-specific
    let matrixDims: (rows: Int, cols: Int)?
    let macroKeyCount: Int
    let hasDial: Bool
    let hasRoller: Bool

    // Mouse-specific
    let dpiMax: Int?
    let buttonCount: Int

    init(pid: UInt16, name: String, type: RazerDeviceType, features: RazerDeviceFeatures,
         proto: RazerProtocolVersion = .standard, txId: UInt8 = RazerTransactionID.standard.rawValue,
         zones: [RazerDeviceZone] = [], matrix: (Int, Int)? = nil,
         macroKeys: Int = 0, dial: Bool = false, roller: Bool = false,
         dpiMax: Int? = nil, buttons: Int = 0) {
        self.pid = pid
        self.name = name
        self.type = type
        self.features = features
        self.protocolVersion = proto
        self.transactionId = txId
        self.zones = zones
        self.matrixDims = matrix
        self.macroKeyCount = macroKeys
        self.hasDial = dial
        self.hasRoller = roller
        self.dpiMax = dpiMax
        self.buttonCount = buttons
    }
}
