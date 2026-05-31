import Foundation

/// Reads the app's version/build from the bundle and provides semantic-version
/// comparison used by the update checker.
enum AppVersion {
    /// Marketing version, e.g. "0.1.0" (CFBundleShortVersionString).
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Build number (CFBundleVersion).
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var displayString: String { "v\(current) (\(build))" }

    /// Compares two semantic version strings (a leading "v" is ignored).
    /// Returns true when `lhs` is strictly newer than `rhs`.
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let a = components(lhs), b = components(rhs)
        for (x, y) in zip(a, b) where x != y { return x > y }
        return false
    }

    /// Parses "v1.2.3" → [1, 2, 3], padding to 3 components.
    static func components(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        var parts = trimmed
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return Array(parts.prefix(3))
    }
}
