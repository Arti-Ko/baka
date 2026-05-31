import AppKit
import AVFoundation

/// Renders a looping video wallpaper using AVFoundation, which decodes on the
/// GPU and is the most battery-friendly path for moving wallpapers.
///
/// `AVPlayerLooper` gives gapless looping; pausing fully halts decode so a
/// paused wallpaper costs essentially nothing.
@MainActor
final class VideoWallpaperRenderer: WallpaperRenderer {
    let view: NSView

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()

    /// Desired playback multiplier (1.0 = normal). 0 freezes the video.
    private var speed: Double = 1.0
    private var isPaused = false

    init() {
        let container = LayerHostingView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = player
        container.hostedLayer = playerLayer
        self.view = container

        player.isMuted = true
        // Loop locally; do not let playback hold up app sleep transitions.
        player.actionAtItemEnd = .none
    }

    func load(_ wallpaper: Wallpaper) throws {
        guard wallpaper.kind == .video, let url = wallpaper.contentURL else {
            throw WallpaperError.missingContent
        }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        looper = AVPlayerLooper(player: player, templateItem: item)
        speed = wallpaper.speedMultiplier
        isPaused = false
        applyRate()
        Log.wallpaper.log("video loaded: \(wallpaper.title, privacy: .public) speed=\(self.speed)")
    }

    func apply(_ directive: RenderDirective, muted: Bool) {
        player.isMuted = muted
        switch directive {
        case .pause:
            isPaused = true
        case .play:
            // Hardware video decode is already efficient; the fps cap is
            // honored by Metal/web renderers, not by AVFoundation playback.
            isPaused = false
        }
        applyRate()
    }

    func setSpeed(_ multiplier: Double) {
        speed = max(0, multiplier)
        applyRate()
    }

    /// Drives the player rate from the current speed + pause state. A speed of
    /// 0 (or a pause directive) halts decode entirely.
    private func applyRate() {
        let rate = (isPaused || speed <= 0) ? 0 : Float(speed)
        if rate == 0 {
            player.pause()
        } else {
            player.rate = rate
        }
    }

    func tearDown() {
        player.pause()
        player.removeAllItems()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
    }
}

/// An NSView whose single hosted layer is kept matched to the view bounds.
final class LayerHostingView: NSView {
    var hostedLayer: CALayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let hostedLayer {
                hostedLayer.frame = bounds
                layer?.addSublayer(hostedLayer)
            }
        }
    }

    override func layout() {
        super.layout()
        // Avoid implicit animations on resize for snappy, cheap relayout.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostedLayer?.frame = bounds
        CATransaction.commit()
    }
}

enum WallpaperError: Error {
    case missingContent
    case unsupportedKind
}
