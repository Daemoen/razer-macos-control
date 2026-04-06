import Foundation
import SwiftUI
import Combine

// MARK: - Connected Device (HID + Database info combined)

@MainActor
class ConnectedDevice: Identifiable, ObservableObject {
    let id = UUID()
    let hidDevice: RazerHIDDevice
    let info: RazerDeviceInfo

    @Published var macroKeysInitialized = false
    @Published var currentBrightness: Double = 1.0
    @Published var firmwareVersion: String?

    var name: String { info.name }
    var type: RazerDeviceType { info.type }
    var pid: UInt16 { info.pid }
    var productName: String { hidDevice.productName }

    var icon: String {
        switch type {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .accessory: return "cable.connector"
        case .headset: return "headphones"
        }
    }

    init(hidDevice: RazerHIDDevice, info: RazerDeviceInfo) {
        self.hidDevice = hidDevice
        self.info = info
    }

    // MARK: - Macro Keys

    func initMacroKeys() -> Bool {
        guard info.macroKeyCount > 0 else { return false }
        let success = hidDevice.initMacroKeys(transactionId: info.transactionId)
        if success { macroKeysInitialized = true }
        return success
    }

    // MARK: - Lighting

    /// Default LED for this device — keyboards use backlight, mice use none (all)
    var defaultLED: RazerLED {
        info.zones.first?.led ?? (type == .keyboard ? .backlight : .none)
    }

    func setStaticColor(_ color: Color) -> Bool {
        let (r, g, b) = color.rgbBytes
        return hidDevice.setStaticColor(
            r: r, g: g, b: b, led: defaultLED,
            protocol: info.protocolVersion,
            transactionId: info.transactionId
        )
    }

    func setStaticColor(r: UInt8, g: UInt8, b: UInt8, led: RazerLED? = nil) -> Bool {
        hidDevice.setStaticColor(
            r: r, g: g, b: b, led: led ?? defaultLED,
            protocol: info.protocolVersion,
            transactionId: info.transactionId
        )
    }

    func setWaveEffect(direction: RazerWaveDirection = .leftToRight, speed: UInt8 = 0x60) -> Bool {
        hidDevice.setWaveEffect(
            direction: direction, speed: speed, led: defaultLED,
            protocol: info.protocolVersion,
            transactionId: info.transactionId
        )
    }

    func setSpectrumEffect() -> Bool {
        hidDevice.setSpectrumEffect(
            led: defaultLED,
            protocol: info.protocolVersion,
            transactionId: info.transactionId
        )
    }

    func setBreathingEffect(_ color: Color) -> Bool {
        let (r, g, b) = color.rgbBytes
        return hidDevice.setBreathingEffect(
            r: r, g: g, b: b, led: defaultLED,
            protocol: info.protocolVersion,
            transactionId: info.transactionId
        )
    }

    func setOff() -> Bool {
        hidDevice.setOff(
            led: defaultLED,
            protocol: info.protocolVersion,
            transactionId: info.transactionId
        )
    }

    func setBrightness(_ value: Double) -> Bool {
        let byte = UInt8(max(0, min(255, value * 255)))
        let success = hidDevice.setBrightness(byte, led: defaultLED, transactionId: info.transactionId)
        if success { currentBrightness = value }
        return success
    }

    func queryFirmware() {
        firmwareVersion = hidDevice.getFirmwareVersion(transactionId: info.transactionId)
    }
}

// MARK: - Device Manager (central coordination)

@MainActor
class DeviceManager: ObservableObject {
    @Published var devices: [ConnectedDevice] = []
    @Published var selectedDevice: ConnectedDevice?
    @Published var isScanning = false
    @Published var lastError: String?

    private let hidManager = RazerHIDManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Observe HID manager for device changes
        hidManager.$connectedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hidDevices in
                self?.syncDevices(hidDevices)
            }
            .store(in: &cancellables)

        hidManager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)
    }

    // MARK: - Scanning

    func startScanning() {
        isScanning = true
        hidManager.start()
    }

    func stopScanning() {
        hidManager.stop()
        isScanning = false
    }

    // MARK: - Sync HID devices with ConnectedDevice wrappers

    private func syncDevices(_ hidDevices: [RazerHIDDevice]) {
        // Add new devices
        for hidDevice in hidDevices {
            if !devices.contains(where: { $0.pid == hidDevice.productId }) {
                if let info = DeviceDatabase.shared.lookup(pid: hidDevice.productId) {
                    let connected = ConnectedDevice(hidDevice: hidDevice, info: info)
                    devices.append(connected)
                    print("[DeviceManager] Added: \(connected.name)")

                    // Auto-select first device
                    if selectedDevice == nil {
                        selectedDevice = connected
                    }
                } else {
                    // Unknown Razer device — still show it
                    let unknownInfo = RazerDeviceInfo(
                        pid: hidDevice.productId,
                        name: hidDevice.productName,
                        type: .keyboard, // guess
                        features: [.staticEffect, .brightnessCtrl],
                        proto: .standard,
                        txId: RazerTransactionID.standard.rawValue
                    )
                    let connected = ConnectedDevice(hidDevice: hidDevice, info: unknownInfo)
                    devices.append(connected)
                    print("[DeviceManager] Added unknown Razer device: \(hidDevice.productName) (PID: \(String(format: "0x%04X", hidDevice.productId)))")

                    if selectedDevice == nil {
                        selectedDevice = connected
                    }
                }
            }
        }

        // Remove disconnected devices
        devices.removeAll { connected in
            !hidDevices.contains(where: { $0.productId == connected.pid })
        }

        // Fix selection if needed
        if let sel = selectedDevice, !devices.contains(where: { $0.id == sel.id }) {
            selectedDevice = devices.first
        }
    }

    // MARK: - Convenience

    var selectedKeyboard: ConnectedDevice? {
        selectedDevice?.type == .keyboard ? selectedDevice : devices.first { $0.type == .keyboard }
    }

    var selectedMouse: ConnectedDevice? {
        selectedDevice?.type == .mouse ? selectedDevice : devices.first { $0.type == .mouse }
    }

    var hasDevices: Bool { !devices.isEmpty }
}

// MARK: - Color → RGB bytes

extension Color {
    var rgbBytes: (UInt8, UInt8, UInt8) {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
            return (0, 255, 0) // fallback green
        }
        return (
            UInt8(max(0, min(255, rgb.redComponent * 255))),
            UInt8(max(0, min(255, rgb.greenComponent * 255))),
            UInt8(max(0, min(255, rgb.blueComponent * 255)))
        )
    }
}
