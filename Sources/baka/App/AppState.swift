import SwiftUI
import Combine
import AppKit

/// Central composition root and observable state for the whole app.
/// Owns the long-lived services and wires them together once at launch.
@MainActor
final class AppState: ObservableObject {
    let library: WallpaperLibrary
    let screens: ScreenManager
    let powerSource: PowerSourceMonitor
    let governor: PowerGovernor
    let controller: WallpaperController
    let importer: WallpaperImporter
    let workshopClient: WorkshopClient
    let workshopInstaller: WorkshopInstaller
    let steam: SteamSession
    let downloads: DownloadManager
    let updater = UpdateChecker()

    @Published var settings: AppSettings {
        didSet { SettingsStore.save(settings) }
    }

    private var cancellables: Set<AnyCancellable> = []

    init() {
        try? AppPaths.ensureDirectories()

        let loadedSettings = SettingsStore.load()
        let library = WallpaperLibrary()
        let screens = ScreenManager()
        let powerSource = PowerSourceMonitor()
        let governor = PowerGovernor(powerSource: powerSource, policy: loadedSettings.power)
        let controller = WallpaperController(
            library: library,
            screens: screens,
            governor: governor,
            settings: loadedSettings
        )

        self.settings = loadedSettings
        self.library = library
        self.screens = screens
        self.powerSource = powerSource
        self.governor = governor
        self.controller = controller
        let client = SteamWorkshopClient()
        let installer = WorkshopInstaller(library: library)
        let steam = SteamSession()
        self.importer = WallpaperImporter(library: library)
        self.workshopClient = client
        self.workshopInstaller = installer
        self.steam = steam
        self.downloads = DownloadManager(
            steam: steam, installer: installer, library: library, client: client
        )

        // Power-source changes feed the governor so it can re-evaluate.
        powerSource.objectWillChange
            .sink { [weak governor] in
                Task { @MainActor in governor?.powerConditionsChanged() }
            }
            .store(in: &cancellables)

        // Re-publish nested observable objects through AppState so any view
        // observing `state` refreshes when the library, screens, downloads,
        // power, or Steam session change.
        let nested: [ObservableObjectPublisher] = [
            library.objectWillChange, screens.objectWillChange,
            powerSource.objectWillChange, governor.objectWillChange,
            downloads.objectWillChange, steam.objectWillChange,
            updater.objectWillChange
        ]
        for publisher in nested {
            publisher
                .sink { [weak self] in Task { @MainActor in self?.objectWillChange.send() } }
                .store(in: &cancellables)
        }

        // Guarantee the app actually quits: tear down the live wallpaper windows
        // (AVPlayer / WKWebView) and hard-exit, so an active wallpaper can never
        // keep the process alive and force a "Force Quit".
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.tearDownAll() }
            exit(0)
        }
    }

    func start() {
        controller.start()
        // Silent update check on launch (respects skipped versions).
        Task { await updater.check(manual: false) }
    }

    func makeWorkshopBrowser() -> WorkshopBrowser {
        WorkshopBrowser(client: workshopClient, library: library, downloads: downloads)
    }

    // MARK: - Mutations that flow back into the controller

    func updatePower(_ policy: PowerPolicy) {
        settings = settings.withPower(policy)
        controller.applySettings(settings)
    }

    func assign(wallpaperID: String?, toScreen key: String) {
        controller.assign(wallpaperID: wallpaperID, toScreen: key)
        // Keep our copy of settings in sync for the UI.
        settings = settings.assigning(wallpaperID, toScreen: key)
    }

    /// Removes every wallpaper and all downloaded content, clears monitor
    /// assignments, and tears down active wallpaper windows. Keeps power
    /// settings and the Steam login.
    func resetAllContent() {
        var cleared = settings
        cleared.assignments = [:]
        settings = cleared
        controller.applySettings(cleared) // tears down windows
        downloads.clearAll()
        library.removeAll()
    }
}
