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

    var activeCount: Int { tasks.filter(\.isActive).count }

    init(steam: SteamSession, installer: WorkshopInstaller,
         library: WallpaperLibrary, client: WorkshopClient) {
        self.steam = steam
        self.installer = installer
        self.library = library
        self.client = client
    }

    func isQueuedOrActive(_ id: String) -> Bool {
        tasks.contains { $0.id == id && $0.isActive }
    }

    func clearFinished() {
        tasks.removeAll { !$0.isActive }
    }

    /// Adds an item to the queue (no-op if already active) and kicks the worker.
    func enqueue(_ item: WorkshopItem) {
        guard !isQueuedOrActive(item.id) else { return }
        items[item.id] = item
        upsert(DownloadTask(id: item.id, title: item.title, previewURL: item.previewURL))
        Task { await processQueue() }
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
            let results = try await steam.downloadItems(ids) { [weak self] finishedID in
                Task { @MainActor in self?.update(finishedID) { $0.state = .installing } }
            }
            for id in ids {
                guard let item = byID[id] else { continue }
                switch results[id] ?? .failed("Нет результата") {
                case .success(let folder):
                    await install(from: folder, item: item, source: "SteamCMD")
                case .notLoggedIn:
                    fail(id, "Сессия Steam недоступна — войдите заново в Настройках")
                case .failed(let message):
                    fail(id, message)
                }
            }
        } catch {
            for id in ids { fail(id, error.localizedDescription) }
        }
    }

    // MARK: - Install

    private func install(from folder: URL, item: WorkshopItem, source: String) async {
        update(item.id) { $0.state = .installing; $0.source = source }
        do {
            try installer.install(from: folder, workshopID: item.id, fallback: item)
            update(item.id) { $0.state = .completed }
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
            if let preview = item.previewURL, let data = try? Data(contentsOf: preview) {
                let p = AppPaths.previews.appendingPathComponent("\(id).jpg")
                try? data.write(to: p)
                previewURL = p
            }
            library.upsert(Wallpaper(
                id: id, title: item.title, kind: kind,
                contentURL: destination, previewURL: previewURL,
                workshopID: item.id, author: item.author, tags: ["workshop"]
            ))
            update(item.id) { $0.state = .completed }
        } catch {
            fail(item.id, friendly(error))
        }
    }

    /// Maps internal wallpaper errors to readable Russian messages.
    private func friendly(_ error: Error) -> String {
        if let we = error as? WallpaperError {
            switch we {
            case .missingContent: return "контент не найден после загрузки"
            case .unsupportedKind: return "формат обоев не поддерживается (Scene/Application)"
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
    }

    private func fail(_ id: String, _ message: String) {
        update(id) { $0.state = .failed(message) }
    }
}
