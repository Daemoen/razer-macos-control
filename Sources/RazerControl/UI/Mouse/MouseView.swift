import SwiftUI

// MARK: - Mouse View

struct MouseView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selectedButton: MouseButton? = nil
    @State private var hoveredButton: MouseButton? = nil
    @State private var dpiStage: Double = 1600
    @State private var showMapperSheet = false
    @State private var batteryPercent: Int? = nil
    @State private var isCharging: Bool? = nil
    /// Last handedness we *set*. The device has no readback command that we
    /// have observed, so this is what the app last asked for, not what the
    /// mouse reports -- it can be wrong if the mode was changed elsewhere.
    @State private var appliedHandedness: RazerHandedness? = nil
    @State private var sideButtonStatus: String? = nil

    private var isViperUltimate: Bool {
        deviceManager.selectedMouse?.pid == 0x007B
    }

    private var visibleButtons: [MouseButton] {
        isViperUltimate
            ? [.leftClick, .rightClick, .wheelClick, .sideLeftForward, .sideLeftBack,
               .sideRightForward, .sideRightBack]
            : [.leftClick, .rightClick, .wheelClick, .sideLeftForward, .sideLeftBack]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deviceManager.selectedMouse?.name ?? "Mouse")
                            .font(RazerFont.title(18))
                            .foregroundColor(.razerTextPrimary)
                        Text("Choose a button below to assign a keystroke, shortcut, Desktop action, or disable it.")
                            .font(RazerFont.body(12))
                            .foregroundColor(.razerTextSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if isViperUltimate {
                    HStack(alignment: .top, spacing: 20) {
                        viperMouseVisualization
                        VStack(spacing: 14) {
                            buttonMappingsPanel
                            devicePanel
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        verticalMouseVisualization
                        VStack(spacing: 14) {
                            buttonMappingsPanel
                            dpiPanel
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showMapperSheet) {
            if let button = selectedButton {
                MouseMapperSheet(button: button, isPresented: $showMapperSheet)
                    .environmentObject(deviceManager)
            }
        }
    }

    // MARK: - Device Panel

    /// Battery, charge state and handedness for the selected mouse.
    ///
    /// Handedness is gated on the Viper because it is the only ambidextrous
    /// device in the database. There is no feature flag for ambidexterity yet,
    /// and adding one means touching every device entry to answer a question
    /// only one of them asks -- worth doing when a second such device appears,
    /// not before.
    @ViewBuilder
    private var devicePanel: some View {
        if let mouse = deviceManager.selectedMouse {
            VStack(alignment: .leading, spacing: 12) {
                RazerSectionHeader("Device", subtitle: mouse.name)

                if mouse.info.features.contains(.wireless) {
                    HStack {
                        Text("Battery")
                            .font(RazerFont.body(12))
                            .foregroundColor(.razerTextSecondary)
                        Spacer()
                        Text(batteryLabel)
                            .font(RazerFont.body(12))
                            .foregroundColor(.razerTextPrimary)
                    }
                }

                if isViperUltimate {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Handedness")
                            .font(RazerFont.body(12))
                            .foregroundColor(.razerTextSecondary)

                        HStack(spacing: 6) {
                            handednessButton(.rightHanded, "Right")
                            handednessButton(.leftHanded, "Left")
                        }

                        Text("Side buttons are numbered from the thumb, so switching sides moves every side-button assignment to the opposite flank.")
                            .font(RazerFont.caption(10))
                            .foregroundColor(.razerTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().overlay(Color.razerBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            let accepted = deviceManager.configureSideButtons()
                            sideButtonStatus = accepted == DeviceManager.sideButtonPlan.count
                                ? "All four side buttons are now visible to RazerControl."
                                : "\(accepted) of \(DeviceManager.sideButtonPlan.count) accepted."
                        } label: {
                            Text("Enable all four side buttons")
                                .font(RazerFont.caption(11))
                                .foregroundColor(.razerGreen)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.razerGreenSubtle)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.razerGreen.opacity(0.4), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            let accepted = deviceManager.applyModifierPreset()
                            sideButtonStatus = accepted == DeviceManager.sideButtonModifierPreset.count
                                ? "Left flank sends Control and Alt; right flank stays Mouse 4 and 5."
                                : "\(accepted) of \(DeviceManager.sideButtonModifierPreset.count) applied."
                        } label: {
                            Text("Modifiers on left flank only")
                                .font(RazerFont.caption(11))
                                .foregroundColor(.razerTextSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.razerSurfaceLight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.razerBorder, lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            let accepted = deviceManager.restoreSideButtonDefaults()
                            sideButtonStatus = accepted == DeviceManager.sideButtonDefaults.count
                                ? "Restored to Mouse 4 and 5. RazerControl can no longer see them."
                                : "\(accepted) of \(DeviceManager.sideButtonDefaults.count) restored."
                        } label: {
                            Text("Restore factory buttons")
                                .font(RazerFont.caption(11))
                                .foregroundColor(.razerTextSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.razerSurfaceLight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.razerBorder, lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)

                        Text(sideButtonStatus ?? "Out of the factory the side buttons report as mouse buttons, which this app cannot see. This reassigns them to F13-F16.")
                            .font(RazerFont.caption(10))
                            .foregroundColor(.razerTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .razerCard()
            .onAppear { refreshDeviceStatus() }
        }
    }

    private var batteryLabel: String {
        guard let batteryPercent else { return "unknown" }
        return isCharging == true ? "\(batteryPercent)% -- charging" : "\(batteryPercent)%"
    }

    private func handednessButton(_ mode: RazerHandedness, _ title: String) -> some View {
        let isActive = appliedHandedness == mode
        return Button {
            applyHandedness(mode)
        } label: {
            Text(title)
                .font(RazerFont.caption(11))
                .foregroundColor(isActive ? .razerGreen : .razerTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.razerGreenSubtle : Color.razerSurfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isActive ? Color.razerGreen.opacity(0.4) : Color.razerBorder,
                                              lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// Reads battery and charge state. Both are queries; nothing is written.
    private func refreshDeviceStatus() {
        guard let mouse = deviceManager.selectedMouse,
              mouse.info.features.contains(.wireless) else { return }
        batteryPercent = mouse.hidDevice.getBatteryLevel(transactionId: mouse.info.transactionId)
        isCharging = mouse.hidDevice.getChargingStatus(transactionId: mouse.info.transactionId)
    }

    /// Writes the handedness mode. Only reflected in the UI if the device
    /// acknowledged it, so a failed write does not leave the panel claiming a
    /// mode the mouse is not in.
    private func applyHandedness(_ mode: RazerHandedness) {
        guard let mouse = deviceManager.selectedMouse else { return }
        if mouse.hidDevice.setHandedness(mode, transactionId: mouse.info.transactionId) {
            appliedHandedness = mode
        }
    }

    // MARK: - Viper Ultimate Visualization

    /// Top-down Viper Ultimate with clickable button hotspots.
    ///
    /// The mouse tab used to draw nothing at all for this device: the only
    /// silhouette in the app was a vertical wedge belonging to the Pro Click,
    /// and it sat in the `else` branch, so an ambidextrous Viper got a bare
    /// table with no picture. The shapes are shared with the lighting preview
    /// so the two views cannot drift into drawing two different mice.
    @ViewBuilder
    private var viperMouseVisualization: some View {
        if let pid = deviceManager.selectedMouse?.pid,
           let artwork = DeviceArt.image(for: pid),
           let hotspots = DeviceArtMap.load(productID: pid,
                                            bundledName: DeviceArt.bundledName(for: pid)) {
            VStack(spacing: 10) {
                RazerSectionHeader(deviceManager.selectedMouse?.name ?? "Mouse",
                                   subtitle: "Click a button to assign its action")
                DeviceArtView(
                    image: artwork,
                    map: hotspots,
                    // Only the left flank reports to us; the rest cannot light.
                    // A button now answers to more than one usage: the
                    // factory modifier it may still be sending, and the
                    // function key we assign it. Picking the first match from
                    // a dictionary would pick arbitrarily between them, so
                    // prefer whichever one is actually held down.
                    hidCode: { id in
                        guard let source = MouseButton(rawValue: id)?.mappingSource
                        else { return nil }
                        let usages = DeviceManager.viperUsageToButton
                            .filter { $0.value == source }
                            .map(\.key)
                        return usages.first { deviceManager.pressedKeyboardUsages.contains($0) }
                            ?? usages.min()
                    },
                    isMapped: { id in
                        guard let button = MouseButton(rawValue: id) else { return false }
                        return deviceManager.mouseMappings[button.mappingSource] != nil
                    },
                    // Unlettered, for the same reason the keypad's thumb
                    // controls are: nothing is printed on the hardware. The
                    // side buttons are also far too slim to letter -- "L Fwd"
                    // truncates to "L F..." -- and the panel beside the artwork
                    // already names every button and its binding. The artwork
                    // locates a control and shows it being pressed; the panel
                    // says what it is.
                    label: { _ in "" },
                    assignment: { _ in "" },
                    pressed: deviceManager.pressedKeyboardUsages,
                    onSelect: { id in
                        guard let button = MouseButton(rawValue: id) else { return }
                        selectedButton = button
                        showMapperSheet = true
                    }
                )
                .frame(width: 300, height: 470)
            }
            .razerCard()
        } else if let pid = deviceManager.selectedMouse?.pid, DeviceArt.hasArt(for: pid) {
            VStack(spacing: 10) {
                RazerSectionHeader(deviceManager.selectedMouse?.name ?? "Mouse",
                                   subtitle: "Click a button to assign its action")
                DeviceArt.view(for: pid, maxWidth: 220, maxHeight: 300)
                    .frame(width: 250, height: 300)
            }
            .razerCard()
        } else {
            drawnViperVisualization
        }
    }

    private var drawnViperVisualization: some View {
        VStack(spacing: 10) {
            RazerSectionHeader("Viper Ultimate", subtitle: "Click a button to assign its action")

            ZStack {
                ViperMouseShape()
                    .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.19), .black],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 152, height: 268)
                    .overlay(ViperMouseShape().stroke(Color.razerBorder, lineWidth: 1.6))
                    .shadow(color: .black.opacity(0.6), radius: 16, y: 8)

                // Separated primary buttons and the centre channel between them.
                ViperButtonSeamShape()
                    .stroke(Color.black.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 134, height: 118)
                    .offset(y: -67)

                Capsule()
                    .fill(Color.black)
                    .frame(width: 22, height: 56)
                    .overlay(
                        VStack(spacing: 4) {
                            ForEach(0..<6, id: \.self) { _ in
                                Capsule().fill(Color.razerTextTertiary.opacity(0.7))
                                    .frame(width: 15, height: 2)
                            }
                        }
                    )
                    .offset(y: -80)

                // Two side buttons per flank -- the Viper is ambidextrous, and
                // that symmetry is the whole reason it has seven mappable
                // controls rather than five.
                buttonHotspot(.wheelClick, x: 0, y: -80, w: 38, h: 46)
                buttonHotspot(.leftClick, x: -34, y: -76, w: 56, h: 86)
                buttonHotspot(.rightClick, x: 34, y: -76, w: 56, h: 86)
                // Side buttons sit on the shell itself, inside the outline --
                // placing them beyond it left the labels clipped by the card.
                buttonHotspot(.sideLeftForward, x: -46, y: 6, w: 36, h: 30)
                buttonHotspot(.sideLeftBack, x: -46, y: 42, w: 36, h: 30)
                buttonHotspot(.sideRightForward, x: 46, y: 6, w: 36, h: 30)
                buttonHotspot(.sideRightBack, x: 46, y: 42, w: 36, h: 30)
            }
            .frame(width: 250, height: 300)
        }
        .razerCard()
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

                // Wheel click
                buttonHotspot(.wheelClick, x: 0, y: -105, w: 28, h: 16)

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
                buttonHotspot(.sideLeftForward, x: -82, y: -15, w: 24, h: 28)

                // Side button 4 (Back) - lower thumb area
                buttonHotspot(.sideLeftBack, x: -82, y: 25, w: 24, h: 28)

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
                ForEach(visibleButtons) { btn in
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

                ForEach(visibleButtons) { button in
                HStack {
                    Text(button.label)
                        .font(RazerFont.body(12))
                        .foregroundColor(.razerTextPrimary)
                        .frame(width: 110, alignment: .leading)

                    Text(currentAssignment(for: button))
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

    /// What this row should say the button does.
    ///
    /// Three sources, most specific first: a mapping the user set inside this
    /// app, then whatever the app last wrote to the device, then the factory
    /// behaviour. The middle one matters because the presets change what the
    /// hardware emits -- without it, pressing "Restore factory buttons" left
    /// this panel claiming assignments that were no longer true.
    private func currentAssignment(for button: MouseButton) -> String {
        if let mapped = deviceManager.mouseMappings[button.mappingSource]?.displayName {
            return mapped
        }
        if let slot = button.assignmentSlot,
           let applied = deviceManager.sideButtonAssignments[slot.rawValue] {
            return applied.displayName
        }
        return button.defaultAction
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
    case leftClick, rightClick, wheelClick
    case sideLeftForward, sideLeftBack, sideRightForward, sideRightBack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .sideLeftForward: return "Left Side Fwd"
        case .sideLeftBack: return "Left Side Back"
        case .sideRightForward: return "Right Side Fwd"
        case .sideRightBack: return "Right Side Back"
        case .wheelClick: return "Wheel Click"
        }
    }

    var shortLabel: String {
        switch self {
        case .leftClick: return "L"
        case .rightClick: return "R"
        case .sideLeftForward: return "L Fwd"
        case .sideLeftBack: return "L Back"
        case .sideRightForward: return "R Fwd"
        case .sideRightBack: return "R Back"
        case .wheelClick: return "Wheel"
        }
    }

    var defaultAction: String {
        switch self {
        case .leftClick: return "Click"
        case .rightClick: return "Right Click"
        case .sideLeftForward, .sideRightForward: return "Forward"
        case .sideLeftBack, .sideRightBack: return "Back"
        case .wheelClick: return "Middle Click"
        }
    }

    /// The assignment slot this button occupies, for the four that have one.
    /// The primaries and the wheel are not assignable through this command.
    var assignmentSlot: RazerButtonSlot? {
        switch self {
        case .sideLeftBack: return .leftBack
        case .sideLeftForward: return .leftFront
        case .sideRightBack: return .rightBack
        case .sideRightForward: return .rightFront
        default: return nil
        }
    }

    /// Internal binding key. Values 1000/1001 represent
    /// Viper side controls emitted through its keyboard interface.
    var mappingSource: Int {
        switch self {
        case .leftClick: return 0
        case .rightClick: return 1
        case .wheelClick: return 2
        case .sideLeftForward: return 1000
        case .sideLeftBack: return 1001
        case .sideRightForward: return 4
        case .sideRightBack: return 3
        }
    }
}

private extension KeyAction {
    var displayName: String {
        switch self {
        case .keystroke(let key):
            return KeyCodeMap.hidKeyName(key)
        case .shortcut(let modifiers, let key):
            var parts: [String] = []
            if modifiers & 0x08 != 0 { parts.append("Ctrl") }
            if modifiers & 0x04 != 0 { parts.append("Opt") }
            if modifiers & 0x02 != 0 { parts.append("Shift") }
            if modifiers & 0x01 != 0 { parts.append("Cmd") }
            parts.append(KeyCodeMap.hidKeyName(key))
            return parts.joined(separator: " + ")
        case .spaceSwitch(let direction):
            if direction == "next" { return "Next Desktop →" }
            if direction == "previous" { return "← Previous Desktop" }
            return "Desktop \(direction)"
        case .launchApp:
            return "Launch Application"
        case .mediaControl(let control):
            return control.replacingOccurrences(of: "_", with: " ").capitalized
        case .disabled:
            return "Disabled"
        case .macroSequence:
            return "Macro"
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

    var cgButtonNumber: Int {
        button.mappingSource
    }

    private var currentAssignment: String {
        deviceManager.mouseMappings[cgButtonNumber]?.displayName
            ?? button.defaultAction
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remap \(button.label)")
                        .font(RazerFont.title(16)).foregroundColor(.razerTextPrimary)
                    Text("Current: \(currentAssignment)")
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
                    deviceManager.clearMouseMapping(button: cgButtonNumber)
                    applyFeedback = "Mapping cleared"
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
            guard let hidCode = KeyMapperSheet.nameToHIDKey[selectedKey] else {
                applyFeedback = "Unknown key"
                return
            }
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
