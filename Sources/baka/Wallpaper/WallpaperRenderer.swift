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

    /// Apply the current render directive (play/pause, fps, mute).
    func apply(_ directive: RenderDirective, muted: Bool)

    /// Stop playback and free resources before the window is torn down.
    func tearDown()
}
