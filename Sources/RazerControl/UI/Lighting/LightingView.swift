import SwiftUI

enum PreviewDevice: String, CaseIterable {
    case keyboard = "Keyboard"
    // Mouse RGB not supported on Pro Click V2 Vertical — removed for now
}

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
    @State private var previewDevice: PreviewDevice = .keyboard
    @State private var applyStatus: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lighting Effects")
                            .font(RazerFont.title(20))
                            .foregroundColor(.razerTextPrimary)
                        Text("Customize RGB lighting for your device. No permissions required.")
                            .font(RazerFont.body())
                            .foregroundColor(.razerTextSecondary)
                    }
                    Spacer()

                    if let status = applyStatus {
                        Text(status)
                            .font(RazerFont.caption(11))
                            .foregroundColor(status == "Applied!" ? .razerSuccess : .razerWarning)
                    }

                    // Reset button (fixes stuck lights after macro init)
                    Button {
                        if let kb = deviceManager.selectedKeyboard {
                            _ = kb.setStaticColor(r: 0, g: 255, b: 0) // reset to green
                        }
                    } label: {
                        Text("Reset")
                    }
                    .buttonStyle(.razerSecondary)

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
            RazerSectionHeader("Preview", subtitle: "Keyboard")

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(previewGradient)
                    .frame(height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.razerBorder, lineWidth: 1)
                    )
                    .shadow(color: primaryColor.opacity(0.3), radius: 20)

                // Keyboard silhouette
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(0..<(14 - (row == 4 ? 5 : 0)), id: \.self) { col in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(keyColor(row: row, col: col).opacity(brightness))
                                    .frame(width: row == 4 && col == 3 ? 80 : 28, height: 18)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .razerCard()
    }

    private var previewGradient: some ShapeStyle {
        LinearGradient(
            colors: [Color.razerBg, Color.razerBg.opacity(0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
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
                ForEach(LightingEffect.allCases) { effect in
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

    private var zoneSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            RazerSectionHeader("Zone", subtitle: "Apply effect to specific areas")

            HStack(spacing: 6) {
                ForEach(LightingZone.allCases) { zone in
                    Button {
                        selectedZone = zone
                    } label: {
                        Text(zone.label)
                            .font(RazerFont.caption(11))
                            .foregroundColor(selectedZone == zone ? .razerGreen : .razerTextSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedZone == zone ? Color.razerGreenSubtle : Color.razerSurfaceLight)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(
                                                selectedZone == zone ? Color.razerGreen.opacity(0.4) : Color.razerBorder,
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
        guard let device = deviceManager.selectedKeyboard else {
            applyStatus = "No keyboard connected"
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

        applyStatus = success ? "Applied!" : "Failed to apply"

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if applyStatus == "Applied!" || applyStatus == "Failed to apply" {
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
