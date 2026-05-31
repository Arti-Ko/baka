import SwiftUI
import AppKit

/// Power & performance settings — the controls behind baka's battery story.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    Text("Baka")
                        .font(.system(size: 22, weight: .bold))
                    Text(AppVersion.displayString)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Питание и производительность") {
                Picker("На батарее", selection: batteryBehavior) {
                    ForEach(BatteryBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                }

                if state.settings.power.batteryBehavior == .throttle {
                    Stepper(value: batteryFPS, in: 10...60, step: 5) {
                        Text("Лимит FPS на батарее: \(state.settings.power.batteryFPSCap)")
                    }
                }

                Toggle("Пауза, когда обои перекрыты окном", isOn: pauseWhenCovered)
                Toggle("Пауза в режиме энергосбережения", isOn: pauseInLowPower)
                Toggle("Без звука", isOn: muted)
            }

            SteamSettingsView(steam: state.steam)

            Section("О программе") {
                HStack {
                    Button {
                        Task { await state.updater.check(manual: true) }
                    } label: {
                        Label("Проверить обновления", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(state.updater.isChecking)
                    if state.updater.isChecking { ProgressView().controlSize(.small) }
                }
                if let message = state.updater.statusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Состояние") {
                LabeledContent("Источник питания",
                               value: state.powerSource.isOnBattery ? "Батарея" : "Сеть")
                LabeledContent("Режим энергосбережения",
                               value: state.powerSource.isLowPowerMode ? "Вкл" : "Выкл")
                LabeledContent("Рендеринг",
                               value: state.governor.directive.isPaused ? "Пауза" : "Активен")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки")
    }

    // MARK: - Bindings that route mutations through AppState

    private var batteryBehavior: Binding<BatteryBehavior> {
        Binding(
            get: { state.settings.power.batteryBehavior },
            set: { var p = state.settings.power; p.batteryBehavior = $0; state.updatePower(p) }
        )
    }

    private var batteryFPS: Binding<Int> {
        Binding(
            get: { state.settings.power.batteryFPSCap },
            set: { var p = state.settings.power; p.batteryFPSCap = $0; state.updatePower(p) }
        )
    }

    private var pauseWhenCovered: Binding<Bool> {
        Binding(
            get: { state.settings.power.pauseWhenCovered },
            set: { var p = state.settings.power; p.pauseWhenCovered = $0; state.updatePower(p) }
        )
    }

    private var pauseInLowPower: Binding<Bool> {
        Binding(
            get: { state.settings.power.pauseInLowPowerMode },
            set: { var p = state.settings.power; p.pauseInLowPowerMode = $0; state.updatePower(p) }
        )
    }

    private var muted: Binding<Bool> {
        Binding(
            get: { state.settings.power.muted },
            set: { var p = state.settings.power; p.muted = $0; state.updatePower(p) }
        )
    }
}
