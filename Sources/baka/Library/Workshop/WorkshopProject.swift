import Foundation

/// A parsed Wallpaper Engine `project.json`, describing one downloaded workshop
/// item on disk. WE stores the real content filename and type here.
struct WorkshopProject {
    let title: String?
    let kind: WallpaperKind        // only video/web are representable
    let contentFile: URL           // the actual asset to render
    let previewFile: URL?

    /// Loads a renderable wallpaper from `folder`. Strategy, in order:
    /// 1. Trust project.json's declared type + file (video/web).
    /// 2. If the declared type is unknown/scene/application, *salvage* by
    ///    scanning for a real video or HTML file anyway — many items are
    ///    mistagged, and any folder that actually contains an mp4/html is
    ///    playable regardless of what project.json claims.
    /// 3. Returns nil only when there is genuinely nothing renderable.
    static func load(from folder: URL) -> WorkshopProject? {
        let root = readProject(folder)
        let title = root?["title"] as? String
        let declared = (root?["type"] as? String)?.lowercased() ?? ""
        let namedFile = root?["file"] as? String
        let preview = (root?["preview"] as? String).map { folder.appendingPathComponent($0) }

        // 1. Recognized type → resolve named file, else scan for that kind.
        if let kind = mapKind(declared) {
            if let content = resolveContent(named: namedFile, kind: kind, in: folder) {
                return WorkshopProject(title: title, kind: kind, contentFile: content, previewFile: preview)
            }
        }

        // 2. Salvage: any renderable file present, regardless of declared type.
        if let video = scan(folder, for: .video) {
            return WorkshopProject(title: title, kind: .video, contentFile: video, previewFile: preview)
        }
        if let web = scan(folder, for: .web) {
            return WorkshopProject(title: title, kind: .web, contentFile: web, previewFile: preview)
        }

        // 3. Nothing renderable (true Scene/Application).
        return nil
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
            }
        }
        return kind == .web ? htmlCandidates.first : nil
    }
}
