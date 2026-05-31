import Foundation

/// What baka does with animated wallpapers when the machine is running on
/// battery. Defaults are chosen to protect battery life out of the box.
enum BatteryBehavior: String, Codable, CaseIterable, Sendable {
    /// Stop rendering entirely; show the last frame as a static image.
    case pause
    /// Keep playing but cap the frame rate to `PowerPolicy.batteryFPSCap`.
    case throttle
    /// Keep full playback (not recommended for laptops).
    case fullSpeed

    var label: String {
        switch self {
        case .pause: return "Пауза (статичный кадр)"
        case .throttle: return "Снизить FPS"
        case .fullSpeed: return "Без ограничений"
        }
    }
}

/// User-tunable performance/power policy. Immutable; UI produces new copies.
struct PowerPolicy: Codable, Equatable, Sendable {
    /// Behavior while on battery power.
    var batteryBehavior: BatteryBehavior = .pause

    /// Pause rendering when a fullscreen app or any opaque window fully covers
    /// the desktop (driven by the window occlusion state — essentially free).
    var pauseWhenCovered: Bool = true

    /// Pause when macOS Low Power Mode is enabled, regardless of power source.
    var pauseInLowPowerMode: Bool = true

    /// Frame-rate cap applied when `batteryBehavior == .throttle`.
    var batteryFPSCap: Int = 30

    /// Frame-rate cap on AC power. 0 means "match display refresh rate".
    var acFPSCap: Int = 0

    /// Master mute — silences every wallpaper regardless of its own volume.
    /// Off by default; per-wallpaper volume (also 0 by default) is the primary
    /// control.
    var muted: Bool = false

    static let `default` = PowerPolicy()
}
