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
    @Published var pressedKeyboardUsages: Set<UInt8> = []
    @Published var isNativeInputActive = false

    /// Active key mappings: HID keycode → action
    @Published var keyMappings: [UInt8: KeyAction] = [:]
    @Published var isRemappingActive = false

    let profileManager = ProfileManager()
    private let karabinerBackend = KarabinerBackend()
    private let nativeRemapper = NativeHIDRemapper()
    private let privilegedInput = PrivilegedInputClient()

    /// Active mouse button mappings: button number → action
    @Published var mouseMappings: [Int: KeyAction] = [:]
    @Published var isMouseRemappingActive = false

    private let hidManager = RazerHIDManager()
    private let inputMonitor = RazerHIDInputMonitor()
    private var cancellables = Set<AnyCancellable>()

    // Mappings belong to a device, not to the application.
    //
    // They were previously one dictionary keyed by HID usage with no device
    // dimension at all, so plugging in a second keypad inherited the first
    // one's bindings wholesale. That is not merely untidy: the Orbweaver's top
    // row begins with a backtick and the Tartarus's begins with 1, so the two
    // decks are offset by one key, and five bindings would land on their
    // neighbour's key without anything appearing to be wrong.
    private static func keyMappingsKey(for productID: UInt16) -> String {
        String(format: "SavedKeyMappings.%04x", productID)
    }

    private static func mouseMappingsKey(for productID: UInt16) -> String {
        String(format: "SavedMouseMappings.%04x", productID)
    }

    /// The original device-less entries. Left in place permanently as a backup;
    /// nothing reads them after the migration and nothing overwrites them.
    private static let legacyKeyMappingsKey = "SavedKeyMappings"
    private static let legacyMouseMappingsKey = "SavedMouseMappings"
    private static let migrationFlagKey = "MappingsMigratedToPerDevice"

    /// Devices that inherit the pre-migration bindings. Those bindings were
    /// authored on the Orbweaver; the Tartarus is included because its rows two
    /// through four are identical to the Orbweaver's, so every binding lands on
    /// the same physical key. Bindings for keys the Tartarus lacks simply never
    /// match anything.
    private static let legacyKeypadInheritors: [UInt16] = [0x0207, 0x022B, 0x0208, 0x0244]
    private static let legacyMouseInheritors: [UInt16] = [0x007B, 0x007C]

    /// Which device the in-memory mappings currently belong to.
    private var loadedKeyboardPID: UInt16?
    private var loadedMousePID: UInt16?

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

        inputMonitor.$pressedKeyboardUsages
            .receive(on: DispatchQueue.main)
            .assign(to: &$pressedKeyboardUsages)

        privilegedInput.$isActive
            .receive(on: DispatchQueue.main)
            .assign(to: &$isNativeInputActive)

        inputMonitor.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)

        privilegedInput.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)

        privilegedInput.onKeyboardUsage = { [weak self] usage, isPressed in
            guard let self else { return }
            if isPressed { self.pressedKeyboardUsages.insert(usage) }
            else { self.pressedKeyboardUsages.remove(usage) }
            self.nativeRemapper.handle(source: usage, isPressed: isPressed)
        }

        privilegedInput.start()

        Self.migrateLegacyMappingsIfNeeded()

        // Mappings follow the selected device, so they load when one is chosen
        // rather than at construction.
        $selectedDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMappingsForSelection() }
            .store(in: &cancellables)
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
            // Kraken Kitty exposes a separate USB audio function. Configuration
            // belongs to its 0x0F19 Chroma controller, not the audio endpoint.
            if hidDevice.productId == 0x0521 { continue }
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

        if devices.contains(where: { $0.pid == 0x0207 }) {
            nativeRemapper.updateMappings(keyMappings)
        } else {
            nativeRemapper.releaseAll()
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
    var isKarabinerReady: Bool { karabinerBackend.isConfigured }

    /// Installing a root daemon requires privilege the app does not and should
    /// not hold. Installation is an explicit administrator action performed by
    /// Scripts/install-daemon.sh; the app only re-attempts the connection.
    func reconnectNativeInput() {
        privilegedInput.reconnect()
    }

    var isNativeInputInstalled: Bool { privilegedInput.isDaemonInstalled }

    // MARK: - Key Mapping

    /// Save a key mapping: source HID keycode → target action
    func setKeyMapping(sourceHID: UInt8, action: KeyAction) {
        keyMappings[sourceHID] = action
        print("[DeviceManager] Mapped HID 0x\(String(format: "%02X", sourceHID)) → \(action)")
        saveMappings()
        nativeRemapper.updateMappings(keyMappings)
        isRemappingActive = !keyMappings.isEmpty && isNativeInputActive
    }

    func clearKeyMapping(sourceHID: UInt8) {
        keyMappings.removeValue(forKey: sourceHID)
        saveMappings()
        nativeRemapper.updateMappings(keyMappings)
        isRemappingActive = !keyMappings.isEmpty && isNativeInputActive
    }

    /// Enable the native, device-scoped remapper.
    func startRemapping() {
        guard !keyMappings.isEmpty else { return }
        nativeRemapper.updateMappings(keyMappings)
        isRemappingActive = isNativeInputActive
    }

    /// Stop remapping
    func stopRemapping() {
        nativeRemapper.updateMappings([:])
        isRemappingActive = false
    }

    // MARK: - Mouse Mapping

    func setMouseMapping(button: Int, action: KeyAction) {
        mouseMappings[button] = action
        print("[DeviceManager] Mouse button \(button) → \(action)")
        saveMappings()
        syncKarabinerMappings()
    }

    func clearMouseMapping(button: Int) {
        mouseMappings.removeValue(forKey: button)
        saveMappings()
        syncKarabinerMappings()
    }

    func startMouseRemapping() {
        guard !mouseMappings.isEmpty else { return }
        syncKarabinerMappings()
    }

    func stopMouseRemapping() {
        syncKarabinerMappings()
    }

    private func syncKarabinerMappings() {
        do {
            try karabinerBackend.apply(
                keyMappings: keyMappings,
                mouseMappings: mouseMappings
            )
            isRemappingActive = !keyMappings.isEmpty
            isMouseRemappingActive = !mouseMappings.isEmpty
            lastError = nil
        } catch {
            isRemappingActive = false
            isMouseRemappingActive = false
            lastError = error.localizedDescription
            print("[KarabinerBackend] \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private func saveMappings() {
        let encoder = JSONEncoder()

        if let pid = loadedKeyboardPID {
            let keyDict = Dictionary(uniqueKeysWithValues: keyMappings.map { (String($0.key), $0.value) })
            if let data = try? encoder.encode(keyDict) {
                UserDefaults.standard.set(data, forKey: Self.keyMappingsKey(for: pid))
            }
        }

        if let pid = loadedMousePID {
            let mouseDict = Dictionary(uniqueKeysWithValues: mouseMappings.map { (String($0.key), $0.value) })
            if let data = try? encoder.encode(mouseDict) {
                UserDefaults.standard.set(data, forKey: Self.mouseMappingsKey(for: pid))
            }
        }

        print("[DeviceManager] Saved \(keyMappings.count) key + \(mouseMappings.count) mouse mappings")
    }

    /// Copies the pre-migration bindings to each device that should inherit
    /// them. Runs once. The original entries are never modified, so the old
    /// configuration remains recoverable.
    private static func migrateLegacyMappingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlagKey) else { return }

        if let legacy = defaults.data(forKey: legacyKeyMappingsKey) {
            for pid in legacyKeypadInheritors where defaults.data(forKey: keyMappingsKey(for: pid)) == nil {
                defaults.set(legacy, forKey: keyMappingsKey(for: pid))
            }
        }
        if let legacy = defaults.data(forKey: legacyMouseMappingsKey) {
            for pid in legacyMouseInheritors where defaults.data(forKey: mouseMappingsKey(for: pid)) == nil {
                defaults.set(legacy, forKey: mouseMappingsKey(for: pid))
            }
        }
        defaults.set(true, forKey: migrationFlagKey)
        print("[DeviceManager] Migrated shared mappings to per-device storage")
    }

    /// Reloads mappings when the selected keyboard or mouse changes, writing
    /// the outgoing device's bindings back first.
    private func refreshMappingsForSelection() {
        let keyboardPID = selectedKeyboard?.pid
        let mousePID = selectedMouse?.pid
        guard keyboardPID != loadedKeyboardPID || mousePID != loadedMousePID else { return }
        saveMappings()
        loadedKeyboardPID = keyboardPID
        loadedMousePID = mousePID
        loadMappings()
    }

    private func loadMappings() {
        let decoder = JSONDecoder()

        keyMappings = [:]
        mouseMappings = [:]

        // Load key mappings
        if let pid = loadedKeyboardPID,
           let data = UserDefaults.standard.data(forKey: Self.keyMappingsKey(for: pid)),
           let dict = try? decoder.decode([String: KeyAction].self, from: data) {
            keyMappings = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                UInt8(k).map { ($0, v) }
            })
            print("[DeviceManager] Loaded \(keyMappings.count) key mappings")
        }

        // Load mouse mappings
        if let pid = loadedMousePID,
           let data = UserDefaults.standard.data(forKey: Self.mouseMappingsKey(for: pid)),
           let dict = try? decoder.decode([String: KeyAction].self, from: data) {
            mouseMappings = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                Int(k).map { ($0, v) }
            })
            print("[DeviceManager] Loaded \(mouseMappings.count) mouse mappings")
        }

        // Auto-start remapping if mappings exist
        if !keyMappings.isEmpty { startRemapping() }
        if !mouseMappings.isEmpty { startMouseRemapping() }
    }

    /// Build a KeyAction from captured key info
    func makeAction(fromCGKeyCode cgKey: UInt16, modifiers: NSEvent.ModifierFlags) -> KeyAction {
        // Find the HID code for this CG keycode
        let hidCode = KeyCodeMap.hidToCG.first(where: { $0.value == cgKey })?.key ?? 0

        let hasModifiers = modifiers.contains(.command) || modifiers.contains(.shift) ||
                           modifiers.contains(.option) || modifiers.contains(.control)

        if hasModifiers {
            var modByte: UInt8 = 0
            if modifiers.contains(.command) { modByte |= 0x01 }
            if modifiers.contains(.shift) { modByte |= 0x02 }
            if modifiers.contains(.option) { modByte |= 0x04 }
            if modifiers.contains(.control) { modByte |= 0x08 }
            return .shortcut(modifiers: modByte, key: hidCode)
        } else {
            return .keystroke(hidCode)
        }
    }
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
