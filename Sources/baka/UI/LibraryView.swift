import SwiftUI
import UniformTypeIdentifiers

/// Library tab: a horizontal strip of monitors (the assignment target) above
/// the wallpaper grid. Picking a monitor, then a wallpaper, assigns it.
struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedScreenKey: String?
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 0) {
            MonitorStrip(selectedScreenKey: $selectedScreenKey)
            Divider()
            LibraryGrid(
                selectedScreenKey: effectiveScreenKey,
                onImport: { showImporter = true }
            )
        }
        .navigationTitle("Библиотека")
        .onAppear(perform: ensureSelection)
        .onChange(of: state.screens.screens) { _, _ in ensureSelection() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { handleImport($0) }
    }

    private var effectiveScreenKey: String? {
        selectedScreenKey ?? state.screens.screens.first?.key
    }

    private func ensureSelection() {
        if selectedScreenKey == nil ||
            !state.screens.screens.contains(where: { $0.key == selectedScreenKey }) {
            selectedScreenKey = state.screens.screens.first?.key
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            _ = try? state.importer.importVideo(at: url)
        }
    }
}

/// Horizontal, selectable monitor cards with a live preview of the assigned
/// wallpaper. Doubles as the assignment target indicator.
struct MonitorStrip: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedScreenKey: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(state.screens.screens) { screen in
                    MonitorCard(
                        screen: screen,
                        wallpaper: assignedWallpaper(for: screen.key),
                        isSelected: screen.key == selectedScreenKey,
                        onSelect: { selectedScreenKey = screen.key },
                        onClear: { state.assign(wallpaperID: nil, toScreen: screen.key) }
                    )
                }
            }
            .padding(16)
        }
        .frame(height: 132)
        .background(.black.opacity(0.12))
    }

    private func assignedWallpaper(for key: String) -> Wallpaper? {
        guard let id = state.settings.assignedWallpaperID(forScreen: key) else { return nil }
        return state.library.wallpaper(withID: id)
    }
}

private struct MonitorCard: View {
    let screen: ScreenInfo
    let wallpaper: Wallpaper?
    let isSelected: Bool
    let onSelect: () -> Void
    let onClear: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                ThumbnailView(wallpaper: wallpaper)
                    .frame(width: 150, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.08),
                                          lineWidth: isSelected ? 3 : 1)
                    )
                Text(screen.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if wallpaper != nil {
                Button(role: .destructive, action: onClear) {
                    Label("Убрать обои", systemImage: "xmark.circle")
                }
            }
        }
    }
}
