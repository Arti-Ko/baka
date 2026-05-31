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
    /// Progress phase + fraction (0…1) reported to the UI during an update.
    typealias ProgressHandler = @Sendable (_ fraction: Double, _ phase: String) -> Void

    /// Downloads + stages the update, then relaunches. On success this call
    /// terminates the app and never returns normally. `onProgress` reports the
    /// download/unzip/install phases so the UI can show a live status bar.
    static func installAndRelaunch(from assetURL: URL, onProgress: @escaping ProgressHandler) async throws {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else { throw SelfUpdateError.notBundled }
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            throw SelfUpdateError.notWritable
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("baka-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        // 1. Download the zip with progress (mapped to 0…0.9 of the bar).
        onProgress(0, "Подготовка…")
        let downloader = ProgressDownloader()
        downloader.onProgress = { fraction in
            onProgress(fraction * 0.9, "Скачивание \(Int(fraction * 100))%")
        }
        let downloaded = try await downloader.download(assetURL)
        let zip = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)

        // 2. Unzip with ditto.
        onProgress(0.92, "Распаковка…")
        let unzipDir = work.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        let (out, code) = try runSync("/usr/bin/ditto", ["-x", "-k", zip.path, unzipDir.path])
        guard code == 0 else { throw SelfUpdateError.unzipFailed(out) }

        // 3. Locate the new .app bundle.
        onProgress(0.97, "Установка…")
        guard let newApp = findApp(in: unzipDir) else { throw SelfUpdateError.appNotFound }

        // 4. Write the swap+relaunch script and launch it FULLY detached.
        let script = swapScript()
        let scriptURL = work.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let logPath = AppPaths.support.appendingPathComponent("update.log").path
        let pid = ProcessInfo.processInfo.processIdentifier

        // Double-detach: the `-c` shell backgrounds an nohup'd copy of the
        // script and exits immediately, so the worker is reparented to launchd
        // and cannot be killed when this app terminates. Paths are passed as
        // positional args ($0..$3) to avoid any quoting issues with spaces.
        let command = "nohup /bin/bash \"$0\" \"$1\" \"$2\" \"$3\" > '\(logPath)' 2>&1 &"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command, scriptURL.path, String(pid), newApp.path, appURL.path]
        try task.run()
        task.waitUntilExit() // the -c shell returns immediately after backgrounding

        onProgress(1.0, "Перезапуск…")
        Log.app.log("self-update staged (log: \(logPath)); exiting to swap")
        // 5. Quit so the worker can replace the bundle. Use a hard exit (not
        // NSApp.terminate) so a presented sheet/runloop can't delay or cancel
        // termination — a lingering process caused a second instance to launch.
        try? await Task.sleep(nanoseconds: 400_000_000)
        exit(0) // terminate immediately; the detached worker takes over
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
        echo "[baka-update] $(date) start pid=$pid"
        echo "[baka-update] src=$src"
        echo "[baka-update] dest=$dest"

        # Wait (up to ~10s) for the running app to quit.
        for _ in $(seq 1 50); do
          kill -0 "$pid" 2>/dev/null || break
          sleep 0.2
        done
        # If it's still alive, force it down so we never end up with two copies.
        if kill -0 "$pid" 2>/dev/null; then
          echo "[baka-update] app still alive; terminating pid $pid"
          kill -TERM "$pid" 2>/dev/null; sleep 1
          kill -9 "$pid" 2>/dev/null; sleep 0.5
        fi
        echo "[baka-update] app exited; swapping"
        sleep 0.5

        backup="${dest}.old"
        rm -rf "$backup"
        if ! mv "$dest" "$backup"; then
          echo "[baka-update] ERROR: could not move old bundle (permissions?)"
        fi
        if /usr/bin/ditto "$src" "$dest"; then
          xattr -dr com.apple.quarantine "$dest" 2>/dev/null
          rm -rf "$backup"
          echo "[baka-update] swap OK"
        else
          echo "[baka-update] ERROR: ditto failed; restoring old bundle"
          rm -rf "$dest"
          mv "$backup" "$dest" 2>/dev/null
        fi

        # Relaunch the (now single) instance. No -n: never spawn a duplicate.
        sleep 0.5
        for _ in 1 2 3; do
          if open "$dest"; then echo "[baka-update] relaunched"; break; fi
          echo "[baka-update] open failed; retrying"
          sleep 1
        done
        echo "[baka-update] $(date) done"
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

/// A `URLSessionDownloadDelegate` that reports byte progress and returns the
/// finished file. `URLSession.download(from:)` gives no progress callbacks, so
/// we drive a download task ourselves.
private final class ProgressDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// Called on each chunk with the completed fraction (0…1).
    var onProgress: (@Sendable (Double) -> Void)?

    private var continuation: CheckedContinuation<URL, Error>?

    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is removed once this returns, so move it out now.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("baka-dl-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume(returning: dest)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
