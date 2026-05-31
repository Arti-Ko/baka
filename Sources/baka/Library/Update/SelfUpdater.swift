import AppKit

enum SelfUpdateError: LocalizedError {
    case notBundled
    case unzipFailed(String)
    case appNotFound
    case notWritable

    var errorDescription: String? {
        switch self {
        case .notBundled: return "Авто-обновление доступно только в собранном приложении (.app)."
        case .unzipFailed(let m): return "Не удалось распаковать обновление: \(m)"
        case .appNotFound: return "В архиве не найден Baka.app."
        case .notWritable: return "Нет прав на замену приложения. Переместите Baka в /Applications."
        }
    }
}

/// Performs a real in-place update without Sparkle:
/// downloads the release `.zip`, unzips it, then launches a small detached
/// shell script that waits for this process to quit, swaps the app bundle in
/// place, strips quarantine, and relaunches the new build.
enum SelfUpdater {
    /// Downloads + stages the update, then relaunches. On success this call
    /// terminates the app and never returns normally.
    static func installAndRelaunch(from assetURL: URL) async throws {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else { throw SelfUpdateError.notBundled }
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            throw SelfUpdateError.notWritable
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("baka-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        // 1. Download the zip.
        let (tmp, _) = try await URLSession.shared.download(from: assetURL)
        let zip = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: tmp, to: zip)

        // 2. Unzip with ditto.
        let unzipDir = work.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        let (out, code) = try runSync("/usr/bin/ditto", ["-x", "-k", zip.path, unzipDir.path])
        guard code == 0 else { throw SelfUpdateError.unzipFailed(out) }

        // 3. Locate the new .app bundle.
        guard let newApp = findApp(in: unzipDir) else { throw SelfUpdateError.appNotFound }

        // 4. Write the swap+relaunch script and launch it detached.
        let script = swapScript()
        let scriptURL = work.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path, String(pid), newApp.path, appURL.path]
        // Detach so it survives this app's termination.
        task.standardOutput = nil
        task.standardError = nil
        try task.run()

        Log.app.log("self-update staged; relaunching")
        // 5. Quit so the script can replace the bundle.
        await MainActor.run { NSApp.terminate(nil) }
    }

    // MARK: - Helpers

    private static func findApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return nil }
        return entries.first { $0.pathExtension == "app" }
    }

    /// Waits for the app to quit, swaps the bundle, clears quarantine, relaunches.
    private static func swapScript() -> String {
        """
        #!/bin/bash
        pid="$1"; src="$2"; dest="$3"
        # Wait (up to ~20s) for the running app to terminate.
        for _ in $(seq 1 100); do
          kill -0 "$pid" 2>/dev/null || break
          sleep 0.2
        done
        # Swap the bundle: move the old aside, copy the new into place.
        backup="${dest}.old"
        rm -rf "$backup"
        mv "$dest" "$backup" 2>/dev/null
        if /usr/bin/ditto "$src" "$dest"; then
          xattr -dr com.apple.quarantine "$dest" 2>/dev/null
          rm -rf "$backup"
        else
          # Restore on failure.
          rm -rf "$dest"
          mv "$backup" "$dest" 2>/dev/null
        fi
        open "$dest"
        """
    }

    private static func runSync(_ launch: String, _ args: [String]) throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }
}
