import Foundation

/// Resolves and creates the on-disk locations baka uses for its library,
/// downloaded content, and settings. All paths live under Application Support.
enum AppPaths {
    static let bundleID = "com.baka.app"

    /// ~/Library/Application Support/baka
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("baka", isDirectory: true)
    }

    /// Downloaded / imported wallpaper content lives here, one folder per id.
    static var content: URL { support.appendingPathComponent("Content", isDirectory: true) }

    /// Cached preview thumbnails.
    static var previews: URL { support.appendingPathComponent("Previews", isDirectory: true) }

    /// Serialized library catalog.
    static var libraryFile: URL { support.appendingPathComponent("library.json") }

    /// Serialized settings + per-screen assignments.
    static var settingsFile: URL { support.appendingPathComponent("settings.json") }

    /// Persisted download queue (incomplete + failed items) so they survive
    /// restarts and can resume / be retried.
    static var downloadsFile: URL { support.appendingPathComponent("downloads.json") }

    /// Creates all required directories. Safe to call repeatedly.
    static func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [support, content, previews] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func contentDirectory(for id: String) -> URL {
        content.appendingPathComponent(id, isDirectory: true)
    }
}
