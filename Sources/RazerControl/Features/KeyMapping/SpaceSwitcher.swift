import Foundation
import CoreGraphics

// MARK: - Space Switcher (Private SkyLight API)
//
// Switches macOS Spaces/Desktops using the private SkyLight framework.
// CGEventPost cannot trigger Mission Control shortcuts, but this API
// can switch spaces directly. Same approach used by yabai, skhd, etc.
//
// WARNING: Private API — may break in future macOS updates.

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

        let available = getConn != nil && getActive != nil && copySpaces != nil && setSpace != nil
        print("[SpaceSwitcher] Initialized: \(available ? "OK" : "FAILED — some symbols missing")")
    }

    var isAvailable: Bool {
        getConn != nil && getActive != nil && copySpaces != nil && setSpace != nil
    }

    // MARK: - Get Current Space Info

    private func connection() -> Int { getConn?() ?? 0 }
    private func activeSpace() -> Int { getActive?(connection()) ?? 0 }

    /// Get all space IDs for the current display, in order
    private func currentDisplaySpaces() -> (displayUUID: String, spaceIDs: [Int])? {
        guard let copyFn = copySpaces else { return nil }
        let conn = connection()
        let current = activeSpace()

        guard let displays = copyFn(conn) as? [[String: Any]] else { return nil }

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.compactMap { $0["id64"] as? Int }
            if ids.contains(current) {
                let uuid = display["Display Identifier"] as? String ?? ""
                return (uuid, ids)
            }
        }
        return nil
    }

    // MARK: - Switch Space

    func switchToNextSpace() {
        guard let setFn = setSpace, let info = currentDisplaySpaces() else { return }
        let current = activeSpace()
        guard let idx = info.spaceIDs.firstIndex(of: current) else { return }
        let nextIdx = (idx + 1) % info.spaceIDs.count
        let nextSpace = info.spaceIDs[nextIdx]
        setFn(connection(), info.displayUUID as CFString, nextSpace)
        print("[SpaceSwitcher] Switched to next space: \(nextSpace)")
    }

    func switchToPreviousSpace() {
        guard let setFn = setSpace, let info = currentDisplaySpaces() else { return }
        let current = activeSpace()
        guard let idx = info.spaceIDs.firstIndex(of: current) else { return }
        let prevIdx = idx > 0 ? idx - 1 : info.spaceIDs.count - 1
        let prevSpace = info.spaceIDs[prevIdx]
        setFn(connection(), info.displayUUID as CFString, prevSpace)
        print("[SpaceSwitcher] Switched to previous space: \(prevSpace)")
    }

    func switchToSpace(index: Int) {
        guard let setFn = setSpace, let info = currentDisplaySpaces() else { return }
        guard index >= 0 && index < info.spaceIDs.count else { return }
        let targetSpace = info.spaceIDs[index]
        setFn(connection(), info.displayUUID as CFString, targetSpace)
        print("[SpaceSwitcher] Switched to space \(index): \(targetSpace)")
    }

    var spaceCount: Int {
        currentDisplaySpaces()?.spaceIDs.count ?? 0
    }

    var currentSpaceIndex: Int {
        guard let info = currentDisplaySpaces() else { return 0 }
        let current = activeSpace()
        return info.spaceIDs.firstIndex(of: current) ?? 0
    }
}
