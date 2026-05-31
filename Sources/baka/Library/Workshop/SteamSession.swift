import SwiftUI

/// Observable Steam account/session state on top of `SteamCMD`.
///
/// We persist only the username (never the password). After the first
/// successful login, SteamCMD caches the session, so downloads use `+login
/// <user>` without re-entering credentials.
@MainActor
final class SteamSession: ObservableObject {
    @Published private(set) var username: String?
    @Published private(set) var isInstalling = false
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private let cmd = SteamCMD()
    private let defaultsKey = "steam.username"

    var isLoggedIn: Bool { username != nil }
    var hasLocalSteam: Bool { SteamLocator.hasLocalWorkshop }

    init() {
        username = UserDefaults.standard.string(forKey: defaultsKey)
    }

    // MARK: - Login

    /// Attempts login; on success stores the username. Returns the raw result
    /// so the UI can prompt for a Steam Guard code and retry.
    func login(user: String, password: String, guardCode: String?) async -> SteamLoginResult {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let result = try await cmd.login(user: user, password: password, guardCode: guardCode)
            if result == .success {
                username = user
                UserDefaults.standard.set(user, forKey: defaultsKey)
                // Persist the password so downloads can always re-authenticate
                // (the machine is Steam-Guard-trusted after this login).
                CredentialStore.save(password: password)
            }
            return result
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failed(lastError ?? "")
        }
    }

    func signOut() {
        CredentialStore.clear()
        username = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func installSteamCMD() async {
        isInstalling = true
        lastError = nil
        defer { isInstalling = false }
        do { try await cmd.ensureInstalled() }
        catch { lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    // MARK: - Download

    /// True when we have stored credentials to authenticate downloads.
    var hasStoredPassword: Bool { CredentialStore.hasPassword }

    /// Downloads a batch of workshop items in one SteamCMD session (single
    /// login → avoids rate-limiting). `onItemFinished(id)` fires as each item
    /// completes. Returns per-id results.
    func downloadItems(_ ids: [String], onItemFinished: (@Sendable (String) -> Void)? = nil)
        async throws -> [String: SteamDownloadResult] {
        guard let user = username else { return ids.reduce(into: [:]) { $0[$1] = .notLoggedIn } }
        let password = CredentialStore.password() ?? ""
        return try await cmd.downloadItems(ids, user: user, password: password,
                                           onItemFinished: onItemFinished)
    }
}
