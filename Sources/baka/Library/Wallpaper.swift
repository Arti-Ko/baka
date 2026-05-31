import Foundation

/// The kind of content a wallpaper renders. Scene (.pkg) is intentionally
/// excluded — it is Wallpaper Engine's proprietary compiled format and cannot
/// be rendered without their engine.
enum WallpaperKind: String, Codable, Sendable {
    case video
    case web
}

/// Recognized file formats, kept nonisolated so any context can consult them.
enum WallpaperFormats {
    static let video: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]
}

/// An immutable description of a single wallpaper available in the library.
///
/// Values are never mutated in place; updates produce new copies via `with`.
struct Wallpaper: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: WallpaperKind

    /// Location of the playable asset on disk once downloaded.
    /// For `.video` this is the media file; for `.web` this is the entry HTML.
    let contentURL: URL?

    /// Local preview thumbnail (image) if available.
    let previewURL: URL?

    /// Steam Workshop published file id, when sourced from the workshop.
    let workshopID: String?

    let author: String?
    let tags: [String]

    /// Playback speed multiplier (1.0 = normal). Optional for backward
    /// compatibility with libraries saved before speed existed (nil → 1.0).
    let speed: Double?

    init(
        id: String,
        title: String,
        kind: WallpaperKind,
        contentURL: URL? = nil,
        previewURL: URL? = nil,
        workshopID: String? = nil,
        author: String? = nil,
        tags: [String] = [],
        speed: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.contentURL = contentURL
        self.previewURL = previewURL
        self.workshopID = workshopID
        self.author = author
        self.tags = tags
        self.speed = speed
    }

    var isInstalled: Bool { contentURL != nil }

    /// Effective playback multiplier, clamped to a sane range (0…10 = 0–1000%).
    var speedMultiplier: Double { min(max(speed ?? 1.0, 0), 10) }

    /// Returns a new copy with the content location filled in.
    func withContentURL(_ url: URL) -> Wallpaper {
        Wallpaper(
            id: id, title: title, kind: kind, contentURL: url,
            previewURL: previewURL, workshopID: workshopID,
            author: author, tags: tags, speed: speed
        )
    }

    /// Returns a new copy with the given speed multiplier (1.0 = normal).
    func withSpeed(_ multiplier: Double) -> Wallpaper {
        Wallpaper(
            id: id, title: title, kind: kind, contentURL: contentURL,
            previewURL: previewURL, workshopID: workshopID,
            author: author, tags: tags, speed: multiplier
        )
    }
}
