import SwiftUI

// MARK: - Mouse View

struct MouseView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selectedButton: MouseButton? = nil
    @State private var hoveredButton: MouseButton? = nil
    @State private var dpiStage: Double = 1600
    @State private var showMapperSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pro Click V2 Vertical Edition")
                            .font(RazerFont.title(18))
                            .foregroundColor(.razerTextPrimary)
                        Text("Vertical ergonomic mouse (71.7\u{00B0}). Click buttons to remap.")
                            .font(RazerFont.body(12))
                            .foregroundColor(.razerTextSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                HStack(alignment: .top, spacing: 20) {
                    // Left: 3D-ish vertical mouse visualization
                    verticalMouseVisualization

                    // Right: Mappings + DPI
                    VStack(spacing: 14) {
                        buttonMappingsPanel
                        dpiPanel
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showMapperSheet) {
            if let button = selectedButton {
                MouseMapperSheet(button: button, isPresented: $showMapperSheet)
                    .environmentObject(deviceManager)
            }
        }
    }

    // MARK: - Vertical Mouse Visualization

    private var verticalMouseVisualization: some View {
        VStack(spacing: 12) {
            // Main view: side profile of vertical mouse
            ZStack {
                // Mouse body - vertical wedge shape
                VerticalMouseShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.15, blue: 0.18),
                                Color(red: 0.10, green: 0.10, blue: 0.13),
                                Color(red: 0.08, green: 0.08, blue: 0.10),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 200, height: 260)
                    .overlay(
                        VerticalMouseShape()
                            .strokeBorder(Color.razerBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

                // === Button overlays ===

                // DPI button - top ridge
                buttonHotspot(.dpiButton, x: 0, y: -105, w: 28, h: 16)

                // Left click - upper left of angled face
                buttonHotspot(.leftClick, x: -35, y: -55, w: 55, h: 50)

                // Right click - upper right of angled face
                buttonHotspot(.rightClick, x: 35, y: -55, w: 55, h: 50)

                // Scroll wheel between clicks
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.razerSurfaceHover)
                        .frame(width: 12, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.razerBorder, lineWidth: 0.5)
                        )
                    // Scroll lines
                    VStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 0.5)
                                .fill(Color.razerTextTertiary.opacity(0.3))
                                .frame(width: 6, height: 1)
                        }
                    }
                }
                .offset(y: -55)

                // Side button 5 (Forward) - upper thumb area
                buttonHotspot(.sideForward, x: -82, y: -15, w: 24, h: 28)

                // Side button 4 (Back) - lower thumb area
                buttonHotspot(.sideBack, x: -82, y: 25, w: 24, h: 28)

                // Thumb grip texture indicator
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<2, id: \.self) { _ in
                                Circle()
                                    .fill(Color.razerTextTertiary.opacity(0.15))
                                    .frame(width: 3, height: 3)
                            }
                        }
                    }
                }
                .offset(x: -80, y: 65)

                // RGB underglow at base
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.razerGreen.opacity(0.4))
                    .frame(width: 140, height: 4)
                    .offset(y: 118)
                    .razerGlow(color: .razerGreen, radius: 6, isActive: true)

                // "71.7°" angle label
                Text("71.7\u{00B0}")
                    .font(RazerFont.mono(9))
                    .foregroundColor(.razerTextTertiary)
                    .offset(x: 75, y: 30)

                // Angle line indicator
                Path { path in
                    path.move(to: CGPoint(x: 160, y: 170))
                    path.addLine(to: CGPoint(x: 175, y: 60))
                }
                .stroke(Color.razerTextTertiary.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            }
            .frame(width: 220, height: 280)

            // Button legend
            HStack(spacing: 16) {
                ForEach(MouseButton.allCases) { btn in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(selectedButton == btn ? Color.razerGreen : Color.razerTextTertiary)
                            .frame(width: 6, height: 6)
                        Text(btn.shortLabel)
                            .font(RazerFont.caption(9))
                            .foregroundColor(selectedButton == btn ? .razerGreen : .razerTextTertiary)
                    }
                }
            }
        }
        .razerCard(padding: 16)
    }

    private func buttonHotspot(_ button: MouseButton, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let isSel = selectedButton == button
        let isHov = hoveredButton == button

        return Button {
            selectedButton = button
            showMapperSheet = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSel ? Color.razerGreen.opacity(0.2) : isHov ? Color.razerSurfaceHover.opacity(0.5) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isSel ? Color.razerGreen.opacity(0.7) : isHov ? Color.razerGreen.opacity(0.3) : Color.razerBorder.opacity(0.3),
                                lineWidth: isSel ? 1.5 : 1
                            )
                    )

                Text(button.shortLabel)
                    .font(RazerFont.caption(8))
                    .foregroundColor(isSel ? .razerGreen : isHov ? .razerTextPrimary : .razerTextSecondary)
            }
            .frame(width: w, height: h)
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? button : nil }
        .offset(x: x, y: y)
    }

    // MARK: - Button Mappings

    private var buttonMappingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            RazerSectionHeader("Button Mappings", subtitle: "Current assignments")

            ForEach(MouseButton.allCases) { button in
                HStack {
                    Text(button.label)
                        .font(RazerFont.body(12))
                        .foregroundColor(.razerTextPrimary)
                        .frame(width: 110, alignment: .leading)

                    Text(button.defaultAction)
                        .font(RazerFont.mono(11))
                        .foregroundColor(.razerTextSecondary)

                    Spacer()

                    Button("Edit") {
                        selectedButton = button
                        showMapperSheet = true
                    }
                    .font(RazerFont.caption(11))
                    .foregroundColor(.razerGreen)
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selectedButton == button ? Color.razerGreenSubtle : Color.clear)
                )
            }
        }
        .razerCard()
    }

    // MARK: - DPI Panel

    private var dpiPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            RazerSectionHeader("DPI Settings", subtitle: "Focus Pro 35K sensor")

            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("\(Int(dpiStage))")
                        .font(RazerFont.title(26))
                        .foregroundColor(.razerGreen)
                        .razerGlow(radius: 3)
                    Text("DPI")
                        .font(RazerFont.caption(9))
                        .foregroundColor(.razerTextTertiary)
                }
                .frame(width: 70)

                VStack(spacing: 6) {
                    Slider(value: $dpiStage, in: 100...35000, step: 50)
                        .tint(.razerGreen)
                    HStack {
                        Text("100").font(RazerFont.caption(9)).foregroundColor(.razerTextTertiary)
                        Spacer()
                        Text("35000").font(RazerFont.caption(9)).foregroundColor(.razerTextTertiary)
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach([400, 800, 1600, 3200, 6400], id: \.self) { dpi in
                    Button("\(dpi)") {
                        withAnimation { dpiStage = Double(dpi) }
                    }
                    .font(RazerFont.caption(10))
                    .foregroundColor(Int(dpiStage) == dpi ? .razerGreen : .razerTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Int(dpiStage) == dpi ? Color.razerGreenSubtle : Color.razerSurfaceLight)
                    )
                    .buttonStyle(.plain)
                }
            }
        }
        .razerCard()
    }
}

// MARK: - Mouse Button Model

enum MouseButton: String, CaseIterable, Identifiable {
    case leftClick, rightClick, sideForward, sideBack, dpiButton

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .sideForward: return "Btn 5 (Fwd)"
        case .sideBack: return "Btn 4 (Back)"
        case .dpiButton: return "DPI / AI"
        }
    }

    var shortLabel: String {
        switch self {
        case .leftClick: return "L"
        case .rightClick: return "R"
        case .sideForward: return "Fwd"
        case .sideBack: return "Back"
        case .dpiButton: return "DPI"
        }
    }

    var defaultAction: String {
        switch self {
        case .leftClick: return "Click"
        case .rightClick: return "Right Click"
        case .sideForward: return "Forward"
        case .sideBack: return "Back"
        case .dpiButton: return "DPI Cycle / AI"
        }
    }
}

// MARK: - Vertical Mouse Shape (side profile, 71.7° angle)

struct VerticalMouseShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width - insetAmount * 2
        let h = rect.height - insetAmount * 2
        let x = rect.minX + insetAmount
        let y = rect.minY + insetAmount

        // Vertical wedge shape - tall, angled, like a handshake grip
        // The left side (thumb side) is more vertical, right side leans out

        // Start at top-center (DPI button area)
        path.move(to: CGPoint(x: x + w * 0.4, y: y + h * 0.02))

        // Top ridge curves right
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.65, y: y + h * 0.08),
            control: CGPoint(x: x + w * 0.55, y: y)
        )

        // Right side slopes down (the angled face where buttons are)
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.85, y: y + h * 0.45),
            control: CGPoint(x: x + w * 0.78, y: y + h * 0.2)
        )

        // Right lower curve (palm rest area)
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.75, y: y + h * 0.85),
            control: CGPoint(x: x + w * 0.90, y: y + h * 0.65)
        )

        // Bottom curve
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.25, y: y + h * 0.88),
            control: CGPoint(x: x + w * 0.50, y: y + h * 0.98)
        )

        // Left side (thumb side) - more vertical
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.15, y: y + h * 0.45),
            control: CGPoint(x: x + w * 0.10, y: y + h * 0.70)
        )

        // Left upper (where thumb buttons are)
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.25, y: y + h * 0.12),
            control: CGPoint(x: x + w * 0.12, y: y + h * 0.25)
        )

        // Close back to top
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.4, y: y + h * 0.02),
            control: CGPoint(x: x + w * 0.30, y: y + h * 0.02)
        )

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - Mouse Mapper Sheet

enum MouseActionMode: String, CaseIterable {
    case shortcut = "Shortcut"
    case spaceSwitch = "Switch Desktop"
    case disable = "Disable"
}

struct MouseMapperSheet: View {
    let button: MouseButton
    @Binding var isPresented: Bool
    @EnvironmentObject var deviceManager: DeviceManager

    @State private var actionMode: MouseActionMode = .spaceSwitch
    @State private var useCtrl = false
    @State private var useOpt = false
    @State private var useShift = false
    @State private var useCmd = false
    @State private var selectedKey = "1"
    @State private var spaceDirection = "next"
    @State private var applyFeedback: String?

    var previewText: String {
        switch actionMode {
        case .disable: return "Disabled"
        case .spaceSwitch:
            switch spaceDirection {
            case "next": return "Next Desktop →"
            case "previous": return "← Previous Desktop"
            default: return "Desktop \(spaceDirection)"
            }
        case .shortcut:
            var parts: [String] = []
            if useCtrl { parts.append("Ctrl") }
            if useOpt { parts.append("Opt") }
            if useShift { parts.append("Shift") }
            if useCmd { parts.append("Cmd") }
            parts.append(selectedKey)
            return parts.joined(separator: " + ")
        }
    }

    /// Map mouse button to CGEvent button number (for MouseMapper)
    var cgButtonNumber: Int {
        switch button {
        case .leftClick: return 0
        case .rightClick: return 1
        case .sideForward: return 4   // Button 5 = Forward
        case .sideBack: return 3      // Button 4 = Back
        case .dpiButton: return 2     // Middle / DPI
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remap \(button.label)")
                        .font(RazerFont.title(16)).foregroundColor(.razerTextPrimary)
                    Text("Current: \(button.defaultAction)")
                        .font(RazerFont.body(12)).foregroundColor(.razerTextSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 20)

            // Action mode selector
            Picker("Action:", selection: $actionMode) {
                ForEach(MouseActionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            // Mode-specific options
            if actionMode == .spaceSwitch {
                VStack(alignment: .leading, spacing: 8) {
                    RazerSectionHeader("Desktop / Space", subtitle: "Uses private macOS API (same as yabai)")
                    Picker("Direction:", selection: $spaceDirection) {
                        Text("Next Desktop →").tag("next")
                        Text("← Previous Desktop").tag("previous")
                        ForEach(1...9, id: \.self) { i in
                            Text("Go to Desktop \(i)").tag("\(i)")
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 20)
            }

            if actionMode == .shortcut {
                VStack(alignment: .leading, spacing: 8) {
                    RazerSectionHeader("Shortcut")
                    HStack(spacing: 16) {
                        Toggle("Ctrl", isOn: $useCtrl).toggleStyle(.checkbox)
                        Toggle("Opt", isOn: $useOpt).toggleStyle(.checkbox)
                        Toggle("Shift", isOn: $useShift).toggleStyle(.checkbox)
                        Toggle("Cmd", isOn: $useCmd).toggleStyle(.checkbox)
                    }
                    .font(RazerFont.body(13))
                    .foregroundColor(.razerTextPrimary)

                    Picker("Key:", selection: $selectedKey) {
                        ForEach(KeyMapperSheet.keyChoices, id: \.0) { name, label in
                            Text(label).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 20)
            }

            // Preview
            HStack {
                Image(systemName: actionMode == .disable ? "xmark.circle.fill" :
                        actionMode == .spaceSwitch ? "desktopcomputer" : "arrow.right.circle.fill")
                    .foregroundColor(actionMode == .disable ? .razerError : .razerGreen)
                Text("\(button.shortLabel) → \(previewText)")
                    .font(RazerFont.mono(14))
                    .foregroundColor(actionMode == .disable ? .razerError : .razerGreen)
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.razerBg)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.razerGreen.opacity(0.3), lineWidth: 1)))
            .padding(.horizontal, 20)

            Spacer()

            if let feedback = applyFeedback {
                Text(feedback).font(RazerFont.caption(11)).foregroundColor(.razerSuccess)
                    .padding(.horizontal, 20)
            }

            HStack {
                Button("Cancel") { isPresented = false }.buttonStyle(.razerSecondary)
                Spacer()
                Button("Clear") {
                    deviceManager.mouseMapper.updateMappings([:])
                    applyFeedback = "Cleared"
                }.buttonStyle(.razerSecondary)
                Button("Apply") { applyMapping() }.buttonStyle(.razerPrimary)
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(width: 420, height: 440)
        .background(Color.razerSurface)
        .onAppear { loadCurrentMapping() }
    }

    private func loadCurrentMapping() {
        guard let action = deviceManager.mouseMappings[cgButtonNumber] else { return }
        switch action {
        case .disabled:
            actionMode = .disable
        case .spaceSwitch(let dir):
            actionMode = .spaceSwitch
            spaceDirection = dir
        case .keystroke(let hidKey):
            actionMode = .shortcut
            if let cgKey = KeyCodeMap.hidToCG[hidKey] {
                selectedKey = KeyCodeMap.cgKeyName(cgKey)
            }
        case .shortcut(let mods, let hidKey):
            actionMode = .shortcut
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
        let action: KeyAction

        switch actionMode {
        case .disable:
            action = .disabled
        case .spaceSwitch:
            action = .spaceSwitch(spaceDirection)
        case .shortcut:
            guard let cgKey = KeyMapperSheet.nameToCGKey[selectedKey] else {
                applyFeedback = "Unknown key"
                return
            }
            let hidCode = KeyCodeMap.hidToCG.first(where: { $0.value == cgKey })?.key ?? 0
            var modByte: UInt8 = 0
            if useCmd { modByte |= 0x01 }
            if useShift { modByte |= 0x02 }
            if useOpt { modByte |= 0x04 }
            if useCtrl { modByte |= 0x08 }
            action = modByte > 0 ? .shortcut(modifiers: modByte, key: hidCode) : .keystroke(hidCode)
        }

        deviceManager.setMouseMapping(button: cgButtonNumber, action: action)
        applyFeedback = "Mapped! \(button.shortLabel) → \(previewText)"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isPresented = false
        }
    }
}
