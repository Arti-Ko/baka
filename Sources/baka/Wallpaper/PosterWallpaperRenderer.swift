import AppKit

/// Renders a "poster" wallpaper: a static image or animated GIF.
///
/// Used for `scene` / `application` items, whose proprietary content (Wallpaper
/// Engine's compiled `.pkg`, or a Windows `.exe`) cannot run natively on macOS.
/// Rather than failing to load — the old behavior that produced a wall of
/// download errors — we present the item's bundled preview so it still shows
/// real, often-animated content on the desktop.
///
/// `NSImageView` animates GIFs for free and decodes lazily, so a paused poster
/// costs almost nothing once `animates` is turned off.
@MainActor
final class PosterWallpaperRenderer: WallpaperRenderer {
    let view: NSView

    private let imageView = NSImageView()
    private var isPaused = false

    init() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        // Preserve aspect ratio (letterbox on black) and keep animated GIFs
        // playing. Filling instead of fitting would crop unpredictably across
        // the many aspect ratios Scene previews ship in.
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = container.bounds
        container.addSubview(imageView)
        self.view = container
    }

    func load(_ wallpaper: Wallpaper) throws {
        guard !wallpaper.kind.isLiveRendered,
              let url = wallpaper.contentURL,
              let image = NSImage(contentsOf: url)
        else {
            throw WallpaperError.missingContent
        }
        imageView.image = image
        imageView.animates = !isPaused
        Log.wallpaper.log("poster loaded: \(wallpaper.title, privacy: .public) kind=\(wallpaper.kind.rawValue, privacy: .public)")
    }

    func apply(_ directive: RenderDirective) {
        isPaused = directive.isPaused
        // Stopping animation releases the decode/redraw cost entirely; the last
        // frame stays on screen.
        imageView.animates = !isPaused
    }

    /// Posters have no playback timeline, so speed is a no-op.
    func setSpeed(_ multiplier: Double) {}

    /// Posters are silent.
    func setVolume(_ level: Double) {}

    func tearDown() {
        imageView.animates = false
        imageView.image = nil
    }
}
