import Foundation

/// Locates downloaded Wallpaper Engine workshop content across **both** places
/// it can live on macOS:
/// 1. The standard Steam install — `~/Library/Application Support/Steam/...`
///    (used by the real Steam client *and* by SteamCMD, which writes here).
/// 2. Baka's own SteamCMD install dir — `…/Application Support/baka/steamcmd/…`
///    (in case a setup downloads relative to the tool instead).
///
/// All lookups search every existing root, so an item is found no matter which
/// directory it landed in.
enum SteamLocator {
    static let weAppID = "431960"

    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Candidate workshop-content roots, in priority order.
    private static var candidateRoots: [URL] {
        [
            appSupport.appendingPathComponent("Steam/steamapps/workshop/content/\(weAppID)"),
            AppPaths.support.appendingPathComponent("steamcmd/steamapps/workshop/content/\(weAppID)")
        ]
    }

    /// Existing workshop-content roots.
    static var contentDirs: [URL] {
        candidateRoots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Returns the on-disk folder for an item from *any* root, requiring it to
    /// exist and be non-empty (a partial download leaves an empty folder).
    static func localFolder(forItem id: String) -> URL? {
        for root in candidateRoots {
            let folder = root.appendingPathComponent(id, isDirectory: true)
            let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
            if contents?.isEmpty == false { return folder }
        }
        return nil
    }

    /// True when at least one root with workshop content exists.
    static var hasLocalWorkshop: Bool { !contentDirs.isEmpty }
}
