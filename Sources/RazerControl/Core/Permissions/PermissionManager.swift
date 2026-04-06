import Foundation
import AppKit
import IOKit.hid

// MARK: - Permission Status

enum PermissionStatus {
    case granted
    case denied
    case unknown

    var label: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Required"
        case .unknown: return "Unknown"
        }
    }

    var isGranted: Bool { self == .granted }
}

// MARK: - Permission Manager

@MainActor
class PermissionManager: ObservableObject {
    @Published var accessibilityStatus: PermissionStatus = .unknown
    @Published var inputMonitoringStatus: PermissionStatus = .unknown

    // MARK: - Check Permissions

    func checkAll() {
        checkAccessibility()
        checkInputMonitoring()
    }

    /// Check Accessibility permission via AXIsProcessTrusted()
    func checkAccessibility() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
    }

    /// Check Input Monitoring by attempting to create an IOHIDManager
    /// and checking if we can receive input callbacks.
    /// Note: This is a heuristic — IOKit doesn't give a clean "permission denied"
    /// signal. We check if the event tap permission exists instead.
    func checkInputMonitoring() {
        // CGPreflightListenEventAccess was added in macOS 10.15
        if #available(macOS 10.15, *) {
            let hasAccess = CGPreflightListenEventAccess()
            inputMonitoringStatus = hasAccess ? .granted : .denied
        } else {
            inputMonitoringStatus = .unknown
        }
    }

    // MARK: - Request Permissions (opens System Settings)

    func requestAccessibility() {
        // This shows the macOS prompt and opens System Settings
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Also open the System Settings pane directly
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        if #available(macOS 10.15, *) {
            // Request access — this prompts the user
            CGRequestListenEventAccess()
        }

        // Open the System Settings pane
        openSystemSettings(pane: "Privacy_ListenEvent")
    }

    // MARK: - Open System Settings

    private func openSystemSettings(pane: String) {
        // macOS 13+ uses the new System Settings app
        if #available(macOS 13, *) {
            let urlString: String
            switch pane {
            case "Privacy_Accessibility":
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case "Privacy_ListenEvent":
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            default:
                urlString = "x-apple.systempreferences:com.apple.preference.security"
            }

            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Feature Requirements

    /// RGB lighting only needs write access — no special permissions
    static var rgbRequiresPermissions: Bool { false }

    /// Key mapping requires both Input Monitoring (to capture keys) and Accessibility (to inject keys)
    static var keyMappingRequiresPermissions: Bool { true }

    var canUseKeyMapping: Bool {
        accessibilityStatus.isGranted && inputMonitoringStatus.isGranted
    }

    var canUseLighting: Bool {
        true // RGB never needs permissions
    }
}
