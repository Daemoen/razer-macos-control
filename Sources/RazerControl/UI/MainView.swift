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
    @State private var selectedTab: AppTab = .keyboard
    @State private var selectedDevice: MockDevice? = MockDevice.samples.first

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 220)

            // Divider
            Rectangle()
                .fill(Color.razerBorder)
                .frame(width: 1)

            // Content
            ZStack {
                Color.razerBg.ignoresSafeArea()

                Group {
                    switch selectedTab {
                    case .keyboard:
                        KeyboardView()
                    case .mouse:
                        MouseView()
                    case .lighting:
                        LightingView()
                    case .profiles:
                        PlaceholderTab(name: "Profiles", icon: "person.crop.circle")
                    case .settings:
                        PlaceholderTab(name: "Settings", icon: "gearshape")
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
            // Logo area
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    // Razer triple-snake icon approximation
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.razerGreen)
                        .razerGlow(radius: 6)

                    Text("RAZERCONTROL")
                        .font(.system(size: 14, weight: .black, design: .default))
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

            // Device selector
            deviceSelector
                .padding(.horizontal, 12)
                .padding(.bottom, 16)

            Divider()
                .background(Color.razerBorder)
                .padding(.horizontal, 16)

            // Navigation
            VStack(spacing: 2) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    sidebarItem(tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()

            // Status bar
            VStack(spacing: 8) {
                Divider()
                    .background(Color.razerBorder)
                    .padding(.horizontal, 16)

                if let device = selectedDevice {
                    RazerStatusBadge(
                        status: .connected,
                        label: "\(device.name) connected"
                    )
                    .padding(.horizontal, 16)
                } else {
                    RazerStatusBadge(
                        status: .disconnected,
                        label: "No device connected"
                    )
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

    private var deviceSelector: some View {
        Menu {
            ForEach(MockDevice.samples) { device in
                Button {
                    selectedDevice = device
                } label: {
                    Label(device.name, systemImage: device.icon)
                }
            }
            Divider()
            Button("Scan for Devices...") {}
        } label: {
            HStack(spacing: 10) {
                if let device = selectedDevice {
                    Image(systemName: device.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.razerGreen)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.razerGreenSubtle)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name)
                            .font(RazerFont.caption(12))
                            .foregroundColor(.razerTextPrimary)
                            .lineLimit(1)
                        Text(device.type)
                            .font(RazerFont.caption(10))
                            .foregroundColor(.razerTextTertiary)
                    }
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.razerTextSecondary)
                    Text("Select Device")
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.razerBorder, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func sidebarItem(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedTab = tab
            }
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == tab ? Color.razerGreenSubtle : Color.clear)
            )
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
            Text(name)
                .font(RazerFont.heading(18))
                .foregroundColor(.razerTextSecondary)
            Text("Coming soon")
                .font(RazerFont.caption())
                .foregroundColor(.razerTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mock Data

struct MockDevice: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let icon: String

    static let samples = [
        MockDevice(name: "BlackWidow V4 Pro", type: "Keyboard", icon: "keyboard"),
        MockDevice(name: "Pro Click V2 Vertical", type: "Mouse", icon: "computermouse"),
    ]
}
