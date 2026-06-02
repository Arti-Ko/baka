import Foundation

/// The kind of content a wallpaper renders.
///
/// `video` and `web` are rendered live. `scene` (Wallpaper Engine's proprietary
/// compiled `.pkg`) and `application` (a Windows executable) cannot run natively
/// on macOS, so they are rendered as a **poster** — their bundled preview image
/// or animated GIF — instead of failing to load.
enum WallpaperKind: String, Codable, Sendable, CaseIterable {
    case video
    case web
    case scene
    case application

    /// True when the content is rendered live (motion driven by a real engine),
    /// false when we can only show a static/animated poster.
    var isLiveRendered: Bool { self == .video || self == .web }

    /// The Steam Workshop `requiredtags` value for this kind.
    var workshopTag: String {
        switch self {
        case .video: return "Video"
        case .web: return "Web"
        case .scene: return "Scene"
        case .application: return "Application"
        }
    }

    /// Short uppercase badge label shown on cards.
    var badgeText: String {
        switch self {
        case .video: return "VIDEO"
        case .web: return "WEB"
        case .scene: return "SCENE"
        case .application: return "APP"
        }
    }

    /// SF Symbol used as a placeholder / badge icon.
    var symbolName: String {
        switch self {
        case .video: return "film.fill"
        case .web: return "globe"
        case .scene: return "cube.fill"
        case .application: return "app.fill"
        }
    }

    /// Human-readable Russian label for the preview/header.
    var displayName: String {
        switch self {
        case .video: return "Видео-обои"
        case .web: return "Web-обои"
        case .scene: return "Scene (превью)"
        case .application: return "Application (превью)"
        }
    }
}

/// Recognized file formats, kept nonisolated so any context can consult them.
enum WallpaperFormats {
    static let video: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]

    /// Image formats usable as a poster for Scene/Application wallpapers.
    /// `gif` is animated by `NSImageView`, so animated previews stay alive.
    static let image: Set<String> = ["gif", "png", "jpg", "jpeg", "webp", "bmp", "heic", "tiff", "tif"]
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

    /// Audio volume 0…1. Optional for backward compat (nil → 0 = silent, the
    /// sensible default for a wallpaper).
    let volume: Double?

    init(
        id: String,
        title: String,
        kind: WallpaperKind,
        contentURL: URL? = nil,
        previewURL: URL? = nil,
        workshopID: String? = nil,
        author: String? = nil,
        tags: [String] = [],
        speed: Double? = nil,
        volume: Double? = nil
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
        self.volume = volume
    }

    var isInstalled: Bool { contentURL != nil }

    /// Effective playback multiplier, clamped to a sane range (0…10 = 0–1000%).
    var speedMultiplier: Double { min(max(speed ?? 1.0, 0), 10) }

    /// Effective audio volume, clamped to 0…1 (default silent).
    var volumeLevel: Double { min(max(volume ?? 0, 0), 1) }

    /// Returns a new copy with the content location filled in.
    func withContentURL(_ url: URL) -> Wallpaper {
        Wallpaper(
            id: id, title: title, kind: kind, contentURL: url,
            previewURL: previewURL, workshopID: workshopID,
            author: author, tags: tags, speed: speed, volume: volume
        )
    }

    /// Returns a new copy with the given speed multiplier (1.0 = normal).
    func withSpeed(_ multiplier: Double) -> Wallpaper {
        Wallpaper(
            id: id, title: title, kind: kind, contentURL: contentURL,
            previewURL: previewURL, workshopID: workshopID,
            author: author, tags: tags, speed: multiplier, volume: volume
        )
    }

    /// Returns a new copy with the given audio volume (0…1).
    func withVolume(_ level: Double) -> Wallpaper {
        Wallpaper(
            id: id, title: title, kind: kind, contentURL: contentURL,
            previewURL: previewURL, workshopID: workshopID,
            author: author, tags: tags, speed: speed, volume: level
        )
    }
}
