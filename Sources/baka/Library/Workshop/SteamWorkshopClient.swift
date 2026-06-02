import Foundation

/// Reverse-engineered Steam Workshop client for Wallpaper Engine (app 431960).
///
/// Strategy:
/// - **Search** scrapes the public community browse page for `publishedfileid`s
///   (order-preserving), which is resilient to layout churn since we only need
///   the IDs.
/// - **Details** then calls the public `GetPublishedFileDetails` endpoint (no
///   API key required) to get clean title/preview/file metadata.
///
/// Note: most WE items deliver content through SteamPipe, so `file_url` is
/// usually empty and the asset needs SteamCMD. We surface that honestly rather
/// than pretending we can fetch it.
final class SteamWorkshopClient: WorkshopClient {
    static let appID = "431960"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search

    func search(_ query: WorkshopQuery) async throws -> [WorkshopItem] {
        // Author mode: list a specific creator's published WE items.
        if let author = query.authorID {
            return try await searchByAuthor(author, page: query.page)
        }
        let kinds = query.type.kinds
        if kinds.count == 1 {
            return try await searchSingle(query, kind: kinds[0])
        }
        // "Both": fetch each type, then interleave so the grid mixes them.
        var perKind: [[WorkshopItem]] = []
        for kind in kinds {
            perKind.append((try? await searchSingle(query, kind: kind)) ?? [])
        }
        return Self.interleave(perKind)
    }

    /// Scrapes a creator's published WE items from their profile workshop page.
    private func searchByAuthor(_ steamID: String, page: Int) async throws -> [WorkshopItem] {
        // Only digits are a valid steamID64 path segment.
        let id = steamID.filter(\.isNumber)
        guard !id.isEmpty else { return [] }
        var components = URLComponents(
            string: "https://steamcommunity.com/profiles/\(id)/myworkshopfiles/")!
        components.queryItems = [
            .init(name: "appid", value: Self.appID),
            .init(name: "p", value: String(max(1, page))),
            .init(name: "numperpage", value: "30")
        ]
        guard let url = components.url else { return [] }
        let html = try await fetchString(url)
        let ids = Self.extractPublishedFileIDs(from: html)
        guard !ids.isEmpty else { return [] }
        return try await details(for: ids)
    }

    private func searchSingle(_ query: WorkshopQuery, kind: WallpaperKind) async throws -> [WorkshopItem] {
        guard let url = Self.browseURL(for: query, kind: kind) else { throw WorkshopError.parsing }
        let html = try await fetchString(url)
        let ids = Self.extractPublishedFileIDs(from: html)
        guard !ids.isEmpty else { return [] }
        return try await details(for: ids)
    }

    /// Round-robin merge so both types appear mixed, de-duplicated by id.
    static func interleave(_ lists: [[WorkshopItem]]) -> [WorkshopItem] {
        var result: [WorkshopItem] = []
        var seen = Set<String>()
        let maxCount = lists.map(\.count).max() ?? 0
        for i in 0..<maxCount {
            for list in lists where i < list.count {
                let item = list[i]
                if seen.insert(item.id).inserted { result.append(item) }
            }
        }
        return result
    }

    /// Builds the community browse URL. Type is filtered server-side via
    /// `requiredtags` so each page returns a full set of renderable items
    /// (instead of being decimated by client-side Scene filtering).
    static func browseURL(for query: WorkshopQuery, kind: WallpaperKind) -> URL? {
        var components = URLComponents(string: "https://steamcommunity.com/workshop/browse/")!
        var items: [URLQueryItem] = [
            .init(name: "appid", value: appID),
            .init(name: "section", value: "readytouseitems"),
            .init(name: "p", value: String(max(1, query.page))),
            .init(name: "numperpage", value: "30")
        ]

        let trimmed = query.text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            items.append(.init(name: "browsesort", value: query.sort.rawValue))
            if query.sort == .trend {
                items.append(.init(name: "days", value: String(query.period.rawValue)))
            }
        } else {
            // Text search overrides sort on Steam's side.
            items.append(.init(name: "searchtext", value: trimmed))
            items.append(.init(name: "browsesort", value: "textsearch"))
        }

        // Type tag (Video / Web) + categories + resolution, all server-side.
        // This is the key fix for "only a handful of results".
        for tag in query.requiredTags(for: kind) {
            items.append(.init(name: "requiredtags[]", value: tag))
        }

        components.queryItems = items
        return components.url
    }

    // MARK: - Details

    func details(for ids: [String]) async throws -> [WorkshopItem] {
        guard !ids.isEmpty else { return [] }
        let url = URL(string: "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")!

        var body = "itemcount=\(ids.count)"
        for (index, id) in ids.enumerated() {
            body += "&publishedfileids%5B\(index)%5D=\(id)"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        return Self.parseDetails(data, order: ids)
    }

    // MARK: - Downloadability

    func downloadability(for item: WorkshopItem) async throws -> WorkshopDownloadability {
        // Refresh in case the item came from a list without a file url.
        let enriched = (try? await details(for: [item.id]))?.first ?? item
        guard let kind = enriched.kind else { return .unavailable }
        if let url = enriched.fileURL {
            return .direct(url, kind)
        }
        return .requiresSteamCMD
    }

    // MARK: - Networking helpers

    private func fetchString(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        // A desktop UA reduces the chance of a stripped-down mobile layout.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        do {
            let (data, response) = try await session.data(for: request)
            try Self.validate(response)
            return String(decoding: data, as: UTF8.self)
        } catch {
            throw WorkshopError.network(error.localizedDescription)
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw WorkshopError.network("HTTP \(http.statusCode)")
        }
    }

    // MARK: - Parsing

    /// Pulls unique `?id=<digits>` published file ids out of the browse HTML,
    /// preserving their display order.
    static func extractPublishedFileIDs(from html: String) -> [String] {
        let pattern = #"filedetails/\?id=(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)

        var seen = Set<String>()
        var ordered: [String] = []
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: html) else { return }
            let id = String(html[r])
            if seen.insert(id).inserted { ordered.append(id) }
        }
        return ordered
    }

    /// Parses the GetPublishedFileDetails JSON envelope, returning items in the
    /// requested order.
    static func parseDetails(_ data: Data, order: [String]) -> [WorkshopItem] {
        guard
            let root = try? JSONSerialization.jsonObject(with: sanitizeJSON(data)) as? [String: Any],
            let response = root["response"] as? [String: Any],
            let details = response["publishedfiledetails"] as? [[String: Any]]
        else { return [] }

        var byID: [String: WorkshopItem] = [:]
        for entry in details {
            guard let id = entry["publishedfileid"] as? String,
                  (entry["result"] as? Int) == 1
            else { continue }

            let title = (entry["title"] as? String) ?? "Без названия"
            let preview = (entry["preview_url"] as? String).flatMap(URL.init(string:))
            let fileURLString = entry["file_url"] as? String
            let fileURL = (fileURLString?.isEmpty == false) ? URL(string: fileURLString!) : nil
            let rawTags = entry["tags"] as? [[String: Any]]
            let tagNames = (rawTags ?? []).compactMap { ($0["tag"] as? String)?.lowercased() }
            // file_size may arrive as Int or String.
            let size = (entry["file_size"] as? Int)
                ?? Int(entry["file_size"] as? String ?? "") ?? 0

            byID[id] = WorkshopItem(
                id: id,
                title: title,
                previewURL: preview,
                author: entry["creator"] as? String,
                fileURL: fileURL,
                kind: kind(fromTags: rawTags),
                tags: tagNames,
                fileSize: size
            )
        }

        return order.compactMap { byID[$0] }
    }

    /// Steam frequently returns raw control characters (e.g. `\r\n` inside
    /// item descriptions), which is invalid JSON and makes the strict
    /// `JSONSerialization` reject the entire response — silently dropping every
    /// result on the page. We replace control bytes (< 0x20, except tab) with
    /// spaces; this never touches already-escaped sequences like `\\n`.
    static func sanitizeJSON(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        for index in bytes.indices where bytes[index] < 0x20 && bytes[index] != 0x09 {
            bytes[index] = 0x20
        }
        return Data(bytes)
    }

    /// Maps Workshop type tags to a wallpaper kind. Video/Web render live;
    /// Scene/Application render as a poster (their bundled preview).
    private static func kind(fromTags tags: [[String: Any]]?) -> WallpaperKind? {
        guard let tags else { return nil }
        let names = tags.compactMap { ($0["tag"] as? String)?.lowercased() }
        if names.contains("video") { return .video }
        if names.contains("web") { return .web }
        if names.contains("scene") { return .scene }
        if names.contains("application") { return .application }
        return nil // unknown / untyped item
    }
}
