import SwiftUI
import AppKit

/// Rasterises the device views to PNG files without showing a window.
///
/// Visual work needs a feedback loop, and the alternative -- screen-capturing a
/// live session -- needs Screen Recording authorisation over someone's personal
/// desktop. This needs no authorisation at all.
///
/// It is read-only with respect to hardware: discovery goes through
/// RazerHIDManager, which reads the IORegistry and never opens an HID device or
/// writes a feature report. Nothing here can change how a device behaves.
///
/// Run with:  RazerControl --render-device-art <output-directory>
@MainActor
enum DeviceArtRenderer {
    private struct Shot {
        let file: String
        let width: CGFloat
        let height: CGFloat
        let pid: UInt16?
        let build: (DeviceManager) -> AnyView
    }

    static func run(outputDirectory: String) -> (passed: Bool, report: String) {
        var lines: [String] = []
        do {
            try FileManager.default.createDirectory(atPath: outputDirectory,
                                                    withIntermediateDirectories: true)
        } catch {
            return (false, "FAIL could not create \(outputDirectory): \(error)")
        }

        let manager = DeviceManager()
        manager.startScanning()
        // Discovery publishes through Combine on the main queue, so the run loop
        // has to turn before `devices` is populated.
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))

        lines.append("Discovered \(manager.devices.count) device(s): "
                     + manager.devices.map { String(format: "%@ (0x%04X)", $0.name, Int($0.pid)) }
                                      .joined(separator: ", "))

        // Usages to report as held, so a static render can show the press
        // highlight. Key 08, key 13 and the D-pad Up direction.
        let simulatedPresses: Set<UInt8> = [0x1A, 0x16, 0x52]

        let shots: [Shot] = [
            .init(file: "keyboard-orbweaver-config", width: 1080, height: 720, pid: 0x0207,
                  build: { AnyView(KeyboardView().environmentObject($0)) }),
            .init(file: "keyboard-orbweaver-pressed", width: 1080, height: 720, pid: 0x0207,
                  build: { manager in
                      manager.pressedKeyboardUsages = simulatedPresses
                      return AnyView(KeyboardView().environmentObject(manager))
                  }),
            .init(file: "lighting-orbweaver", width: 1080, height: 720, pid: 0x0207,
                  build: { AnyView(LightingView().environmentObject($0)) }),
            // Two frames of the same wave, a third of a cycle apart. If the
            // effect really crosses the keys these differ per key; a whole-image
            // tint would differ only in overall hue.
            .init(file: "lighting-orbweaver-wave-a", width: 1080, height: 720, pid: 0x0207,
                  build: { AnyView(LightingView(previewEffect: .wave, previewPhase: 0.0)
                                    .environmentObject($0)) }),
            .init(file: "lighting-orbweaver-wave-b", width: 1080, height: 720, pid: 0x0207,
                  build: { AnyView(LightingView(previewEffect: .wave, previewPhase: 1.1)
                                    .environmentObject($0)) }),
            .init(file: "keyboard-blackwidow-config", width: 1080, height: 720, pid: 0x024E,
                  build: { AnyView(KeyboardView().environmentObject($0)) }),
            .init(file: "lighting-blackwidow", width: 1080, height: 720, pid: 0x024E,
                  build: { AnyView(LightingView().environmentObject($0)) }),
            .init(file: "mouse-viper-config", width: 1080, height: 720, pid: 0x007B,
                  build: { AnyView(MouseView().environmentObject($0)) }),
            .init(file: "lighting-viper", width: 1080, height: 720, pid: 0x007B,
                  build: { AnyView(LightingView().environmentObject($0)) }),
            .init(file: "lighting-dock", width: 1080, height: 720, pid: 0x007E,
                  build: { AnyView(LightingView().environmentObject($0)) }),
            .init(file: "lighting-kraken", width: 1080, height: 720, pid: 0x0F19,
                  build: { AnyView(LightingView().environmentObject($0)) }),
        ]

        var wrote = 0, skipped = 0, blank = 0

        for shot in shots {
            if let pid = shot.pid {
                // Prefer the real attached device, but fall back to a stand-in
                // built from the device database. Layout does not depend on the
                // hardware being present, and requiring it means a view cannot
                // be reviewed whenever the peripheral is unplugged -- or, for a
                // device we are adding support for, has never been plugged in.
                let device = manager.devices.first(where: { $0.pid == pid })
                    ?? Self.standIn(for: pid)
                guard let device else {
                    lines.append(String(format: "  SKIP  %@ (0x%04X unknown to the device database)",
                                        shot.file, Int(pid)))
                    skipped += 1
                    continue
                }
                if !manager.devices.contains(where: { $0.pid == pid }) {
                    lines.append(String(format: "  note  0x%04X not attached; rendering from database",
                                        Int(pid)))
                    manager.devices.append(device)
                }
                manager.selectedDevice = device
            }

            if !shot.file.hasSuffix("-pressed") { manager.pressedKeyboardUsages = [] }
            let content = shot.build(manager)
                .frame(width: shot.width, height: shot.height)
                .background(Color.razerBg)
                .preferredColorScheme(.dark)

            guard let rep = snapshot(content, width: shot.width, height: shot.height) else {
                lines.append("  FAIL  \(shot.file): offscreen render produced nothing")
                continue
            }

            // A previous version of this tool used ImageRenderer, which returned
            // a correctly-sized image containing only the background colour and
            // reported success. Uniform output is therefore treated as failure,
            // not as a render.
            let distinct = distinctColourCount(rep)
            if distinct < 8 {
                lines.append("  BLANK \(shot.file): only \(distinct) distinct colour(s) — view did not lay out")
                blank += 1
                continue
            }

            guard let png = rep.representation(using: .png, properties: [:]) else {
                lines.append("  FAIL  \(shot.file): PNG encode failed")
                continue
            }
            let path = (outputDirectory as NSString).appendingPathComponent(shot.file + ".png")
            do {
                try png.write(to: URL(fileURLWithPath: path))
                lines.append(String(format: "  OK    %@.png  %dx%d  %d colours  %.0f KB",
                                    shot.file, rep.pixelsWide, rep.pixelsHigh, distinct,
                                    Double(png.count) / 1024.0))
                wrote += 1
            } catch {
                lines.append("  FAIL  \(shot.file): \(error)")
            }
        }

        lines.append("Wrote \(wrote), blank \(blank), skipped \(skipped) -> \(outputDirectory)")
        // Any blank is a failure of the tool, not of the art.
        return (wrote > 0 && blank == 0, lines.joined(separator: "\n"))
    }

    /// A ConnectedDevice assembled from the database rather than from USB.
    /// Carries no HID interfaces, so it can describe a device but not talk to
    /// one -- which is all a layout render needs.
    private static func standIn(for productID: UInt16) -> ConnectedDevice? {
        guard let info = DeviceDatabase.shared.lookup(pid: productID) else { return nil }
        let placeholder = RazerHIDDevice(vendorId: 0x1532,
                                         productId: productID,
                                         productName: info.name,
                                         serialNumber: "render-only")
        return ConnectedDevice(hidDevice: placeholder, info: info)
    }

    /// Renders through a real NSHostingView inside an offscreen window.
    ///
    /// Two things are load-bearing here. SwiftUI needs an *attached* view
    /// hierarchy to run a full layout pass -- detached rendering silently
    /// produces empty content for ScrollView and GeometryReader layouts, which
    /// is most of this app. And the pixels must be read off the layer tree
    /// rather than through `cacheDisplay(in:to:)`: SwiftUI expresses effects
    /// like `rotation3DEffect` as layer transforms, and the cacheDisplay path
    /// draws the view's own content without them, so transformed subviews go
    /// missing while everything around them renders correctly.
    private static func snapshot<V: View>(_ view: V,
                                          width: CGFloat,
                                          height: CGFloat,
                                          scale: CGFloat = 2.0) -> NSBitmapImageRep? {
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = frame
        hosting.wantsLayer = true

        let window = NSWindow(contentRect: frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))  // never visible
        window.orderFront(nil)
        window.displayIfNeeded()

        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI resolve the hierarchy and any observed-object updates
        // before the pixels are read.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        defer { window.orderOut(nil) }

        guard let layer = hosting.layer else { return nil }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(width * scale),
                                         pixelsHigh: Int(height * scale),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: height)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        // The rep is `scale` times larger in pixels than its point size, and
        // NSGraphicsContext already maps points onto those pixels -- scaling
        // again here would zoom the output. CALayer.render(in:) draws with a
        // top-left origin, so the only transform needed is a vertical flip.
        cg.translateBy(x: 0, y: height)
        cg.scaleBy(x: 1, y: -1)
        layer.render(in: cg)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Sparse sample of distinct colours; enough to tell "rendered" from "flat fill".
    private static func distinctColourCount(_ rep: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        let stepX = max(1, rep.pixelsWide / 120)
        let stepY = max(1, rep.pixelsHigh / 120)
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                let r = UInt32(max(0, min(255, colour.redComponent * 255)))
                let g = UInt32(max(0, min(255, colour.greenComponent * 255)))
                let b = UInt32(max(0, min(255, colour.blueComponent * 255)))
                seen.insert(r << 16 | g << 8 | b)
                if seen.count >= 64 { return seen.count }
            }
        }
        return seen.count
    }
}
