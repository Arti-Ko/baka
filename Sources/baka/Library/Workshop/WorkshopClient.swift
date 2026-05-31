import Foundation

enum WorkshopError: LocalizedError {
    case network(String)
    case parsing
    case requiresSteamCMD

    var errorDescription: String? {
        switch self {
        case .network(let m): return "Сеть: \(m)"
        case .parsing: return "Не удалось разобрать ответ Steam"
        case .requiresSteamCMD:
            return "Контент доставляется через SteamPipe и требует SteamCMD / Steam-клиента"
        }
    }
}

/// Abstraction over the Workshop backend. Implemented today by reverse-
/// engineering Steam's public endpoints; deliberately swappable so a future
/// SteamCMD-backed client can drop in without touching the UI.
protocol WorkshopClient: Sendable {
    /// Search the Wallpaper Engine workshop with type/sort/category filters.
    func search(_ query: WorkshopQuery) async throws -> [WorkshopItem]

    /// Enrich a set of items with detailed metadata (preview, file url, etc.).
    func details(for ids: [String]) async throws -> [WorkshopItem]

    /// Determine how (or whether) an item's asset can be fetched.
    func downloadability(for item: WorkshopItem) async throws -> WorkshopDownloadability
}
