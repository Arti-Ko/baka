import SwiftUI

/// Renders a wallpaper's preview image, with graceful placeholders for missing
/// previews and for web wallpapers (which have no generated thumbnail yet).
struct ThumbnailView: View {
    let wallpaper: Wallpaper?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(white: 0.16), Color(white: 0.09)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
    }

    private var previewImage: NSImage? {
        guard let url = wallpaper?.previewURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private var placeholderIcon: String {
        guard let kind = wallpaper?.kind else { return "rectangle.dashed" }
        return kind.symbolName
    }
}
