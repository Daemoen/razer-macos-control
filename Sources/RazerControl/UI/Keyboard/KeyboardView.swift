import SwiftUI

// MARK: - Keyboard Layout Definitions

enum KeyboardLayout: String, CaseIterable, Identifiable {
    case qwerty_ansi = "QWERTY (US ANSI)"
    case qwertz_iso = "QWERTZ (DE ISO)"
    case azerty_iso = "AZERTY (FR ISO)"

    var id: String { rawValue }
    var label: String { rawValue }
    var isISO: Bool { self != .qwerty_ansi }

    var numberRowSymbols: [String] {
        switch self {
        case .qwerty_ansi: return ["~", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
        case .qwertz_iso:  return ["^", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "ß", "´"]
        case .azerty_iso:  return ["²", "&", "é", "\"", "'", "(", "-", "è", "_", "ç", "à", ")", "="]
        }
    }
    var topRow: [String] {
        switch self {
        case .qwerty_ansi: return ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]"]
        case .qwertz_iso:  return ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "Ü", "+"]
        case .azerty_iso:  return ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P", "^", "$"]
        }
    }
    var homeRow: [String] {
        switch self {
        case .qwerty_ansi: return ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'"]
        case .qwertz_iso:  return ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö", "Ä"]
        case .azerty_iso:  return ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M", "ù"]
        }
    }
    var homeRowExtra: String { // ISO has an extra key before Enter
        switch self {
        case .qwerty_ansi: return ""
        case .qwertz_iso:  return "#"
        case .azerty_iso:  return "*"
        }
    }
    var bottomRow: [String] {
        switch self {
        case .qwerty_ansi: return ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"]
        case .qwertz_iso:  return ["Y", "X", "C", "V", "B", "N", "M", ",", ".", "-"]
        case .azerty_iso:  return ["W", "X", "C", "V", "B", "N", ",", ";", ":", "!"]
        }
    }
    var isoExtraKey: String { // key between short left shift and first alpha
        switch self {
        case .qwerty_ansi: return ""
        case .qwertz_iso:  return "<>"
        case .azerty_iso:  return "<>"
        }
    }
    var backslashKey: String {
        switch self {
        case .qwerty_ansi: return "\\"
        case .qwertz_iso:  return "#"
        case .azerty_iso:  return "*"
        }
    }
}

// MARK: - Key Info

struct KeyInfo: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let hidCode: UInt8
    let width: CGFloat
    let height: CGFloat
    let isMacro: Bool
    let isSpecial: Bool
    var mapping: String?

    init(_ label: String, _ hidCode: UInt8, w: CGFloat = 1.0, h: CGFloat = 1.0,
         macro: Bool = false, special: Bool = false, mapping: String? = nil) {
        self.label = label; self.hidCode = hidCode; self.width = w; self.height = h
        self.isMacro = macro; self.isSpecial = special; self.mapping = mapping
    }

    static func == (lhs: KeyInfo, rhs: KeyInfo) -> Bool { lhs.id == rhs.id }
}

// MARK: - Keyboard View

struct KeyboardView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    private let isLightingPreview: Bool
    private let lightingPreviewColor: Color
    @State private var selectedKey: KeyInfo? = nil
    @State private var hoveredKey: KeyInfo? = nil
    @State private var testInput = ""
    @State private var showMapperSheet = false
    @State private var selectedLayout: KeyboardLayout = .qwerty_ansi
    @State private var dialMode = "Volume"
    @State private var macroInitError: String?

    private var macroKeysInitialized: Bool {
        deviceManager.selectedKeyboard?.macroKeysInitialized ?? false
    }

    private let dialModes = ["Volume", "Brightness", "Zoom", "Scroll H", "Scroll V", "Brush Size", "Opacity", "Custom"]
    private let ks: CGFloat = 32   // base key unit size
    private let sp: CGFloat = 2    // spacing
    private let topRowHID: [UInt8] = [0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13, 0x2F, 0x30]
    private let homeRowHID: [UInt8] = [0x04, 0x16, 0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F, 0x33, 0x34]
    private let bottomRowHID: [UInt8] = [0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10, 0x36, 0x37, 0x38]

    init(isLightingPreview: Bool = false, lightingPreviewColor: Color = .white) {
        self.isLightingPreview = isLightingPreview
        self.lightingPreviewColor = lightingPreviewColor
    }

    private var isOrbweaver: Bool {
        deviceManager.selectedKeyboard?.pid == 0x0207
    }

    private var isBlackWidowV3: Bool {
        deviceManager.selectedKeyboard?.pid == 0x024E
    }

    var body: some View {
        Group {
            if isLightingPreview {
                lightingLayoutPreview
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        header
                        if isOrbweaver {
                            orbweaverKeypad
                        } else {
                            fullKeyboard
                            bottomPanels
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showMapperSheet) {
            if let key = selectedKey {
                KeyMapperSheet(key: key, isPresented: $showMapperSheet)
                    .environmentObject(deviceManager)
            }
        }
    }

    /// Uses the exact mapping-screen geometry in the compact lighting card.
    /// Keeping this here prevents the two device representations from drifting.
    private var lightingLayoutPreview: some View {
        GeometryReader { geometry in
            // The Orbweaver art canvas carries a wide empty margin around the
            // device. Sizing the preview to the canvas rather than to the
            // drawn content left the device floating small in the middle of the
            // card, so the preview is sized to the content box instead.
            let hasPhoto = (deviceManager.selectedKeyboard?.pid).map { DeviceArt.hasArt(for: $0) } ?? false
            let designSize = isOrbweaver
                ? (hasPhoto ? CGSize(width: 766, height: 1022) : CGSize(width: 512, height: 384))
                : CGSize(width: 920, height: 235)
            let scale = min(
                geometry.size.width / designSize.width,
                geometry.size.height / designSize.height
            )

            let renderedSize = CGSize(
                width: designSize.width * scale,
                height: designSize.height * scale
            )

            ZStack(alignment: .topLeading) {
                Group {
                    if isOrbweaver {
                        if hasPhoto {
                            orbweaverDeviceArt(rows: Self.orbweaverRows)
                                .frame(width: designSize.width, height: designSize.height)
                        } else {
                            orbweaverDeviceArt(rows: Self.orbweaverRows)
                                .frame(width: 680, height: 465, alignment: .topLeading)
                                .offset(x: -78, y: -38)
                                .frame(width: designSize.width, height: designSize.height,
                                       alignment: .topLeading)
                                .clipped()
                        }
                    } else {
                        fullKeyboard
                            .frame(width: designSize.width, height: designSize.height, alignment: .topLeading)
                    }
                }
                .colorMultiply(lightingPreviewColor)
                .allowsHitTesting(false)
                .scaleEffect(scale, anchor: .topLeading)
            }
            // Collapse the layout footprint after scaling, then center that
            // real rendered footprint rather than the original design canvas.
            .frame(width: renderedSize.width, height: renderedSize.height, alignment: .topLeading)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(deviceManager.selectedKeyboard?.name ?? "Keyboard")
                        .font(RazerFont.title(18))
                        .foregroundColor(.razerTextPrimary)
                    if deviceManager.isRemappingActive {
                        HStack(spacing: 4) {
                            Circle().fill(Color.razerSuccess).frame(width: 6, height: 6)
                                .razerGlow(color: .razerSuccess, radius: 3, isActive: true)
                            Text("\(deviceManager.keyMappings.count) remaps active")
                                .font(RazerFont.caption(10))
                                .foregroundColor(.razerSuccess)
                        }
                    }
                }
                Text("Click any key to remap it. Click Record, press the target key, then Apply.")
                    .font(RazerFont.body(12))
                    .foregroundColor(.razerTextSecondary)
            }
            Spacer()

            if !isOrbweaver {
                Picker("", selection: $selectedLayout) {
                    ForEach(KeyboardLayout.allCases) { l in Text(l.label).tag(l) }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            if !isOrbweaver {
                Button {
                    if let kb = deviceManager.selectedKeyboard {
                        let success = kb.initMacroKeys()
                        macroInitError = success ? nil : "Failed to init macro keys"
                    } else {
                        macroInitError = "No keyboard connected"
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(macroKeysInitialized ? Color.razerSuccess : Color.razerTextTertiary)
                            .frame(width: 7, height: 7)
                            .razerGlow(color: .razerSuccess, radius: 3, isActive: macroKeysInitialized)
                        Text(macroKeysInitialized ? "Macros Active" : "Init Macros")
                            .font(RazerFont.caption(11))
                    }
                }
                .buttonStyle(.razerPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Orbweaver Chroma

    /// Factory keyboard usages emitted by the Orbweaver. Karabiner scopes the
    /// resulting mappings to the Orbweaver's vendor/product ID.
    private var orbweaverKeypad: some View {
        let rows = Self.orbweaverRows

        let usesPhoto = (deviceManager.selectedKeyboard?.pid).map { DeviceArt.hasArt(for: $0) } ?? false

        return VStack(alignment: .leading, spacing: 14) {
            if usesPhoto {
                // A photograph cannot carry hit targets the way the drawn deck
                // did -- the device sits at an angle and its keys do not line up
                // with any grid we could overlay. So the picture identifies the
                // hardware and the list beside it does the work. That also fills
                // the empty half of a landscape card, which a portrait photo
                // leaves bare.
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        RazerSectionHeader("Orbweaver Chroma", subtitle: "Your device")
                        orbweaverDeviceArt(rows: rows)
                            .frame(width: 330, height: 440)
                    }
                    orbweaverKeyList(rows: rows)
                }
            } else {
                RazerSectionHeader("Orbweaver Chroma", subtitle: "Click a physical control to assign its action")
                orbweaverDeviceArt(rows: rows)
                    .frame(height: 465)
            }
            Text("Factory sources: `/1/2/3/4, Tab/Q/W/E/R, Caps/A/S/D/F, Shift/Z/X/C/V; thumb pad arrows, Alt and Space")
                .font(RazerFont.caption(10))
                .foregroundColor(.razerTextTertiary)
        }
        .razerCard()
        .padding(.horizontal, 20)
    }

    private var devicePlastic: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.12, green: 0.12, blue: 0.14), .black, Color(red: 0.08, green: 0.08, blue: 0.09)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var palmTexture: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.16, green: 0.16, blue: 0.17), Color(red: 0.06, green: 0.06, blue: 0.065)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Device art only -- no section header, no caption.
    ///
    /// The lighting preview embeds this. It used to embed `orbweaverKeypad`
    /// instead, which carried the heading and the factory-sources caption along
    /// with it, so the RGB page showed an unreadable thumbnail of the entire
    /// mapping screen rather than a picture of the device.
    /// Every assignable control, in physical order, with its current mapping.
    private func orbweaverKeyList(rows: [[KeyInfo]]) -> some View {
        let thumbControls = [
            KeyInfo("Thumb", 0xE2), KeyInfo("Space", 0x2C),
            KeyInfo("Up", 0x52), KeyInfo("Down", 0x51),
            KeyInfo("Left", 0x50), KeyInfo("Right", 0x4F),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            RazerSectionHeader("Controls", subtitle: "Click any control to assign its action")

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows.flatMap { $0 }) { key in
                        orbweaverKeyRow(key, caption: "Key")
                    }
                    Divider()
                        .background(Color.razerBorder)
                        .padding(.vertical, 6)
                    ForEach(thumbControls) { key in
                        orbweaverKeyRow(key, caption: "Thumb")
                    }
                }
            }
            .frame(maxHeight: 430)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .razerCard()
    }

    private func orbweaverKeyRow(_ key: KeyInfo, caption: String) -> some View {
        let mapped = deviceManager.keyMappings[key.hidCode] != nil
        return Button { selectedKey = key; showMapperSheet = true } label: {
            HStack(spacing: 10) {
                Text(key.label)
                    .font(RazerFont.body(12))
                    .foregroundColor(.razerTextPrimary)
                    .frame(width: 52, alignment: .leading)
                Text(caption)
                    .font(RazerFont.caption(9))
                    .foregroundColor(.razerTextTertiary)
                    .frame(width: 40, alignment: .leading)
                Text(orbweaverAssignment(for: key))
                    .font(RazerFont.mono(11))
                    .foregroundColor(mapped ? .razerGreen : .razerTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("Edit")
                    .font(RazerFont.caption(10))
                    .foregroundColor(.razerGreen)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func orbweaverDeviceArt(rows: [[KeyInfo]]) -> some View {
        if let pid = deviceManager.selectedKeyboard?.pid, DeviceArt.hasArt(for: pid) {
            // A photograph of the actual device beats any drawing of it.
            GeometryReader { geometry in
                DeviceArt.view(for: pid,
                               maxWidth: geometry.size.width,
                               maxHeight: geometry.size.height)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        } else {
            drawnOrbweaverArt(rows: rows)
        }
    }

    private func drawnOrbweaverArt(rows: [[KeyInfo]]) -> some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / 680)
            ZStack(alignment: .topLeading) {
                // Single palm rest. Two overlapping rounded shapes read as a
                // pair of blobs rather than one moulded surface.
                OrbweaverPalmRestShape()
                    .fill(palmTexture)
                    .overlay(OrbweaverPalmRestShape().stroke(Color.black.opacity(0.85), lineWidth: 1.6))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
                    .frame(width: 272, height: 116)
                    .position(x: 224, y: 344)

                // Thumb module. Positioned so its inboard edge meets the key
                // deck; on the real device these are one moulded body, and
                // floating them apart is what made the drawing read as two
                // unrelated objects.
                OrbweaverThumbWingShape()
                    .fill(devicePlastic)
                    .overlay(OrbweaverThumbWingShape().stroke(Color.razerBorder, lineWidth: 1.3))
                    .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
                    .frame(width: 178, height: 292)
                    .position(x: 498, y: 202)

                thumbKey(KeyInfo("Thumb", 0xE2), symbol: "\u{2325}")
                    .frame(width: 62, height: 38)
                    .rotationEffect(.degrees(-7))
                    .position(x: 486, y: 116)

                orbweaverDPad
                    .frame(width: 122, height: 122)
                    .position(x: 497, y: 206)

                thumbKey(KeyInfo("Space", 0x2C), symbol: "Space")
                    .frame(width: 76, height: 42)
                    .rotationEffect(.degrees(-11))
                    .position(x: 505, y: 306)

                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? Color.razerGreen : Color.black.opacity(0.8))
                            .frame(width: 6, height: 6)
                            .razerGlow(color: .razerGreen, radius: 3, isActive: index == 0)
                    }
                }
                .position(x: 536, y: 74)

                // Deck and keys tilt together as one body.
                //
                // Each key previously carried its own rotation3DEffect, so the
                // keys tilted independently of the deck they sit in and read as
                // stickers laid on top of it. Rotating the group keeps the keys
                // fixed in their keywell. A 2D rotation also renders correctly
                // offscreen, which a per-layer 3D transform does not.
                ZStack(alignment: .topLeading) {
                    OrbweaverKeyDeckShape()
                        .fill(devicePlastic)
                        .overlay(OrbweaverKeyDeckShape().stroke(Color.razerBorder, lineWidth: 1.3))
                        .shadow(color: .black.opacity(0.65), radius: 18, y: 10)
                        .frame(width: 344, height: 252)
                        .position(x: 245, y: 175)

                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        ForEach(Array(row.enumerated()), id: \.element.id) { columnIndex, key in
                            orbweaverDeviceKey(key)
                                .frame(width: 50, height: 44)
                                .position(
                                    x: 129 + CGFloat(columnIndex) * 58,
                                    // Columns are staggered on the real device
                                    // so each finger reaches its own row at the
                                    // same extension.
                                    y: 97 + CGFloat(rowIndex) * 52
                                       + Self.orbweaverColumnStagger[columnIndex]
                                )
                        }
                    }
                }
                .rotationEffect(.degrees(-4), anchor: .center)
            }
            .frame(width: 650, height: 465)
            .scaleEffect(scale, anchor: .topLeading)
        }
    }

    /// Vertical offset per key column, thumb-side to little-finger-side.
    private static let orbweaverColumnStagger: [CGFloat] = [9, 2, 0, 2, 7]

    /// Factory keyboard usages the Orbweaver emits, in physical row order.
    private static let orbweaverRows: [[KeyInfo]] = [
        [KeyInfo("01", 0x35), KeyInfo("02", 0x1E), KeyInfo("03", 0x1F), KeyInfo("04", 0x20), KeyInfo("05", 0x21)],
        [KeyInfo("06", 0x2B), KeyInfo("07", 0x14), KeyInfo("08", 0x1A), KeyInfo("09", 0x08), KeyInfo("10", 0x15)],
        [KeyInfo("11", 0x39), KeyInfo("12", 0x04), KeyInfo("13", 0x16), KeyInfo("14", 0x07), KeyInfo("15", 0x09)],
        [KeyInfo("16", 0xE1), KeyInfo("17", 0x1D), KeyInfo("18", 0x1B), KeyInfo("19", 0x06), KeyInfo("20", 0x19)],
    ]

    private func orbweaverDeviceKey(_ key: KeyInfo) -> some View {
        Button { selectedKey = key; showMapperSheet = true } label: {
            VStack(spacing: 2) {
                Text(key.label).font(.system(size: 10, weight: .bold, design: .rounded))
                Text(orbweaverAssignment(for: key))
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundColor(deviceManager.keyMappings[key.hidCode] == nil ? .razerTextTertiary : .razerGreen)
                    .lineLimit(1).minimumScaleFactor(0.55)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(deviceManager.pressedKeyboardUsages.contains(key.hidCode) ? Color.razerGreen.opacity(0.38) : (hoveredKey?.label == key.label ? Color.razerSurfaceHover : Color(red: 0.09, green: 0.09, blue: 0.11)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selectedKey?.label == key.label || deviceManager.pressedKeyboardUsages.contains(key.hidCode) ? Color.razerGreen : Color.razerBorder, lineWidth: 1))
                    .shadow(color: Color.razerGreen.opacity(deviceManager.pressedKeyboardUsages.contains(key.hidCode) ? 0.8 : (deviceManager.keyMappings[key.hidCode] == nil ? 0 : 0.35)), radius: 5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredKey = $0 ? key : nil }
    }

    private func thumbKey(_ key: KeyInfo, symbol: String) -> some View {
        let isPressed = deviceManager.pressedKeyboardUsages.contains(key.hidCode)
        return Button { selectedKey = key; showMapperSheet = true } label: {
            VStack(spacing: 1) {
                Text(symbol).font(.system(size: 9, weight: .bold))
                Text(orbweaverAssignment(for: key))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(deviceManager.keyMappings[key.hidCode] == nil ? .razerTextTertiary : .razerGreen)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPressed ? Color.razerGreen.opacity(0.38) : Color(red: 0.08, green: 0.08, blue: 0.095))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isPressed ? Color.razerGreen : Color.razerBorder, lineWidth: 1))
                    .shadow(color: Color.razerGreen.opacity(isPressed ? 0.8 : 0), radius: 5)
            )
        }
        .buttonStyle(.plain)
    }

    private var orbweaverDPad: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.9)).overlay(Circle().strokeBorder(Color.razerBorder, lineWidth: 2)).shadow(color: .black.opacity(0.7), radius: 6, y: 4)
            ForEach([
                ("▲", UInt8(0x52), CGFloat(0), CGFloat(-38)),
                ("◀", UInt8(0x50), CGFloat(-38), CGFloat(0)),
                ("▶", UInt8(0x4F), CGFloat(38), CGFloat(0)),
                ("▼", UInt8(0x51), CGFloat(0), CGFloat(38)),
            ], id: \.1) { symbol, code, x, y in
                let key = KeyInfo(symbol, code)
                let isPressed = deviceManager.pressedKeyboardUsages.contains(code)
                Button { selectedKey = key; showMapperSheet = true } label: {
                    Text(symbol)
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(isPressed || deviceManager.keyMappings[code] != nil ? .razerGreen : .razerTextSecondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.razerGreen.opacity(isPressed ? 0.30 : 0)))
                        .shadow(color: Color.razerGreen.opacity(isPressed ? 0.9 : 0), radius: 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: x, y: y)
            }
            Circle().fill(Color(red: 0.12, green: 0.12, blue: 0.13)).frame(width: 34, height: 34).overlay(Circle().strokeBorder(Color.black, lineWidth: 1))
        }
    }

    private func orbweaverAssignment(for key: KeyInfo) -> String {
        guard let action = deviceManager.keyMappings[key.hidCode] else { return "Default" }
        switch action {
        case .keystroke(let target):
            return KeyCodeMap.hidKeyName(target)
        case .shortcut(let modifiers, let target):
            var parts: [String] = []
            if modifiers & 0x08 != 0 { parts.append("Ctrl") }
            if modifiers & 0x04 != 0 { parts.append("Opt") }
            if modifiers & 0x02 != 0 { parts.append("Shift") }
            if modifiers & 0x01 != 0 { parts.append("Cmd") }
            parts.append(KeyCodeMap.hidKeyName(target))
            return parts.joined(separator: "+")
        case .spaceSwitch(let direction):
            if direction == "next" { return "Desktop →" }
            if direction == "previous" { return "← Desktop" }
            return "Desktop \(direction)"
        case .launchApp:
            return "Launch App"
        case .mediaControl(let control):
            return control.capitalized
        case .disabled:
            return "Disabled"
        case .macroSequence:
            return "Macro"
        }
    }

    // MARK: - Full Keyboard (BlackWidow V4 Pro layout)

    private var fullKeyboard: some View {
        HStack(alignment: .top, spacing: 0) {
            // === LEFT SECTION: Dial + M1-M5 macro column ===
            if !isBlackWidowV3 {
                VStack(spacing: 6) {
                    commandDial
                        .padding(.bottom, 4)
                    ForEach(1...5, id: \.self) { i in
                        kv(KeyInfo("M\(i)", UInt8(0x67 + i), macro: true))
                    }
                }
                .padding(.trailing, 6)
            }

            // === MAIN KEYBOARD AREA ===
            VStack(alignment: .leading, spacing: sp) {
                // Function row
                HStack(spacing: sp) {
                    k("Esc", 0x29)
                    blankKeys(1)
                    k("F1", 0x3A); k("F2", 0x3B); k("F3", 0x3C); k("F4", 0x3D)
                    gap(13.5)
                    k("F5", 0x3E); k("F6", 0x3F); k("F7", 0x40); k("F8", 0x41)
                    gap(13.5)
                    k("F9", 0x42); k("F10", 0x43); k("F11", 0x44); k("F12", 0x45)
                    gap(6)
                    k("Prt", 0x46); k("Scr", 0x47); k("Pse", 0x48)
                    if isBlackWidowV3 {
                        gap(8)
                        blackWidowV3MediaCluster
                    }
                }

                // Number row
                HStack(spacing: sp) {
                    ForEach(Array(selectedLayout.numberRowSymbols.enumerated()), id: \.offset) { i, lbl in
                        k(lbl, UInt8(i == 0 ? 0x35 : 0x1E + i - 1))
                    }
                    k("Back", 0x2A, w: 2.0)
                    gap(6)
                    k("Ins", 0x49); k("Hm", 0x4A); k("PU", 0x4B)
                    gap(6)
                    k("NL", 0x53); k("/", 0x54); k("*", 0x55); k("-", 0x56)
                }

                // Top alpha row (QWERTY/QWERTZ)
                HStack(spacing: sp) {
                    k("Tab", 0x2B, w: 1.5)
                    ForEach(Array(selectedLayout.topRow.enumerated()), id: \.offset) { i, lbl in
                        k(lbl, topRowHID[i])
                    }
                    k(selectedLayout.backslashKey, 0x31, w: 1.5)
                    gap(6)
                    k("Del", 0x4C); k("End", 0x4D); k("PD", 0x4E)
                    gap(6)
                    k("7", 0x5F); k("8", 0x60); k("9", 0x61); tallK("+", 0x57)
                }

                // Home row
                HStack(spacing: sp) {
                    k("Caps", 0x39, w: 1.75)
                    ForEach(Array(selectedLayout.homeRow.enumerated()), id: \.offset) { i, lbl in
                        k(lbl, homeRowHID[i])
                    }
                    k("Enter", 0x28, w: 2.25)
                    gap(6)
                    // gap for nav cluster
                    blankKeys(3)
                    gap(6)
                    k("4", 0x5C); k("5", 0x5D); k("6", 0x5E)
                    // + key spans from above
                    blankKeys(1)
                }

                // Bottom alpha row
                HStack(spacing: sp) {
                    k("Shift", 0xE1, w: 2.25)
                    ForEach(Array(selectedLayout.bottomRow.enumerated()), id: \.offset) { i, lbl in
                        k(lbl, bottomRowHID[i])
                    }
                    k("Shift", 0xE5, w: 2.75)
                    gap(6)
                    blankKeys(1); k("Up", 0x52); blankKeys(1)
                    gap(6)
                    k("1", 0x59); k("2", 0x5A); k("3", 0x5B); tallK("Ent", 0x58)
                }

                // Space row
                HStack(spacing: sp) {
                    k("Ctrl", 0xE0, w: 1.25)
                    k("Win", 0xE3, w: 1.25)
                    k("Alt", 0xE2, w: 1.25)
                    k("", 0x2C, w: 6.25)  // spacebar
                    k(selectedLayout.isISO ? "AltGr" : "Alt", 0xE6, w: 1.25)
                    k("Win", 0xE7, w: 1.25)
                    k("Fn", 0xFF, w: 1.25)
                    k("Ctrl", 0xE4, w: 1.25)
                    gap(6)
                    k("Left", 0x50); k("Dn", 0x51); k("Rt", 0x4F)
                    gap(6)
                    k("0", 0x62, w: 2.0); k(".", 0x63)
                    // Enter key from numpad continues
                    blankKeys(1)
                }
            }

            // BlackWidow V3 has its roller and media control above the numpad;
            // newer Pro models use the larger vertical control bank.
            if !isBlackWidowV3 {
                VStack(spacing: 6) {
                    rollerWidget
                        .padding(.bottom, 2)
                    mediaKeysColumn
                }
                .padding(.leading, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color.razerSurface, Color.razerSurface.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.razerBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        )
        .padding(.horizontal, 20)

        // M6-M8 side buttons (physical left edge)
        // Shown as a separate strip
    }

    // MARK: - Side buttons M6-M8

    private var sideButtonsStrip: some View {
        VStack(spacing: 4) {
            Text("Left Edge")
                .font(RazerFont.caption(9))
                .foregroundColor(.razerTextTertiary)
            ForEach(6...8, id: \.self) { i in
                kv(KeyInfo("M\(i)", UInt8(0x6D + i), macro: true))
            }
        }
    }

    // MARK: - Command Dial

    private var commandDial: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [.razerGreen.opacity(0.5), .razerGreen.opacity(0.1), .razerGreen.opacity(0.5)], center: .center),
                        lineWidth: 2.5
                    )
                    .frame(width: 48, height: 48)
                    .razerGlow(color: .razerGreen, radius: 5, isActive: true)

                Circle()
                    .fill(Color.razerSurfaceHover)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().strokeBorder(Color.razerBorder, lineWidth: 0.5))

                // Notch marks
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(Color.razerTextTertiary.opacity(0.3))
                        .frame(width: 1, height: 4)
                        .offset(y: -15)
                        .rotationEffect(.degrees(Double(i) * 30))
                }

                Image(systemName: "dial.medium")
                    .font(.system(size: 13))
                    .foregroundColor(.razerGreen)
            }
            .onTapGesture {
                if let idx = dialModes.firstIndex(of: dialMode) {
                    dialMode = dialModes[(idx + 1) % dialModes.count]
                }
            }

            Text(dialMode)
                .font(RazerFont.caption(8))
                .foregroundColor(.razerTextTertiary)
        }
    }

    // MARK: - Roller

    private var rollerWidget: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.razerSurfaceHover)
                    .frame(width: 20, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.razerBorder, lineWidth: 0.5))

                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.razerTextTertiary.opacity(0.3))
                            .frame(width: 10, height: 1)
                    }
                }

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.razerGreen)
                    .frame(width: 12, height: 2)
                    .offset(y: -6)
                    .razerGlow(color: .razerGreen, radius: 2, isActive: true)
            }

            Text("Vol")
                .font(RazerFont.caption(8))
                .foregroundColor(.razerTextTertiary)
        }
    }

    // MARK: - Media Keys

    private var mediaKeysColumn: some View {
        VStack(spacing: sp) {
            ForEach([
                ("backward.end.fill", "Prev", UInt8(0xB6)),
                ("play.fill", "Play", UInt8(0xB5)),
                ("forward.end.fill", "Next", UInt8(0xB7)),
                ("speaker.slash.fill", "Mute", UInt8(0xB8)),
            ], id: \.2) { icon, label, code in
                let info = KeyInfo(label, code, special: true)
                Button {
                    selectedKey = info; showMapperSheet = true
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundColor(hoveredKey == info ? .razerGreen : .razerTextSecondary)
                        .frame(width: 26, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(hoveredKey == info ? Color.razerSurfaceHover : Color.razerSurfaceLight)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.razerBorder, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveredKey = $0 ? info : nil }
            }
        }
    }

    private var blackWidowV3MediaCluster: some View {
        HStack(spacing: 0) {
            Button {} label: {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.razerTextSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.razerSurfaceHover)
                            .overlay(Circle().strokeBorder(Color.razerBorder, lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Play / pause and media control")

            Spacer(minLength: 0)

            ZStack {
                Capsule()
                    .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                    .frame(width: 3 * (ks - 3) + 2 * sp, height: 18)
                    .overlay(Capsule().strokeBorder(Color.razerBorder, lineWidth: 1))
                HStack(spacing: 3) {
                    ForEach(0..<15, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.razerTextTertiary.opacity(0.42))
                            .frame(width: 1, height: 11)
                    }
                }
            }
            .help("Multi-function volume roller")
        }
        // Four numpad columns wide: button centered on NL/7/4/1 and the
        // roller flush with the outer edge of -/+/Enter.
        .frame(width: 4 * (ks - 3) + 3 * sp, alignment: .leading)
    }

    // MARK: - Key Builders

    private func k(_ label: String, _ code: UInt8, w: CGFloat = 1.0) -> some View {
        let info = KeyInfo(label, code, w: w)
        return kv(info)
    }

    private func kv(_ info: KeyInfo) -> some View {
        KeyCapView(
            key: info, size: ks,
            isSelected: selectedKey?.label == info.label && selectedKey?.hidCode == info.hidCode,
            isHovered: hoveredKey?.label == info.label && hoveredKey?.hidCode == info.hidCode,
            isPressed: deviceManager.pressedKeyboardUsages.contains(info.hidCode),
            isActive: info.isMacro ? macroKeysInitialized : true,
            isMacro: info.isMacro,
            onTap: { selectedKey = info; showMapperSheet = true },
            onHover: { hoveredKey = $0 ? info : nil }
        )
    }

    /// Draws a numpad key across this row and the row below while preserving
    /// the fixed row height used to align the rest of the keyboard.
    private func tallK(_ label: String, _ code: UInt8) -> some View {
        let info = KeyInfo(label, code, h: 2.0)
        return Color.clear
            .frame(width: ks - 3, height: ks - 3)
            .overlay(alignment: .top) {
                kv(info)
            }
            .zIndex(2)
    }

    private func gap(_ width: CGFloat) -> some View {
        Spacer().frame(width: width)
    }

    /// Empty positions measured in the same rendered grid as actual keycaps.
    /// Using the nominal key size here shifts every cluster to the right.
    private func blankKeys(_ count: Int) -> some View {
        Color.clear.frame(width: CGFloat(count) * (ks - 3) + CGFloat(max(0, count - 1)) * sp)
    }

    // MARK: - Bottom Panels

    private var bottomPanels: some View {
        HStack(spacing: 12) {
            // M6-M8 side edge buttons
            if !isBlackWidowV3 {
                VStack(alignment: .leading, spacing: 6) {
                    RazerSectionHeader("Edge Keys", subtitle: "Left physical edge")
                    HStack(spacing: 4) {
                        ForEach(6...8, id: \.self) { i in
                            kv(KeyInfo("M\(i)", UInt8(0x6D + i), macro: true))
                        }
                    }
                }
                .frame(width: 140)
                .razerCard(padding: 12)
            }

            // Test input
            VStack(alignment: .leading, spacing: 6) {
                RazerSectionHeader("Test Input", subtitle: "Test your key mappings")
                ZStack(alignment: .topLeading) {
                    if testInput.isEmpty {
                        Text("Press any mapped key...")
                            .font(RazerFont.mono(12))
                            .foregroundColor(.razerTextTertiary)
                            .padding(10)
                    }
                    TextEditor(text: $testInput)
                        .font(RazerFont.mono(12))
                        .foregroundColor(.razerGreen)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                }
                .frame(height: 70)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.razerBg)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.razerBorder, lineWidth: 1))
                )
            }
            .razerCard(padding: 12)

            // Key info
            VStack(alignment: .leading, spacing: 6) {
                RazerSectionHeader("Key Details")
                if let key = selectedKey ?? hoveredKey {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Key", key.label.isEmpty ? "Space" : key.label)
                        infoRow("HID", String(format: "0x%02X", key.hidCode))
                        infoRow("Map", key.mapping ?? "Default")
                        infoRow("Type", key.isMacro ? "Macro" : key.isSpecial ? "Media" : "Standard")
                    }
                } else {
                    Text("Hover or click a key")
                        .font(RazerFont.caption(11))
                        .foregroundColor(.razerTextTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .frame(width: 160)
            .razerCard(padding: 12)

            // Dial config
            VStack(alignment: .leading, spacing: 6) {
                RazerSectionHeader("Command Dial")
                Picker("", selection: $dialMode) {
                    ForEach(dialModes, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).labelsHidden()

                HStack(spacing: 4) {
                    Image(systemName: "hand.tap").foregroundColor(.razerGreen).font(.system(size: 10))
                    Text("Press: \(dialMode == "Volume" ? "Mute" : "Reset")")
                        .font(RazerFont.caption(10)).foregroundColor(.razerTextSecondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").foregroundColor(.razerGreen).font(.system(size: 10))
                    Text("Rotate: \(dialMode) +/-")
                        .font(RazerFont.caption(10)).foregroundColor(.razerTextSecondary)
                }
            }
            .frame(width: 160)
            .razerCard(padding: 12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(RazerFont.caption(10)).foregroundColor(.razerTextTertiary).frame(width: 35, alignment: .leading)
            Text(value).font(RazerFont.mono(11)).foregroundColor(.razerTextPrimary)
        }
    }
}

// MARK: - Device silhouettes

/// Tapered, asymmetric key deck based on the Orbweaver's adjustable upper body.
private struct OrbweaverKeyDeckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 12, y: rect.minY + 5))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 5, y: rect.minY + 26),
            control: CGPoint(x: rect.midX, y: rect.minY - 5)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 42))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + 22, y: rect.maxY),
            control: CGPoint(x: rect.maxX - 28, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + 9, y: rect.maxY - 28))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 12, y: rect.minY + 5),
            control: CGPoint(x: rect.minX - 3, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

/// Broad lower pad separated from the key deck like the real swiveling palm rest.
private struct OrbweaverPalmRestShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 20, y: rect.minY + 4))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 8, y: rect.minY + 18),
            control: CGPoint(x: rect.midX, y: rect.minY - 8)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 34, y: rect.maxY - 4),
            control: CGPoint(x: rect.maxX + 2, y: rect.midY + 20)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 7, y: rect.maxY - 18),
            control: CGPoint(x: rect.midX - 12, y: rect.maxY + 5)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 20, y: rect.minY + 4),
            control: CGPoint(x: rect.minX - 3, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

private struct OrbweaverWristRestShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 34, y: rect.minY + 4))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 18, y: rect.minY + 16), control: CGPoint(x: rect.midX, y: rect.minY - 5))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 42, y: rect.maxY - 5), control: CGPoint(x: rect.maxX + 4, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 12, y: rect.maxY - 20), control: CGPoint(x: rect.midX, y: rect.maxY + 5))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 34, y: rect.minY + 4), control: CGPoint(x: rect.minX - 5, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct OrbweaverThumbWingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 14, y: rect.minY + 34))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 25, y: rect.minY + 4), control: CGPoint(x: rect.midX, y: rect.minY - 8))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 2, y: rect.midY), control: CGPoint(x: rect.maxX + 4, y: rect.minY + 76))
        path.addLine(to: CGPoint(x: rect.maxX - 35, y: rect.maxY - 4))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 7, y: rect.maxY - 46), control: CGPoint(x: rect.midX, y: rect.maxY + 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 84))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 14, y: rect.minY + 34), control: CGPoint(x: rect.minX - 4, y: rect.minY + 52))
        path.closeSubpath()
        return path
    }
}

// MARK: - Key Cap View

struct KeyCapView: View {
    let key: KeyInfo
    let size: CGFloat
    let isSelected: Bool
    let isHovered: Bool
    let isPressed: Bool
    let isActive: Bool
    let isMacro: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    private var bg: Color {
        if !isActive && isMacro { return Color.razerBg.opacity(0.3) }
        if isPressed { return Color.razerGreen.opacity(0.38) }
        if isSelected { return Color.razerGreen.opacity(0.25) }
        if isHovered { return Color.razerSurfaceHover }
        return Color.razerSurfaceLight
    }
    private var border: Color {
        if !isActive && isMacro { return Color.razerBorder.opacity(0.3) }
        if isPressed { return Color.razerGreen }
        if isSelected { return Color.razerGreen.opacity(0.8) }
        if isHovered { return Color.razerGreen.opacity(0.3) }
        return Color.razerBorder
    }
    private var fg: Color {
        if !isActive && isMacro { return Color.razerTextTertiary.opacity(0.4) }
        if isMacro && isActive { return Color.razerGreen }
        if isSelected { return Color.razerGreen }
        return Color.razerTextPrimary
    }

    var body: some View {
        Button(action: onTap) {
            Text(key.label)
                .font(RazerFont.caption(key.width > 1.5 ? 8 : 9))
                .foregroundColor(fg)
                .frame(
                    width: (size - 3) * key.width + max(0, (key.width - 1) * 2),
                    height: (size - 3) * key.height + max(0, (key.height - 1) * 2)
                )
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(bg)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: isSelected ? 1.5 : 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                )
                .razerGlow(color: .razerGreen, radius: 5, isActive: isSelected || isPressed)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }
}

// MARK: - Key Mapper Sheet

// MARK: - Key Mapper Sheet (Manual Entry)
//
// Uses dropdown pickers instead of key capture to avoid macOS
// intercepting system shortcuts (Ctrl+1 → Mission Control, etc.)

struct KeyMapperSheet: View {
    let key: KeyInfo
    @Binding var isPresented: Bool
    @EnvironmentObject var deviceManager: DeviceManager

    @State private var useCtrl = false
    @State private var useOpt = false
    @State private var useShift = false
    @State private var useCmd = false
    @State private var selectedKey = "1"
    @State private var wantDisable = false
    @State private var applyFeedback: String?

    // Common target keys grouped for the picker
    static let keyChoices: [(String, String)] = {
        var choices: [(String, String)] = []
        // Numbers
        for i in 0...9 { choices.append(("\(i)", "\(i)")) }
        // Letters
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { choices.append((String(c), String(c))) }
        // Function keys
        for i in 1...20 { choices.append(("F\(i)", "F\(i)")) }
        // Special
        choices.append(contentsOf: [
            ("Space", "Space"), ("Return", "Return"), ("Tab", "Tab"),
            ("Esc", "Esc"), ("Backspace", "Backspace"), ("Delete", "Delete"),
            ("Up", "Up"), ("Down", "Down"), ("Left", "Left"), ("Right", "Right"),
            ("Home", "Home"), ("End", "End"), ("Page Up", "Page Up"), ("Page Down", "Page Down"),
        ])
        // Standalone modifiers (useful for mouse/thumb buttons held as keys)
        choices.append(contentsOf: [
            ("Control", "Left Control"), ("Option", "Left Option"),
            ("Shift", "Left Shift"), ("Cmd", "Left Command"),
            ("Right Control", "Right Control"), ("Right Option", "Right Option"),
            ("Right Shift", "Right Shift"), ("Right Cmd", "Right Command"),
        ])
        // Punctuation and symbols
        choices.append(contentsOf: [
            ("`", "`  Backtick"), ("-", "-  Hyphen"), ("=", "=  Equal"),
            ("[", "[  Left bracket"), ("]", "]  Right bracket"),
            ("\\", "\\  Backslash"), (";", ";  Semicolon"), ("'", "'  Apostrophe"),
            (",", ",  Comma"), (".", ".  Period"), ("/", "/  Slash"),
        ])
        return choices
    }()

    /// Map display name → CGKeyCode
    static let nameToCGKey: [String: UInt16] = {
        var map: [String: UInt16] = [:]
        // Build from KeyCodeMap
        for (hid, cg) in KeyCodeMap.hidToCG {
            let name = KeyCodeMap.cgKeyName(cg)
            map[name] = cg
        }
        // Add number keys by digit name
        let digitCG: [String: UInt16] = [
            "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
            "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        ]
        for (name, cg) in digitCG { map[name] = cg }
        return map
    }()

    /// Map picker names directly to HID usages. Going through CGKeyCode is
    /// ambiguous on macOS (for example Print Screen and F13 share 0x69).
    static let nameToHIDKey: [String: UInt8] = {
        var map: [String: UInt8] = [:]
        for (hid, cg) in KeyCodeMap.hidToCG {
            map[KeyCodeMap.cgKeyName(cg)] = hid
        }
        for i in 1...12 { map["F\(i)"] = UInt8(0x39 + i) }
        for i in 13...24 { map["F\(i)"] = UInt8(0x68 + i - 13) }
        return map
    }()

    var previewText: String {
        if wantDisable { return "Disabled" }
        var parts: [String] = []
        if useCtrl { parts.append("Ctrl") }
        if useOpt { parts.append("Opt") }
        if useShift { parts.append("Shift") }
        if useCmd { parts.append("Cmd") }
        parts.append(selectedKey)
        return parts.joined(separator: " + ")
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remap Key").font(RazerFont.title(16)).foregroundColor(.razerTextPrimary)
                    Text("When \(key.label.isEmpty ? "Space" : key.label) is pressed, send:")
                        .font(RazerFont.body(12)).foregroundColor(.razerTextSecondary)
                }
                Spacer()
                Text(key.label.isEmpty ? "Space" : key.label)
                    .font(RazerFont.heading(13)).foregroundColor(.razerGreen)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.razerGreenSubtle)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.razerGreen.opacity(0.4), lineWidth: 1)))
            }.padding(.horizontal, 20).padding(.top, 20)

            // Modifier checkboxes
            VStack(alignment: .leading, spacing: 10) {
                RazerSectionHeader("Modifiers")
                HStack(spacing: 16) {
                    Toggle("Ctrl", isOn: $useCtrl).toggleStyle(.checkbox)
                    Toggle("Opt", isOn: $useOpt).toggleStyle(.checkbox)
                    Toggle("Shift", isOn: $useShift).toggleStyle(.checkbox)
                    Toggle("Cmd", isOn: $useCmd).toggleStyle(.checkbox)
                }
                .font(RazerFont.body(13))
                .foregroundColor(.razerTextPrimary)
                .disabled(wantDisable)
            }
            .padding(.horizontal, 20)

            // Key picker
            VStack(alignment: .leading, spacing: 8) {
                RazerSectionHeader("Key")
                Picker("", selection: $selectedKey) {
                    ForEach(Self.keyChoices, id: \.0) { name, label in
                        Text(label).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(wantDisable)
            }
            .padding(.horizontal, 20)

            // Preview
            HStack {
                Image(systemName: wantDisable ? "xmark.circle.fill" : "arrow.right.circle.fill")
                    .foregroundColor(wantDisable ? .razerError : .razerGreen)
                Text(previewText)
                    .font(RazerFont.mono(16))
                    .foregroundColor(wantDisable ? .razerError : .razerGreen)
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.razerBg)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.razerGreen.opacity(0.3), lineWidth: 1))
            )
            .padding(.horizontal, 20)

            // Disable toggle
            HStack {
                Toggle("Disable this key", isOn: $wantDisable)
                    .font(RazerFont.body(12))
                    .foregroundColor(.razerTextSecondary)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            .padding(.horizontal, 20)

            Spacer()

            if let feedback = applyFeedback {
                Text(feedback)
                    .font(RazerFont.caption(11))
                    .foregroundColor(.razerSuccess)
                    .padding(.horizontal, 20)
            }

            // Buttons
            HStack {
                Button("Cancel") { isPresented = false }.buttonStyle(.razerSecondary)
                Spacer()
                Button("Clear") {
                    deviceManager.clearKeyMapping(sourceHID: key.hidCode)
                    // Reset UI to defaults
                    useCtrl = false; useOpt = false; useShift = false; useCmd = false
                    selectedKey = "1"; wantDisable = false
                    applyFeedback = "Mapping cleared — key restored to default"
                }.buttonStyle(.razerSecondary)

                Button("Apply") { applyMapping() }
                    .buttonStyle(.razerPrimary)
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(width: 440, height: 440)
        .background(Color.razerSurface)
        .onAppear { loadCurrentMapping() }
    }

    /// Load existing mapping for this key (so UI shows current state)
    private func loadCurrentMapping() {
        guard let action = deviceManager.keyMappings[key.hidCode] else { return }

        switch action {
        case .disabled:
            wantDisable = true
        case .keystroke(let hidKey):
            if let cgKey = KeyCodeMap.hidToCG[hidKey] {
                selectedKey = KeyCodeMap.cgKeyName(cgKey)
            }
        case .shortcut(let mods, let hidKey):
            if let cgKey = KeyCodeMap.hidToCG[hidKey] {
                selectedKey = KeyCodeMap.cgKeyName(cgKey)
            }
            useCmd = (mods & 0x01) != 0
            useShift = (mods & 0x02) != 0
            useOpt = (mods & 0x04) != 0
            useCtrl = (mods & 0x08) != 0
        default:
            break
        }
    }

    private func applyMapping() {
        if wantDisable {
            deviceManager.setKeyMapping(sourceHID: key.hidCode, action: .disabled)
            applyFeedback = "Disabled!"
        } else {
            guard let hidCode = Self.nameToHIDKey[selectedKey] else {
                applyFeedback = "Unknown key: \(selectedKey)"
                return
            }

            var modByte: UInt8 = 0
            if useCmd { modByte |= 0x01 }
            if useShift { modByte |= 0x02 }
            if useOpt { modByte |= 0x04 }
            if useCtrl { modByte |= 0x08 }

            let action: KeyAction = modByte > 0
                ? .shortcut(modifiers: modByte, key: hidCode)
                : .keystroke(hidCode)

            deviceManager.setKeyMapping(sourceHID: key.hidCode, action: action)
            applyFeedback = "Mapped! \(key.label) → \(previewText)"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isPresented = false
        }
    }
}
