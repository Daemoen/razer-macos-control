import SwiftUI

/// A device photograph or illustration with its physical controls made live.
///
/// Two jobs. Clicking a control opens its mapping editor. Physically pressing a
/// control on the hardware lights it here -- the daemon forwards HID usages to
/// DeviceManager.pressedKeyboardUsages, and anything in that set glows. That
/// makes "which key is this?" answerable by pressing it, which is the whole
/// reason to draw the device rather than list it.
///
/// Geometry follows DEVICE_ART_SPEC.md §5: aspect-fit, centred, never cropped
/// or stretched, hotspots placed from normalised coordinates.
struct DeviceArtView: View {
    let image: Image
    let map: DeviceArtMap

    /// Resolves a control id to the HID usage the hardware reports. Supplied by
    /// the caller so the codes stay owned by whoever already defines them --
    /// a second table here would be a second thing to drift.
    let hidCode: (String) -> UInt8?

    /// Controls that currently carry a user mapping.
    let isMapped: (String) -> Bool

    /// Short label printed on the control -- its number or name.
    let label: (String) -> String

    /// The control's current binding, printed beneath the label.
    let assignment: (String) -> String

    /// Usages currently held down on the hardware.
    let pressed: Set<UInt8>

    let onSelect: (String) -> Void

    @State private var hovered: String?

    var body: some View {
        GeometryReader { geometry in
            let fit = Self.fit(image: map.imageSize,
                               into: geometry.size,
                               aspect: map.aspect)

            ZStack(alignment: .topLeading) {
                image
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fit.width, height: fit.height)
                    .offset(x: fit.x, y: fit.y)

                ForEach(map.controls) { control in
                    if let bounds = control.bounds(aspect: map.aspect) {
                        hotspot(control, bounds: bounds, fit: fit)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height,
                   alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func hotspot(_ control: DeviceArtMap.Control,
                         bounds: CGRect,
                         fit: Fit) -> some View {
        let frame = CGRect(x: fit.x + bounds.minX * fit.width,
                           y: fit.y + bounds.minY * fit.height,
                           width: bounds.width * fit.width,
                           height: bounds.height * fit.height)

        let isPressed = hidCode(control.id).map { pressed.contains($0) } ?? false
        let isHovered = hovered == control.id
        let mapped = isMapped(control.id)
        let radius: CGFloat = control.shape == .circle
            ? min(frame.width, frame.height) / 2
            : max(3, min(frame.width, frame.height) * 0.18)

        // Type scales with the control so the same artwork stays legible whether
        // it is drawn in the configuration pane or a thumbnail preview.
        let titleSize = max(6, min(15, frame.height * 0.30))
        let valueSize = max(5, min(11, frame.height * 0.21))
        let showValue = frame.height >= 26

        // A Button rather than a tap gesture: a shape filled with .clear does
        // not take hits on its own, and Button is the pattern already proven
        // elsewhere in this view layer.
        Button { onSelect(control.id) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: radius)
                    .fill(fillColour(pressed: isPressed, hovered: isHovered, mapped: mapped))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .strokeBorder(strokeColour(pressed: isPressed,
                                                       hovered: isHovered,
                                                       mapped: mapped),
                                          lineWidth: isPressed ? 2.5 : (isHovered ? 1.8 : 1.2))
                    )

                let title = label(control.id)
                VStack(spacing: 0) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.system(size: titleSize, weight: .bold, design: .rounded))
                            .foregroundColor(isPressed ? .black : .razerTextPrimary)
                        if showValue {
                            Text(assignment(control.id))
                                .font(.system(size: valueSize, weight: .medium, design: .rounded))
                                .foregroundColor(isPressed ? .black.opacity(0.75)
                                                 : (mapped ? .razerGreen : .razerTextTertiary))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                }
                .padding(.horizontal, 2)
                // The artwork carries its own moulding lines and legends. A
                // slight scrim keeps the label readable where it lands on one,
                // without hiding the control underneath it.
                .background(
                    RoundedRectangle(cornerRadius: radius * 0.7)
                        .fill(Color.black.opacity(title.isEmpty || isPressed ? 0 : 0.42))
                        .blur(radius: 2)
                        .padding(-1)
                )
                .shadow(color: .black.opacity(title.isEmpty || isPressed ? 0 : 0.8), radius: 1.5)
            }
            .frame(width: frame.width, height: frame.height)
            .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .shadow(color: isPressed ? Color.razerGreen.opacity(0.9) : .clear,
                radius: isPressed ? 10 : 0)
        .offset(x: frame.minX, y: frame.minY)
        .animation(.easeOut(duration: isPressed ? 0.04 : 0.16), value: isPressed)
        .onHover { inside in
            if inside { hovered = control.id }
            else if hovered == control.id { hovered = nil }
        }
        .help("\(label(control.id)) — \(assignment(control.id))")
    }

    private func fillColour(pressed: Bool, hovered: Bool, mapped: Bool) -> Color {
        if pressed { return Color.razerGreen.opacity(0.55) }
        if hovered { return Color.razerGreen.opacity(0.18) }
        if mapped  { return Color.razerGreen.opacity(0.10) }
        return .clear
    }

    private func strokeColour(pressed: Bool, hovered: Bool, mapped: Bool) -> Color {
        if pressed { return Color.razerGreen }
        if hovered { return Color.razerGreen.opacity(0.75) }
        if mapped  { return Color.razerGreen.opacity(0.45) }
        return .clear
    }

    // MARK: - Geometry

    struct Fit {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
    }

    /// Aspect-fit and centre, per spec §5.1.
    static func fit(image size: DeviceArtMap.ImageSize?,
                    into box: CGSize,
                    aspect: Double) -> Fit {
        let imageAspect: CGFloat = size.map { CGFloat($0.width) / CGFloat($0.height) }
            ?? CGFloat(aspect)
        guard imageAspect > 0, box.width > 0, box.height > 0 else {
            return Fit(x: 0, y: 0, width: box.width, height: box.height)
        }
        let boxAspect = box.width / box.height
        let width  = imageAspect > boxAspect ? box.width  : box.height * imageAspect
        let height = imageAspect > boxAspect ? box.width / imageAspect : box.height
        return Fit(x: (box.width - width) / 2,
                   y: (box.height - height) / 2,
                   width: width, height: height)
    }
}
