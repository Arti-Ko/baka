import AppKit

/// A borderless, click-through window pinned behind the desktop icons on a
/// single screen. It hosts one renderer and combines the global power
/// directive with its own occlusion state (e.g. a fullscreen app covering this
/// screen) to decide whether to actually render.
@MainActor
final class WallpaperWindow: NSWindow {
    private let renderer: WallpaperRenderer
    private var globalDirective: RenderDirective = .play(fpsCap: nil)
    private var muted: Bool = true
    private var occlusionObserver: NSObjectProtocol?

    /// When true, this window's content is currently visible to the user.
    private var isVisibleOnScreen = true

    /// Honor the user policy of pausing when fully covered.
    var pauseWhenCovered = true

    init(screen: NSScreen, renderer: WallpaperRenderer) {
        self.renderer = renderer
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureForDesktop(on: screen)
        installRenderer()
        observeOcclusion()
    }

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    private func configureForDesktop(on screen: NSScreen) {
        // Sit just above the wallpaper but below the desktop icons.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true        // clicks pass through to the desktop
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: true)
    }

    private func installRenderer() {
        let host = NSView(frame: contentRect(forFrameRect: frame))
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        renderer.view.frame = host.bounds
        renderer.view.autoresizingMask = [.width, .height]
        host.addSubview(renderer.view)
        contentView = host
    }

    private func observeOcclusion() {
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.occlusionChanged() }
        }
    }

    // MARK: - Public control

    func show() {
        orderFront(nil)
        applyEffectiveDirective()
    }

    func load(_ wallpaper: Wallpaper) throws {
        try renderer.load(wallpaper)
        applyEffectiveDirective()
    }

    func updateDirective(_ directive: RenderDirective, muted: Bool) {
        globalDirective = directive
        self.muted = muted
        applyEffectiveDirective()
    }

    func moveTo(screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }

    func close(tearingDown: Bool) {
        if tearingDown { renderer.tearDown() }
        orderOut(nil)
    }

    // MARK: - Effective state

    private func occlusionChanged() {
        isVisibleOnScreen = occlusionState.contains(.visible)
        Log.wallpaper.debug("occlusion visible=\(self.isVisibleOnScreen)")
        applyEffectiveDirective()
    }

    /// The window renders only when the global directive says play AND the
    /// content is actually visible (unless the user disabled occlusion pause).
    private func applyEffectiveDirective() {
        let coveredAndShouldPause = pauseWhenCovered && !isVisibleOnScreen
        let effective: RenderDirective = (globalDirective.isPaused || coveredAndShouldPause)
            ? .pause
            : globalDirective
        renderer.apply(effective, muted: muted)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
