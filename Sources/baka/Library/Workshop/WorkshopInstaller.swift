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
    func install(from sourceFolder: URL, workshopID: String, fallback: WorkshopItem?) async throws -> Wallpaper {
        guard let project = WorkshopProject.load(from: sourceFolder) else {
            throw WallpaperError.unsupportedKind
        }

        let id = "ws-\(workshopID)"
        let destDir = AppPaths.contentDirectory(for: id)
        let fm = FileManager.default
        try? fm.removeItem(at: destDir)
        try fm.copyItem(at: sourceFolder, to: destDir)

        // Re-resolve the content file inside the copied directory. Computing the
        // relative path component-wise (rather than string-replacing the source
        // prefix) survives symlinked roots like /var → /private/var, which used
        // to produce a wrong contentURL and a spurious "контент не найден".
        let contentURL = Self.remap(project.contentFile, from: sourceFolder, to: destDir) ?? destDir

        let previewURL = await resolvePreview(project: project, destDir: destDir,
                                              sourceFolder: sourceFolder, id: id, fallback: fallback)

        let wallpaper = Wallpaper(
            id: id,
            title: project.title ?? fallback?.title ?? "Workshop \(workshopID)",
            kind: project.kind,
            contentURL: contentURL,
            // Posters have no separate thumbnail — fall back to the content
            // image itself so the library card still shows something.
            previewURL: previewURL ?? (project.kind.isLiveRendered ? nil : contentURL),
            workshopID: workshopID,
            author: fallback?.author,
            tags: ["workshop"]
        )
        library.upsert(wallpaper)
        Log.workshop.log("installed ws-\(workshopID, privacy: .public) kind=\(project.kind.rawValue, privacy: .public)")
        return wallpaper
    }

    /// Prefers the project's bundled preview; otherwise downloads the listing
    /// thumbnail from the workshop item, if any. The remote fetch is awaited
    /// (not a blocking `Data(contentsOf:)`) so it never stalls the main thread.
    private func resolvePreview(project: WorkshopProject, destDir: URL, sourceFolder: URL,
                                id: String, fallback: WorkshopItem?) async -> URL? {
        if let preview = project.previewFile,
           let copied = Self.remap(preview, from: sourceFolder, to: destDir),
           FileManager.default.fileExists(atPath: copied.path) {
            return copied
        }
        if let remote = fallback?.previewURL,
           let (data, _) = try? await URLSession.shared.data(from: remote) {
            let p = AppPaths.previews.appendingPathComponent("\(id).jpg")
            try? data.write(to: p, options: .atomic)
            return p
        }
        return nil
    }

    /// Rebuilds a URL that lived under `oldRoot` so it points at the same
    /// relative location under `newRoot`, comparing standardized path components
    /// (symlink-safe). Returns nil if `url` isn't actually inside `oldRoot`.
    nonisolated static func remap(_ url: URL, from oldRoot: URL, to newRoot: URL) -> URL? {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let base = oldRoot.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard target.count >= base.count, Array(target.prefix(base.count)) == base else {
            return nil
        }
        let relative = target.dropFirst(base.count)
        return relative.reduce(newRoot) { $0.appendingPathComponent($1) }
    }
}
