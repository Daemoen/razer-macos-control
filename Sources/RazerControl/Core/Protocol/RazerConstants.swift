import Foundation

// MARK: - Razer USB Constants

enum RazerUSB {
    static let vendorId: UInt16 = 0x1532

    // USB Control Transfer parameters
    static let requestType: UInt8 = 0x21     // Host-to-device, Class, Interface
    static let request: UInt8 = 0x09         // SET_REPORT
    static let value: UInt16 = 0x0300        // Feature report, report ID 0
    static let index: UInt16 = 0x0002        // Interface 2 (control)
    static let readRequestType: UInt8 = 0xA1 // Device-to-host, Class, Interface
    static let readRequest: UInt8 = 0x01     // GET_REPORT

    // Timing (microseconds)
    static let standardDelay: UInt32 = 600       // Standard wired devices
    static let wirelessDelay: UInt32 = 5000      // Wireless/Bluetooth devices
    static let postWriteDelay: UInt32 = 100_000  // 100ms after write before read
}

// MARK: - Packet Status

enum RazerStatus: UInt8 {
    case new = 0x00
    case busy = 0x01
    case successful = 0x02
    case failure = 0x03
    case timeout = 0x04
    case notSupported = 0x05
}

// MARK: - Command Classes

enum RazerCommandClass: UInt8 {
    case device = 0x00          // Device info, driver mode, handedness
    case standard = 0x03        // Standard lighting effects + per-key matrix
    case buttonAssignment = 0x02 // Per-button action assignment
    case power = 0x07           // Battery level, charging status
    case extended = 0x0F        // Extended lighting protocol (newer devices)
}

// MARK: - Command IDs (raw UInt8, since IDs overlap across command classes)

enum RazerCmd {
    // Device class (0x00)
    static let deviceMode: UInt8 = 0x04
    static let handedness: UInt8 = 0x33
    static let firmwareVersion: UInt8 = 0x81
    static let serialNumber: UInt8 = 0x82

    // Button assignment class (0x02)
    static let buttonAssignment: UInt8 = 0x0C

    // Power class (0x07)
    static let batteryLevel: UInt8 = 0x80
    static let chargingStatus: UInt8 = 0x84

    // Standard class (0x03)
    static let stdBrightness: UInt8 = 0x01
    static let stdEffect: UInt8 = 0x0A
    static let stdCustomFrame: UInt8 = 0x0B

    // Extended class (0x0F)
    static let extEffect: UInt8 = 0x02
    static let extMatrixFrame: UInt8 = 0x03
    static let extBrightness: UInt8 = 0x04
}

// MARK: - Standard Effect IDs (class 0x03, command 0x0A)

enum RazerStandardEffect: UInt8 {
    case off = 0x00
    case wave = 0x01
    case reactive = 0x02
    case breathing = 0x03
    case spectrum = 0x04
    case custom = 0x05       // per-key matrix mode
    case `static` = 0x06
    case starlight = 0x19
}

// MARK: - Extended Effect IDs (class 0x0F, command 0x02)

enum RazerExtendedEffect: UInt8 {
    case off = 0x00
    case `static` = 0x01
    case breathing = 0x02
    case spectrum = 0x03
    case wave = 0x04
    case reactive = 0x05
    case starlight = 0x07
}

// MARK: - LED IDs

enum RazerLED: UInt8 {
    case none = 0x00
    case scrollWheel = 0x01
    case battery = 0x03
    case logo = 0x04
    case backlight = 0x05
    case macro = 0x07
    case game = 0x08
    case rightSide = 0x09
    case underglow = 0x0A     // Wrist rest underglow
}

// MARK: - LED Storage

enum RazerLEDStorage: UInt8 {
    case noStore = 0x00
    case variableStore = 0x01
}

// MARK: - Device Mode

enum RazerDeviceMode: UInt8 {
    case normal = 0x00
    case driver = 0x03   // Required for macro keys to emit keycodes
}

// MARK: - Handedness (ambidextrous mice)

/// Which flank the thumb rests on.
///
/// This is not cosmetic. The side buttons are addressed by *slot*, and the
/// slots are numbered relative to the thumb -- slot 0 is the rear button on the
/// thumb flank. Changing the mode moves every side-button assignment to the
/// opposite flank without altering the assignment itself, so a stored button
/// mapping only means anything alongside the mode it was made under.
enum RazerHandedness: UInt8 {
    case rightHanded = 0x00
    case leftHanded = 0x01
}

// MARK: - Button Assignment (class 0x02, command 0x0C)

/// Which physical side button an assignment addresses.
///
/// These are absolute hardware positions, not thumb-relative slots. Synapse
/// renumbers what it *displays* when handedness changes, but the wire always
/// addresses the same physical button, so an assignment does not have to be
/// re-derived when the mode is switched.
enum RazerButtonSlot: UInt8 {
    case leftBack = 0x04
    case leftFront = 0x05
    case rightBack = 0x06
    case rightFront = 0x07
}

/// What a button does, as the device models it.
///
/// The wire encodes this as type-length-value, which is why the two cases are
/// different lengths. The type corresponds to the category Synapse asks for
/// first -- "Mouse Function", "Keyboard Function" and so on. Only the keyboard
/// case is reachable from macOS: a mouse-function assignment reports on the
/// pointer interface, which the input daemon deliberately never seizes, so a
/// button assigned that way cannot be observed at all.
enum RazerButtonAction {
    case mouseButton(UInt8)
    case keyboardKey(UInt8)

    var payload: [UInt8] {
        switch self {
        case .mouseButton(let button):
            return [0x01, 0x01, button]
        case .keyboardKey(let usage):
            return [0x02, 0x02, 0x00, usage]
        }
    }
}

// MARK: - Transaction IDs (varies per device family)

enum RazerTransactionID: UInt8 {
    case standard = 0xFF
    case v4Keyboard = 0x1F
    case mouse = 0x3F
    case accessory = 0x9F
}

// MARK: - Wave Direction

enum RazerWaveDirection: UInt8 {
    case leftToRight = 0x01
    case rightToLeft = 0x02
}

// MARK: - Protocol Version

enum RazerProtocolVersion {
    case standard     // Older devices: class 0x03
    case extended     // Newer devices: class 0x0F
    case mouseExtended // Mice: class 0x03 but different effect IDs
}
