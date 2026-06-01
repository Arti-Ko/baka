import SwiftUI

/// Downloads tab: live progress for queued, downloading, installing, completed
/// and failed workshop downloads.
struct DownloadsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if state.downloads.tasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(state.downloads.tasks) { task in
                        DownloadRow(
                            task: task,
                            onRetry: { state.downloads.retry(task.id) },
                            onDismiss: { state.downloads.dismiss(task.id) },
                            onCancel: { state.downloads.cancel(task.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Загрузки")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.downloads.clearFinished()
                } label: {
                    Label("Очистить завершённые", systemImage: "trash")
                }
                .disabled(!state.downloads.tasks.contains { !$0.isActive })
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Нет активных загрузок")
                .foregroundStyle(.secondary)
            Text("Скачивайте обои во вкладке Workshop")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DownloadRow: View {
    let task: DownloadTask
    let onRetry: () -> Void
    let onDismiss: () -> Void
    let onCancel: () -> Void

    private var isFailed: Bool {
        if case .failed = task.state { return true } else { return false }
    }

    private var isActive: Bool {
        switch task.state {
        case .queued, .downloading, .installing: return true
        default: return false
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailImage(url: task.previewURL)
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let size = sizeString {
                        Text(size).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                statusLine
            }
            Spacer(minLength: 0)
            if isFailed {
                Button(action: onRetry) { Label("Повторить", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Убрать из списка")
            } else if isActive {
                Button(action: onCancel) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Отменить загрузку")
            } else {
                trailingIcon
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch task.state {
        case .queued:
            Text("В очереди…").font(.caption).foregroundStyle(.secondary)
        case .downloading:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
                Text(downloadStatus).font(.caption).foregroundStyle(.secondary)
            }
        case .installing:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView().progressViewStyle(.linear)
                Text("Установка…").font(.caption).foregroundStyle(.secondary)
            }
        case .completed:
            Label("Готово (\(task.source))", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).lineLimit(2)
        }
    }

    private var sizeString: String? {
        guard task.sizeBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(task.sizeBytes), countStyle: .file)
    }

    /// "SteamCMD · 42% · 54 MB из 128 MB"
    private var downloadStatus: String {
        let pct = Int(task.progress * 100)
        var parts: [String] = []
        if !task.source.isEmpty { parts.append(task.source) }
        parts.append("\(pct)%")
        if task.sizeBytes > 0 {
            let done = Int64(Double(task.sizeBytes) * task.progress)
            let total = Int64(task.sizeBytes)
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append("\(f.string(fromByteCount: done)) из \(f.string(fromByteCount: total))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailingIcon: some View {
        switch task.state {
        case .completed: Image(systemName: "checkmark").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark").foregroundStyle(.orange)
        default: EmptyView()
        }
    }
}

/// Small preview image for download rows (local file or remote URL).
private struct ThumbnailImage: View {
    let url: URL?

    var body: some View {
        if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            RemoteImage(url: url, thumbnailWidth: 160)
        }
    }
}
