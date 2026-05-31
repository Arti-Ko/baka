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
