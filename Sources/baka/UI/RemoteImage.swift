import SwiftUI

/// Loads and caches remote preview images reliably.
///
/// `AsyncImage` failed on some Steam previews because the raw `preview_url`
/// points at full-resolution art (multi-MB, slow / occasionally rejected). We:
/// - rewrite Steam Akamai URLs to request a sized thumbnail (`imw/imh/ima`),
/// - send a desktop User-Agent,
/// - cache decoded images in-memory by URL.
actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 20

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = NSImage(data: data)
        else { return nil }

        cache.setObject(image, forKey: key)
        return image
    }

    /// Steam's Akamai CDN supports on-the-fly resizing via query params, which
    /// gives small, fast, reliable thumbnails.
    nonisolated static func thumbnail(_ url: URL, width: Int = 480, height: Int = 270) -> URL {
        guard url.host?.contains("akamaihd.net") == true ||
              url.host?.contains("steamusercontent") == true,
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }

        var items = comps.queryItems ?? []
        items.removeAll { ["imw", "imh", "ima", "impolicy", "letterbox"].contains($0.name) }
        items.append(contentsOf: [
            .init(name: "imw", value: String(width)),
            .init(name: "imh", value: String(height)),
            .init(name: "ima", value: "fit"),
            .init(name: "impolicy", value: "Letterbox"),
            .init(name: "letterbox", value: "false")
        ])
        comps.queryItems = items
        return comps.url ?? url
    }
}

/// A drop-in image view backed by `ImageLoader`, with a loading shimmer and a
/// graceful failure placeholder.
struct RemoteImage: View {
    let url: URL?
    var thumbnailWidth: Int = 480

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if failed || url == nil {
                placeholder
            } else {
                Rectangle().fill(Color(white: 0.12))
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) { await reload() }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Color(white: 0.12))
            Image(systemName: "photo")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private func reload() async {
        guard let url else { return }
        image = nil
        failed = false
        let target = ImageLoader.thumbnail(url, width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
        let loaded = await ImageLoader.shared.image(for: target)
        if loaded == nil {
            // Fall back to the original URL if the thumbnail variant failed.
            image = await ImageLoader.shared.image(for: url)
        } else {
            image = loaded
        }
        failed = image == nil
    }
}
