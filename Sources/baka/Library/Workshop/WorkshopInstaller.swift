import Foundation

/// Installs a downloaded workshop item (from local Steam or SteamCMD) into the
/// Baka library: copies the content into managed storage, unpacks any Wallpaper
/// Engine `.pkg` archives so a Scene's bundled assets become renderable, parses
/// `project.json`, and registers a `Wallpaper`.
@MainActor
final class WorkshopInstaller {
    private let library: WallpaperLibrary

    init(library: WallpaperLibrary) {
        self.library = library
    }

    /// Installs from `sourceFolder` for the given workshop id. `fallback`
    /// supplies title/preview when project.json lacks them.
    ///
    /// The item is copied into managed storage *first*, then parsed from there,
    /// so content paths are always rooted in our own directory — no fragile
    /// re-mapping of the (possibly symlinked) Steam source path.
    @discardableResult
    func install(from sourceFolder: URL, workshopID: String, fallback: WorkshopItem?) async throws -> Wallpaper {
        let id = "ws-\(workshopID)"
        let destDir = AppPaths.contentDirectory(for: id)
        let fm = FileManager.default
        try? fm.removeItem(at: destDir)
        try fm.copyItem(at: sourceFolder, to: destDir)

        // Unpack any WE .pkg archives in place: a Scene that bundles a plain
        // video/image now exposes it for live rendering or a full-res poster.
        PkgArchive.unpackAll(in: destDir)

        guard let project = WorkshopProject.load(from: destDir) else {
            throw WallpaperError.unsupportedKind
        }

        let previewURL = await resolvePreview(project: project, id: id, fallback: fallback)

        let wallpaper = Wallpaper(
            id: id,
            title: project.title ?? fallback?.title ?? "Workshop \(workshopID)",
            kind: project.kind,
            contentURL: project.contentFile,
            // Posters have no separate thumbnail — fall back to the content
            // image itself so the library card still shows something.
            previewURL: previewURL ?? (project.kind.isLiveRendered ? nil : project.contentFile),
            workshopID: workshopID,
            author: fallback?.author,
            tags: ["workshop"]
        )
        library.upsert(wallpaper)
        Log.workshop.log("installed ws-\(workshopID, privacy: .public) kind=\(project.kind.rawValue, privacy: .public)")
        return wallpaper
    }

    /// Prefers the project's bundled preview (already inside managed storage);
    /// otherwise downloads the listing thumbnail. The remote fetch is awaited
    /// (not a blocking `Data(contentsOf:)`) so it never stalls the main thread.
    private func resolvePreview(project: WorkshopProject, id: String, fallback: WorkshopItem?) async -> URL? {
        if let preview = project.previewFile,
           FileManager.default.fileExists(atPath: preview.path) {
            return preview
        }
        if let remote = fallback?.previewURL,
           let (data, _) = try? await URLSession.shared.data(from: remote) {
            let p = AppPaths.previews.appendingPathComponent("\(id).jpg")
            try? data.write(to: p, options: .atomic)
            return p
        }
        return nil
    }
}
