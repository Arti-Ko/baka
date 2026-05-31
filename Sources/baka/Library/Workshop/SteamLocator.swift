import Foundation

/// Locates a local Steam installation and the Wallpaper Engine workshop content
/// it has already downloaded. When an item is here, we can import it instantly
/// with no SteamCMD round-trip.
enum SteamLocator {
    static let weAppID = "431960"

    /// Standard macOS Steam data root: ~/Library/Application Support/Steam
    static var steamRoot: URL? {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Steam", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// .../Steam/steamapps/workshop/content/431960
    static var workshopContentDir: URL? {
        guard let root = steamRoot else { return nil }
        let dir = root
            .appendingPathComponent("steamapps/workshop/content/\(weAppID)", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Returns the on-disk folder for a published file id if Steam already has
    /// it downloaded locally.
    static func localFolder(forItem id: String) -> URL? {
        guard let base = workshopContentDir else { return nil }
        let folder = base.appendingPathComponent(id, isDirectory: true)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    /// True when a usable Steam install with WE workshop content is present.
    static var hasLocalWorkshop: Bool { workshopContentDir != nil }
}
