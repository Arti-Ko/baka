import SwiftUI

/// The menu bar dropdown: quick power state, a global pause toggle, and access
/// to the main window / settings / quit. Lets baka live in the menu bar like a
/// real wallpaper engine.
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text(statusText)

            Divider()

            Button(pauseToggleLabel) { toggleGlobalPause() }

            Button("Открыть библиотеку…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            Divider()

            Button("Выход") { NSApp.terminate(nil) }
        }
    }

    private var statusText: String {
        if state.governor.directive.isPaused { return "Baka — пауза" }
        return state.powerSource.isOnBattery ? "Baka — от батареи" : "Baka — активен"
    }

    private var pauseToggleLabel: String {
        state.settings.power.batteryBehavior == .pause && state.powerSource.isOnBattery
            ? "Возобновить"
            : "Пауза на батарее"
    }

    /// Quick toggle: flips the battery behavior between full speed and pause.
    private func toggleGlobalPause() {
        var policy = state.settings.power
        policy.batteryBehavior = policy.batteryBehavior == .pause ? .fullSpeed : .pause
        state.updatePower(policy)
    }
}
