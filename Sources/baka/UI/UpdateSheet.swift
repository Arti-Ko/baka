import SwiftUI

/// Update dialog: shows the new version and its release notes with three
/// choices — update now, remind me next time, or skip this version.
struct UpdateSheet: View {
    @ObservedObject var updater: UpdateChecker
    let info: UpdateInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            notes
            Divider()
            footer
        }
        .frame(width: 520, height: 460)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Доступно обновление Baka")
                    .font(.title3.weight(.semibold))
                Text("\(AppVersion.displayString)  →  v\(info.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(info.name)
                    .font(.headline)
                Text(info.notes)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if updater.isInstalling {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(updater.updatePhase.isEmpty ? "Обновление…" : updater.updatePhase)
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(updater.updateProgress * 100))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: updater.updateProgress)
                    .progressViewStyle(.linear)
                Text("Приложение перезапустится автоматически. Не закрывайте окно.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let error = updater.installError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    Button("Пропустить версию") { updater.skip() }
                        .help("Больше не предлагать эту версию")
                    Spacer()
                    Button("В следующий раз") { updater.remindLater() }
                    Button("Обновиться сейчас") { updater.updateNow() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }
}
