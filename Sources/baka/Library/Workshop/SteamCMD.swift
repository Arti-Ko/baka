import Foundation

/// Mutable holder for the currently-downloading item id, used inside the
/// single-threaded output drain closure.
private final class CurrentItem: @unchecked Sendable {
    var id: String?
}

/// Thread-safe handle to the currently running process, so a download can be
/// cancelled from another actor/thread by terminating it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    func set(_ p: Process?) { lock.lock(); process = p; lock.unlock() }
    func terminate() { lock.lock(); process?.terminate(); lock.unlock() }
}

/// Result of a login attempt.
enum SteamLoginResult: Sendable, Equatable {
    case success
    case needsSteamGuard          // a code is required (email or mobile)
    case invalidPassword
    case rateLimited
    case failed(String)
}

/// Result of a workshop download.
enum SteamDownloadResult: Sendable {
    case success(URL)             // local folder containing the item
    case notLoggedIn
    case failed(String)
}

enum SteamCMDError: LocalizedError {
    case notInstalled
    case installFailed(String)
    case rosettaMissing

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "SteamCMD не установлен"
        case .installFailed(let m): return "Не удалось установить SteamCMD: \(m)"
        case .rosettaMissing:
            return "SteamCMD требует Rosetta. Установите: softwareupdate --install-rosetta"
        }
    }
}

/// Wraps the official Valve SteamCMD command-line client: installs it on demand,
/// logs into the user's Steam account (handling Steam Guard by passing the code
/// as a login argument), and downloads Wallpaper Engine workshop items the
/// account owns.
///
/// An `actor` so concurrent UI actions can't run two steamcmd processes at once.
actor SteamCMD {
    private let installDir: URL
    private let downloadURL = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz")!
    /// Handle to the in-flight process, for cancellation.
    private let processBox = ProcessBox()

    /// Terminates the currently running steamcmd process (cancels a download).
    func cancelCurrent() {
        processBox.terminate()
    }

    init() {
        installDir = AppPaths.support.appendingPathComponent("steamcmd", isDirectory: true)
    }

    /// Path to the bootstrap script once installed.
    private var scriptPath: URL { installDir.appendingPathComponent("steamcmd.sh") }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath.path)
    }

    // MARK: - Install

    /// Downloads and extracts SteamCMD if not already present.
    func ensureInstalled() async throws {
        if isInstalled { return }
        Log.workshop.log("installing SteamCMD…")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        let tarball = installDir.appendingPathComponent("steamcmd.tar.gz")
        try? FileManager.default.removeItem(at: tarball)
        try FileManager.default.moveItem(at: tempURL, to: tarball)

        let (out, code) = try await runProcess(
            launch: "/usr/bin/tar",
            args: ["-xzf", tarball.path, "-C", installDir.path],
            cwd: installDir
        )
        guard code == 0 else { throw SteamCMDError.installFailed(out) }
        try? FileManager.default.removeItem(at: tarball)
    }

    // MARK: - Login

    /// Attempts login. Pass `guardCode` when retrying after `.needsSteamGuard`.
    func login(user: String, password: String, guardCode: String?) async throws -> SteamLoginResult {
        try await ensureInstalled()
        var loginArgs = ["+login", user, password]
        if let guardCode, !guardCode.isEmpty { loginArgs.append(guardCode) }
        let args = loginArgs + ["+quit"]

        let (out, _) = try await runSteamCMD(args)
        return Self.classifyLogin(out)
    }

    // MARK: - Download

    /// Downloads one or more workshop items in a SINGLE steamcmd session: one
    /// `+login` followed by many `+workshop_download_item`. Batching is critical
    /// — a separate login per item triggers Steam login rate-limiting, which is
    /// what caused the intermittent "session unavailable" failures.
    ///
    /// `onItemFinished(id)` fires live as each item's success line is printed,
    /// so the UI can mark items done as they complete.
    func downloadItems(
        _ ids: [String],
        user: String,
        password: String,
        onProgress: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> [String: SteamDownloadResult] {
        try await ensureInstalled()
        guard !ids.isEmpty else { return [:] }

        var args = ["+login", user]
        if !password.isEmpty { args.append(password) }
        for id in ids {
            args += ["+workshop_download_item", SteamLocator.weAppID, id]
        }
        args.append("+quit")

        // Track which item SteamCMD is currently downloading so we can attribute
        // its `[ NN%]` progress lines (which don't carry the id themselves).
        let current = CurrentItem()
        let (out, _) = try await runSteamCMD(args) { line in
            if let id = Self.extractDownloadingItemID(line) {
                current.id = id
            } else if let id = Self.extractFinishedItemID(line) {
                onProgress?(id, 1.0)
                current.id = nil
            } else if let pct = Self.parseDownloadPercent(line), let id = current.id {
                onProgress?(id, pct)
            }
        }

        let loggedOut = Self.indicatesLoginFailure(out)
        var results: [String: SteamDownloadResult] = [:]
        for id in ids {
            if let folder = downloadedFolder(for: id, output: out) {
                results[id] = .success(folder)
            } else if loggedOut {
                results[id] = .notLoggedIn
            } else {
                results[id] = .failed(Self.downloadError(for: id, in: out))
            }
        }
        return results
    }

    /// Locates the downloaded item folder. SteamCMD on macOS stores workshop
    /// content under the *standard* Steam path (`~/Library/Application
    /// Support/Steam/...`), NOT under our install dir — so we trust the path
    /// printed in the success line first, then fall back to known locations.
    /// Only returns a folder that exists AND is non-empty.
    private func downloadedFolder(for id: String, output: String) -> URL? {
        // Trust the exact path SteamCMD printed first…
        if let reported = Self.extractDownloadedPath(for: id, in: output) {
            let folder = URL(fileURLWithPath: reported)
            let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
            if contents?.isEmpty == false { return folder }
        }
        // …otherwise search both known workshop roots.
        return SteamLocator.localFolder(forItem: id)
    }

    /// Parses the exact path from `Downloaded item <id> to "<path>" (...)`.
    nonisolated static func extractDownloadedPath(for id: String, in output: String) -> String? {
        let pattern = "Downloaded item \(id) to \"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output)
        else { return nil }
        return String(output[range])
    }

    // MARK: - Process plumbing

    private func runSteamCMD(
        _ args: [String],
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> (String, Int32) {
        guard isInstalled else { throw SteamCMDError.notInstalled }
        return try await runProcess(launch: "/bin/bash",
                                    args: [scriptPath.path] + args,
                                    cwd: installDir,
                                    onLine: onLine)
    }

    /// Runs a process to completion, draining stdout+stderr continuously (to
    /// avoid pipe-buffer deadlock) and forwarding each line to `onLine` for live
    /// progress. Returns the combined output and exit code.
    private func runProcess(
        launch: String,
        args: [String],
        cwd: URL,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> (String, Int32) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launch)
                process.arguments = args
                process.currentDirectoryURL = cwd

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                // Closed stdin: any prompt steamcmd tries to read gets EOF and
                // fails fast instead of hanging the process forever.
                process.standardInput = FileHandle.nullDevice

                self.processBox.set(process)
                do {
                    try process.run()
                } catch {
                    self.processBox.set(nil)
                    continuation.resume(throwing: error)
                    return
                }

                // Synchronous drain loop on this background queue: availableData
                // blocks until bytes arrive or returns empty at EOF. No handler
                // races, no pipe-buffer deadlock.
                let handle = pipe.fileHandleForReading
                var full = ""
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    let text = String(decoding: chunk, as: UTF8.self)
                    full += text
                    if let onLine {
                        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                            onLine(String(line))
                        }
                    }
                }
                process.waitUntilExit()
                self.processBox.set(nil)
                continuation.resume(returning: (full, process.terminationStatus))
            }
        }
    }

    // MARK: - Output classification

    nonisolated static func classifyLogin(_ output: String) -> SteamLoginResult {
        let lower = output.lowercased()
        if lower.contains("logged in ok") || lower.contains("waiting for user info...ok") {
            return .success
        }
        if lower.contains("steam guard") || lower.contains("two-factor")
            || lower.contains("account logon denied") || lower.contains("invalid login auth code") {
            return .needsSteamGuard
        }
        if lower.contains("invalid password") || lower.contains("invalidpassword") {
            return .invalidPassword
        }
        if lower.contains("rate limit") || lower.contains("ratelimitexceeded") {
            return .rateLimited
        }
        return .failed(lastMeaningfulLine(output))
    }

    /// Extracts the item id from a "Success. Downloaded item <id> to ..." line.
    nonisolated static func extractFinishedItemID(_ line: String) -> String? {
        guard line.contains("Downloaded item"),
              let range = line.range(of: #"Downloaded item (\d+)"#, options: .regularExpression)
        else { return nil }
        return String(line[range].drop { !$0.isNumber })
    }

    /// Extracts the id from a "Downloading item <id> ..." start line.
    nonisolated static func extractDownloadingItemID(_ line: String) -> String? {
        guard line.contains("Downloading item"),
              let range = line.range(of: #"Downloading item (\d+)"#, options: .regularExpression)
        else { return nil }
        return String(line[range].drop { !$0.isNumber })
    }

    /// Parses a SteamCMD progress line "[ NN%] Downloading update (...)" → 0…1.
    nonisolated static func parseDownloadPercent(_ line: String) -> Double? {
        guard let range = line.range(of: #"\[\s*(\d+)%\]"#, options: .regularExpression) else {
            return nil
        }
        let digits = line[range].filter(\.isNumber)
        guard let value = Double(digits) else { return nil }
        return min(max(value / 100.0, 0), 1)
    }

    /// True only for genuine login failures. Deliberately does NOT match
    /// "using cached credentials", which is a normal success message.
    nonisolated static func indicatesLoginFailure(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("login failure")
            || lower.contains("invalid password")
            || lower.contains("rate limit")
            || lower.contains("account logon denied")
            || lower.contains("two-factor")
            || lower.contains("steam guard")
    }

    /// Produces a useful failure message for an item: prefers an explicit
    /// SteamCMD error line, never the noise like "Unloading Steam API...OK".
    nonisolated static func downloadError(for id: String, in output: String) -> String {
        let lines = output.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 1. An explicit "ERROR! Download item <id> failed (...)" line.
        if let line = lines.first(where: {
            $0.lowercased().contains("error") && $0.contains(id)
        }) { return line }
        // 2. Any error/failure line.
        if let line = lines.last(where: {
            let l = $0.lowercased()
            return l.contains("error") || l.contains("failed") || l.contains("failure")
        }) { return line }
        // 3. Generic — avoid trailing "...OK" noise.
        return "Не удалось скачать (SteamCMD). Проверьте вход в Steam и попробуйте снова."
    }

    nonisolated static func lastMeaningfulLine(_ output: String) -> String {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last ?? "Неизвестная ошибка SteamCMD"
    }
}
