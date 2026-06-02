import Foundation

/// A parsed Wallpaper Engine `project.json`, describing one downloaded workshop
/// item on disk. WE stores the real content filename and type here.
struct WorkshopProject {
    let title: String?
    let kind: WallpaperKind        // video/web render live; scene/application = poster
    let contentFile: URL           // the asset to render (a media file, or a poster image)
    let previewFile: URL?

    /// Loads a renderable wallpaper from `folder`. Strategy, in order:
    /// 1. Trust project.json's declared *live* type + file (video/web).
    /// 2. *Salvage* by scanning for a real video or HTML file anyway — many
    ///    items are mistagged, and any folder that actually contains an mp4/html
    ///    is playable regardless of what project.json claims.
    /// 3. For genuine Scene/Application items (proprietary content we can't run
    ///    on macOS), fall back to a **poster**: the bundled preview image/GIF,
    ///    so the wallpaper still shows real content instead of failing to load.
    /// 4. Returns nil only when there is nothing displayable at all.
    static func load(from folder: URL) -> WorkshopProject? {
        let root = readProject(folder)
        let title = root?["title"] as? String
        let declared = (root?["type"] as? String)?.lowercased() ?? ""
        let namedFile = root?["file"] as? String
        let preview = (root?["preview"] as? String).map { folder.appendingPathComponent($0) }

        // 1. Recognized live type → resolve named file, else scan for that kind.
        if let kind = mapKind(declared) {
            if let content = resolveContent(named: namedFile, kind: kind, in: folder) {
                return WorkshopProject(title: title, kind: kind, contentFile: content, previewFile: preview)
            }
        }

        // 2. Salvage: any renderable live file present, regardless of declared type.
        if let video = scan(folder, for: .video) {
            return WorkshopProject(title: title, kind: .video, contentFile: video, previewFile: preview)
        }
        if let web = scan(folder, for: .web) {
            return WorkshopProject(title: title, kind: .web, contentFile: web, previewFile: preview)
        }

        // 3. Scene: composited natively from scene.json when present, else shown
        //    as a poster. We point contentFile at the poster when we have one
        //    (so the renderer can fall back), otherwise at scene.json itself.
        let poster = posterFile(in: folder, declaredPreview: preview)
        let sceneJSON = findSceneJSON(in: folder)
        if declared != "application", sceneJSON != nil || poster != nil {
            let content = poster ?? sceneJSON!
            return WorkshopProject(title: title, kind: .scene, contentFile: content, previewFile: preview)
        }

        // 3b. Application: no native renderer — show a poster if one exists.
        if let poster {
            return WorkshopProject(title: title, kind: .application, contentFile: poster, previewFile: preview)
        }

        // 4. Nothing displayable at all.
        return nil
    }

    /// Locates a `scene.json` anywhere in the (already-unpacked) item folder.
    private static func findSceneJSON(in folder: URL) -> URL? {
        let direct = folder.appendingPathComponent("scene.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent.lowercased() == "scene.json" {
            return url
        }
        return nil
    }

    /// Finds a bundled preview image to use as a poster for Scene/Application
    /// items. Prefers the project's declared preview, then any animated GIF
    /// (which looks alive), then any still image.
    private static func posterFile(in folder: URL, declaredPreview: URL?) -> URL? {
        let fm = FileManager.default
        if let declaredPreview,
           fm.fileExists(atPath: declaredPreview.path),
           WallpaperFormats.image.contains(declaredPreview.pathExtension.lowercased()) {
            return declaredPreview
        }
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var gif: URL?
        var still: URL?
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ext == "gif" {
                if gif == nil { gif = url }
            } else if WallpaperFormats.image.contains(ext) {
                if still == nil { still = url }
            }
        }
        return gif ?? still
    }

    private static func readProject(_ folder: URL) -> [String: Any]? {
        let url = folder.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(
                  with: SteamWorkshopClient.sanitizeJSON(data)
              ) as? [String: Any]
        else { return nil }
        return root
    }

    private static func mapKind(_ type: String) -> WallpaperKind? {
        switch type {
        case "video": return .video
        case "web": return .web
        default: return nil
        }
    }

    /// Resolves the content file, trusting the named file but falling back to a
    /// directory scan when the name is missing or wrong.
    private static func resolveContent(named name: String?, kind: WallpaperKind, in folder: URL) -> URL? {
        if let name, !name.isEmpty {
            let candidate = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return scan(folder, for: kind)
    }

    /// Recursively finds a plausible content file by extension (one item folder
    /// is small, so a full shallow walk is cheap).
    private static func scan(_ folder: URL, for kind: WallpaperKind) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var htmlCandidates: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            switch kind {
            case .video:
                if WallpaperFormats.video.contains(ext) { return url }
            case .web:
                if url.lastPathComponent.lowercased() == "index.html" { return url }
                if ext == "html" { htmlCandidates.append(url) }
            case .scene, .application:
                break // poster kinds aren't found by live-content scanning
            }
        }
        return kind == .web ? htmlCandidates.first : nil
    }
}
