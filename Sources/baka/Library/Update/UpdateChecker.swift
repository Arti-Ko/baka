import SwiftUI

/// Information about an available release, shown in the update dialog.
struct UpdateInfo: Identifiable, Equatable {
    var id: String { version }
    let version: String        // e.g. "0.2.0"
    let name: String           // release title
    let notes: String          // release body / changelog
    let pageURL: URL           // GitHub release page
    let assetURL: URL?         // direct .zip asset, if published
}

/// Checks GitHub Releases for a newer version and drives the update dialog.
///
/// "Skip this version" is remembered in UserDefaults so the dialog won't nag
/// for a version the user declined; "remind later" simply dismisses and the
/// next check (launch or manual) will surface it again.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Set when a newer, non-skipped release is found → presents the dialog.
    @Published var available: UpdateInfo?
    @Published private(set) var isChecking = false
    /// Result of a *manual* check ("up to date" / error), for Settings.
    @Published var statusMessage: String?

    /// GitHub repository hosting releases.
    static let repo = "Arti-Ko/baka"
    private let skippedKey = "update.skippedVersion"

    // MARK: - Checking

    func check(manual: Bool) async {
        isChecking = true
        if manual { statusMessage = nil }
        defer { isChecking = false }

        do {
            guard let latest = try await fetchLatest() else {
                if manual { statusMessage = "Не удалось получить информацию о релизах." }
                return
            }

            guard AppVersion.isNewer(latest.version, than: AppVersion.current) else {
                if manual { statusMessage = "У вас актуальная версия (\(AppVersion.displayString))." }
                return
            }

            // Honor a previously skipped version (auto-checks only).
            if !manual, skippedVersion == latest.version { return }

            available = latest
        } catch {
            if manual {
                statusMessage = "Ошибка проверки: \(error.localizedDescription)"
            }
            Log.app.error("update check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - User actions

    func updateNow() {
        guard let info = available else { return }
        // No code-signing/Sparkle pipeline yet: open the download so the user
        // can install the new build. Prefer the direct asset, else the page.
        NSWorkspace.shared.open(info.assetURL ?? info.pageURL)
        available = nil
    }

    func remindLater() {
        available = nil
    }

    func skip() {
        if let info = available {
            UserDefaults.standard.set(info.version, forKey: skippedKey)
        }
        available = nil
    }

    private var skippedVersion: String? {
        UserDefaults.standard.string(forKey: skippedKey)
    }

    // MARK: - GitHub API

    private func fetchLatest() async throws -> UpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("baka-app", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil // no releases published yet
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String,
              let htmlString = root["html_url"] as? String,
              let pageURL = URL(string: htmlString)
        else { return nil }

        let assets = root["assets"] as? [[String: Any]] ?? []
        let zipURL = assets
            .compactMap { $0["browser_download_url"] as? String }
            .first { $0.lowercased().hasSuffix(".zip") }
            .flatMap(URL.init(string:))

        return UpdateInfo(
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            name: (root["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag,
            notes: (root["body"] as? String) ?? "Описание обновления отсутствует.",
            pageURL: pageURL,
            assetURL: zipURL
        )
    }
}
