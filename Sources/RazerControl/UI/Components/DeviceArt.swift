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
        0x0207: "0207",             // Orbweaver Chroma -- clean-room schematic + hotspot map
        0x0208: "tartarus",         // Tartarus V2
        0x0244: "tartarus",         // Tartarus Pro -- same shell
        0x007B: "viper-ultimate",   // Viper Ultimate (wireless)
        0x007C: "viper-ultimate",   // Viper Ultimate (wired)
    ]

    /// Cached because SwiftUI rebuilds these views constantly and decoding a
    /// megapixel PNG on every layout pass is not free.
    private static var cache: [String: NSImage] = [:]

    /// Where a user may drop their own artwork, outside the app bundle.
    ///
    /// Files here take precedence over anything shipped, and nothing here is
    /// ever redistributed -- it is not in the repository and not in the bundle.
    /// That separation is the point. This project is GPLv2, and the GPL requires
    /// every part of the distributed work to be licensable under its terms, so
    /// artwork whose rights we do not hold cannot ship with it at any price.
    /// What someone installs on their own machine, from software they have
    /// licensed, is a different question and their own to answer.
    ///
    /// Name each file for the device's product ID in lowercase hex:
    ///     ~/Library/Application Support/RazerControl/DeviceArt/0207.png
    ///
    /// Transparent PNG works best against the dark UI; an opaque image renders
    /// as a rectangle.
    static var userArtDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RazerControl/DeviceArt",
                                    isDirectory: true)
    }

    private static func userArtURL(for productID: UInt16) -> URL? {
        let url = userArtDirectory
            .appendingPathComponent(String(format: "%04x.png", productID))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func bundledArtURL(for productID: UInt16) -> URL? {
        guard let name = byProductID[productID] else { return nil }
        return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Devices")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
    }

    static func image(for productID: UInt16) -> Image? {
        let key = String(format: "%04x", productID)
        if let cached = cache[key] { return Image(nsImage: cached) }
        // User-supplied art wins over anything shipped.
        guard let url = userArtURL(for: productID) ?? bundledArtURL(for: productID),
              let loaded = NSImage(contentsOf: url) else { return nil }
        cache[key] = loaded
        return Image(nsImage: loaded)
    }

    /// Basename of the shipped asset, if any. The hotspot map is looked up
    /// under the same name so artwork and map always travel together.
    static func bundledName(for productID: UInt16) -> String? {
        byProductID[productID]
    }

    static func hasArt(for productID: UInt16) -> Bool {
        userArtURL(for: productID) != nil || byProductID[productID] != nil
    }

    /// Clears the decode cache so a replaced file is picked up without a relaunch.
    static func reloadUserArt() {
        cache.removeAll()
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
