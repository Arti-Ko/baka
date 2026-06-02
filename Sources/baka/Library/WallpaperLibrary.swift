import Foundation

/// The persisted catalog of wallpapers the user has imported or downloaded.
/// Kept deliberately simple: a JSON-backed list with id-keyed lookups.
@MainActor
final class WallpaperLibrary: ObservableObject {
    @Published private(set) var items: [Wallpaper] = []

    init() {
        load()
    }

    func wallpaper(withID id: String) -> Wallpaper? {
        items.first { $0.id == id }
    }

    /// Inserts a new wallpaper or replaces an existing one with the same id.
    func upsert(_ wallpaper: Wallpaper) {
        if let index = items.firstIndex(where: { $0.id == wallpaper.id }) {
            items[index] = wallpaper
        } else {
            items.append(wallpaper)
        }
        save()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        // Best-effort cleanup of downloaded content.
        try? FileManager.default.removeItem(at: AppPaths.contentDirectory(for: id))
        save()
    }

    /// Removes every wallpaper and deletes all downloaded/imported content and
    /// cached previews from disk.
    func removeAll() {
        items = []
        save()
        let fm = FileManager.default
        try? fm.removeItem(at: AppPaths.content)
        try? fm.removeItem(at: AppPaths.previews)
        try? AppPaths.ensureDirectories()
        Log.library.log("library reset: all content removed")
    }

    // MARK: - Disk reconciliation

    /// Keeps the catalog and the on-disk `Content/` directory in sync after a
    /// crash, interrupted install, or manual deletion:
    /// 1. Drops catalog entries whose backing content file has vanished.
    /// 2. Deletes content folders that no catalog entry references (orphans left
    ///    behind by a failed install).
    ///
    /// `contentDir` is injectable for testing; production uses `AppPaths.content`.
    func reconcileWithDisk(contentDir: URL = AppPaths.content) {
        let stale = Set(Self.staleEntries(items).map(\.id))
        let live = items.filter { !stale.contains($0.id) }

        let orphans = Self.orphanFolders(in: contentDir, knownIDs: Set(live.map(\.id)))
        for url in orphans { try? FileManager.default.removeItem(at: url) }

        if !stale.isEmpty {
            items = live
            save()
        }
        if !stale.isEmpty || !orphans.isEmpty {
            Log.library.log("reconciled library: \(stale.count) stale entries, \(orphans.count) orphan folders removed")
        }
    }

    /// Catalog entries whose content URL is set but no longer exists on disk.
    /// Pure (filesystem reads only) so it is unit-testable.
    nonisolated static func staleEntries(_ items: [Wallpaper]) -> [Wallpaper] {
        items.filter { wallpaper in
            guard let url = wallpaper.contentURL else { return false }
            return !FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Subfolders of `contentDir` whose name is not in `knownIDs` — leftover
    /// content from interrupted/removed installs. Pure and unit-testable.
    nonisolated static func orphanFolders(in contentDir: URL, knownIDs: Set<String>) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: contentDir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { !knownIDs.contains($0.lastPathComponent) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.libraryFile),
              let decoded = try? JSONDecoder().decode([Wallpaper].self, from: data)
        else {
            items = []
            return
        }
        items = decoded
    }

    private func save() {
        do {
            try AppPaths.ensureDirectories()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: AppPaths.libraryFile, options: .atomic)
        } catch {
            Log.library.error("Failed to save library: \(error.localizedDescription)")
        }
    }
}
