import Foundation
import Combine

// MARK: - Profile Manager

@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [DeviceProfile] = []
    @Published var activeProfileId: UUID?

    private let storageDir: URL

    var activeProfile: DeviceProfile? {
        get { profiles.first { $0.id == activeProfileId } }
        set {
            if let profile = newValue, let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx] = profile
                activeProfileId = profile.id
            }
        }
    }

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("RazerControl/profiles", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        loadAll()
    }

    // MARK: - CRUD

    func createProfile(name: String, for device: ConnectedDevice) -> DeviceProfile {
        var profile = DeviceProfile(name: name, devicePID: device.pid, deviceSerial: device.hidDevice.serialNumber)
        save(profile)
        profiles.append(profile)
        if activeProfileId == nil {
            activeProfileId = profile.id
        }
        return profile
    }

    func duplicateProfile(_ profile: DeviceProfile) -> DeviceProfile {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        save(copy)
        profiles.append(copy)
        return copy
    }

    func deleteProfile(_ profile: DeviceProfile) {
        profiles.removeAll { $0.id == profile.id }
        let file = storageDir.appendingPathComponent("\(profile.id.uuidString).json")
        try? FileManager.default.removeItem(at: file)

        if activeProfileId == profile.id {
            activeProfileId = profiles.first?.id
        }
    }

    func updateProfile(_ profile: DeviceProfile) {
        var updated = profile
        updated.updatedAt = Date()
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = updated
        }
        save(updated)
    }

    // MARK: - Profiles for Device

    func profiles(for device: ConnectedDevice) -> [DeviceProfile] {
        profiles.filter { $0.devicePID == device.pid }
    }

    func activeProfile(for device: ConnectedDevice) -> DeviceProfile? {
        if let active = profiles.first(where: { $0.id == activeProfileId && $0.devicePID == device.pid }) {
            return active
        }
        return profiles(for: device).first
    }

    /// Get or create default profile for a device
    func ensureProfile(for device: ConnectedDevice) -> DeviceProfile {
        if let existing = profiles(for: device).first {
            return existing
        }
        return createProfile(name: "Default", for: device)
    }

    // MARK: - Apply Profile to Device

    func applyLighting(from profile: DeviceProfile, to device: ConnectedDevice) {
        let config = profile.lighting

        // Set brightness
        _ = device.setBrightness(config.brightness)

        // Set effect
        let color = config.primaryColor.swiftUIColor
        switch config.effect {
        case "static":
            _ = device.setStaticColor(color)
        case "breathing":
            _ = device.setBreathingEffect(color)
        case "wave":
            let dir: RazerWaveDirection = config.waveDirection == 0 ? .leftToRight : .rightToLeft
            _ = device.setWaveEffect(direction: dir)
        case "spectrum":
            _ = device.setSpectrumEffect()
        case "off":
            _ = device.setOff()
        default:
            _ = device.setStaticColor(color)
        }
    }

    // MARK: - Persistence

    private func save(_ profile: DeviceProfile) {
        let file = storageDir.appendingPathComponent("\(profile.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(profile) {
            try? data.write(to: file)
        }
    }

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }

        for file in files {
            if let data = try? Data(contentsOf: file),
               let profile = try? decoder.decode(DeviceProfile.self, from: data) {
                profiles.append(profile)
            }
        }

        // Set active to first profile
        activeProfileId = profiles.first?.id
    }
}
