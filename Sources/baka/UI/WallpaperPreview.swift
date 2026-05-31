import SwiftUI
import AppKit

/// Live preview shown when a wallpaper is tapped: renders the actual wallpaper
/// (video/web) at a large size so you see exactly how it will look, then lets
/// you apply it to a chosen monitor.
struct WallpaperPreviewView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let wallpaper: Wallpaper
    /// Monitor pre-selected as the apply target.
    let initialScreenKey: String?

    @State private var targetKey: String = ""

    var body: some View {
        VStack(spacing: 0) {
            RendererPreview(wallpaper: wallpaper)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(.black)

            controls
        }
        .frame(width: 760, height: 560)
        .onAppear {
            targetKey = initialScreenKey
                ?? state.screens.screens.first?.key
                ?? ""
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(wallpaper.kind == .video ? "Видео-обои" : "Web-обои")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isAppliedToTarget {
                    Label("Применено", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 12) {
                if state.screens.screens.count > 1 {
                    Picker("Монитор", selection: $targetKey) {
                        ForEach(state.screens.screens) { screen in
                            Text(screen.name).tag(screen.key)
                        }
                    }
                    .frame(maxWidth: 280)
                }
                Spacer()
                Button("Закрыть") { dismiss() }
                Button(isAppliedToTarget ? "Убрать с монитора" : "Применить") {
                    if isAppliedToTarget {
                        state.assign(wallpaperID: nil, toScreen: targetKey)
                    } else {
                        state.assign(wallpaperID: wallpaper.id, toScreen: targetKey)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(targetKey.isEmpty)
            }
        }
        .padding(18)
    }

    private var isAppliedToTarget: Bool {
        !targetKey.isEmpty && state.settings.assignedWallpaperID(forScreen: targetKey) == wallpaper.id
    }
}

/// Bridges a `WallpaperRenderer` into SwiftUI so the preview plays the real
/// content. The renderer is torn down when the preview goes away.
private struct RendererPreview: NSViewRepresentable {
    let wallpaper: Wallpaper

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let renderer: WallpaperRenderer = wallpaper.kind == .video
            ? VideoWallpaperRenderer()
            : WebWallpaperRenderer()
        context.coordinator.renderer = renderer

        let view = renderer.view
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)

        do {
            try renderer.load(wallpaper)
            renderer.apply(.play(fpsCap: nil), muted: true)
        } catch {
            Log.wallpaper.error("preview load failed: \(error.localizedDescription)")
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.renderer?.tearDown()
        coordinator.renderer = nil
    }

    @MainActor
    final class Coordinator {
        var renderer: WallpaperRenderer?
    }
}
