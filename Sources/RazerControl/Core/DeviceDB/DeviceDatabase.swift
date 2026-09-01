import Foundation

// MARK: - Device Database
//
// Static database of Razer device PIDs and their capabilities.
// Derived from the OpenRazer project (GPLv2).
// No runtime USB query exists for capabilities — the device doesn't report
// which effects it supports, so we must maintain this list manually.

final class DeviceDatabase {
    static let shared = DeviceDatabase()

    private var devices: [UInt16: RazerDeviceInfo] = [:]

    private init() {
        registerKeyboards()
        registerMice()
        registerAccessories()
    }

    // MARK: - Lookup

    func lookup(pid: UInt16) -> RazerDeviceInfo? {
        devices[pid]
    }

    func allDevices() -> [RazerDeviceInfo] {
        Array(devices.values).sorted { $0.name < $1.name }
    }

    func devices(ofType type: RazerDeviceType) -> [RazerDeviceInfo] {
        allDevices().filter { $0.type == type }
    }

    // MARK: - Registration

    private func register(_ device: RazerDeviceInfo) {
        devices[device.pid] = device
    }

    // MARK: - Keyboards

    private func registerKeyboards() {
        let kbZones = [
            RazerDeviceZone(led: .backlight, label: "Keys"),
            RazerDeviceZone(led: .logo, label: "Logo"),
        ]
        let kbZonesWithUnderglow = kbZones + [
            RazerDeviceZone(led: .underglow, label: "Underglow"),
        ]

        // BlackWidow V4 Pro
        register(RazerDeviceInfo(
            pid: 0x028D, name: "BlackWidow V4 Pro", type: .keyboard,
            features: [.keyboardFull, .macroKeys, .dial, .roller, .underglow],
            proto: .extended, txId: 0x1F,
            zones: kbZonesWithUnderglow,
            matrix: (6, 22), macroKeys: 8, dial: true, roller: true
        ))

        // BlackWidow V4 75%
        register(RazerDeviceInfo(
            pid: 0x028E, name: "BlackWidow V4 75%", type: .keyboard,
            features: [.keyboardFull, .dial],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 16), dial: true
        ))

        // BlackWidow V4
        register(RazerDeviceInfo(
            pid: 0x028C, name: "BlackWidow V4", type: .keyboard,
            features: [.keyboardFull, .macroKeys, .roller],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 22), macroKeys: 6, roller: true
        ))

        // BlackWidow V3
        register(RazerDeviceInfo(
            pid: 0x0258, name: "BlackWidow V3", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 22)
        ))

        // BlackWidow V3 (wired)
        register(RazerDeviceInfo(
            pid: 0x024E, name: "BlackWidow V3", type: .keyboard,
            features: [.staticEffect, .breathingEffect, .waveEffect, .spectrumEffect,
                       .matrixRGB, .brightnessCtrl],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 22)
        ))

        // BlackWidow V3 TKL
        register(RazerDeviceInfo(
            pid: 0x0A24, name: "BlackWidow V3 TKL", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 18)
        ))

        // Huntsman V3 Pro
        register(RazerDeviceInfo(
            pid: 0x02A0, name: "Huntsman V3 Pro", type: .keyboard,
            features: [.keyboardFull, .macroKeys, .dial, .roller],
            proto: .extended, txId: 0x1F,
            zones: kbZonesWithUnderglow,
            matrix: (6, 22), macroKeys: 8, dial: true, roller: true
        ))

        // Huntsman V3 Pro TKL
        register(RazerDeviceInfo(
            pid: 0x02A1, name: "Huntsman V3 Pro TKL", type: .keyboard,
            features: [.keyboardFull, .dial],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 18), dial: true
        ))

        // Huntsman V2
        register(RazerDeviceInfo(
            pid: 0x026B, name: "Huntsman V2", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 22)
        ))

        // DeathStalker V2 Pro
        register(RazerDeviceInfo(
            pid: 0x0295, name: "DeathStalker V2 Pro", type: .keyboard,
            features: [.keyboardFull, .wireless, .bluetooth],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 22)
        ))

        // Ornata V3
        register(RazerDeviceInfo(
            pid: 0x0291, name: "Ornata V3", type: .keyboard,
            features: [.keyboardFull, .underglow],
            proto: .extended, txId: 0x1F,
            zones: kbZonesWithUnderglow, matrix: (6, 22)
        ))

        // Cynosa V2
        register(RazerDeviceInfo(
            pid: 0x025E, name: "Cynosa V2", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 22)
        ))

        // Huntsman V2 TKL
        register(RazerDeviceInfo(
            pid: 0x026C, name: "Huntsman V2 TKL", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 18)
        ))

        // Huntsman Mini
        register(RazerDeviceInfo(
            pid: 0x0257, name: "Huntsman Mini", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (5, 15)
        ))

        // Huntsman Elite
        register(RazerDeviceInfo(
            pid: 0x0226, name: "Huntsman Elite", type: .keyboard,
            features: [.keyboardFull, .underglow],
            proto: .extended, txId: 0x1F,
            zones: kbZonesWithUnderglow, matrix: (6, 22)
        ))

        // BlackWidow V3 Pro (Wireless)
        register(RazerDeviceInfo(
            pid: 0x025A, name: "BlackWidow V3 Pro", type: .keyboard,
            features: [.keyboardFull, .wireless, .bluetooth],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 22)
        ))

        // BlackWidow V3 Mini HyperSpeed
        register(RazerDeviceInfo(
            pid: 0x0271, name: "BlackWidow V3 Mini", type: .keyboard,
            features: [.keyboardFull, .wireless, .bluetooth],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (5, 16)
        ))

        // DeathStalker V2
        register(RazerDeviceInfo(
            pid: 0x0293, name: "DeathStalker V2", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 22)
        ))

        // DeathStalker V2 Pro TKL
        register(RazerDeviceInfo(
            pid: 0x0297, name: "DeathStalker V2 Pro TKL", type: .keyboard,
            features: [.keyboardFull, .wireless, .bluetooth],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 18)
        ))

        // Ornata V3 TKL
        register(RazerDeviceInfo(
            pid: 0x0292, name: "Ornata V3 TKL", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 18)
        ))

        // Orbweaver Chroma
        register(RazerDeviceInfo(
            pid: 0x0207, name: "Orbweaver Chroma", type: .keyboard,
            features: [.staticEffect, .breathingEffect, .waveEffect, .spectrumEffect,
                       .matrixRGB, .brightnessCtrl, .macroKeys],
            proto: .standard, txId: 0xFF,
            zones: kbZones, matrix: (5, 22), macroKeys: 20
        ))

        // Tartarus V2 as it actually enumerates on hardware here. The 0x0208
        // entry below is retained: both identifiers are in circulation.
        register(RazerDeviceInfo(
            pid: 0x022B, name: "Tartarus V2", type: .keyboard,
            features: [.staticEffect, .breathingEffect, .waveEffect, .spectrumEffect,
                       .matrixRGB, .brightnessCtrl, .macroKeys],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (4, 5), macroKeys: 20
        ))

        // Tartarus V2
        register(RazerDeviceInfo(
            pid: 0x0208, name: "Tartarus V2", type: .keyboard,
            features: [.allEffects, .matrixRGB, .brightnessCtrl, .macroKeys],
            proto: .standard, txId: 0xFF,
            zones: kbZones, matrix: (4, 6), macroKeys: 32
        ))

        // Tartarus Pro
        register(RazerDeviceInfo(
            pid: 0x0244, name: "Tartarus Pro", type: .keyboard,
            features: [.allEffects, .matrixRGB, .brightnessCtrl, .macroKeys],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (4, 6), macroKeys: 32
        ))

        // Blade (laptop keyboards with Chroma)
        register(RazerDeviceInfo(
            pid: 0x029F, name: "Blade 16 (2024)", type: .keyboard,
            features: [.keyboardFull],
            proto: .extended, txId: 0x1F,
            zones: kbZones, matrix: (6, 16)
        ))
    }

    // MARK: - Mice

    private func registerMice() {
        let mouseZonesBasic = [
            RazerDeviceZone(led: .none, label: "All"),
        ]
        let mouseZonesUnderglow = [
            RazerDeviceZone(led: .none, label: "All"),
            RazerDeviceZone(led: .underglow, label: "Underglow"),
        ]

        // Pro Click V2 Vertical Edition (wired)
        register(RazerDeviceInfo(
            pid: 0x00C7, name: "Pro Click V2 Vertical Edition", type: .mouse,
            features: [.staticEffect, .breathingEffect, .spectrumEffect, .brightnessCtrl,
                       .dpiControl, .onboardMemory, .wireless, .bluetooth],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow,
            dpiMax: 35000, buttons: 6
        ))

        // Pro Click V2 Vertical Edition (wireless dongle)
        register(RazerDeviceInfo(
            pid: 0x00C8, name: "Pro Click V2 Vertical Edition (Wireless)", type: .mouse,
            features: [.staticEffect, .breathingEffect, .spectrumEffect, .brightnessCtrl,
                       .dpiControl, .onboardMemory, .wireless, .bluetooth],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow,
            dpiMax: 35000, buttons: 6
        ))

        // DeathAdder V3 Pro
        register(RazerDeviceInfo(
            pid: 0x00B7, name: "DeathAdder V3 Pro", type: .mouse,
            features: [.staticEffect, .breathingEffect, .spectrumEffect, .dpiControl, .wireless],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesBasic, dpiMax: 30000, buttons: 5
        ))

        // Viper V3 Pro
        register(RazerDeviceInfo(
            pid: 0x00C3, name: "Viper V3 Pro", type: .mouse,
            features: [.allEffects, .dpiControl, .wireless, .bluetooth, .brightnessCtrl],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow, dpiMax: 35000, buttons: 5
        ))

        // Viper Ultimate (wireless dongle)
        register(RazerDeviceInfo(
            pid: 0x007B, name: "Viper Ultimate (Wireless)", type: .mouse,
            features: [.staticEffect, .breathingEffect, .spectrumEffect, .reactiveEffect,
                       .matrixRGB, .brightnessCtrl, .dpiControl, .pollRateCtrl, .wireless],
            proto: .extended, txId: 0x3F,
            zones: [RazerDeviceZone(led: .logo, label: "Logo")],
            matrix: (1, 1), dpiMax: 20000, buttons: 8
        ))

        // Basilisk V3
        register(RazerDeviceInfo(
            pid: 0x0099, name: "Basilisk V3", type: .mouse,
            features: [.allEffects, .dpiControl, .brightnessCtrl, .matrixRGB],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow, dpiMax: 26000, buttons: 11
        ))

        // Naga V2 Pro
        register(RazerDeviceInfo(
            pid: 0x00B3, name: "Naga V2 Pro", type: .mouse,
            features: [.allEffects, .dpiControl, .wireless, .bluetooth, .brightnessCtrl],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow, dpiMax: 30000, buttons: 12
        ))

        // Pro Click Mini
        register(RazerDeviceInfo(
            pid: 0x009A, name: "Pro Click Mini", type: .mouse,
            features: [.staticEffect, .dpiControl, .wireless, .bluetooth],
            proto: .extended, txId: 0x3F,
            zones: [], dpiMax: 12000, buttons: 7
        ))

        // DeathAdder V3
        register(RazerDeviceInfo(
            pid: 0x00B6, name: "DeathAdder V3", type: .mouse,
            features: [.dpiControl, .brightnessCtrl],
            proto: .extended, txId: 0x3F,
            zones: [], dpiMax: 30000, buttons: 5
        ))

        // DeathAdder V3 HyperSpeed
        register(RazerDeviceInfo(
            pid: 0x00B8, name: "DeathAdder V3 HyperSpeed", type: .mouse,
            features: [.dpiControl, .wireless, .bluetooth],
            proto: .extended, txId: 0x3F,
            zones: [], dpiMax: 30000, buttons: 5
        ))

        // Viper V3 HyperSpeed
        register(RazerDeviceInfo(
            pid: 0x00C4, name: "Viper V3 HyperSpeed", type: .mouse,
            features: [.allEffects, .dpiControl, .wireless, .bluetooth, .brightnessCtrl],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow, dpiMax: 35000, buttons: 5
        ))

        // Basilisk V3 Pro
        register(RazerDeviceInfo(
            pid: 0x00AA, name: "Basilisk V3 Pro", type: .mouse,
            features: [.allEffects, .dpiControl, .wireless, .bluetooth, .brightnessCtrl, .matrixRGB],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow, dpiMax: 30000, buttons: 13
        ))

        // Basilisk V3 X HyperSpeed
        register(RazerDeviceInfo(
            pid: 0x00B9, name: "Basilisk V3 X HyperSpeed", type: .mouse,
            features: [.dpiControl, .wireless, .bluetooth],
            proto: .extended, txId: 0x3F,
            zones: [], dpiMax: 18000, buttons: 6
        ))

        // Cobra Pro
        register(RazerDeviceInfo(
            pid: 0x00C0, name: "Cobra Pro", type: .mouse,
            features: [.allEffects, .dpiControl, .wireless, .bluetooth, .brightnessCtrl, .matrixRGB],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow, dpiMax: 30000, buttons: 10
        ))

        // Naga V2 HyperSpeed
        register(RazerDeviceInfo(
            pid: 0x00B4, name: "Naga V2 HyperSpeed", type: .mouse,
            features: [.allEffects, .dpiControl, .wireless, .bluetooth, .brightnessCtrl],
            proto: .extended, txId: 0x3F,
            zones: mouseZonesUnderglow, dpiMax: 30000, buttons: 19
        ))

        // Orochi V2
        register(RazerDeviceInfo(
            pid: 0x0094, name: "Orochi V2", type: .mouse,
            features: [.staticEffect, .dpiControl, .wireless, .bluetooth],
            proto: .extended, txId: 0x3F,
            zones: [], dpiMax: 18000, buttons: 6
        ))
    }

    // MARK: - Accessories

    private func registerAccessories() {
        // Viper Ultimate Mouse Dock Chroma
        register(RazerDeviceInfo(
            pid: 0x007E, name: "Viper Ultimate Mouse Dock", type: .accessory,
            features: [.staticEffect, .breathingEffect, .spectrumEffect, .brightnessCtrl],
            proto: .extended, txId: 0x3F,
            zones: [RazerDeviceZone(led: .none, label: "Base Ring")]
        ))

        // Kraken Kitty Edition Chroma controller. The companion USB audio
        // function (0x0521) is intentionally not presented as a control device.
        register(RazerDeviceInfo(
            pid: 0x0F19, name: "Kraken Kitty Edition", type: .headset,
            features: [.staticEffect, .breathingEffect, .spectrumEffect, .brightnessCtrl],
            proto: .extended, txId: 0x1F,
            zones: [RazerDeviceZone(led: .none, label: "All Lighting")]
        ))

        // Mouse Dock Pro
        register(RazerDeviceInfo(
            pid: 0x00BE, name: "Mouse Dock Pro", type: .accessory,
            features: [.allEffects, .brightnessCtrl],
            proto: .extended, txId: 0x9F,
            zones: [RazerDeviceZone(led: .underglow, label: "Underglow")]
        ))

        // Chroma Addressable RGB Controller
        register(RazerDeviceInfo(
            pid: 0x0F1F, name: "Chroma ARGB Controller", type: .accessory,
            features: [.allEffects, .matrixRGB, .brightnessCtrl],
            proto: .extended, txId: 0x9F,
            zones: [RazerDeviceZone(led: .backlight, label: "Channel")]
        ))
    }
}
