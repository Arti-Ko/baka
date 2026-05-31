import SwiftUI

/// View model for the Workshop browser: holds the active query/filters, runs
/// paginated searches (accumulating for "load more"), applies the NSFW filter,
/// and hands downloads off to the shared `DownloadManager`.
@MainActor
final class WorkshopBrowser: ObservableObject {
    @Published var query = WorkshopQuery()
    @Published private(set) var items: [WorkshopItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hiddenNSFWCount = 0

    private let client: WorkshopClient
    private let library: WallpaperLibrary
    private let downloads: DownloadManager

    init(client: WorkshopClient, library: WallpaperLibrary, downloads: DownloadManager) {
        self.client = client
        self.library = library
        self.downloads = downloads
    }

    func runSearch() async {
        query.page = 1
        await load(reset: true)
    }

    /// Mutate the query via a closure then re-search (used by filter controls).
    func apply(_ mutate: (inout WorkshopQuery) -> Void) async {
        mutate(&query)
        await runSearch()
    }

    func loadMore() async {
        guard !isLoading, canLoadMore else { return }
        query.page += 1
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        isLoading = true
        errorMessage = nil
        if reset { hiddenNSFWCount = 0 }
        defer { isLoading = false }
        do {
            let results = try await client.search(query)
            canLoadMore = results.count >= 30

            var supported = results.filter { $0.kind != nil }
            switch query.nsfw {
            case .hide:
                let before = supported.count
                supported = supported.filter { !$0.isNSFW }
                hiddenNSFWCount += before - supported.count
            case .show:
                break
            case .only:
                supported = supported.filter { $0.isNSFW }
            }

            if reset {
                items = supported
            } else {
                let known = Set(items.map(\.id))
                items += supported.filter { !known.contains($0.id) }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            canLoadMore = false
        }
    }

    // MARK: - Download / install state (delegated)

    func download(_ item: WorkshopItem) {
        downloads.enqueue(item)
    }

    func isInstalled(_ item: WorkshopItem) -> Bool {
        library.wallpaper(withID: "ws-\(item.id)") != nil
    }

    func isDownloading(_ item: WorkshopItem) -> Bool {
        downloads.isQueuedOrActive(item.id)
    }
}
