import Foundation

/// Stores the Steam password locally in a 0600 file under Application Support.
///
/// We deliberately do NOT use the Keychain here: this app is ad-hoc signed and
/// rebuilt frequently, and Keychain ACLs are bound to the app's code signature,
/// so a password saved by one build becomes unreadable by the next — which
/// surfaced as "session unavailable" after every rebuild. A user-only-readable
/// file in the app's own support directory is reliable across rebuilds.
///
/// Tradeoff: the password is stored obfuscated (not encrypted) on the user's
/// own machine. Acceptable for a personal, local, single-user wallpaper app.
enum CredentialStore {
    private static var file: URL { AppPaths.support.appendingPathComponent(".steam_cred") }

    static func save(password: String) {
        do {
            try AppPaths.ensureDirectories()
            // Light obfuscation so it isn't plainly visible at rest.
            let data = Data(password.utf8).base64EncodedData()
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: file.path
            )
        } catch {
            Log.workshop.error("Failed to store credentials: \(error.localizedDescription)")
        }
    }

    static func password() -> String? {
        guard let data = try? Data(contentsOf: file),
              let decoded = Data(base64Encoded: data)
        else { return nil }
        return String(decoding: decoded, as: UTF8.self)
    }

    static var hasPassword: Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}
