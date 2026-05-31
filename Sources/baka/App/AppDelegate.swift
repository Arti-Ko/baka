import AppKit

/// Minimal app delegate. The heavy lifting lives in `AppState`; this hook just
/// ensures the wallpaper windows come up once the app finishes launching and
/// that closing the last UI window doesn't quit the app (it keeps running in
/// the menu bar, like a real wallpaper engine).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Always allow Quit to proceed immediately (the real teardown + hard exit
    /// happens on `willTerminate`), so Quit never stalls into needing Force Quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }
}
