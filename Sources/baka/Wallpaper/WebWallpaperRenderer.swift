import AppKit
import WebKit

/// Renders an HTML/WebGL wallpaper in a `WKWebView`.
///
/// Power handling:
/// - **pause** navigates the web view to `about:blank`, which fully stops the
///   page's timers, animation loop, and GPU work (web content can't otherwise
///   be reliably frozen from outside).
/// - **fps cap** injects a user script at document start that throttles
///   `requestAnimationFrame` to the requested rate.
@MainActor
final class WebWallpaperRenderer: WallpaperRenderer {
    let view: NSView

    private let webView: WKWebView
    private var currentURL: URL?
    private var currentFPSCap: Int?
    private var isBlanked = false

    init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground") // transparent background
        web.autoresizingMask = [.width, .height]
        self.webView = web
        self.view = web
    }

    func load(_ wallpaper: Wallpaper) throws {
        guard wallpaper.kind == .web, let url = wallpaper.contentURL else {
            throw WallpaperError.missingContent
        }
        currentURL = url
        isBlanked = false
        installFPSCapScript(currentFPSCap)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        Log.wallpaper.log("web loaded: \(wallpaper.title, privacy: .public)")
    }

    func apply(_ directive: RenderDirective, muted: Bool) {
        // Web audio mute is best-effort via injected script.
        switch directive {
        case .pause:
            blank()
        case .play(let fpsCap):
            if fpsCap != currentFPSCap {
                currentFPSCap = fpsCap
                installFPSCapScript(fpsCap)
                isBlanked = true // force a reload to apply the new cap
            }
            resume()
        }
    }

    func tearDown() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        currentURL = nil
    }

    // MARK: - Pause / resume

    private func blank() {
        guard !isBlanked else { return }
        isBlanked = true
        webView.loadHTMLString("<html><body style=\"background:black\"></body></html>", baseURL: nil)
    }

    private func resume() {
        guard isBlanked, let url = currentURL else { return }
        isBlanked = false
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: - FPS throttling

    private func installFPSCapScript(_ fpsCap: Int?) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        guard let fpsCap, fpsCap > 0 else { return }
        let interval = 1000.0 / Double(fpsCap)
        let js = """
        (function() {
          const minInterval = \(interval);
          let last = 0;
          const nativeRAF = window.requestAnimationFrame.bind(window);
          window.requestAnimationFrame = function(cb) {
            return nativeRAF(function(ts) {
              if (ts - last >= minInterval) { last = ts; cb(ts); }
              else { window.requestAnimationFrame(cb); }
            });
          };
        })();
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(script)
    }
}
