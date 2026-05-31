import Foundation
import IOKit.ps

/// Observes the system power source (AC vs battery) and Low Power Mode,
/// publishing changes on the main actor so the governor can react instantly.
@MainActor
final class PowerSourceMonitor: ObservableObject {
    @Published private(set) var isOnBattery: Bool = false
    @Published private(set) var isLowPowerMode: Bool = false

    private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
        startObserving()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    private func startObserving() {
        // IOKit power-source change callback. We pass `self` as context and
        // bounce back onto the main actor to mutate published state.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }

        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        // Low Power Mode toggles via NSProcessInfo notification.
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        isOnBattery = Self.currentlyOnBattery()
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        Log.power.debug("power refresh: battery=\(self.isOnBattery) lowPower=\(self.isLowPowerMode)")
    }

    /// Returns true when the providing power source is the internal battery.
    /// Desktops (always AC) report false.
    private static func currentlyOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String?
        else {
            return false
        }
        return providing == kIOPSBatteryPowerValue
    }
}
