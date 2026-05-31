import SwiftUI

/// Top-level sections of the app, shown as a source-list sidebar.
enum AppSection: String, CaseIterable, Identifiable {
    case library, workshop, downloads
    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Библиотека"
        case .workshop: return "Workshop"
        case .downloads: return "Загрузки"
        }
    }
    var icon: String {
        switch self {
        case .library: return "photo.on.rectangle.angled"
        case .workshop: return "square.grid.2x2"
        case .downloads: return "arrow.down.circle"
        }
    }
}

/// Root window: a navigation sidebar (Library / Workshop / Downloads) plus the
/// selected section's content. Workshop and Downloads are now first-class tabs
/// rather than a modal sheet.
struct MainView: View {
    @EnvironmentObject private var state: AppState
    @State private var section: AppSection? = .library
    @StateObject private var browser: WorkshopBrowser

    init(makeBrowser: @autoclosure @escaping () -> WorkshopBrowser) {
        _browser = StateObject(wrappedValue: makeBrowser())
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 960, minHeight: 600)
        .sheet(item: Binding(
            get: { state.updater.available },
            set: { if $0 == nil { state.updater.remindLater() } }
        )) { info in
            UpdateSheet(updater: state.updater, info: info)
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                ForEach(AppSection.allCases) { item in
                    Label(item.title, systemImage: item.icon)
                        .badge(item == .downloads ? state.downloads.activeCount : 0)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            PowerStatusBar().padding(12)
        }
    }

    /// Switches to the Workshop tab and shows the given author's wallpapers.
    private func showAuthor(_ id: String, _ label: String?) {
        section = .workshop
        Task { await browser.showAuthor(id: id, label: label) }
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .library {
        case .library:
            LibraryView(onShowAuthor: showAuthor)
        case .workshop:
            WorkshopView(browser: browser)
        case .downloads:
            DownloadsView()
        }
    }
}

/// Compact live power-state indicator pinned to the bottom of the sidebar.
struct PowerStatusBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName).foregroundStyle(tint)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        if state.governor.directive.isPaused { return "pause.circle.fill" }
        return state.powerSource.isOnBattery ? "battery.50" : "bolt.fill"
    }
    private var tint: Color { state.governor.directive.isPaused ? .orange : .green }
    private var statusText: String {
        if state.governor.directive.isPaused { return "Пауза — экономия батареи" }
        return state.powerSource.isOnBattery ? "От батареи" : "Воспроизведение"
    }
}
