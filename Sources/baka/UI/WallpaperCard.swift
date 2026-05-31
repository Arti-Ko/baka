import SwiftUI

/// A single wallpaper tile with hover elevation, an active-assignment ring,
/// and a context menu for removal. Designed to feel native on macOS.
struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(wallpaper: wallpaper)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(activeRing)
                    .overlay(alignment: .topTrailing) { kindBadge }
                    .shadow(color: .black.opacity(isHovering ? 0.28 : 0.16),
                            radius: isHovering ? 12 : 6, y: isHovering ? 6 : 3)

                Text(wallpaper.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var activeRing: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isActive ? Color.accentColor : .white.opacity(0.06),
                          lineWidth: isActive ? 3 : 1)
    }

    private var kindBadge: some View {
        Image(systemName: wallpaper.kind == .video ? "film.fill" : "globe")
            .font(.system(size: 10, weight: .semibold))
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .padding(8)
            .opacity(isHovering || isActive ? 1 : 0.0)
    }
}
