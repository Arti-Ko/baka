import SwiftUI

/// The wallpaper library shown as a responsive card grid. Clicking a card
/// assigns that wallpaper to the currently selected monitor.
struct LibraryGrid: View {
    @EnvironmentObject private var state: AppState
    let selectedScreenKey: String?
    let onImport: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)]

    var body: some View {
        ScrollView {
            if state.library.items.isEmpty {
                EmptyLibraryView(onImport: onImport)
                    .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(state.library.items) { wallpaper in
                        WallpaperCard(
                            wallpaper: wallpaper,
                            isActive: isAssignedToSelected(wallpaper),
                            onSelect: { assign(wallpaper) },
                            onDelete: { state.library.remove(id: wallpaper.id) }
                        )
                    }
                }
                .padding(20)
            }
        }
        .background(.background)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onImport) {
                    Label("Импорт видео", systemImage: "plus")
                }
            }
        }
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        guard let key = selectedScreenKey,
              let screen = state.screens.screens.first(where: { $0.key == key })
        else { return "" }
        return "Цель: \(screen.name)"
    }

    private func isAssignedToSelected(_ wallpaper: Wallpaper) -> Bool {
        guard let key = selectedScreenKey else { return false }
        return state.settings.assignedWallpaperID(forScreen: key) == wallpaper.id
    }

    private func assign(_ wallpaper: Wallpaper) {
        guard let key = selectedScreenKey else { return }
        state.assign(wallpaperID: wallpaper.id, toScreen: key)
    }
}

private struct EmptyLibraryView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Библиотека пуста")
                .font(.title2.weight(.semibold))
            Text("Импортируйте видео-обои или скачайте их во вкладке Workshop.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: onImport) {
                Label("Импорт видео", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }
}
