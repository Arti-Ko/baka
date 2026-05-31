import SwiftUI

/// Workshop tab: browse Wallpaper Engine's workshop with flexible filters
/// (type, sort, period, multiple genres, resolution, NSFW) and queue downloads.
struct WorkshopView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var browser: WorkshopBrowser

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(browser: browser)
            Divider()
            content
        }
        .navigationTitle("Workshop")
        .task { if browser.items.isEmpty && browser.errorMessage == nil { await browser.runSearch() } }
    }

    @ViewBuilder
    private var content: some View {
        if let error = browser.errorMessage {
            errorState(error)
        } else if browser.items.isEmpty && !browser.isLoading {
            emptyState
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            if browser.hiddenNSFWCount > 0 {
                nsfwNotice
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(browser.items) { item in
                    WorkshopCard(
                        item: item,
                        isDownloading: browser.isDownloading(item),
                        isInstalled: browser.isInstalled(item),
                        onDownload: { browser.download(item) }
                    )
                }
            }
            .padding(16)

            if browser.canLoadMore {
                Button { Task { await browser.loadMore() } } label: {
                    if browser.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Загрузить ещё").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .padding([.horizontal, .bottom], 16)
            }
        }
    }

    private var nsfwNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.slash")
            Text("Скрыто 18+ материалов: \(browser.hiddenNSFWCount). Включите NSFW в фильтрах, чтобы показать.")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Ничего не найдено")
                .foregroundStyle(.secondary)
            Text("Поддерживаются только Video и Web (Scene не рендерится)")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).padding(.horizontal, 40)
            Button("Повторить") { Task { await browser.runSearch() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filter bar

private struct FilterBar: View {
    @ObservedObject var browser: WorkshopBrowser

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск в Workshop…", text: $browser.query.text)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await browser.runSearch() } }
                if browser.isLoading { ProgressView().controlSize(.small) }
                Button("Найти") { Task { await browser.runSearch() } }
                    .keyboardShortcut(.return)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Picker("", selection: kindBinding) {
                        Text("Видео").tag(WallpaperKind.video)
                        Text("Web").tag(WallpaperKind.web)
                    }
                    .pickerStyle(.segmented).fixedSize()

                    sortMenu
                    if browser.query.sort == .trend && browser.query.text.isEmpty { periodMenu }
                    categoryMenu
                    resolutionMenu
                    nsfwMenu

                    if hasActiveFilters {
                        Button("Сбросить") { Task { await browser.apply { clearFilters(&$0) } } }
                            .buttonStyle(.link)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(14)
    }

    private var hasActiveFilters: Bool {
        !browser.query.categories.isEmpty || !browser.query.resolution.isEmpty
            || browser.query.nsfw != .hide
    }

    private func clearFilters(_ q: inout WorkshopQuery) {
        q.categories = []; q.resolution = ""; q.nsfw = .hide
    }

    private var nsfwMenu: some View {
        Menu {
            ForEach(NSFWFilter.allCases, id: \.self) { filter in
                Button {
                    Task { await browser.apply { $0.nsfw = filter } }
                } label: {
                    Label(filter.label, systemImage: browser.query.nsfw == filter ? "checkmark" : filter.icon)
                }
            }
        } label: {
            Label(browser.query.nsfw.label, systemImage: browser.query.nsfw.icon)
        }
        .fixedSize()
        .tint(browser.query.nsfw == .hide ? nil : .red)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(WorkshopSort.allCases, id: \.self) { sort in
                Button(sort.label) { Task { await browser.apply { $0.sort = sort } } }
            }
        } label: { Label(browser.query.sort.label, systemImage: "arrow.up.arrow.down") }
        .fixedSize()
    }

    private var periodMenu: some View {
        Menu {
            ForEach(TrendPeriod.allCases, id: \.self) { period in
                Button(period.label) { Task { await browser.apply { $0.period = period } } }
            }
        } label: { Label(browser.query.period.label, systemImage: "calendar") }
        .fixedSize()
    }

    private var categoryMenu: some View {
        Menu {
            if !browser.query.categories.isEmpty {
                Button("Очистить категории") { Task { await browser.apply { $0.categories = [] } } }
                Divider()
            }
            ForEach(WorkshopCategory.all, id: \.self) { cat in
                Button {
                    Task { await browser.apply { toggle(cat, in: &$0.categories) } }
                } label: {
                    Label(cat, systemImage: browser.query.categories.contains(cat) ? "checkmark" : "")
                }
            }
        } label: {
            Label(categoryLabel, systemImage: "tag")
        }
        .fixedSize()
    }

    private var categoryLabel: String {
        let c = browser.query.categories
        if c.isEmpty { return "Категории" }
        if c.count == 1 { return c.first! }
        return "Категории: \(c.count)"
    }

    private var resolutionMenu: some View {
        Menu {
            ForEach(WorkshopResolution.all, id: \.1) { (label, tag) in
                Button {
                    Task { await browser.apply { $0.resolution = tag } }
                } label: {
                    Label(label, systemImage: browser.query.resolution == tag ? "checkmark" : "")
                }
            }
        } label: {
            Label(WorkshopResolution.label(for: browser.query.resolution), systemImage: "rectangle.split.2x1")
        }
        .fixedSize()
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private var kindBinding: Binding<WallpaperKind> {
        Binding(get: { browser.query.kind },
                set: { k in Task { await browser.apply { $0.kind = k } } })
    }
}

// MARK: - Card

private struct WorkshopCard: View {
    let item: WorkshopItem
    let isDownloading: Bool
    let isInstalled: Bool
    let onDownload: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RemoteImage(url: item.previewURL)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if isInstalled {
                    badge("В библиотеке", "checkmark.circle.fill", alignment: .bottomTrailing)
                } else if isDownloading {
                    badge("В очереди", "arrow.down.circle", alignment: .bottomTrailing)
                } else if isHovering {
                    Button(action: onDownload) { Label("Скачать", systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(.borderedProminent)
                }

                if let kind = item.kind { kindBadge(kind) }
                if item.isNSFW { nsfwBadge }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.06)))
            .shadow(color: .black.opacity(isHovering ? 0.25 : 0.12),
                    radius: isHovering ? 10 : 4, y: isHovering ? 5 : 2)

            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .scaleEffect(isHovering ? 1.015 : 1)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
    }

    private func badge(_ text: String, _ icon: String, alignment: Alignment) -> some View {
        VStack {
            if alignment == .bottomTrailing { Spacer() }
            HStack {
                Spacer()
                Label(text, systemImage: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
        }
    }

    private func kindBadge(_ kind: WallpaperKind) -> some View {
        VStack {
            HStack {
                Text(kind == .video ? "VIDEO" : "WEB")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                Spacer()
            }
            Spacer()
        }
    }

    private var nsfwBadge: some View {
        VStack {
            HStack {
                Spacer()
                Text("18+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.red.opacity(0.85), in: Capsule())
                    .padding(8)
            }
            Spacer()
        }
    }
}
