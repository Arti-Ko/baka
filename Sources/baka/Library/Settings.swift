import Foundation

/// Persisted application settings, including the power policy and the mapping
/// of screens to assigned wallpapers.
///
/// Screens are keyed by a stable identifier derived from the display, not by
/// the volatile `NSScreen` ordering, so assignments survive reconnects.
struct AppSettings: Codable, Equatable, Sendable {
    var power: PowerPolicy = .default

    /// screenKey -> wallpaper id
    var assignments: [String: String] = [:]

    /// Launch baka at login.
    var launchAtLogin: Bool = false

    static let `default` = AppSettings()

    func assignedWallpaperID(forScreen key: String) -> String? {
        assignments[key]
    }

    /// Returns a new copy assigning `wallpaperID` to `screenKey`.
    func assigning(_ wallpaperID: String?, toScreen key: String) -> AppSettings {
        var copy = self
        if let wallpaperID {
            copy.assignments[key] = wallpaperID
        } else {
            copy.assignments.removeValue(forKey: key)
        }
        return copy
    }

    func withPower(_ policy: PowerPolicy) -> AppSettings {
        var copy = self
        copy.power = policy
        return copy
    }
}

/// Loads and saves `AppSettings` atomically as JSON.
enum SettingsStore {
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: AppPaths.settingsFile),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        do {
            try AppPaths.ensureDirectories()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: AppPaths.settingsFile, options: .atomic)
        } catch {
            Log.library.error("Failed to save settings: \(error.localizedDescription)")
        }
    }
}
