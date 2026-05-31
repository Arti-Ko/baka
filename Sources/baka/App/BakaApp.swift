import SwiftUI

@main
struct BakaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Baka", id: "main") {
            MainView(makeBrowser: state.makeWorkshopBrowser())
                .environmentObject(state)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { state.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("Baka", systemImage: "photo.on.rectangle.angled") {
            MenuBarContent()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(width: 460)
        }
    }
}
