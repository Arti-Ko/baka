import Foundation

/// Installs a downloaded workshop item (from local Steam or SteamCMD) into the
/// Baka library: parses `project.json`, copies the content into managed storage
/// (preserving web asset folders), and registers a `Wallpaper`.
@MainActor
final class WorkshopInstaller {
    private let library: WallpaperLibrary

    init(library: WallpaperLibrary) {
        self.library = library
    }

    /// Installs from `sourceFolder` for the given workshop id. `fallback`
    /// supplies title/preview when project.json lacks them.
    @discardableResult
    func install(from sourceFolder: URL, workshopID: String, fallback: WorkshopItem?) throws -> Wallpaper {
        guard let project = WorkshopProject.load(from: sourceFolder) else {
            throw WallpaperError.unsupportedKind
        }

        let id = "ws-\(workshopID)"
        let destDir = AppPaths.contentDirectory(for: id)
        let fm = FileManager.default
        try? fm.removeItem(at: destDir)
        try fm.copyItem(at: sourceFolder, to: destDir)

        // Re-resolve the content file inside the copied directory.
        let relative = project.contentFile.path
            .replacingOccurrences(of: sourceFolder.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let contentURL = destDir.appendingPathComponent(relative)

        let previewURL = resolvePreview(project: project, destDir: destDir,
                                        sourceFolder: sourceFolder, id: id, fallback: fallback)

        let wallpaper = Wallpaper(
            id: id,
            title: project.title ?? fallback?.title ?? "Workshop \(workshopID)",
            kind: project.kind,
            contentURL: contentURL,
            previewURL: previewURL,
            workshopID: workshopID,
            author: fallback?.author,
            tags: ["workshop"]
        )
        library.upsert(wallpaper)
        Log.workshop.log("installed ws-\(workshopID, privacy: .public) kind=\(project.kind.rawValue, privacy: .public)")
        return wallpaper
    }

    /// Prefers the project's bundled preview; otherwise downloads the listing
    /// thumbnail from the workshop item, if any.
    private func resolvePreview(project: WorkshopProject, destDir: URL, sourceFolder: URL,
                                id: String, fallback: WorkshopItem?) -> URL? {
        if let preview = project.previewFile {
            let relative = preview.path
                .replacingOccurrences(of: sourceFolder.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let copied = destDir.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: copied.path) { return copied }
        }
        if let remote = fallback?.previewURL, let data = try? Data(contentsOf: remote) {
            let p = AppPaths.previews.appendingPathComponent("\(id).jpg")
            try? data.write(to: p)
            return p
        }
        return nil
    }
}
