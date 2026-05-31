import AppKit

/// A connected display, paired with a stable identity key that survives
/// reconnects and `NSScreen` reordering.
struct ScreenInfo: Identifiable, Equatable {
    let key: String
    let displayID: CGDirectDisplayID
    let name: String
    let frame: NSRect

    var id: String { key }

    static func == (lhs: ScreenInfo, rhs: ScreenInfo) -> Bool {
        lhs.key == rhs.key && lhs.frame == rhs.frame
    }
}

/// Observes display connect/disconnect and resolution changes, exposing the
/// current set of screens with stable keys for per-monitor assignment.
@MainActor
final class ScreenManager: ObservableObject {
    @Published private(set) var screens: [ScreenInfo] = []

    /// Fired after the screen set changes so the controller can re-place windows.
    var onChange: (() -> Void)?

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleParametersChanged() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func screen(forKey key: String) -> NSScreen? {
        NSScreen.screens.first { Self.key(for: $0) == key }
    }

    private func handleParametersChanged() {
        refresh()
        onChange?()
    }

    private func refresh() {
        screens = NSScreen.screens.map { screen in
            ScreenInfo(
                key: Self.key(for: screen),
                displayID: Self.displayID(for: screen),
                name: screen.localizedName,
                frame: screen.frame
            )
        }
        Log.screens.log("screens: \(self.screens.map(\.name).joined(separator: ", "), privacy: .public)")
    }

    // MARK: - Stable identity

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    /// Builds a key from the display's vendor/model/serial so it stays stable
    /// across reconnects. Falls back to name + size when those are unavailable
    /// (e.g. some virtual or built-in displays report zeros).
    static func key(for screen: NSScreen) -> String {
        let id = displayID(for: screen)
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        let serial = CGDisplaySerialNumber(id)
        if vendor != 0 || model != 0 || serial != 0 {
            return "disp-\(vendor)-\(model)-\(serial)"
        }
        let size = screen.frame.size
        return "name-\(screen.localizedName)-\(Int(size.width))x\(Int(size.height))"
    }
}
