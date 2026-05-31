import AppKit
import Combine

/// Orchestrates wallpaper windows across all screens: creates one window per
/// display, applies the per-screen assignment from `Settings`, reacts to
/// monitor hotplug, and fans out the global power directive to every window.
@MainActor
final class WallpaperController: ObservableObject {
    private let library: WallpaperLibrary
    private let screens: ScreenManager
    private let governor: PowerGovernor

    /// screenKey -> live window
    private var windows: [String: WallpaperWindow] = [:]
    /// screenKey -> kind currently rendered, so we can rebuild on kind change.
    private var windowKinds: [String: WallpaperKind] = [:]
    private var settings: AppSettings

    init(
        library: WallpaperLibrary,
        screens: ScreenManager,
        governor: PowerGovernor,
        settings: AppSettings
    ) {
        self.library = library
        self.screens = screens
        self.governor = governor
        self.settings = settings

        screens.onChange = { [weak self] in self?.syncWindows() }
        governor.onChange = { [weak self] directive in self?.broadcast(directive) }
    }

    func start() {
        syncWindows()
    }

    /// Tears down every wallpaper window and its renderer (stops AVPlayers /
    /// WKWebViews). Called on app termination so nothing keeps the process alive.
    func tearDownAll() {
        for window in windows.values { window.close(tearingDown: true) }
        windows.removeAll()
        windowKinds.removeAll()
    }

    /// Apply a freshly edited settings object (assignments + power policy).
    func applySettings(_ newSettings: AppSettings) {
        settings = newSettings
        governor.updatePolicy(newSettings.power)
        for window in windows.values {
            window.pauseWhenCovered = newSettings.power.pauseWhenCovered
        }
        syncWindows()
        broadcast(governor.directive)
    }

    /// Assigns a wallpaper to one screen and reloads just that window.
    func assign(wallpaperID: String?, toScreen key: String) {
        settings = settings.assigning(wallpaperID, toScreen: key)
        SettingsStore.save(settings)
        reload(screenKey: key)
    }

    // MARK: - Window lifecycle

    private func syncWindows() {
        let liveKeys = Set(screens.screens.map(\.key))

        // Tear down windows for disconnected screens.
        for key in windows.keys where !liveKeys.contains(key) {
            windows[key]?.close(tearingDown: true)
            windows.removeValue(forKey: key)
            windowKinds.removeValue(forKey: key)
        }

        // Create or reposition windows for current screens.
        for info in screens.screens {
            guard let nsScreen = screens.screen(forKey: info.key) else { continue }
            if let existing = windows[info.key] {
                existing.moveTo(screen: nsScreen)
            } else {
                createWindow(for: info.key, on: nsScreen)
            }
            reload(screenKey: info.key)
        }
    }

    private func createWindow(for key: String, on screen: NSScreen) {
        guard let wallpaper = assignedWallpaper(for: key) else {
            // No assignment yet — defer window creation until one is chosen.
            return
        }
        let renderer = makeRenderer(for: wallpaper.kind)
        let window = WallpaperWindow(screen: screen, renderer: renderer)
        window.pauseWhenCovered = settings.power.pauseWhenCovered
        windows[key] = window
        windowKinds[key] = wallpaper.kind
        window.show()
    }

    private func reload(screenKey key: String) {
        guard let nsScreen = screens.screen(forKey: key) else { return }

        guard let wallpaper = assignedWallpaper(for: key) else {
            // Assignment cleared: remove the window so the OS wallpaper shows.
            windows[key]?.close(tearingDown: true)
            windows.removeValue(forKey: key)
            windowKinds.removeValue(forKey: key)
            return
        }

        // Rebuild the window if the renderer kind changed (video <-> web).
        if let existingKind = windowKinds[key], existingKind != wallpaper.kind {
            windows[key]?.close(tearingDown: true)
            windows.removeValue(forKey: key)
            windowKinds.removeValue(forKey: key)
        }

        // Recreate the window if it doesn't exist.
        if windows[key] == nil {
            createWindow(for: key, on: nsScreen)
        }

        guard let window = windows[key] else { return }
        do {
            try window.load(wallpaper)
            window.updateDirective(governor.directive)
            window.setVolume(effectiveVolume(for: wallpaper))
        } catch {
            Log.wallpaper.error("Failed to load wallpaper on \(key): \(error.localizedDescription)")
        }
    }

    private func broadcast(_ directive: RenderDirective) {
        for window in windows.values {
            window.updateDirective(directive)
        }
    }

    /// Per-wallpaper volume, silenced entirely by the global mute switch.
    private func effectiveVolume(for wallpaper: Wallpaper) -> Double {
        settings.power.muted ? 0 : wallpaper.volumeLevel
    }

    // MARK: - Helpers

    private func assignedWallpaper(for key: String) -> Wallpaper? {
        guard let id = settings.assignedWallpaperID(forScreen: key) else { return nil }
        let wallpaper = library.wallpaper(withID: id)
        return wallpaper?.isInstalled == true ? wallpaper : nil
    }

    private func makeRenderer(for kind: WallpaperKind) -> WallpaperRenderer {
        switch kind {
        case .video: return VideoWallpaperRenderer()
        case .web: return WebWallpaperRenderer()
        }
    }
}
