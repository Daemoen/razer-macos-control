import Foundation

/// A hotspot map: where each physical control sits on a device artwork.
///
/// Wire format is DEVICE_ART_SPEC.md v1.1. Coordinates are normalised against
/// the image's own dimensions, origin top-left, so a map survives any later
/// rescale of the artwork provided the crop does not change.
struct DeviceArtMap: Decodable {
    struct ImageSize: Decodable {
        let width: Int
        let height: Int
    }

    struct Control: Decodable, Identifiable {
        enum Shape: String, Decodable {
            case rect, circle
        }

        let id: String
        let shape: Shape

        // rect
        let x: Double?
        let y: Double?
        let w: Double?
        let h: Double?

        // circle -- note `r` is normalised against image WIDTH only, never
        // height. Normalised units are anisotropic on a non-square image, so a
        // radius expressed against both axes would describe an ellipse.
        let cx: Double?
        let cy: Double?
        let r: Double?

        /// Bounding box in normalised coordinates, whatever the shape.
        /// `aspect` is imageWidth / imageHeight, needed to convert a
        /// width-relative radius into height-relative units.
        func bounds(aspect: Double) -> CGRect? {
            switch shape {
            case .rect:
                guard let x, let y, let w, let h else { return nil }
                return CGRect(x: x, y: y, width: w, height: h)
            case .circle:
                guard let cx, let cy, let r else { return nil }
                let rv = r * aspect          // radius in height-relative units
                return CGRect(x: cx - r, y: cy - rv, width: 2 * r, height: 2 * rv)
            }
        }

        /// Hit test in normalised image space, per spec §5.2.
        func contains(u: Double, v: Double, aspect: Double) -> Bool {
            switch shape {
            case .rect:
                guard let x, let y, let w, let h else { return false }
                return u >= x && u < x + w && v >= y && v < y + h
            case .circle:
                guard let cx, let cy, let r else { return false }
                let dx = u - cx
                // Convert the vertical delta into width-relative units before
                // the distance test, since `r` is width-relative.
                let dy = (v - cy) / aspect
                return dx * dx + dy * dy <= r * r
            }
        }
    }

    let version: Int
    let productId: String
    let device: String?
    let image: String?
    let imageSize: ImageSize?
    let controls: [Control]

    var aspect: Double {
        guard let imageSize, imageSize.height > 0 else { return 1 }
        return Double(imageSize.width) / Double(imageSize.height)
    }

    /// Loads the map that accompanies a device artwork.
    ///
    /// User-supplied maps win over bundled ones, matching how DeviceArt
    /// resolves the image itself -- the two must come from the same place or a
    /// user's artwork would be drawn with the shipped artwork's hotspots.
    static func load(productID: UInt16, bundledName: String?) -> DeviceArtMap? {
        let hex = String(format: "%04x", productID)

        let userURL = DeviceArt.userArtDirectory.appendingPathComponent("\(hex).json")
        if FileManager.default.fileExists(atPath: userURL.path),
           let map = decode(userURL) {
            return map
        }

        guard let bundledName,
              let url = Bundle.module.url(forResource: bundledName,
                                          withExtension: "json",
                                          subdirectory: "Devices")
                ?? Bundle.module.url(forResource: bundledName, withExtension: "json")
        else { return nil }
        return decode(url)
    }

    private static func decode(_ url: URL) -> DeviceArtMap? {
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode(DeviceArtMap.self, from: data)
        else { return nil }
        // An unknown version means fields may have changed meaning. Falling back
        // to no hotspots leaves a readable picture; guessing does not.
        guard map.version == 1 else { return nil }
        return map
    }
}
