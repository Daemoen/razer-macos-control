import SwiftUI

// MARK: - Razer Color Palette

extension Color {
    // Primary brand
    static let razerGreen = Color(red: 0.0, green: 1.0, blue: 0.0)
    static let razerGreenDim = Color(red: 0.0, green: 0.7, blue: 0.0)
    static let razerGreenSubtle = Color(red: 0.0, green: 1.0, blue: 0.0).opacity(0.15)

    // Backgrounds (darkest to lightest)
    static let razerBg = Color(red: 0.04, green: 0.04, blue: 0.06)           // #0A0A0F
    static let razerSurface = Color(red: 0.08, green: 0.08, blue: 0.12)      // #14141F
    static let razerSurfaceLight = Color(red: 0.11, green: 0.11, blue: 0.16) // #1C1C29
    static let razerSurfaceHover = Color(red: 0.14, green: 0.14, blue: 0.20) // #242433
    static let razerBorder = Color.white.opacity(0.08)
    static let razerBorderActive = Color.razerGreen.opacity(0.4)

    // Text
    static let razerTextPrimary = Color.white.opacity(0.95)
    static let razerTextSecondary = Color.white.opacity(0.55)
    static let razerTextTertiary = Color.white.opacity(0.30)

    // Status
    static let razerSuccess = Color(red: 0.2, green: 0.85, blue: 0.4)
    static let razerWarning = Color(red: 1.0, green: 0.75, blue: 0.0)
    static let razerError = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let razerInfo = Color(red: 0.3, green: 0.6, blue: 1.0)
}

// MARK: - Typography

struct RazerFont {
    static func title(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
    static func heading(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
    static func mono(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - Card Style

struct RazerCardModifier: ViewModifier {
    var isSelected: Bool = false
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.razerSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color.razerBorderActive : Color.razerBorder,
                                lineWidth: 1
                            )
                    )
            )
    }
}

extension View {
    func razerCard(isSelected: Bool = false, padding: CGFloat = 16) -> some View {
        modifier(RazerCardModifier(isSelected: isSelected, padding: padding))
    }
}

// MARK: - Glow Effect

struct GlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.6) : .clear, radius: radius)
            .shadow(color: isActive ? color.opacity(0.3) : .clear, radius: radius * 2)
    }
}

extension View {
    func razerGlow(color: Color = .razerGreen, radius: CGFloat = 8, isActive: Bool = true) -> some View {
        modifier(GlowModifier(color: color, radius: radius, isActive: isActive))
    }
}

// MARK: - Button Styles

struct RazerPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RazerFont.heading(13))
            .foregroundColor(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        configuration.isPressed
                            ? Color.razerGreenDim
                            : Color.razerGreen
                    )
            )
            .razerGlow(radius: 4, isActive: !configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RazerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RazerFont.heading(13))
            .foregroundColor(.razerTextPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.razerSurfaceLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.razerBorder, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RazerPrimaryButtonStyle {
    static var razerPrimary: RazerPrimaryButtonStyle { RazerPrimaryButtonStyle() }
}

extension ButtonStyle where Self == RazerSecondaryButtonStyle {
    static var razerSecondary: RazerSecondaryButtonStyle { RazerSecondaryButtonStyle() }
}

// MARK: - Section Header

struct RazerSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(RazerFont.heading(14))
                .foregroundColor(.razerTextPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(RazerFont.caption())
                    .foregroundColor(.razerTextSecondary)
            }
        }
    }
}

// MARK: - Tab Item Style

struct RazerTabItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .razerGreen : .razerTextSecondary)

                Text(label)
                    .font(RazerFont.caption(10))
                    .foregroundColor(isSelected ? .razerGreen : .razerTextSecondary)
            }
            .frame(width: 72, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.razerGreenSubtle : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

struct RazerStatusBadge: View {
    enum Status { case connected, disconnected, warning }

    let status: Status
    let label: String

    var color: Color {
        switch status {
        case .connected: return .razerSuccess
        case .disconnected: return .razerTextTertiary
        case .warning: return .razerWarning
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .razerGlow(color: color, radius: 3, isActive: status == .connected)
            Text(label)
                .font(RazerFont.caption())
                .foregroundColor(.razerTextSecondary)
        }
    }
}
