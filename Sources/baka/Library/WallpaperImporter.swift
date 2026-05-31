import Foundation
import AVFoundation
import AppKit

/// Imports local media into the library: copies the asset into managed
/// storage, generates a preview thumbnail, and registers a `Wallpaper`.
@MainActor
final class WallpaperImporter {
    private let library: WallpaperLibrary

    /// Extensions we treat as video wallpapers.
    static let videoExtensions = WallpaperFormats.video

    init(library: WallpaperLibrary) {
        self.library = library
    }

    /// Import a single video file. Returns the created wallpaper or throws.
    @discardableResult
    func importVideo(at source: URL) throws -> Wallpaper {
        let ext = source.pathExtension.lowercased()
        guard Self.videoExtensions.contains(ext) else {
            throw WallpaperError.unsupportedKind
        }

        let id = UUID().uuidString
        let dir = AppPaths.contentDirectory(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let destination = dir.appendingPathComponent("content.\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)

        let previewURL = try? generatePreview(for: destination, id: id)

        let wallpaper = Wallpaper(
            id: id,
            title: source.deletingPathExtension().lastPathComponent,
            kind: .video,
            contentURL: destination,
            previewURL: previewURL,
            tags: ["imported"]
        )
        library.upsert(wallpaper)
        Log.library.log("imported video: \(wallpaper.title, privacy: .public)")
        return wallpaper
    }

    /// Import a web wallpaper from a folder containing an entry HTML file.
    @discardableResult
    func importWebFolder(at source: URL, entry: String = "index.html") throws -> Wallpaper {
        let entryURL = source.appendingPathComponent(entry)
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            throw WallpaperError.missingContent
        }

        let id = UUID().uuidString
        let dir = AppPaths.contentDirectory(for: id)
        try FileManager.default.copyItem(at: source, to: dir)

        let wallpaper = Wallpaper(
            id: id,
            title: source.lastPathComponent,
            kind: .web,
            contentURL: dir.appendingPathComponent(entry),
            tags: ["imported", "web"]
        )
        library.upsert(wallpaper)
        Log.library.log("imported web: \(wallpaper.title, privacy: .public)")
        return wallpaper
    }

    // MARK: - Thumbnails

    private func generatePreview(for videoURL: URL, id: String) throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw WallpaperError.missingContent
        }
        let previewURL = AppPaths.previews.appendingPathComponent("\(id).jpg")
        try data.write(to: previewURL, options: .atomic)
        return previewURL
    }
}
