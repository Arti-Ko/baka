import Foundation

/// How Steam should order workshop results. Raw values map directly to the
/// community browse `browsesort` parameter.
enum WorkshopSort: String, CaseIterable, Sendable {
    case trend
    case mostRecent = "mostrecent"
    case lastUpdated = "lastupdated"
    case topRated = "toprated"
    case mostSubscribed = "totaluniquesubscribers"

    var label: String {
        switch self {
        case .trend: return "В тренде"
        case .mostRecent: return "Новые"
        case .lastUpdated: return "Обновлённые"
        case .topRated: return "По рейтингу"
        case .mostSubscribed: return "Популярные"
        }
    }
}

/// Trend window (only meaningful for `.trend` sort).
enum TrendPeriod: Int, CaseIterable, Sendable {
    case day = 1, week = 7, month = 30, sixMonths = 180, year = 365, allTime = -1

    var label: String {
        switch self {
        case .day: return "За день"
        case .week: return "За неделю"
        case .month: return "За месяц"
        case .sixMonths: return "За полгода"
        case .year: return "За год"
        case .allTime: return "За всё время"
        }
    }
}

/// How to treat 18+ (Mature/Questionable) content in results.
enum NSFWFilter: String, CaseIterable, Sendable {
    case hide       // drop NSFW (default)
    case show       // include everything
    case only       // only 18+

    var label: String {
        switch self {
        case .hide: return "Скрыть 18+"
        case .show: return "Показывать 18+"
        case .only: return "Только 18+"
        }
    }
    var icon: String {
        switch self {
        case .hide: return "eye.slash"
        case .show: return "eye"
        case .only: return "18.circle"
        }
    }
}

/// Which renderable types to show. `both` runs two queries (video + web) and
/// merges them, since Steam's `requiredtags` are AND-combined.
enum WallpaperTypeFilter: String, CaseIterable, Sendable {
    case video, web, both

    var label: String {
        switch self {
        case .video: return "Видео"
        case .web: return "Web"
        case .both: return "Оба"
        }
    }
    var kinds: [WallpaperKind] {
        switch self {
        case .video: return [.video]
        case .web: return [.web]
        case .both: return [.video, .web]
        }
    }
}

/// A fully described Workshop search. Immutable; the UI produces new copies.
struct WorkshopQuery: Equatable, Sendable {
    var text: String = ""
    /// Type filter applied server-side (`requiredtags`). We only support the
    /// renderable types, so this is never Scene/Application.
    var type: WallpaperTypeFilter = .both
    var sort: WorkshopSort = .trend
    var period: TrendPeriod = .week
    /// Multiple genre/category tags (AND-combined by Steam).
    var categories: Set<String> = []
    /// Optional resolution tag (e.g. "3840 x 2160"); empty means any.
    var resolution: String = ""
    /// 18+ handling: hide (default), show, or only.
    var nsfw: NSFWFilter = .hide
    /// When set, results are restricted to this Steam author (creator id);
    /// other filters/sort don't apply in author mode.
    var authorID: String?
    /// Display label for the author banner (best-effort; often the title of one
    /// of their wallpapers).
    var authorLabel: String?
    var page: Int = 1

    var isAuthorMode: Bool { authorID != nil }

    /// All server-side `requiredtags` for a specific kind (type + categories +
    /// resolution + age). For "only 18+" we request the Mature tag from Steam
    /// directly so we actually receive adult items.
    func requiredTags(for kind: WallpaperKind) -> [String] {
        var tags = [kind == .video ? "Video" : "Web"]
        tags.append(contentsOf: categories.sorted())
        if !resolution.isEmpty { tags.append(resolution) }
        if nsfw == .only { tags.append("Mature") }
        return tags
    }
}

/// Common Wallpaper Engine genre tags surfaced as multi-select filters.
enum WorkshopCategory {
    static let all: [String] = [
        "Abstract", "Anime", "Cartoon", "CGI", "Cyberpunk", "Fantasy",
        "Game", "Girls", "Guys", "Landscape", "Medieval", "Memes",
        "Music", "Nature", "Pixel art", "Relaxing", "Retro", "Sci-Fi",
        "Space", "Sports", "Technology", "Vehicle"
    ]
}

/// Resolution / aspect filters mapped to Workshop tags.
enum WorkshopResolution {
    /// (display label, Steam tag)
    static let all: [(String, String)] = [
        ("Любое", ""),
        ("1080p (16:9)", "1920 x 1080"),
        ("1440p", "2560 x 1440"),
        ("4K (3840×2160)", "3840 x 2160"),
        ("Ultrawide", "2560 x 1080"),
        ("Портрет", "Portrait"),
        ("Два монитора", "Dual monitor"),
        ("Три монитора", "Triple monitor")
    ]

    static func label(for tag: String) -> String {
        all.first { $0.1 == tag }?.0 ?? "Любое"
    }
}
