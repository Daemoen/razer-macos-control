import SwiftUI

enum AppTab: String, CaseIterable {
    case keyboard = "Keyboard"
    case mouse = "Mouse"
    case lighting = "Lighting"
    case profiles = "Profiles"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .lighting: return "lightbulb.fill"
        case .profiles: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selectedTab: AppTab = .keyboard

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Rectangle().fill(Color.razerBorder).frame(width: 1)

            ZStack {
                Color.razerBg.ignoresSafeArea()
                Group {
                    switch selectedTab {
                    case .keyboard: KeyboardView()
                    case .mouse:    MouseView()
                    case .lighting: LightingView()
                    case .profiles: PlaceholderTab(name: "Profiles", icon: "person.crop.circle")
                    case .settings: PlaceholderTab(name: "Settings", icon: "gearshape")
                    }
                }
                .transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
        }
        .background(Color.razerBg)
        .ignoresSafeArea()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Logo
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.razerGreen)
                        .razerGlow(radius: 6)
                    Text("RAZERCONTROL")
                        .font(.system(size: 14, weight: .black))
                        .tracking(2)
                        .foregroundColor(.razerTextPrimary)
                }
                .padding(.top, 24)
                Text("Open Source")
                    .font(RazerFont.caption(9))
                    .foregroundColor(.razerTextTertiary)
                    .tracking(1.5)
            }
            .padding(.bottom, 20)

            // Device selector (real devices)
            deviceSelector
                .padding(.horizontal, 12)
                .padding(.bottom, 16)

            Divider().background(Color.razerBorder).padding(.horizontal, 16)

            // Tabs
            VStack(spacing: 2) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    sidebarItem(tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()

            // Status
            VStack(spacing: 8) {
                Divider().background(Color.razerBorder).padding(.horizontal, 16)

                if let device = deviceManager.selectedDevice {
                    RazerStatusBadge(status: .connected, label: "\(device.name)")
                        .padding(.horizontal, 16)

                    if let fw = device.firmwareVersion {
                        Text("FW: \(fw)")
                            .font(RazerFont.mono(9))
                            .foregroundColor(.razerTextTertiary)
                    }
                } else if deviceManager.isScanning {
                    RazerStatusBadge(status: .warning, label: "Scanning...")
                        .padding(.horizontal, 16)
                } else {
                    RazerStatusBadge(status: .disconnected, label: "No device")
                        .padding(.horizontal, 16)
                }

                if let err = deviceManager.lastError {
                    Text(err)
                        .font(RazerFont.caption(9))
                        .foregroundColor(.razerError)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                }

                Text("v0.1.0-alpha")
                    .font(RazerFont.caption(9))
                    .foregroundColor(.razerTextTertiary)
            }
            .padding(.bottom, 16)
        }
        .background(Color.razerSurface.opacity(0.5))
    }

    // MARK: - Device Selector

    private var deviceSelector: some View {
        Menu {
            if deviceManager.devices.isEmpty {
                Text("No Razer devices found")
            } else {
                ForEach(deviceManager.devices) { device in
                    Button {
                        deviceManager.selectedDevice = device
                    } label: {
                        Label {
                            Text(device.name)
                        } icon: {
                            Image(systemName: device.icon)
                        }
                    }
                }
            }
            Divider()
            Button("Rescan") {
                deviceManager.stopScanning()
                deviceManager.startScanning()
            }
        } label: {
            HStack(spacing: 10) {
                if let device = deviceManager.selectedDevice {
                    Image(systemName: device.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.razerGreen)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.razerGreenSubtle))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name)
                            .font(RazerFont.caption(12))
                            .foregroundColor(.razerTextPrimary)
                            .lineLimit(1)
                        Text(device.type.rawValue.capitalized)
                            .font(RazerFont.caption(10))
                            .foregroundColor(.razerTextTertiary)
                    }
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.razerTextSecondary)
                    Text(deviceManager.isScanning ? "Scanning..." : "No Device")
                        .font(RazerFont.caption(12))
                        .foregroundColor(.razerTextSecondary)
                }

                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.razerTextTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.razerSurfaceLight)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.razerBorder, lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func sidebarItem(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedTab == tab ? .razerGreen : .razerTextSecondary)
                    .frame(width: 20)
                Text(tab.rawValue)
                    .font(RazerFont.body(13))
                    .foregroundColor(selectedTab == tab ? .razerTextPrimary : .razerTextSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selectedTab == tab ? Color.razerGreenSubtle : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Placeholder

struct PlaceholderTab: View {
    let name: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .thin))
                .foregroundColor(.razerTextTertiary)
            Text(name).font(RazerFont.heading(18)).foregroundColor(.razerTextSecondary)
            Text("Coming soon").font(RazerFont.caption()).foregroundColor(.razerTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
