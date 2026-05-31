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
                        DownloadRow(task: task)
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

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailImage(url: task.previewURL)
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                statusLine
            }
            Spacer(minLength: 0)
            trailingIcon
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
                ProgressView()
                    .progressViewStyle(.linear)
                Text(task.source.isEmpty ? "Скачивание…" : "Скачивание через \(task.source)…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
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
