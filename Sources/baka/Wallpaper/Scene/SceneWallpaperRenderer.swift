import AppKit

/// Renders a Wallpaper Engine **Scene** natively by compositing its image
/// layers, instead of falling back to a single poster.
///
/// Phase 1 scope: static layered scenes — each visible image/texture layer is
/// decoded (via `TexDecoder` for `.tex`, ImageIO otherwise) and placed as a
/// `CALayer` using the scene's orthographic projection (position, size, scale,
/// rotation, opacity, z-order). Particle systems, shader effects, per-layer
/// animation and audio reactivity are not yet rendered.
///
/// If the scene can't be parsed or no layer decodes, the renderer degrades
/// gracefully to the bundled poster image — never a blank desktop.
@MainActor
final class SceneWallpaperRenderer: WallpaperRenderer {
    let view: NSView
    private let host: SceneHostView
    private let posterImageView = NSImageView()

    init() {
        host = SceneHostView()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.autoresizingMask = [.width, .height]

        posterImageView.imageScaling = .scaleProportionallyUpOrDown
        posterImageView.imageAlignment = .alignCenter
        posterImageView.animates = true
        posterImageView.autoresizingMask = [.width, .height]
        posterImageView.isHidden = true

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        host.frame = container.bounds
        posterImageView.frame = container.bounds
        container.addSubview(host)
        container.addSubview(posterImageView)
        view = container
    }

    func load(_ wallpaper: Wallpaper) throws {
        guard let contentURL = wallpaper.contentURL else { throw WallpaperError.missingContent }
        let folder = contentURL.deletingLastPathComponent()

        if let sceneURL = Self.findSceneJSON(startingAt: contentURL, folder: folder),
           let data = try? Data(contentsOf: sceneURL),
           let document = SceneDocument.parse(data) {
            let composed = host.compose(document, folder: sceneURL.deletingLastPathComponent())
            if composed > 0 {
                posterImageView.isHidden = true
                host.isHidden = false
                Log.wallpaper.log("scene composed: \(wallpaper.title, privacy: .public) layers=\(composed)")
                return
            }
        }

        // Fallback: show the bundled poster image so the desktop is never blank.
        guard !wallpaper.kind.isLiveRendered, let image = NSImage(contentsOf: contentURL) else {
            throw WallpaperError.missingContent
        }
        host.isHidden = true
        posterImageView.isHidden = false
        posterImageView.image = image
        Log.wallpaper.log("scene fell back to poster: \(wallpaper.title, privacy: .public)")
    }

    func apply(_ directive: RenderDirective) {
        // Drive layer parallax only while playing; pause fully halts the display
        // link so a covered/on-battery scene costs nothing. The animated-GIF
        // poster fallback honors pause too.
        host.setPlaying(!directive.isPaused)
        posterImageView.animates = !directive.isPaused
    }

    func setSpeed(_ multiplier: Double) {}
    func setVolume(_ level: Double) {}

    func tearDown() {
        host.setPlaying(false)
        host.clear()
        posterImageView.animates = false
        posterImageView.image = nil
    }

    /// Locates `scene.json`: next to the content first, then a shallow search of
    /// the item folder (WE keeps it at the package root).
    static func findSceneJSON(startingAt contentURL: URL, folder: URL) -> URL? {
        if contentURL.lastPathComponent.lowercased() == "scene.json" { return contentURL }
        let direct = folder.appendingPathComponent("scene.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent.lowercased() == "scene.json" {
            return url
        }
        return nil
    }
}

/// Hosts the composited scene layers and keeps their geometry in sync with the
/// view bounds. Each layer stores its projection-space geometry so a resize just
/// recomputes frames — no re-decoding.
private final class SceneHostView: NSView {
    private struct Composited {
        let layer: CALayer
        let centerX: Double      // projection-space center (origin bottom-left, y up)
        let centerY: Double
        let pixelW: Double       // authored size × scale, in projection pixels
        let pixelH: Double
        let parallax: CGPoint    // per-axis parallax depth
    }

    private struct Emitter {
        let layer: CAEmitterLayer
        let centerX: Double
        let centerY: Double
        let parallax: CGPoint
    }

    private var projectionWidth: Double = 1920
    private var projectionHeight: Double = 1080
    private var composited: [Composited] = []
    private var emitters: [Emitter] = []

    // Parallax state.
    private var displayLink: CADisplayLink?
    private var currentLook: CGPoint = .zero
    private var targetLook: CGPoint = .zero
    private var parallaxActive = false
    private var hasParallax: Bool {
        composited.contains { $0.parallax != .zero } || !emitters.isEmpty
    }

    override var isFlipped: Bool { false } // y-up, matching WE projection space

    deinit { displayLink?.invalidate() }

    /// Builds CALayers for every decodable visible layer. Returns the count
    /// actually composited (0 → caller should fall back to a poster).
    func compose(_ document: SceneDocument, folder: URL) -> Int {
        clear()
        projectionWidth = max(document.projectionWidth, 1)
        projectionHeight = max(document.projectionHeight, 1)

        for sceneLayer in document.layers where sceneLayer.visible && sceneLayer.alpha > 0 {
            guard let url = SceneAssetResolver.textureURL(for: sceneLayer.imageRef, in: folder),
                  let cgImage = Self.decode(url) else { continue }

            let pixelW = (sceneLayer.sizeW ?? Double(cgImage.width)) * abs(sceneLayer.scaleX)
            let pixelH = (sceneLayer.sizeH ?? Double(cgImage.height)) * abs(sceneLayer.scaleY)
            guard pixelW > 0, pixelH > 0 else { continue }

            let calayer = CALayer()
            calayer.contents = cgImage
            calayer.opacity = Float(min(max(sceneLayer.alpha, 0), 1))
            calayer.zPosition = CGFloat(composited.count)
            calayer.contentsGravity = .resize
            if sceneLayer.angleZ != 0 {
                calayer.transform = CATransform3DMakeRotation(
                    CGFloat(sceneLayer.angleZ) * .pi / 180, 0, 0, 1)
            }
            layer?.addSublayer(calayer)
            composited.append(Composited(
                layer: calayer,
                centerX: sceneLayer.originX, centerY: sceneLayer.originY,
                pixelW: pixelW, pixelH: pixelH,
                parallax: CGPoint(x: sceneLayer.parallaxX, y: sceneLayer.parallaxY)
            ))
        }

        for ref in document.particles {
            guard let emitter = buildEmitter(ref, folder: folder) else { continue }
            layer?.addSublayer(emitter.layer)
            emitters.append(emitter)
        }

        needsLayout = true
        return composited.count + emitters.count
    }

    /// Resolves and builds one particle emitter; nil when the definition or its
    /// sprite can't be loaded (the rest of the scene still renders).
    private func buildEmitter(_ ref: SceneParticleRef, folder: URL) -> Emitter? {
        let url = folder.appendingPathComponent(ref.particleRef)
        guard let data = try? Data(contentsOf: url),
              let system = ParticleSystem.parse(data),
              let spriteRef = system.spriteRef,
              let spriteURL = SceneAssetResolver.textureURL(for: spriteRef, in: folder),
              let sprite = Self.decode(spriteURL)
        else { return nil }

        let config = EmitterConfig.from(system, spriteBaseSize: Double(sprite.width))
        let emitterSize = system.emitterSize > 0 ? system.emitterSize : projectionWidth
        let layer = ParticleEmitterBuilder.makeLayer(
            config: config, sprite: sprite, shape: system.shape, emitterSize: emitterSize)
        layer.zPosition = CGFloat(composited.count + emitters.count)
        return Emitter(layer: layer, centerX: ref.originX, centerY: ref.originY,
                       parallax: CGPoint(x: ref.parallaxX, y: ref.parallaxY))
    }

    func clear() {
        composited.forEach { $0.layer.removeFromSuperlayer() }
        composited.removeAll()
        emitters.forEach { $0.layer.removeFromSuperlayer() }
        emitters.removeAll()
    }

    override func layout() {
        super.layout()
        reposition()
    }

    /// Positions every layer and emitter for the current view size and parallax
    /// look vector.
    private func reposition() {
        guard !composited.isEmpty || !emitters.isEmpty else { return }

        // Aspect-fill the projection into the view.
        let scale = max(bounds.width / projectionWidth, bounds.height / projectionHeight)
        let offsetX = (bounds.width - projectionWidth * scale) / 2
        let offsetY = (bounds.height - projectionHeight * scale) / 2
        // Parallax travel scaled to the display so depth=1 shifts ~3% of it.
        let strength = min(bounds.width, bounds.height) * 0.03

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in composited {
            let w = item.pixelW * scale
            let h = item.pixelH * scale
            let shift = SceneParallax.offset(parallaxDepth: item.parallax,
                                             look: currentLook, strength: strength)
            let cx = offsetX + item.centerX * scale + shift.x
            let cy = offsetY + item.centerY * scale + shift.y
            item.layer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            item.layer.position = CGPoint(x: cx, y: cy)
        }
        for emitter in emitters {
            let shift = SceneParallax.offset(parallaxDepth: emitter.parallax,
                                             look: currentLook, strength: strength)
            emitter.layer.frame = bounds
            emitter.layer.emitterPosition = CGPoint(
                x: offsetX + emitter.centerX * scale + shift.x,
                y: offsetY + emitter.centerY * scale + shift.y)
        }
        CATransaction.commit()
    }

    // MARK: - Animation driver

    /// Starts/stops scene animation (layer parallax + particle simulation). Only
    /// runs when playing *and* the scene actually animates, so a flat scene never
    /// spins up a display link and a covered/paused scene costs nothing.
    func setPlaying(_ playing: Bool) {
        // Freeze/run the particle simulation by toggling layer time.
        for emitter in emitters { emitter.layer.speed = playing ? 1 : 0 }

        let shouldRun = playing && hasParallax
        guard shouldRun != parallaxActive else { return }
        parallaxActive = shouldRun
        if shouldRun {
            let link = displayLink ?? makeDisplayLink()
            displayLink = link
            link.isPaused = false
        } else {
            displayLink?.isPaused = true
            // Ease back to center so a paused scene rests in its neutral pose.
            currentLook = .zero
            targetLook = .zero
            reposition()
        }
    }

    private func makeDisplayLink() -> CADisplayLink {
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .current, forMode: .common)
        return link
    }

    @objc private func step(_ link: CADisplayLink) {
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        targetLook = SceneParallax.look(mouse: NSEvent.mouseLocation,
                                        in: screen?.frame ?? bounds)
        currentLook = SceneParallax.smoothed(currentLook, toward: targetLook, factor: 0.12)
        reposition()
    }

    /// Decodes a layer asset: `.tex` via TexDecoder, anything else via ImageIO.
    static func decode(_ url: URL) -> CGImage? {
        if url.pathExtension.lowercased() == "tex" {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return TexDecoder.decodeImage(from: data)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return TexDecoder.cgImageFromFileBytes(data)
    }
}
