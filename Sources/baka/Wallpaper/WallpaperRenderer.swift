import AppKit

/// What the rendering layer should currently be doing. Produced by the
/// `PowerGovernor` (global conditions) and refined per-window by occlusion.
enum RenderDirective: Equatable {
    /// Render at the given frame cap. `nil` fps means "match display".
    case play(fpsCap: Int?)
    /// Freeze on the last frame and release as much GPU/CPU as possible.
    case pause

    var isPaused: Bool { self == .pause }
}

/// A renderer owns the `NSView` that draws a single wallpaper into one
/// `WallpaperWindow`. Implementations must be cheap when paused.
@MainActor
protocol WallpaperRenderer: AnyObject {
    /// The backing view inserted into the wallpaper window's content view.
    var view: NSView { get }

    /// Load and begin presenting the given wallpaper.
    func load(_ wallpaper: Wallpaper) throws

    /// Apply the current render directive (play/pause, fps).
    func apply(_ directive: RenderDirective)

    /// Set the playback speed multiplier (1.0 = normal, 0 = frozen, 10 = 1000%).
    func setSpeed(_ multiplier: Double)

    /// Set the audio volume (0…1, 0 = muted).
    func setVolume(_ level: Double)

    /// Stop playback and free resources before the window is torn down.
    func tearDown()
}

/// Single source of truth for mapping a `WallpaperKind` to its renderer, shared
/// by the desktop controller and the in-app preview so they never diverge.
@MainActor
enum WallpaperRendererFactory {
    static func make(for kind: WallpaperKind) -> WallpaperRenderer {
        switch kind {
        case .video: return VideoWallpaperRenderer()
        case .web: return WebWallpaperRenderer()
        case .scene, .application: return PosterWallpaperRenderer()
        }
    }
}
