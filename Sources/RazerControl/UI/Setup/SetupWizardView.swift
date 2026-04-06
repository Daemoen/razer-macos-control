import SwiftUI

// MARK: - Setup Wizard

struct SetupWizardView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @StateObject private var permissions = PermissionManager()
    @Binding var isPresented: Bool
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with steps
            wizardHeader

            Divider().background(Color.razerBorder)

            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: deviceStep
                case 2: permissionsStep
                case 3: completeStep
                default: completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Color.razerBorder)

            // Navigation buttons
            wizardFooter
        }
        .frame(width: 560, height: 480)
        .background(Color.razerSurface)
        .onAppear {
            permissions.checkAll()
        }
    }

    // MARK: - Header

    private var wizardHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.razerGreen)
                    .razerGlow(radius: 4)
                Text("SETUP")
                    .font(.system(size: 12, weight: .black))
                    .tracking(3)
                    .foregroundColor(.razerTextPrimary)
            }

            // Step indicators
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { step in
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(step <= currentStep ? Color.razerGreen : Color.razerSurfaceLight)
                                .frame(width: 24, height: 24)
                            if step < currentStep {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black)
                            } else {
                                Text("\(step + 1)")
                                    .font(RazerFont.caption(10))
                                    .foregroundColor(step == currentStep ? .black : .razerTextTertiary)
                            }
                        }
                        if step < 3 {
                            Rectangle()
                                .fill(step < currentStep ? Color.razerGreen.opacity(0.5) : Color.razerBorder)
                                .frame(width: 40, height: 1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.razerGreen)
                .razerGlow(radius: 10)

            Text("Welcome to RazerControl")
                .font(RazerFont.title(22))
                .foregroundColor(.razerTextPrimary)

            Text("Open source configuration for Razer devices on macOS.\nNo root required. No kernel extensions.")
                .font(RazerFont.body(13))
                .foregroundColor(.razerTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "lightbulb.fill", text: "RGB lighting control", detail: "No permissions needed")
                featureRow(icon: "keyboard", text: "Key remapping & macros", detail: "Requires permissions")
                featureRow(icon: "computermouse", text: "Mouse button mapping", detail: "Requires permissions")
                featureRow(icon: "slider.horizontal.3", text: "DPI & sensitivity", detail: "No permissions needed")
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func featureRow(icon: String, text: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.razerGreen)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(RazerFont.body(13))
                    .foregroundColor(.razerTextPrimary)
                Text(detail)
                    .font(RazerFont.caption(10))
                    .foregroundColor(.razerTextTertiary)
            }
            Spacer()
        }
    }

    // MARK: - Step 2: Device Detection

    private var deviceStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if deviceManager.hasDevices {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.razerSuccess)
                    .razerGlow(color: .razerSuccess, radius: 8)

                Text("Devices Found!")
                    .font(RazerFont.title(20))
                    .foregroundColor(.razerTextPrimary)

                VStack(spacing: 8) {
                    ForEach(deviceManager.devices) { device in
                        HStack(spacing: 10) {
                            Image(systemName: device.icon)
                                .font(.system(size: 14))
                                .foregroundColor(.razerGreen)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.razerGreenSubtle))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name)
                                    .font(RazerFont.body(13))
                                    .foregroundColor(.razerTextPrimary)
                                Text("PID: \(String(format: "0x%04X", device.pid))")
                                    .font(RazerFont.mono(10))
                                    .foregroundColor(.razerTextTertiary)
                            }
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundColor(.razerSuccess)
                        }
                        .padding(10)
                        .razerCard(padding: 0)
                    }
                }
                .padding(.horizontal, 60)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 42))
                    .foregroundColor(.razerWarning)

                Text("No Razer Devices Found")
                    .font(RazerFont.title(20))
                    .foregroundColor(.razerTextPrimary)

                Text("Connect a Razer keyboard or mouse via USB.\nThe app will detect it automatically.")
                    .font(RazerFont.body(13))
                    .foregroundColor(.razerTextSecondary)
                    .multilineTextAlignment(.center)

                Button("Rescan") {
                    deviceManager.stopScanning()
                    deviceManager.startScanning()
                }
                .buttonStyle(.razerSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Step 3: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Permissions")
                .font(RazerFont.title(20))
                .foregroundColor(.razerTextPrimary)

            Text("Key remapping needs macOS permissions.\nRGB lighting works without any permissions.")
                .font(RazerFont.body(13))
                .foregroundColor(.razerTextSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                // Accessibility
                permissionCard(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Required to inject remapped key events (CGEventPost)",
                    status: permissions.accessibilityStatus,
                    action: { permissions.requestAccessibility() }
                )

                // Input Monitoring
                permissionCard(
                    icon: "eye.fill",
                    title: "Input Monitoring",
                    description: "Required to capture keyboard/mouse input for remapping",
                    status: permissions.inputMonitoringStatus,
                    action: { permissions.requestInputMonitoring() }
                )

                // RGB (no permission needed)
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.razerGreen)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.razerGreenSubtle))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RGB Lighting")
                            .font(RazerFont.heading(13))
                            .foregroundColor(.razerTextPrimary)
                        Text("No permissions needed — works immediately")
                            .font(RazerFont.caption(11))
                            .foregroundColor(.razerTextTertiary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.razerSuccess)
                }
                .padding(12)
                .razerCard(padding: 0)
            }
            .padding(.horizontal, 40)

            Button("Refresh Status") {
                permissions.checkAll()
            }
            .buttonStyle(.razerSecondary)

            Spacer()
        }
    }

    private func permissionCard(icon: String, title: String, description: String,
                                status: PermissionStatus, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(status.isGranted ? .razerSuccess : .razerWarning)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(status.isGranted ? Color.razerSuccess.opacity(0.15) : Color.razerWarning.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RazerFont.heading(13))
                    .foregroundColor(.razerTextPrimary)
                Text(description)
                    .font(RazerFont.caption(10))
                    .foregroundColor(.razerTextTertiary)
                    .lineLimit(2)
            }

            Spacer()

            if status.isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.razerSuccess)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.razerPrimary)
            }
        }
        .padding(12)
        .razerCard(isSelected: !status.isGranted, padding: 0)
    }

    // MARK: - Step 4: Complete

    private var completeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundColor(.razerGreen)
                .razerGlow(radius: 12)

            Text("You're All Set!")
                .font(RazerFont.title(22))
                .foregroundColor(.razerTextPrimary)

            VStack(alignment: .leading, spacing: 8) {
                statusRow("Devices", value: "\(deviceManager.devices.count) connected",
                          ok: deviceManager.hasDevices)
                statusRow("RGB Lighting", value: "Ready", ok: true)
                statusRow("Key Remapping", value: permissions.canUseKeyMapping ? "Ready" : "Permissions needed",
                          ok: permissions.canUseKeyMapping)
            }
            .padding(.horizontal, 60)

            if !permissions.canUseKeyMapping {
                Text("You can still use RGB lighting and DPI settings.\nGrant permissions later in Settings to enable key remapping.")
                    .font(RazerFont.caption(11))
                    .foregroundColor(.razerTextTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    private func statusRow(_ label: String, value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(ok ? .razerSuccess : .razerWarning)
            Text(label)
                .font(RazerFont.body(13))
                .foregroundColor(.razerTextPrimary)
            Spacer()
            Text(value)
                .font(RazerFont.caption(11))
                .foregroundColor(.razerTextSecondary)
        }
    }

    // MARK: - Footer Navigation

    private var wizardFooter: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
                .buttonStyle(.razerSecondary)
            }

            Spacer()

            if currentStep == 2 {
                // On permissions step, allow skipping
                Button("Skip") {
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.razerSecondary)
            }

            if currentStep < 3 {
                Button("Next") {
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.razerPrimary)
            } else {
                Button("Get Started") {
                    isPresented = false
                }
                .buttonStyle(.razerPrimary)
            }
        }
        .padding(16)
    }
}
