import Foundation
import AppKit

/// Centralizes the decision of how wallpapers should render *right now*,
/// combining power source, Low Power Mode, screen lock / display sleep, and
/// the user's `PowerPolicy` into a single global `RenderDirective`.
///
/// Per-window occlusion (a fullscreen app covering one screen) is layered on
/// top by each `WallpaperWindow`, so this governor only handles the
/// machine-wide conditions.
@MainActor
final class PowerGovernor: ObservableObject {
    @Published private(set) var directive: RenderDirective = .play(fpsCap: nil)

    private let powerSource: PowerSourceMonitor
    private var policy: PowerPolicy
    private var displayAsleep = false
    private var screenLocked = false
    private var observers: [NSObjectProtocol] = []

    /// Called whenever the directive changes so the controller can push it.
    var onChange: ((RenderDirective) -> Void)?

    init(powerSource: PowerSourceMonitor, policy: PowerPolicy) {
        self.powerSource = powerSource
        self.policy = policy
        observeSystemEvents()
        recompute()
    }

    deinit {
        for token in observers {
            DistributedNotificationCenter.default().removeObserver(token)
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func updatePolicy(_ newPolicy: PowerPolicy) {
        policy = newPolicy
        recompute()
    }

    /// Re-evaluate after a published power-source change.
    func powerConditionsChanged() {
        recompute()
    }

    // MARK: - System event wiring

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter

        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.displayAsleep = true; self?.recompute() }
        })

        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.displayAsleep = false; self?.recompute() }
        })

        // Screen lock / unlock arrives over the distributed notification center.
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenLocked = true; self?.recompute() }
        })
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenLocked = false; self?.recompute() }
        })
    }

    // MARK: - Decision

    private func recompute() {
        let next = computeDirective()
        guard next != directive else { return }
        directive = next
        Log.power.log("directive -> \(String(describing: next))")
        onChange?(next)
    }

    private func computeDirective() -> RenderDirective {
        // Hard pause conditions first — nothing is visible anyway.
        if displayAsleep || screenLocked {
            return .pause
        }

        if policy.pauseInLowPowerMode && powerSource.isLowPowerMode {
            return .pause
        }

        if powerSource.isOnBattery {
            switch policy.batteryBehavior {
            case .pause:
                return .pause
            case .throttle:
                return .play(fpsCap: policy.batteryFPSCap)
            case .fullSpeed:
                return .play(fpsCap: acFPSCap())
            }
        }

        return .play(fpsCap: acFPSCap())
    }

    private func acFPSCap() -> Int? {
        policy.acFPSCap > 0 ? policy.acFPSCap : nil
    }
}
