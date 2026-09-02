import SwiftUI

struct LightingView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selectedEffect: LightingEffect = .static_
    @State private var primaryColor: Color = .razerGreen
    @State private var secondaryColor: Color = .blue
    @State private var brightness: Double = 1.0
    @State private var speed: Double = 0.5
    @State private var direction: Int = 0
    @State private var selectedZone: LightingZone = .all
    @State private var hexColor: String = "#00FF00"
    @State private var animationPhase: Double = 0

    /// Seeds the effect and its animation phase. Only the offscreen renderer
    /// passes these: a still frame cannot show an effect travelling, so a
    /// review render has to be able to freeze one mid-sweep.
    init(previewEffect: LightingEffect? = nil, previewPhase: Double? = nil) {
        if let previewEffect { _selectedEffect = State(initialValue: previewEffect) }
        if let previewPhase { _animationPhase = State(initialValue: previewPhase) }
    }
    @State private var applyStatus: String?
    @State private var transactionLog: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lighting Effects")
                            .font(RazerFont.title(20))
                            .foregroundColor(.razerTextPrimary)
                        Text("Customize RGB lighting and inspect the device protocol.")
                            .font(RazerFont.body())
                            .foregroundColor(.razerTextSecondary)
                    }
                    Spacer()

                    if let status = applyStatus {
                        Text(status)
                            .font(RazerFont.caption(11))
                            .foregroundColor(status == "Applied!" ? .razerSuccess : .razerWarning)
                    }

                    // Reset driver mode only applies to keyboard-class devices.
                    if deviceManager.selectedDevice?.type == .keyboard {
                        Button {
                        if let kb = deviceManager.selectedKeyboard {
                            // 1. Clear cached interface (may be stale after macro init)
                            kb.hidDevice.resetInterfaceCache()

                            // 2. Set device back to normal mode (undo driver/macro mode)
                            let normalPkt = RazerPacket(
                                transactionId: kb.info.transactionId,
                                commandClass: .device,
                                commandId: RazerCmd.deviceMode,
                                args: [0x00, 0x00]  // normal mode
                            )
                            _ = kb.hidDevice.sendPacket(normalPkt)
                            kb.macroKeysInitialized = false
                            usleep(200_000)

                            // 3. Set static green
                            let ok = kb.setStaticColor(r: 0, g: 255, b: 0)
                            applyStatus = ok ? "Reset!" : "Reset failed — try unplugging keyboard"
                            print("[Lighting] Reset: normal mode + green = \(ok)")
                        }
                        } label: {
                            Text("Reset")
                        }
                        .buttonStyle(.razerSecondary)
                    }

                    // Apply button
                    Button {
                        applyEffectToDevice()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                            Text("Apply")
                        }
                    }
                    .buttonStyle(.razerPrimary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                if let transactionLog {
                    DisclosureGroup("Last device transaction") {
                        Text(transactionLog)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.razerTextSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .font(RazerFont.caption(11))
                    .foregroundColor(.razerTextSecondary)
                    .padding(.horizontal, 24)
                }

                HStack(alignment: .top, spacing: 20) {
                    // Left: Effect preview + selector
                    VStack(spacing: 16) {
                        effectPreview
                        effectSelector
                    }

                    // Right: Color picker + settings
                    VStack(spacing: 16) {
                        colorPickerPanel
                        effectSettings
                        zoneSelector
                    }
                    .frame(width: 280)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    // MARK: - Effect Preview

    private var effectPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            RazerSectionHeader("Preview", subtitle: deviceManager.selectedDevice?.name ?? "No device")

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(previewGradient)
                    .frame(height: previewHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.razerBorder, lineWidth: 1)
                    )
                    .shadow(color: primaryColor.opacity(0.3), radius: 20)

                selectedDevicePreview
                    .padding(18)
            }
        }
        .razerCard()
    }

    /// Sized by what is being drawn, not by whether artwork happens to exist.
    ///
    /// The rule used to be that a device with artwork got the room and everything
    /// else got 180 points. That gave the most space to a portrait keypad and the
    /// least to a full keyboard -- the widest thing this app draws -- because a
    /// keyboard has no artwork file. It scaled itself down to fit and came out
    /// unreadable, which is not a statement about the keyboard so much as about
    /// the rule.
    private var previewHeight: CGFloat {
        switch deviceManager.selectedDevice?.type {
        case .keyboard: return 300
        case .mouse, .headset, .accessory: return 180
        case nil: return 180
        }
    }

    @ViewBuilder
    private var selectedDevicePreview: some View {
        switch deviceManager.selectedDevice?.type {
        case .headset:
            headsetPreview
        case .accessory:
            dockPreview
        case .mouse:
            mousePreview
        case .keyboard:
            keyboardPreview
        case nil:
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 48))
                .foregroundColor(.razerTextTertiary)
        }
    }

    @ViewBuilder
    private var keyboardPreview: some View {
        if let pid = deviceManager.selectedDevice?.pid,
           let artwork = DeviceArt.image(for: pid),
           let hotspots = DeviceArtMap.load(productID: pid,
                                            bundledName: DeviceArt.bundledName(for: pid)) {
            // Light each control from its own position, so an effect crosses
            // the keys instead of tinting the whole picture.
            DeviceArtLightingPreview(image: artwork,
                                     map: hotspots,
                                     colour: { u, v in keyColour(u: u, v: v) },
                                     brightness: brightness)
        } else {
            KeyboardView(
                isLightingPreview: true,
                lightingPreviewColor: keyColor(row: 2, col: 7).opacity(brightness),
                lightingColourAt: { u, v in keyColour(u: u, v: v).opacity(brightness) }
            )
        }
    }

    private var headsetPreview: some View {
        let glow = keyColor(row: 0, col: 3).opacity(brightness)
        let shell = Color(red: 0.82, green: 0.55, blue: 0.64)
        let cushion = Color(red: 0.12, green: 0.10, blue: 0.12)
        return GeometryReader { proxy in
            let scale = min(proxy.size.width / 390, proxy.size.height / 150)
            ZStack {
                // Padded headband and the two suspended earcup forks.
                KrakenHeadbandShape()
                    .stroke(shell, style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round))
                    .overlay(KrakenHeadbandShape().stroke(.white.opacity(0.16), lineWidth: 2))
                    .frame(width: 238, height: 126)
                    .offset(y: 13)

                HStack(spacing: 104) {
                    KrakenCatEarShape()
                        .fill(shell)
                        .overlay(KrakenCatEarShape().stroke(glow, lineWidth: 4))
                        .shadow(color: glow, radius: 10)
                    KrakenCatEarShape()
                        .fill(shell)
                        .overlay(KrakenCatEarShape().stroke(glow, lineWidth: 4))
                        .shadow(color: glow, radius: 10)
                }
                .frame(width: 202, height: 47)
                .offset(y: -47)

                HStack(spacing: 112) {
                    ForEach(0..<2, id: \.self) { side in
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(shell)
                                .frame(width: 68, height: 91)
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.18), lineWidth: 2))
                            RoundedRectangle(cornerRadius: 20)
                                .fill(cushion)
                                .frame(width: 57, height: 80)
                            RazerLogoMark()
                                .stroke(glow, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .frame(width: 34, height: 34)
                                .shadow(color: glow, radius: 9)
                        }
                    }
                }
                .offset(y: 29)
            }
            .frame(width: 390, height: 150)
            .scaleEffect(scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var dockPreview: some View {
        let glow = keyColor(row: 1, col: 7).opacity(brightness)
        return ZStack {
            DockPedestalShape()
                .fill(LinearGradient(colors: [Color.razerSurfaceHover, .black], startPoint: .top, endPoint: .bottom))
                .frame(width: 92, height: 112)
                .overlay(DockPedestalShape().stroke(Color.razerBorder, lineWidth: 2))
                .offset(y: -5)
            Capsule()
                .stroke(glow, lineWidth: 7)
                .frame(width: 128, height: 34)
                .shadow(color: glow, radius: 14)
                .offset(y: 55)
            HStack(spacing: 9) {
                Circle().fill(Color.razerTextTertiary).frame(width: 7, height: 7)
                Circle().fill(Color.razerTextTertiary).frame(width: 7, height: 7)
            }
            .offset(y: -44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var mousePreview: some View {
        if let pid = deviceManager.selectedDevice?.pid,
           let artwork = DeviceArt.image(for: pid),
           let hotspots = DeviceArtMap.load(productID: pid,
                                            bundledName: DeviceArt.bundledName(for: pid)) {
            DeviceArtLightingPreview(image: artwork,
                                     map: hotspots,
                                     colour: { u, v in keyColour(u: u, v: v) },
                                     brightness: brightness)
        } else if let pid = deviceManager.selectedDevice?.pid, DeviceArt.hasArt(for: pid) {
            DeviceArt.view(for: pid, maxWidth: 300, maxHeight: 150)
        } else {
            drawnMousePreview
        }
    }

    private var drawnMousePreview: some View {
        let glow = keyColor(row: 2, col: 5).opacity(brightness)
        return ZStack {
            ViperMouseShape()
                .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.16, blue: 0.18), .black], startPoint: .top, endPoint: .bottom))
                .frame(width: 84, height: 148)
                .overlay(ViperMouseShape().stroke(Color.razerBorder, lineWidth: 2))

            // Viper Ultimate's separated primary buttons and center channel.
            ViperButtonSeamShape()
                .stroke(Color.black.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 74, height: 66)
                .offset(y: -37)
            Capsule()
                .fill(Color.black)
                .frame(width: 11, height: 32)
                .overlay(
                    VStack(spacing: 3) {
                        ForEach(0..<6, id: \.self) { _ in
                            Capsule().fill(Color.razerTextTertiary.opacity(0.7)).frame(width: 10, height: 2)
                        }
                    }
                )
                .offset(y: -37)

            // Symmetrical textured side grips are a defining Viper feature.
            HStack(spacing: 96) {
                ViperGripShape().fill(Color.black.opacity(0.85))
                ViperGripShape().fill(Color.black.opacity(0.85)).scaleEffect(x: -1, y: 1)
            }
            .frame(width: 124, height: 61)
            .offset(y: 19)

            RazerLogoMark()
                .stroke(glow, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 32, height: 32)
                .shadow(color: glow, radius: 10)
                .offset(y: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewGradient: some ShapeStyle {
        LinearGradient(
            colors: [Color.razerBg, Color.razerBg.opacity(0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Colour for a control at a normalised position in the artwork.
    ///
    /// The grid-indexed version below cannot describe the thumb module, which
    /// sits at an angle and belongs to no row or column. Position works for
    /// every control on any device.
    private func keyColour(u: Double, v: Double) -> Color {
        switch selectedEffect {
        case .static_:
            return primaryColor
        case .breathing:
            let phase = sin(animationPhase * 2) * 0.5 + 0.5
            return primaryColor.opacity(phase)
        case .wave:
            // Travel is left to right with a slight downward lean, matching the
            // hardware. The multipliers put roughly one full hue sweep across
            // the width of the key grid.
            let offset = u * 1.4 + v * 0.35
            let hue = (animationPhase * 0.3 + offset).truncatingRemainder(dividingBy: 1.0)
            return Color(hue: abs(hue), saturation: 1.0, brightness: 1.0)
        case .spectrum:
            let hue = animationPhase.truncatingRemainder(dividingBy: 1.0)
            return Color(hue: abs(hue), saturation: 1.0, brightness: 1.0)
        case .reactive:
            return primaryColor.opacity(0.3)
        case .starlight:
            let twinkle = sin(animationPhase * 3 + u * 37 + v * 17) > 0.7 ? 1.0 : 0.1
            return primaryColor.opacity(twinkle)
        case .off:
            return Color.clear
        }
    }

    private func keyColor(row: Int, col: Int) -> Color {
        switch selectedEffect {
        case .static_:
            return primaryColor
        case .breathing:
            let phase = sin(animationPhase * 2) * 0.5 + 0.5
            return primaryColor.opacity(phase)
        case .wave:
            let offset = Double(col) * 0.15 + Double(row) * 0.05
            let hue = (animationPhase * 0.3 + offset).truncatingRemainder(dividingBy: 1.0)
            return Color(hue: abs(hue), saturation: 1.0, brightness: 1.0)
        case .spectrum:
            let hue = animationPhase.truncatingRemainder(dividingBy: 1.0)
            return Color(hue: abs(hue), saturation: 1.0, brightness: 1.0)
        case .reactive:
            return primaryColor.opacity(0.3)
        case .starlight:
            let seed = Double(row * 14 + col)
            let twinkle = sin(animationPhase * 3 + seed) > 0.7 ? 1.0 : 0.1
            return primaryColor.opacity(twinkle)
        case .off:
            return Color.razerSurfaceLight.opacity(0.3)
        }
    }

    // MARK: - Effect Selector

    private var effectSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            RazerSectionHeader("Effect")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(supportedEffects) { effect in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedEffect = effect
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(effectThumbnailGradient(effect))
                                    .frame(width: 36, height: 36)
                                Image(systemName: effect.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            Text(effect.label)
                                .font(RazerFont.caption(10))
                                .foregroundColor(selectedEffect == effect ? .razerGreen : .razerTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedEffect == effect ? Color.razerGreenSubtle : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            selectedEffect == effect ? Color.razerGreen.opacity(0.4) : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .razerCard()
    }

    private var supportedEffects: [LightingEffect] {
        guard let features = deviceManager.selectedDevice?.info.features else {
            return [.off]
        }
        return LightingEffect.allCases.filter { effect in
            switch effect {
            case .static_: return features.contains(.staticEffect)
            case .breathing: return features.contains(.breathingEffect)
            case .wave: return features.contains(.waveEffect)
            case .spectrum: return features.contains(.spectrumEffect)
            case .reactive: return features.contains(.reactiveEffect)
            case .starlight: return features.contains(.starlightEffect)
            case .off: return true
            }
        }
    }

    private func effectThumbnailGradient(_ effect: LightingEffect) -> some ShapeStyle {
        switch effect {
        case .static_: return LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case .breathing: return LinearGradient(colors: [.green.opacity(0.8), .green.opacity(0.2)], startPoint: .top, endPoint: .bottom)
        case .wave: return LinearGradient(colors: [.red, .yellow, .green, .blue, .purple], startPoint: .leading, endPoint: .trailing)
        case .spectrum: return LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple], startPoint: .leading, endPoint: .trailing)
        case .reactive: return LinearGradient(colors: [.orange, .orange.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        case .starlight: return LinearGradient(colors: [.white, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom)
        case .off: return LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Color Picker

    private var colorPickerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            RazerSectionHeader("Color")

            // Primary color
            HStack(spacing: 12) {
                ColorPicker("", selection: $primaryColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Primary")
                        .font(RazerFont.caption(11))
                        .foregroundColor(.razerTextTertiary)

                    HStack(spacing: 4) {
                        Text("#")
                            .font(RazerFont.mono(12))
                            .foregroundColor(.razerTextTertiary)
                        TextField("00FF00", text: $hexColor)
                            .font(RazerFont.mono(12))
                            .foregroundColor(.razerTextPrimary)
                            .textFieldStyle(.plain)
                            .frame(width: 70)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.razerBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.razerBorder, lineWidth: 1)
                            )
                    )
                }

                Spacer()
            }

            // Quick presets
            HStack(spacing: 6) {
                ForEach(colorPresets, id: \.self) { color in
                    Button {
                        withAnimation { primaryColor = color }
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        primaryColor.description == color.description ? Color.white : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Brightness
            HStack(spacing: 12) {
                Image(systemName: "sun.min")
                    .font(.system(size: 12))
                    .foregroundColor(.razerTextTertiary)
                Slider(value: $brightness, in: 0...1)
                    .tint(.razerGreen)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.razerTextSecondary)
                Text("\(Int(brightness * 100))%")
                    .font(RazerFont.mono(11))
                    .foregroundColor(.razerTextSecondary)
                    .frame(width: 36)
            }
        }
        .razerCard()
    }

    private var colorPresets: [Color] {
        [.razerGreen, .red, .blue, .purple, .orange, .yellow, .cyan, .white]
    }

    // MARK: - Effect Settings

    private var effectSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            RazerSectionHeader("Effect Settings")

            if selectedEffect == .wave || selectedEffect == .breathing {
                HStack(spacing: 12) {
                    Text("Speed")
                        .font(RazerFont.caption(11))
                        .foregroundColor(.razerTextTertiary)
                        .frame(width: 50, alignment: .leading)
                    Slider(value: $speed, in: 0.1...1.0)
                        .tint(.razerGreen)
                    Text(speedLabel)
                        .font(RazerFont.mono(11))
                        .foregroundColor(.razerTextSecondary)
                        .frame(width: 40)
                }
            }

            if selectedEffect == .wave {
                HStack(spacing: 12) {
                    Text("Direction")
                        .font(RazerFont.caption(11))
                        .foregroundColor(.razerTextTertiary)
                        .frame(width: 50, alignment: .leading)

                    Picker("", selection: $direction) {
                        Text("Left → Right").tag(0)
                        Text("Right → Left").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if selectedEffect == .off {
                Text("Lighting is disabled")
                    .font(RazerFont.body())
                    .foregroundColor(.razerTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .razerCard()
    }

    private var speedLabel: String {
        if speed < 0.3 { return "Slow" }
        if speed < 0.7 { return "Med" }
        return "Fast"
    }

    // MARK: - Zone Selector

    /// The zones this device actually has.
    ///
    /// The panel used to offer the same four to everything, so a Viper whose
    /// only lit region is its logo was given Keys and Underglow buttons
    /// addressing LEDs it does not contain. Where a device ships an artwork
    /// map, its declared zones are the authority -- they were measured off the
    /// hardware when the artwork was drawn. A device with no map keeps the full
    /// list, because nothing better is known about it and an empty selector is
    /// worse than an over-broad one.
    /// The zones the device database says this hardware actually has.
    private var declaredZones: [LightingZone] {
        guard let zones = deviceManager.selectedDevice?.info.zones, !zones.isEmpty
        else { return LightingZone.allCases }
        let mapped: [LightingZone] = zones.compactMap {
            switch $0.led {
            case .backlight: return .backlight
            case .logo: return .logo
            case .underglow: return .underglow
            default: return nil
            }
        }
        guard !mapped.isEmpty else { return LightingZone.allCases }
        return mapped.count > 1 ? [.all] + mapped : mapped
    }

    private var availableZones: [LightingZone] {
        // The device database is the fallback, not the full list. A device with
        // no artwork was previously offered every zone this app knows about,
        // which is how a keyboard with one lit region ended up with buttons for
        // a logo it does not have and an underglow it was never built with.
        guard let pid = deviceManager.selectedDevice?.pid,
              let map = DeviceArtMap.load(productID: pid,
                                          bundledName: DeviceArt.bundledName(for: pid))
        else { return declaredZones }

        let declared = Set(map.lightingRegions.map(\.id))
        let matched = LightingZone.allCases.filter { $0 != .all && declared.contains($0.rawValue) }
        guard !matched.isEmpty else { return declaredZones }
        // "All" only means something when there is more than one zone to be all of.
        return matched.count > 1 ? [.all] + matched : matched
    }

    /// The selection, corrected for devices that do not have it.
    ///
    /// Resolved rather than stored: switching devices would otherwise leave a
    /// stale selection pointing at a zone the new device lacks, and correcting
    /// it on change means reconciling state across every device switch.
    private var effectiveZone: LightingZone {
        availableZones.contains(selectedZone) ? selectedZone : (availableZones.first ?? .all)
    }

    private var zoneSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            RazerSectionHeader("Zone", subtitle: "Apply effect to specific areas")

            HStack(spacing: 6) {
                ForEach(availableZones) { zone in
                    Button {
                        selectedZone = zone
                    } label: {
                        Text(zone.label)
                            .font(RazerFont.caption(11))
                            .foregroundColor(effectiveZone == zone ? .razerGreen : .razerTextSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(effectiveZone == zone ? Color.razerGreenSubtle : Color.razerSurfaceLight)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(
                                                effectiveZone == zone ? Color.razerGreen.opacity(0.4) : Color.razerBorder,
                                                lineWidth: 0.5
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .razerCard()
    }

    // MARK: - Animation

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            animationPhase += 0.02
        }
    }

    // MARK: - Apply to Real Device

    private func applyEffectToDevice() {
        guard let device = deviceManager.selectedDevice else {
            applyStatus = "No lighting device selected"
            return
        }

        var success = false

        // Apply brightness first
        _ = device.setBrightness(brightness)

        // Convert UI speed (0.1-1.0) to USB speed (0xFF=slowest to 0x01=fastest)
        let usbSpeed = UInt8(max(1, min(255, Int((1.0 - speed) * 254) + 1)))

        // Apply the selected effect
        switch selectedEffect {
        case .static_:
            success = device.setStaticColor(primaryColor)
        case .breathing:
            success = device.setBreathingEffect(primaryColor)
        case .wave:
            success = device.setWaveEffect(
                direction: direction == 0 ? .leftToRight : .rightToLeft,
                speed: usbSpeed
            )
        case .spectrum:
            success = device.setSpectrumEffect()
        case .off:
            success = device.setOff()
        case .reactive, .starlight:
            success = device.setStaticColor(primaryColor)
        }

        transactionLog = device.hidDevice.lastTransactionLog.joined(separator: "\n")
        if success {
            applyStatus = "Applied!"
        } else if transactionLog?.contains("0xE00002E2") == true {
            applyStatus = "Input Monitoring permission required"
        } else if transactionLog?.contains("0xE00002C5") == true {
            applyStatus = "HID interface is held exclusively"
        } else {
            applyStatus = "Device rejected the command"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if applyStatus == "Applied!" {
                applyStatus = nil
            }
        }
    }
}

// MARK: - Models

enum LightingEffect: String, CaseIterable, Identifiable {
    case static_ = "static"
    case breathing, wave, spectrum, reactive, starlight, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .static_: return "Static"
        case .breathing: return "Breathing"
        case .wave: return "Wave"
        case .spectrum: return "Spectrum"
        case .reactive: return "Reactive"
        case .starlight: return "Starlight"
        case .off: return "Off"
        }
    }

    var icon: String {
        switch self {
        case .static_: return "circle.fill"
        case .breathing: return "wind"
        case .wave: return "water.waves"
        case .spectrum: return "rainbow"
        case .reactive: return "bolt.fill"
        case .starlight: return "sparkles"
        case .off: return "power"
        }
    }
}

enum LightingZone: String, CaseIterable, Identifiable {
    case all, backlight, logo, underglow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .backlight: return "Keys"
        case .logo: return "Logo"
        case .underglow: return "Underglow"
        }
    }
}

private struct KrakenHeadbandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 12, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 12, y: rect.maxY),
            control1: CGPoint(x: rect.minX + 18, y: rect.minY - 7),
            control2: CGPoint(x: rect.maxX - 18, y: rect.minY - 7)
        )
        return path
    }
}

private struct KrakenCatEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + 1),
            control1: CGPoint(x: rect.minX + 7, y: rect.midY),
            control2: CGPoint(x: rect.midX - 5, y: rect.minY + 2)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - 2, y: rect.maxY),
            control1: CGPoint(x: rect.midX + 5, y: rect.minY + 2),
            control2: CGPoint(x: rect.maxX - 7, y: rect.midY)
        )
        path.addQuadCurve(to: CGPoint(x: rect.minX + 2, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY - 8))
        path.closeSubpath()
        return path
    }
}

private struct RazerLogoMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for angle in stride(from: -90.0, through: 150.0, by: 120.0) {
            let radians = angle * .pi / 180
            let start = CGPoint(
                x: center.x + CGFloat(cos(radians)) * rect.width * 0.12,
                y: center.y + CGFloat(sin(radians)) * rect.height * 0.12
            )
            let outer = CGPoint(
                x: center.x + CGFloat(cos(radians)) * rect.width * 0.43,
                y: center.y + CGFloat(sin(radians)) * rect.height * 0.43
            )
            let curlAngle = radians + 2.25
            let end = CGPoint(
                x: center.x + CGFloat(cos(curlAngle)) * rect.width * 0.27,
                y: center.y + CGFloat(sin(curlAngle)) * rect.height * 0.27
            )
            path.move(to: start)
            path.addQuadCurve(to: end, control: outer)
        }
        return path
    }
}

private struct DockPedestalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 22, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 22, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.minY - 7))
        path.addLine(to: CGPoint(x: rect.maxX - 7, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 7, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Shared with the Mouse tab so the lighting preview and the button
/// mapper cannot drift into drawing two different mice.
struct ViperMouseShape: Shape {
    /// Top-down Viper Ultimate outline, drawn in normalised coordinates so it
    /// keeps its proportions at any size.
    ///
    /// The previous outline used `midY` for the widest point and near-circular
    /// control points, which produced a squat oval. A Viper is roughly 127mm
    /// long by 66mm wide -- close to 2:1 -- and it is an ambidextrous shape:
    /// symmetric about its long axis, gently waisted where the fingers rest,
    /// widest a little behind centre where the palm sits.
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func point(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * fx, y: rect.minY + h * fy)
        }

        var path = Path()
        path.move(to: point(0.50, 0.000))
        // Right front shoulder, then down through the waist to the palm bulge.
        path.addCurve(to: point(0.93, 0.230),
                      control1: point(0.76, 0.000),
                      control2: point(0.93, 0.085))
        path.addCurve(to: point(0.90, 0.560),
                      control1: point(0.93, 0.360),
                      control2: point(0.90, 0.450))
        path.addCurve(to: point(0.86, 0.870),
                      control1: point(0.90, 0.690),
                      control2: point(0.93, 0.790))
        path.addCurve(to: point(0.50, 1.000),
                      control1: point(0.80, 0.960),
                      control2: point(0.66, 1.000))
        // Mirrored left side.
        path.addCurve(to: point(0.14, 0.870),
                      control1: point(0.34, 1.000),
                      control2: point(0.20, 0.960))
        path.addCurve(to: point(0.10, 0.560),
                      control1: point(0.07, 0.790),
                      control2: point(0.10, 0.690))
        path.addCurve(to: point(0.07, 0.230),
                      control1: point(0.10, 0.450),
                      control2: point(0.07, 0.360))
        path.addCurve(to: point(0.50, 0.000),
                      control1: point(0.07, 0.085),
                      control2: point(0.24, 0.000))
        path.closeSubpath()
        return path
    }
}

/// Shared with the Mouse tab so the lighting preview and the button
/// mapper cannot drift into drawing two different mice.
struct ViperButtonSeamShape: Shape {
    /// The centre channel between the two primary buttons, and the curved
    /// break where those buttons end and the shell begins.
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func point(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * fx, y: rect.minY + h * fy)
        }

        var path = Path()
        path.move(to: point(0.50, 0.02))
        path.addLine(to: point(0.50, 0.98))

        path.move(to: point(0.06, 0.86))
        path.addCurve(to: point(0.50, 0.98),
                      control1: point(0.18, 0.94),
                      control2: point(0.33, 0.98))
        path.addCurve(to: point(0.94, 0.86),
                      control1: point(0.67, 0.98),
                      control2: point(0.82, 0.94))
        return path
    }
}

/// Shared with the Mouse tab so the lighting preview and the button
struct ViperGripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 14))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - 6),
                      control1: CGPoint(x: rect.minX + 13, y: rect.minY),
                      control2: CGPoint(x: rect.maxX - 3, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.minX + 2, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX - 10, y: rect.maxY),
                      control2: CGPoint(x: rect.minX + 8, y: rect.maxY + 2))
        path.closeSubpath()
        return path
    }
}
