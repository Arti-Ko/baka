import Foundation

/// A wallpaper listing discovered in the Steam Workshop (app 431960).
/// This is metadata only — the actual asset is fetched on demand.
struct WorkshopItem: Identifiable, Hashable, Sendable {
    let id: String            // publishedfileid
    let title: String
    let previewURL: URL?
    let author: String?

    /// Direct content URL if Steam exposes one (often empty for WE items,
    /// whose content is delivered through SteamPipe and needs SteamCMD).
    let fileURL: URL?

    /// Best guess of the wallpaper kind from tags/metadata.
    let kind: WallpaperKind?

    /// All Workshop tags (type, genre, resolution, age rating, …) lowercased.
    let tags: [String]

    var isDirectlyDownloadable: Bool { fileURL != nil }

    /// True when the item is tagged Mature or Questionable (NSFW).
    var isNSFW: Bool {
        tags.contains("mature") || tags.contains("questionable") || tags.contains("nsfw")
    }
}

/// Outcome of attempting to obtain a downloadable asset for a workshop item.
enum WorkshopDownloadability: Sendable {
    /// Steam exposed a direct file URL we can fetch.
    case direct(URL, WallpaperKind)
    /// Content is delivered via SteamPipe; needs the Steam client / SteamCMD.
    case requiresSteamCMD
    /// We could not determine how to fetch it.
    case unavailable
}
