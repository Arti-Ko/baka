import SwiftUI

/// One tracked download shown in the Downloads tab.
struct DownloadTask: Identifiable, Equatable {
    enum State: Equatable {
        case queued
        case downloading        // indeterminate (steamcmd is headless)
        case installing
        case completed
        case failed(String)
    }

    let id: String              // workshop id
    let title: String
    let previewURL: URL?
    var state: State = .queued
    var progress: Double = 0    // 0…1 during .downloading
    var sizeBytes: Int = 0      // content size, for display
    var source: String = ""     // "Steam" | "SteamCMD" | "Direct"

    var isActive: Bool {
        switch state {
        case .queued, .downloading, .installing: return true
        case .completed, .failed: return false
        }
    }
}

/// Central queue that performs workshop downloads.
///
/// Cheapest source first: local Steam → direct file_url → SteamCMD. Crucially,
/// all SteamCMD-bound items in the queue are downloaded in a SINGLE batched
/// steamcmd session (one login) to avoid Steam login rate-limiting, which was
/// the cause of intermittent "session unavailable" errors.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []

    private let steam: SteamSession
    private let installer: WorkshopInstaller
    private let library: WallpaperLibrary
    private let client: WorkshopClient

    private var items: [String: WorkshopItem] = [:]
    private var processing = false
    /// Items the user cancelled mid-batch (dropped on the current batch's return).
    private var cancelledIDs: Set<String> = []
    /// True when the active batch process was killed by a cancellation, so the
    /// surviving items should be re-queued rather than marked failed.
    private var batchInterrupted = false

    var activeCount: Int { tasks.filter(\.isActive).count }

    init(steam: SteamSession, installer: WorkshopInstaller,
         library: WallpaperLibrary, client: WorkshopClient) {
        self.steam = steam
        self.installer = installer
        self.library = library
        self.client = client
        restore()
    }

    func isQueuedOrActive(_ id: String) -> Bool {
        tasks.contains { $0.id == id && $0.isActive }
    }

    /// Removes only completed downloads; failed/incomplete ones stay so the
    /// user can retry or let them resume.
    func clearFinished() {
        tasks.removeAll { if case .completed = $0.state { return true } else { return false } }
        persist()
    }

    func clearAll() {
        tasks.removeAll()
        items.removeAll()
        persist()
    }

    /// Dismiss a single task (e.g. a failed one the user no longer wants).
    func dismiss(_ id: String) {
        tasks.removeAll { $0.id == id }
        items.removeValue(forKey: id)
        persist()
    }

    /// Adds an item to the queue (no-op if already active) and kicks the worker.
    func enqueue(_ item: WorkshopItem) {
        guard !isQueuedOrActive(item.id) else { return }
        items[item.id] = item
        var task = DownloadTask(id: item.id, title: item.title, previewURL: item.previewURL)
        task.sizeBytes = item.fileSize
        upsert(task)
        persist()
        Task { await processQueue() }
    }

    /// Retry a previously failed download.
    func retry(_ id: String) {
        guard items[id] != nil else { return }
        update(id) { $0.state = .queued }
        persist()
        Task { await processQueue() }
    }

    /// Cancel a download. Queued items are simply dropped; an actively
    /// downloading item terminates the SteamCMD process (other items in the
    /// same batch are re-queued and resume in a fresh batch).
    func cancel(_ id: String) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        switch task.state {
        case .queued, .completed, .failed:
            dismiss(id)
        case .downloading, .installing:
            cancelledIDs.insert(id)
            batchInterrupted = true
            tasks.removeAll { $0.id == id }
            items.removeValue(forKey: id)
            persist()
            Task { await steam.cancelDownload() }
        }
    }

    // MARK: - Queue worker

    private func processQueue() async {
        guard !processing else { return }
        processing = true
        defer { processing = false }

        while true {
            let queued = tasks.filter { $0.state == .queued }
            guard !queued.isEmpty else { break }

            var steamcmdItems: [WorkshopItem] = []
            for task in queued {
                guard let item = items[task.id] else { continue }

                // 1. Local Steam install — instant.
                if let folder = SteamLocator.localFolder(forItem: item.id) {
                    await install(from: folder, item: item, source: "Steam")
                    continue
                }
                // 2. Direct file_url (rare for WE).
                if let direct = try? await client.downloadability(for: item),
                   case .direct(let url, let kind) = direct {
                    await downloadDirect(item, from: url, kind: kind)
                    continue
                }
                // 3. Defer to a single batched SteamCMD run.
                update(item.id) { $0.state = .downloading; $0.source = "SteamCMD" }
                steamcmdItems.append(item)
            }

            if !steamcmdItems.isEmpty {
                await runSteamCMDBatch(steamcmdItems)
            }
        }
    }

    private func runSteamCMDBatch(_ batch: [WorkshopItem]) async {
        guard steam.isLoggedIn else {
            for item in batch { fail(item.id, "Войдите в Steam в Настройках") }
            return
        }
        let byID = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
        let ids = batch.map(\.id)
        do {
            let results = try await steam.downloadItems(ids) { [weak self] id, fraction in
                Task { @MainActor in
                    self?.update(id) {
                        if fraction >= 1.0 {
                            $0.progress = 1
                            $0.state = .installing
                        } else {
                            $0.progress = fraction
                            $0.state = .downloading
                        }
                    }
                }
            }
            let interrupted = batchInterrupted
            batchInterrupted = false
            for id in ids {
                // Item the user cancelled mid-batch → already removed, drop it.
                if cancelledIDs.remove(id) != nil { continue }
                guard let item = byID[id] else { continue }
                switch results[id] ?? .failed("Нет результата") {
                case .success(let folder):
                    await install(from: folder, item: item, source: "SteamCMD")
                case .notLoggedIn:
                    fail(id, "Сессия Steam недоступна — войдите заново в Настройках")
                case .failed(let message):
                    // If the process was killed by a cancellation, the other
                    // items weren't really failures — re-queue them to resume.
                    if interrupted {
                        update(id) { $0.state = .queued; $0.progress = 0 }
                    } else {
                        fail(id, message)
                    }
                }
            }
        } catch {
            let interrupted = batchInterrupted
            batchInterrupted = false
            for id in ids where cancelledIDs.remove(id) == nil {
                if interrupted { update(id) { $0.state = .queued; $0.progress = 0 } }
                else { fail(id, error.localizedDescription) }
            }
        }
    }

    // MARK: - Install

    private func install(from folder: URL, item: WorkshopItem, source: String) async {
        update(item.id) { $0.state = .installing; $0.source = source }
        do {
            try await installer.install(from: folder, workshopID: item.id, fallback: item)
            update(item.id) { $0.state = .completed }
            persist()
        } catch {
            fail(item.id, "Установка не удалась: \(friendly(error))")
        }
    }

    private func downloadDirect(_ item: WorkshopItem, from url: URL, kind: WallpaperKind) async {
        update(item.id) { $0.state = .downloading; $0.source = "Direct" }
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            let id = "ws-\(item.id)"
            let dir = AppPaths.contentDirectory(for: id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = kind == .video ? "mp4" : "html"
            let destination = dir.appendingPathComponent("content.\(ext)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)

            var previewURL: URL?
            if let preview = item.previewURL,
               let (data, _) = try? await URLSession.shared.data(from: preview) {
                let p = AppPaths.previews.appendingPathComponent("\(id).jpg")
                try? data.write(to: p, options: .atomic)
                previewURL = p
            }
            library.upsert(Wallpaper(
                id: id, title: item.title, kind: kind,
                contentURL: destination, previewURL: previewURL,
                workshopID: item.id, author: item.author, tags: ["workshop"]
            ))
            update(item.id) { $0.state = .completed; $0.progress = 1 }
            persist()
        } catch {
            fail(item.id, friendly(error))
        }
    }

    /// Maps internal wallpaper errors to readable Russian messages.
    private func friendly(_ error: Error) -> String {
        if let we = error as? WallpaperError {
            switch we {
            case .missingContent: return "контент не найден после загрузки"
            case .unsupportedKind: return "в загрузке нет ни контента, ни превью для показа"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Task table helpers

    private func upsert(_ task: DownloadTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    private func update(_ id: String, _ transform: (inout DownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        transform(&tasks[index])
        // Note: not persisted here — progress ticks are frequent. Persistence
        // happens at state boundaries (enqueue/fail/complete/retry/clear).
    }

    private func fail(_ id: String, _ message: String) {
        update(id) { $0.state = .failed(message) }
        persist()
    }

    // MARK: - Persistence (survive restarts; resume / retry)

    private struct PersistedDownload: Codable {
        let item: WorkshopItem
        let failed: Bool
        let message: String?
        // Optional for backward compat with queues saved before source existed.
        let source: String?
    }

    private func persist() {
        let entries: [PersistedDownload] = tasks.compactMap { task in
            guard let item = items[task.id] else { return nil }
            switch task.state {
            case .completed:
                return nil // finished — no need to keep
            case .failed(let message):
                return PersistedDownload(item: item, failed: true, message: message, source: task.source)
            case .queued, .downloading, .installing:
                return PersistedDownload(item: item, failed: false, message: nil, source: task.source)
            }
        }
        let data = try? JSONEncoder().encode(entries)
        try? data?.write(to: AppPaths.downloadsFile, options: .atomic)
    }

    /// Reload the queue on launch: failed items stay (retryable), unfinished
    /// ones are re-queued so they continue downloading.
    private func restore() {
        guard let data = try? Data(contentsOf: AppPaths.downloadsFile),
              let saved = try? JSONDecoder().decode([PersistedDownload].self, from: data)
        else { return }

        for entry in saved {
            items[entry.item.id] = entry.item
            let state: DownloadTask.State = entry.failed
                ? .failed(entry.message ?? "Загрузка прервана")
                : .queued
            var task = DownloadTask(id: entry.item.id, title: entry.item.title,
                                    previewURL: entry.item.previewURL, state: state)
            task.source = entry.source ?? ""
            tasks.append(task)
        }
        if tasks.contains(where: { $0.state == .queued }) {
            Task { await processQueue() }
        }
    }
}
