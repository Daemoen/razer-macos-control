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
    private let nativeRemapper = NativeHIDRemapper()
    private let privilegedInput = PrivilegedInputClient()

    /// Active mouse button mappings: button number → action
    @Published var mouseMappings: [Int: KeyAction] = [:]

    /// What each side-button slot was last told to emit.
    ///
    /// The device has no readback we have found, so this is what the app wrote
    /// rather than what the mouse currently holds. Anything that changes the
    /// assignment elsewhere -- Synapse on another machine, a reconnect that
    /// drops back to on-board state -- makes this stale, so it is presented as
    /// the last applied setting and never as an observed one.
    @Published var sideButtonAssignments: [UInt8: RazerButtonAction] = [:]

    /// Which slots the device refused, so a failure can say what failed rather
    /// than only how many did.
    @Published var lastSideButtonFailure: String? = nil

    /// Gap between consecutive commands to a wireless device, in microseconds.
    ///
    /// The dongle relays over the air and will not take a second command while
    /// the first is outstanding. Sized generously: the cost is a fifth of a
    /// second on a button press, and the alternative is a silent partial write.
    static let interCommandDelay: UInt32 = 50_000
    @Published var isMouseRemappingActive = false

    private let hidManager = RazerHIDManager()

    /// Intercepts the buttons the input daemon cannot see.
    ///
    /// The daemon seizes keyboard collections only, deliberately -- taking the
    /// pointer would put the cursor itself behind it. That leaves the primaries,
    /// the wheel, and any side button still set to a mouse function with no
    /// route into this app at all. A CoreGraphics tap sees them system-wide
    /// without owning any device, which is what these bindings used to reach
    /// before they were routed through Karabiner and then lost with it.
    private let mouseMapper = MouseMapper()
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

        privilegedInput.onKeyboardUsage = { [weak self] productID, usage, isPressed in
            self?.handleCapturedInput(productID: productID, usage: usage, isPressed: isPressed)
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

    /// Devices whose input drives the key mappings.
    static let keypadProductIDs: Set<UInt16> = [0x0207, 0x022B, 0x0208, 0x0244]

    /// Devices captured for their buttons rather than their keys.
    static let mouseProductIDs: Set<UInt16> = [0x007B, 0x007C]

    /// Viper side buttons that report on its keyboard interface, mapped to the
    /// button numbers MouseButton.mappingSource uses. Observed on hardware,
    /// not assumed: left-forward reports 0xE0 and left-back 0xE2.
    static let viperUsageToButton: [UInt8: Int] = [
        // Factory-adjacent assignments, kept so a mouse we have never written
        // to still works: these are what the device arrives emitting when its
        // left flank has been set to modifiers by hand.
        0xE0: 1000,   // sideLeftForward
        0xE2: 1001,   // sideLeftBack
        // What the four buttons emit once RC has configured them. Mapped to the
        // same button numbers as above so a mapping saved before the device was
        // configured keeps working afterwards.
        0x69: 1000,   // sideLeftForward   F14
        0x68: 1001,   // sideLeftBack      F13
        0x6B: 4,      // sideRightForward  F16
        0x6A: 3,      // sideRightBack     F15
    ]

    /// What RC writes to make all four side buttons observable.
    ///
    /// A side button left at its factory setting is a mouse button, and a mouse
    /// button reports on the pointer interface, which the input daemon never
    /// seizes. Such a button is not merely unmapped -- it cannot be seen at all.
    /// Reassigning the four to function keys moves them onto the keyboard
    /// interface, where the daemon already listens.
    ///
    /// F13-F16 because nothing on a Mac keyboard produces them, so a button
    /// that leaks past RC types nothing rather than something destructive.
    static let sideButtonPlan: [(slot: RazerButtonSlot, usage: UInt8)] = [
        (.leftBack, 0x68),     // F13
        (.leftFront, 0x69),    // F14
        (.rightBack, 0x6A),    // F15
        (.rightFront, 0x6B),   // F16
    ]

    /// The half-and-half arrangement: modifiers on the left flank, factory
    /// mouse buttons on the right.
    ///
    /// This is what the mouse was carrying before this app could write to it,
    /// and it is a real position rather than a historical curiosity -- the two
    /// modifier buttons are reachable from RazerControl while the right pair
    /// keep working natively for browser back and forward with nothing running.
    /// Someone who wants two configurable buttons without giving up the two
    /// that already work wants exactly this.
    static let sideButtonModifierPreset: [(slot: RazerButtonSlot, action: RazerButtonAction)] = [
        (.leftFront, .keyboardKey(0xE0)),   // Left Control
        (.leftBack, .keyboardKey(0xE2)),    // Left Alt
        (.rightFront, .mouseButton(0x05)),  // Mouse 5
        (.rightBack, .mouseButton(0x04)),   // Mouse 4
    ]

    /// The three plans in one shape, so the UI can compare what is applied
    /// against each of them without knowing how each was declared.
    static var sideButtonPlanActions: [(slot: RazerButtonSlot, action: RazerButtonAction)] {
        sideButtonPlan.map { ($0.slot, .keyboardKey($0.usage)) }
    }

    static var sideButtonDefaultActions: [(slot: RazerButtonSlot, action: RazerButtonAction)] {
        sideButtonDefaults.map { ($0.slot, .mouseButton($0.button)) }
    }

    @discardableResult
    func applyPreset(_ plan: [(slot: RazerButtonSlot, action: RazerButtonAction)],
                     label: String) -> Int {
        applySideButtons(plan, label: label)
    }

    @discardableResult
    func applyModifierPreset() -> Int {
        applySideButtons(Self.sideButtonModifierPreset, label: "modifier preset")
    }

    /// Shared writer for the three presets, so they cannot drift apart.
    @discardableResult
    private func applySideButtons(_ plan: [(slot: RazerButtonSlot, action: RazerButtonAction)],
                                  label: String) -> Int {
        guard let mouse = selectedMouse,
              Self.mouseProductIDs.contains(mouse.pid) else { return 0 }
        var accepted = 0
        var failures: [String] = []
        for (index, entry) in plan.enumerated() {
            // The dongle relays each command over the air and will not accept a
            // second one while the first is still in flight. A single command
            // sent by hand always succeeded; two in a row were intermittent and
            // four in a row failed outright, which is what an absent delay
            // looks like rather than a malformed packet.
            if index > 0 { usleep(Self.interCommandDelay) }

            let packet = RazerPacket.setButtonAssignment(
                slot: entry.slot,
                action: entry.action,
                transactionId: mouse.info.transactionId
            )
            if let response = mouse.hidDevice.sendPacket(packet), response.isSuccess {
                accepted += 1
                sideButtonAssignments[entry.slot.rawValue] = entry.action
            } else {
                failures.append(String(format: "slot %02X", Int(entry.slot.rawValue)))
            }
        }
        lastSideButtonFailure = failures.isEmpty ? nil : failures.joined(separator: ", ")
        print("[DeviceManager] \(label) accepted \(accepted)/\(plan.count)")
        saveSideButtonAssignments(for: mouse.pid)
        return accepted
    }

    private static func sideButtonKey(for productID: UInt16) -> String {
        String(format: "SavedSideButtonAssignments.%04x", productID)
    }

    private func saveSideButtonAssignments(for productID: UInt16) {
        let encoded = Dictionary(uniqueKeysWithValues:
            sideButtonAssignments.map { (String($0.key), $0.value.descriptor) })
        UserDefaults.standard.set(encoded, forKey: Self.sideButtonKey(for: productID))
    }

    func loadSideButtonAssignments(for productID: UInt16) {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.sideButtonKey(for: productID)) as? [String: String]
        else { sideButtonAssignments = [:]; return }
        sideButtonAssignments = Dictionary(uniqueKeysWithValues: stored.compactMap {
            guard let slot = UInt8($0.key), let action = RazerButtonAction(descriptor: $0.value)
            else { return nil }
            return (slot, action)
        })
    }

    /// What the four buttons are set to at the factory.
    ///
    /// Both flanks ship identical -- rear is Mouse 4, forward is Mouse 5 --
    /// which is why an untouched mouse looks to this app as though it has two
    /// buttons rather than four. Restoring these puts the buttons back where
    /// macOS handles them natively: browser back and forward work with nothing
    /// running, at the cost of RazerControl no longer being able to see them.
    static let sideButtonDefaults: [(slot: RazerButtonSlot, button: UInt8)] = [
        (.leftBack, 0x04),
        (.leftFront, 0x05),
        (.rightBack, 0x04),
        (.rightFront, 0x05),
    ]

    /// Puts the four side buttons back to their factory mouse-button actions.
    ///
    /// The inverse of `configureSideButtons()`. Worth having as one action
    /// rather than leaving someone to reconstruct four assignments by hand,
    /// and worth having at all because the configured state is the one this
    /// app imposes -- undoing it should not be harder than doing it.
    @discardableResult
    func restoreSideButtonDefaults() -> Int {
        applySideButtons(Self.sideButtonDefaults.map { ($0.slot, .mouseButton($0.button)) },
                         label: "side-button restore")
    }

    /// Writes `sideButtonPlan` to the selected mouse.
    ///
    /// Returns how many of the four the device acknowledged. The assignment is
    /// pushed at runtime rather than stored in the mouse -- the same thing
    /// Synapse does -- so it is re-sent rather than assumed to persist.
    @discardableResult
    func configureSideButtons() -> Int {
        applySideButtons(Self.sideButtonPlan.map { ($0.slot, .keyboardKey($0.usage)) },
                         label: "side-button configuration")
    }

    /// Routes a captured event to the bindings of the device that produced it.
    ///
    /// Routing by usage alone would be wrong: a keypad's Left arrow and a mouse
    /// side button can report the same number, and whichever set of bindings
    /// happened to contain it would fire.
    private func handleCapturedInput(productID: UInt16, usage: UInt8, isPressed: Bool) {
        if Self.keypadProductIDs.contains(productID) {
            if isPressed { pressedKeyboardUsages.insert(usage) }
            else { pressedKeyboardUsages.remove(usage) }
            nativeRemapper.handle(source: usage, isPressed: isPressed)
            return
        }

        if Self.mouseProductIDs.contains(productID) {
            // Only the left flank reaches us. Those two are configured in the
            // mouse's onboard memory to emit modifier usages, so they arrive on
            // its keyboard interface. The right flank is still on factory
            // defaults and reports as mouse buttons on the pointer interface,
            // which is deliberately not seized -- taking it would put cursor
            // movement itself behind this daemon.
            // The artwork lights from this set regardless of device kind, so a
            // mouse press has to land in it too. Without this the mouse tab
            // draws hotspots that can never illuminate, which reads as the
            // feature being broken rather than absent.
            if isPressed { pressedKeyboardUsages.insert(usage) }
            else { pressedKeyboardUsages.remove(usage) }

            guard let button = Self.viperUsageToButton[usage] else {
                print(String(format: "[DeviceManager] unmapped mouse usage 0x%02X", Int(usage)))
                return
            }
            nativeRemapper.handleMouse(button: button, isPressed: isPressed)
            return
        }

        print(String(format: "[DeviceManager] unrouted pid=0x%04X usage=0x%02X",
                     Int(productID), Int(usage)))
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
        syncMouseMappings()
    }

    /// Button numbers belonging to the four side buttons, across both
    /// transports: two CoreGraphics mouse buttons and two synthetic ids.
    static let sideButtonMappingSources: [Int] = [3, 4, 1000, 1001]

    /// Drops this app's own bindings for the side buttons.
    ///
    /// Restoring the factory assignment puts the buttons back to mouse
    /// functions, but a binding stored against those button numbers still
    /// fires through the event tap -- so the buttons kept doing what this app
    /// had been told, which is not what "factory" means to anyone reading it.
    func clearSideButtonMappings() {
        for source in Self.sideButtonMappingSources {
            mouseMappings.removeValue(forKey: source)
        }
        saveMappings()
        syncMouseMappings()
    }

    func clearMouseMapping(button: Int) {
        mouseMappings.removeValue(forKey: button)
        saveMappings()
        syncMouseMappings()
    }

    func startMouseRemapping() {
        guard !mouseMappings.isEmpty else { return }
        syncMouseMappings()
    }

    func stopMouseRemapping() {
        syncMouseMappings()
    }

    /// Applies mouse bindings through the same native path the keypad uses.
    ///
    /// This previously wrote a rule into Karabiner-Elements' configuration and
    /// depended on it being installed to do anything at all. It was not, so
    /// every mouse binding had silently stopped working.
    private func syncMouseMappings() {
        nativeRemapper.updateMouseMappings(mouseMappings)
        isMouseRemappingActive = !mouseMappings.isEmpty

        // Split by how the press actually arrives. Button numbers below 1000
        // are CoreGraphics mouse buttons and reach us through the tap; 1000 and
        // above are synthetic ids for side buttons emitting keyboard usages,
        // which arrive through the daemon. A binding routed to the wrong one
        // is stored, displayed, and never fires.
        let pointerMappings = mouseMappings.filter { $0.key < 1000 }
        mouseMapper.stop()
        if !pointerMappings.isEmpty {
            mouseMapper.start(with: pointerMappings)
        }
        isRemappingActive = !keyMappings.isEmpty
        lastError = nil
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
