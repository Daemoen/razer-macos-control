import SwiftUI
import AppKit

/// Photographs of the actual hardware, keyed by USB product ID.
///
/// These are pictures of the devices this install talks to, taken by their
/// owner. Drawn approximations of real hardware never resembled the real
/// hardware, and no openly-licensed photographs of these particular peripherals
/// exist -- Polychromatic's device art is GPLv3 against this project's GPLv2 and
/// covers none of these models anyway. Photographs taken by the person who owns
/// the device carry no third-party rights at all, which is why they are the
/// source used here.
///
/// Scope is deliberately narrow: one image per device that is actually in use.
/// Devices without a photograph fall through to the drawn representation.
enum DeviceArt {
    private static let byProductID: [UInt16: String] = [
        0x0207: "orbweaver",        // Orbweaver Chroma
        0x0208: "tartarus",         // Tartarus V2
        0x0244: "tartarus",         // Tartarus Pro -- same shell
        0x007B: "viper-ultimate",   // Viper Ultimate (wireless)
        0x007C: "viper-ultimate",   // Viper Ultimate (wired)
    ]

    /// Cached because SwiftUI rebuilds these views constantly and decoding a
    /// megapixel PNG on every layout pass is not free.
    private static var cache: [String: NSImage] = [:]

    static func image(for productID: UInt16) -> Image? {
        guard let name = byProductID[productID] else { return nil }
        if let cached = cache[name] { return Image(nsImage: cached) }
        guard let url = Bundle.module.url(forResource: name,
                                          withExtension: "png",
                                          subdirectory: "Devices")
                ?? Bundle.module.url(forResource: name, withExtension: "png"),
              let loaded = NSImage(contentsOf: url) else { return nil }
        cache[name] = loaded
        return Image(nsImage: loaded)
    }

    static func hasArt(for productID: UInt16) -> Bool {
        byProductID[productID] != nil
    }

    /// Renders the photograph to fit a box without cropping or distorting it.
    /// The device keeps its own proportions; the surrounding space is empty.
    @ViewBuilder
    static func view(for productID: UInt16, maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        if let image = image(for: productID) {
            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        }
    }
}
