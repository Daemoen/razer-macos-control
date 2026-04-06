import Foundation
import CoreGraphics
import AppKit
import ColorSync

// MARK: - Space Switcher (Private SkyLight API)
//
// Switches macOS Spaces/Desktops using the private SkyLight framework.
// Detects which display the mouse cursor is on and switches spaces
// on THAT display. Works with multiple monitors.

class SpaceSwitcher {
    private var handle: UnsafeMutableRawPointer?
    private var getConn: (@convention(c) () -> Int)?
    private var getActive: (@convention(c) (Int) -> Int)?
    private var copySpaces: (@convention(c) (Int) -> CFArray?)?
    private var setSpace: (@convention(c) (Int, CFString, Int) -> Void)?

    static let shared = SpaceSwitcher()

    private init() {
        handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        guard let h = handle else {
            print("[SpaceSwitcher] Failed to load SkyLight framework")
            return
        }

        if let s = dlsym(h, "SLSMainConnectionID") {
            getConn = unsafeBitCast(s, to: (@convention(c) () -> Int).self)
        }
        if let s = dlsym(h, "SLSGetActiveSpace") {
            getActive = unsafeBitCast(s, to: (@convention(c) (Int) -> Int).self)
        }
        if let s = dlsym(h, "SLSCopyManagedDisplaySpaces") {
            copySpaces = unsafeBitCast(s, to: (@convention(c) (Int) -> CFArray?).self)
        }
        if let s = dlsym(h, "SLSManagedDisplaySetCurrentSpace") {
            setSpace = unsafeBitCast(s, to: (@convention(c) (Int, CFString, Int) -> Void).self)
        }

        print("[SpaceSwitcher] Initialized: \(isAvailable ? "OK" : "FAILED")")
    }

    var isAvailable: Bool {
        getConn != nil && getActive != nil && copySpaces != nil && setSpace != nil
    }

    private func connection() -> Int { getConn?() ?? 0 }
    private func activeSpace() -> Int { getActive?(connection()) ?? 0 }

    // MARK: - All Displays Info

    private struct DisplayInfo {
        let uuid: String
        let spaceIDs: [Int]
    }

    private func allDisplays() -> [DisplayInfo] {
        guard let copyFn = copySpaces else { return [] }
        guard let displays = copyFn(connection()) as? [[String: Any]] else { return [] }

        return displays.compactMap { display in
            guard let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
            let ids = spaces.compactMap { $0["id64"] as? Int }
            let uuid = display["Display Identifier"] as? String ?? ""
            guard !ids.isEmpty else { return nil }
            return DisplayInfo(uuid: uuid, spaceIDs: ids)
        }
    }

    /// Find which display the mouse cursor is on
    private func displayUnderCursor() -> DisplayInfo? {
        let mouseLocation = NSEvent.mouseLocation
        let displays = allDisplays()

        // Get all CGDisplay IDs and match to the one containing the cursor
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)

        for i in 0..<Int(displayCount) {
            let bounds = CGDisplayBounds(displayIDs[i])
            // NSEvent.mouseLocation uses bottom-left origin, CGDisplay uses top-left
            let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
            let flippedY = screenHeight - mouseLocation.y

            if bounds.contains(CGPoint(x: mouseLocation.x, y: flippedY)) {
                // Found the display — now match it to a DisplayInfo by UUID
                guard let cgUUID = CGDisplayCreateUUIDFromDisplayID(displayIDs[i])?.takeUnretainedValue() else { continue }
                let uuidString = CFUUIDCreateString(nil, cgUUID) as String? ?? ""

                // Match by UUID or by index
                if let match = displays.first(where: { $0.uuid.contains(uuidString) || uuidString.contains($0.uuid) }) {
                    return match
                }
            }
        }

        // Fallback: use the display containing the active space
        let current = activeSpace()
        return displays.first { $0.spaceIDs.contains(current) }
    }

    /// Get spaces for the display under the cursor (or active display as fallback)
    private func currentDisplaySpaces() -> DisplayInfo? {
        // First try display under cursor
        if let underCursor = displayUnderCursor() {
            return underCursor
        }

        // Fallback: display with active space
        let current = activeSpace()
        return allDisplays().first { $0.spaceIDs.contains(current) }
    }

    // MARK: - Switch Space

    func switchToNextSpace() {
        guard let setFn = setSpace, let display = currentDisplaySpaces() else { return }
        let current = activeSpace()

        // Find current space on this display, or start from 0
        let idx = display.spaceIDs.firstIndex(of: current) ?? 0
        let nextIdx = (idx + 1) % display.spaceIDs.count
        let nextSpace = display.spaceIDs[nextIdx]

        setFn(connection(), display.uuid as CFString, nextSpace)
        print("[SpaceSwitcher] Next → space \(nextSpace) on display \(display.uuid.prefix(8))")
    }

    func switchToPreviousSpace() {
        guard let setFn = setSpace, let display = currentDisplaySpaces() else { return }
        let current = activeSpace()

        let idx = display.spaceIDs.firstIndex(of: current) ?? 0
        let prevIdx = idx > 0 ? idx - 1 : display.spaceIDs.count - 1
        let prevSpace = display.spaceIDs[prevIdx]

        setFn(connection(), display.uuid as CFString, prevSpace)
        print("[SpaceSwitcher] Prev → space \(prevSpace) on display \(display.uuid.prefix(8))")
    }

    func switchToSpace(index: Int) {
        guard let setFn = setSpace, let display = currentDisplaySpaces() else { return }
        guard index >= 0 && index < display.spaceIDs.count else { return }

        let targetSpace = display.spaceIDs[index]
        setFn(connection(), display.uuid as CFString, targetSpace)
        print("[SpaceSwitcher] Go to space \(index+1) → \(targetSpace)")
    }
}
