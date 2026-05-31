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

    /// Screens chosen to receive the wallpaper (multi-select).
    @State private var selectedKeys: Set<String> = []
    /// Speed in percent: 100 = normal, range 0…1000 (0×…10×).
    @State private var speedPercent: Double = 100

    var body: some View {
        VStack(spacing: 0) {
            RendererPreview(wallpaper: wallpaper, speed: speedPercent / 100.0)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(.black)

            controls
        }
        .frame(width: 760, height: 640)
        .onAppear(perform: initSelection)
    }

    private func initSelection() {
        speedPercent = (wallpaper.speedMultiplier * 100).rounded()
        // Pre-select screens already showing this wallpaper, else the initial.
        let current = state.screens.screens
            .filter { state.settings.assignedWallpaperID(forScreen: $0.key) == wallpaper.id }
            .map(\.key)
        if !current.isEmpty {
            selectedKeys = Set(current)
        } else if let key = initialScreenKey ?? state.screens.screens.first?.key {
            selectedKeys = [key]
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
            }

            speedControl
            monitorSelection

            HStack(spacing: 12) {
                Spacer()
                Button("Закрыть") { dismiss() }
                Button("Применить") { apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedKeys.isEmpty)
            }
        }
        .padding(18)
    }

    private var monitorSelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Мониторы", systemImage: "display.2")
                    .font(.callout.weight(.medium))
                Spacer()
                Button(allSelected ? "Снять все" : "Выбрать все") {
                    selectedKeys = allSelected ? [] : Set(state.screens.screens.map(\.key))
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            // Toggle chips, one per connected display.
            FlexibleChips(screens: state.screens.screens,
                          selected: selectedKeys,
                          toggle: toggleScreen)
        }
    }

    private var allSelected: Bool {
        !state.screens.screens.isEmpty &&
            selectedKeys.count == state.screens.screens.count
    }

    private func toggleScreen(_ key: String) {
        if selectedKeys.contains(key) { selectedKeys.remove(key) } else { selectedKeys.insert(key) }
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Скорость", systemImage: "speedometer")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(Int(speedPercent))%  ·  \(speedString)×")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    speedPercent = 100
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Сбросить к 100%")
            }
            Slider(value: $speedPercent, in: 0...1000, step: 5)
        }
    }

    private var speedString: String {
        String(format: "%.2g", speedPercent / 100.0)
    }

    private func apply() {
        // Persist the chosen speed onto the wallpaper before assigning so the
        // desktop renderer plays it at this speed.
        let updated = wallpaper.withSpeed(speedPercent / 100.0)
        state.library.upsert(updated)

        for screen in state.screens.screens {
            if selectedKeys.contains(screen.key) {
                state.assign(wallpaperID: updated.id, toScreen: screen.key)
            } else if state.settings.assignedWallpaperID(forScreen: screen.key) == wallpaper.id {
                // Deselected a screen that currently shows this wallpaper → clear it.
                state.assign(wallpaperID: nil, toScreen: screen.key)
            }
        }
        dismiss()
    }
}

/// A row of selectable monitor chips. Shows a checkmark when selected and a
/// subtle marker when the screen already displays this wallpaper.
private struct FlexibleChips: View {
    let screens: [ScreenInfo]
    let selected: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(screens) { screen in
                let isOn = selected.contains(screen.key)
                Button {
                    toggle(screen.key)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? Color.accentColor : .secondary)
                        Text(screen.name).lineLimit(1)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isOn ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isOn ? Color.accentColor.opacity(0.5) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Bridges a `WallpaperRenderer` into SwiftUI so the preview plays the real
/// content. The renderer is torn down when the preview goes away.
private struct RendererPreview: NSViewRepresentable {
    let wallpaper: Wallpaper
    let speed: Double

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
            renderer.setSpeed(speed)
            context.coordinator.lastSpeed = speed
        } catch {
            Log.wallpaper.error("preview load failed: \(error.localizedDescription)")
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Apply live speed changes from the slider.
        if context.coordinator.lastSpeed != speed {
            context.coordinator.lastSpeed = speed
            context.coordinator.renderer?.setSpeed(speed)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.renderer?.tearDown()
        coordinator.renderer = nil
    }

    @MainActor
    final class Coordinator {
        var renderer: WallpaperRenderer?
        var lastSpeed: Double = 1.0
    }
}
