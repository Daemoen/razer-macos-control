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
        case .qwertz_iso:  return ""   // ISO doesn't have backslash in this position
        case .azerty_iso:  return ""
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
    @State private var selectedKey: KeyInfo? = nil
    @State private var hoveredKey: KeyInfo? = nil
    @State private var testInput = ""
    @State private var showMapperSheet = false
    @State private var selectedLayout: KeyboardLayout = .qwertz_iso
    @State private var dialMode = "Volume"
    @State private var macroInitError: String?

    private var macroKeysInitialized: Bool {
        deviceManager.selectedKeyboard?.macroKeysInitialized ?? false
    }

    private let dialModes = ["Volume", "Brightness", "Zoom", "Scroll H", "Scroll V", "Brush Size", "Opacity", "Custom"]
    private let ks: CGFloat = 32   // base key unit size
    private let sp: CGFloat = 2    // spacing

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                fullKeyboard
                bottomPanels
            }
        }
        .sheet(isPresented: $showMapperSheet) {
            if let key = selectedKey {
                KeyMapperSheet(key: key, isPresented: $showMapperSheet)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BlackWidow V4 Pro")
                    .font(RazerFont.title(18))
                    .foregroundColor(.razerTextPrimary)
                Text("Click any key to remap. M6-M8 are on the physical left edge.")
                    .font(RazerFont.body(12))
                    .foregroundColor(.razerTextSecondary)
            }
            Spacer()

            Picker("", selection: $selectedLayout) {
                ForEach(KeyboardLayout.allCases) { l in Text(l.label).tag(l) }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

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
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Full Keyboard (BlackWidow V4 Pro layout)

    private var fullKeyboard: some View {
        HStack(alignment: .top, spacing: 0) {
            // === LEFT SECTION: Dial + M1-M5 macro column ===
            VStack(spacing: 6) {
                commandDial
                    .padding(.bottom, 4)
                ForEach(1...5, id: \.self) { i in
                    kv(KeyInfo("M\(i)", UInt8(0x67 + i), macro: true))
                }
            }
            .padding(.trailing, 6)

            // === MAIN KEYBOARD AREA ===
            VStack(spacing: sp) {
                // Function row
                HStack(spacing: sp) {
                    k("Esc", 0x29)
                    gap(12)
                    k("F1", 0x3A); k("F2", 0x3B); k("F3", 0x3C); k("F4", 0x3D)
                    gap(6)
                    k("F5", 0x3E); k("F6", 0x3F); k("F7", 0x40); k("F8", 0x41)
                    gap(6)
                    k("F9", 0x42); k("F10", 0x43); k("F11", 0x44); k("F12", 0x45)
                    gap(6)
                    k("Prt", 0x46); k("Scr", 0x47); k("Pse", 0x48)
                }

                // Number row
                HStack(spacing: sp) {
                    ForEach(Array(selectedLayout.numberRowSymbols.enumerated()), id: \.offset) { i, lbl in
                        k(lbl, UInt8(i == 0 ? 0x35 : 0x1E + i - 1))
                    }
                    k("Back", 0x2A, w: selectedLayout.isISO ? 1.5 : 2.0)
                    gap(6)
                    k("Ins", 0x49); k("Hm", 0x4A); k("PU", 0x4B)
                    gap(6)
                    k("NL", 0x53); k("/", 0x54); k("*", 0x55); k("-", 0x56)
                }

                // Top alpha row (QWERTY/QWERTZ)
                HStack(spacing: sp) {
                    k("Tab", 0x2B, w: 1.5)
                    ForEach(Array(selectedLayout.topRow.enumerated()), id: \.offset) { i, lbl in
                        k(lbl, UInt8(0x14 + i))
                    }
                    if selectedLayout.isISO {
                        // ISO: no backslash here, Enter spans 2 rows (shown as tall key in home row)
                        // But we show a narrow placeholder for the row return area
                        gap(2)
                    } else {
                        k("\\", 0x31, w: 1.5)
                    }
                    gap(6)
                    k("Del", 0x4C); k("End", 0x4D); k("PD", 0x4E)
                    gap(6)
                    k("7", 0x5F); k("8", 0x60); k("9", 0x61); k("+", 0x57)
                }

                // Home row
                HStack(spacing: sp) {
                    k("Caps", 0x39, w: 1.75)
                    ForEach(Array(selectedLayout.homeRow.enumerated()), id: \.offset) { i, lbl in
                        k(lbl, UInt8(0x04 + i))
                    }
                    if selectedLayout.isISO {
                        k(selectedLayout.homeRowExtra, 0x32)
                    }
                    k("Enter", 0x28, w: selectedLayout.isISO ? 1.25 : 2.25)
                    gap(6)
                    // gap for nav cluster
                    gap(ks * 3 + sp * 2)
                    gap(6)
                    k("4", 0x5C); k("5", 0x5D); k("6", 0x5E)
                    // + key spans from above
                    gap(ks)
                }

                // Bottom alpha row
                HStack(spacing: sp) {
                    if selectedLayout.isISO {
                        k("Shift", 0xE1, w: 1.25)
                        k(selectedLayout.isoExtraKey, 0x64) // extra ISO key
                    } else {
                        k("Shift", 0xE1, w: 2.25)
                    }
                    ForEach(Array(selectedLayout.bottomRow.enumerated()), id: \.offset) { i, lbl in
                        k(lbl, UInt8(0x1D + i))
                    }
                    k("Shift", 0xE5, w: selectedLayout.isISO ? 1.75 : 2.75)
                    gap(6)
                    gap(ks); k("Up", 0x52); gap(ks)
                    gap(6)
                    k("1", 0x59); k("2", 0x5A); k("3", 0x5B); k("Ent", 0x58)
                }

                // Space row
                HStack(spacing: sp) {
                    k("Ctrl", 0xE0, w: 1.25)
                    k("Win", 0xE3, w: 1.25)
                    k("Alt", 0xE2, w: 1.25)
                    k("", 0x2C, w: 6.25)  // spacebar
                    k(selectedLayout.isISO ? "AltGr" : "Alt", 0xE6, w: 1.25)
                    k("Win", 0xE7, w: 1.0)
                    k("Fn", 0xFF, w: 1.0)
                    k("Ctrl", 0xE4, w: 1.25)
                    gap(6)
                    k("Left", 0x50); k("Dn", 0x51); k("Rt", 0x4F)
                    gap(6)
                    k("0", 0x62, w: 2.0); k(".", 0x63)
                    // Enter key from numpad continues
                    gap(ks)
                }
            }

            // === RIGHT SECTION: Roller + Media keys ===
            VStack(spacing: 6) {
                rollerWidget
                    .padding(.bottom, 2)
                mediaKeysColumn
            }
            .padding(.leading, 8)
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
            isActive: info.isMacro ? macroKeysInitialized : true,
            isMacro: info.isMacro,
            onTap: { selectedKey = info; showMapperSheet = true },
            onHover: { hoveredKey = $0 ? info : nil }
        )
    }

    private func gap(_ width: CGFloat) -> some View {
        Spacer().frame(width: width)
    }

    // MARK: - Bottom Panels

    private var bottomPanels: some View {
        HStack(spacing: 12) {
            // M6-M8 side edge buttons
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

// MARK: - Key Cap View

struct KeyCapView: View {
    let key: KeyInfo
    let size: CGFloat
    let isSelected: Bool
    let isHovered: Bool
    let isActive: Bool
    let isMacro: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    private var bg: Color {
        if !isActive && isMacro { return Color.razerBg.opacity(0.3) }
        if isSelected { return Color.razerGreen.opacity(0.25) }
        if isHovered { return Color.razerSurfaceHover }
        return Color.razerSurfaceLight
    }
    private var border: Color {
        if !isActive && isMacro { return Color.razerBorder.opacity(0.3) }
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
                    width: size * key.width + max(0, (key.width - 1) * 2) - 3,
                    height: size * key.height - 3
                )
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(bg)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: isSelected ? 1.5 : 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                )
                .razerGlow(color: .razerGreen, radius: 3, isActive: isSelected)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }
}

// MARK: - Key Mapper Sheet

struct KeyMapperSheet: View {
    let key: KeyInfo
    @Binding var isPresented: Bool
    @State private var selectedAction = 0
    @State private var capturedKeyName: String = ""
    @State private var capturedKeyCode: UInt16 = 0
    @State private var capturedModifiers: NSEvent.ModifierFlags = []
    @State private var isListening = false
    @State private var eventMonitor: Any? = nil

    let actions = ["Keystroke", "Shortcut", "Launch App", "Media", "Macro", "Disable"]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remap Key").font(RazerFont.title(16)).foregroundColor(.razerTextPrimary)
                    Text("Assign action to \(key.label.isEmpty ? "Space" : key.label)")
                        .font(RazerFont.body(12)).foregroundColor(.razerTextSecondary)
                }
                Spacer()
                Text(key.label.isEmpty ? "Space" : key.label)
                    .font(RazerFont.heading(13)).foregroundColor(.razerGreen)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.razerGreenSubtle)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.razerGreen.opacity(0.4), lineWidth: 1)))
                    .razerGlow(radius: 5)
            }.padding(.horizontal, 20).padding(.top, 20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(actions.indices, id: \.self) { i in
                    Button { selectedAction = i } label: {
                        VStack(spacing: 4) {
                            Image(systemName: ["keyboard","command","app.gift","play.circle","repeat","xmark.circle"][i])
                                .font(.system(size: 16))
                            Text(actions[i]).font(RazerFont.caption(10))
                        }
                        .foregroundColor(selectedAction == i ? .razerGreen : .razerTextSecondary)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .razerCard(isSelected: selectedAction == i, padding: 6)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20)

            // Key capture area
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Target key combination:").font(RazerFont.body(12)).foregroundColor(.razerTextSecondary)
                    Spacer()
                    Button(isListening ? "Stop" : "Record") {
                        if isListening { stopListening() } else { startListening() }
                    }
                    .font(RazerFont.caption(11))
                    .foregroundColor(.razerGreen)
                    .buttonStyle(.plain)
                }

                HStack {
                    if capturedKeyName.isEmpty {
                        if isListening {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.razerError)
                                    .frame(width: 8, height: 8)
                                Text("Press any key or shortcut...")
                                    .font(RazerFont.mono(13))
                                    .foregroundColor(.razerWarning)
                            }
                        } else {
                            Text("Click \"Record\" then press the target key")
                                .font(RazerFont.mono(12))
                                .foregroundColor(.razerTextTertiary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.razerSuccess)
                            Text(capturedKeyName)
                                .font(RazerFont.mono(14))
                                .foregroundColor(.razerGreen)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.razerBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isListening ? Color.razerWarning.opacity(0.6) : Color.razerGreen.opacity(0.3),
                                    lineWidth: isListening ? 2 : 1
                                )
                        )
                )
            }.padding(.horizontal, 20)

            Spacer()

            HStack {
                Button("Cancel") { stopListening(); isPresented = false }.buttonStyle(.razerSecondary)
                Spacer()
                Button("Clear") { capturedKeyName = ""; capturedKeyCode = 0 }.buttonStyle(.razerSecondary)
                Button("Apply") { stopListening(); isPresented = false }.buttonStyle(.razerPrimary)
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(width: 480, height: 400)
        .background(Color.razerSurface)
        .onDisappear { stopListening() }
    }

    // MARK: - Key Capture via NSEvent

    private func startListening() {
        isListening = true
        capturedKeyName = ""

        // Local monitor captures keys even when sheet is focused
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                let keyCode = event.keyCode
                capturedKeyCode = keyCode
                capturedModifiers = event.modifierFlags

                // Build display string
                var parts: [String] = []
                if event.modifierFlags.contains(.command) { parts.append("Cmd") }
                if event.modifierFlags.contains(.shift) { parts.append("Shift") }
                if event.modifierFlags.contains(.option) { parts.append("Opt") }
                if event.modifierFlags.contains(.control) { parts.append("Ctrl") }
                parts.append(KeyCodeMap.cgKeyName(keyCode))

                capturedKeyName = parts.joined(separator: " + ")
                stopListening()
                return nil // consume the event
            }
            return event
        }
    }

    private func stopListening() {
        isListening = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
