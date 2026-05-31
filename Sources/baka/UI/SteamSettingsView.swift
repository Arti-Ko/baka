import SwiftUI

/// Steam account section for Settings: shows login state, installs SteamCMD,
/// and opens a login sheet (handling Steam Guard) so the user can download
/// Workshop wallpapers they own via Wallpaper Engine.
struct SteamSettingsView: View {
    @ObservedObject var steam: SteamSession
    @State private var showLogin = false

    var body: some View {
        Section("Steam / Wallpaper Engine") {
            if steam.hasLocalSteam {
                Label("Найден локальный Steam — подписанные обои ставятся мгновенно",
                      systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            if let user = steam.username {
                LabeledContent("Аккаунт Steam", value: user)
                Button("Выйти") { steam.signOut() }
            } else {
                LabeledContent("Аккаунт Steam", value: "Не выполнен вход")
                Button {
                    showLogin = true
                } label: {
                    Label("Войти в Steam…", systemImage: "person.crop.circle")
                }
            }

            if steam.isInstalling {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Устанавливаю SteamCMD…") }
            }

            if let error = steam.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }

            Text("SteamCMD скачивает обои с твоего аккаунта, на котором куплен Wallpaper Engine. Данные входа хранятся локально в защищённом файле (0600) и используются только для входа в Steam.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showLogin) {
            SteamLoginSheet(steam: steam)
        }
    }
}

/// Modal login form with Steam Guard handling.
private struct SteamLoginSheet: View {
    @ObservedObject var steam: SteamSession
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var guardCode = ""
    @State private var needsGuard = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Вход в Steam")
                .font(.title2.weight(.semibold))

            Text("Используй аккаунт, на котором куплен Wallpaper Engine.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                TextField("Логин Steam", text: $username)
                    .textContentType(.username)
                SecureField("Пароль", text: $password)
                if needsGuard {
                    TextField("Код Steam Guard", text: $guardCode)
                        .textContentType(.oneTimeCode)
                }
            }
            .formStyle(.grouped)
            .frame(height: needsGuard ? 150 : 110)

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button(needsGuard ? "Подтвердить" : "Войти") {
                    Task { await attemptLogin() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty || steam.isBusy
                          || (needsGuard && guardCode.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 420)
        .overlay {
            if steam.isBusy {
                ProgressView().controlSize(.large)
            }
        }
    }

    private func attemptLogin() async {
        message = nil
        let result = await steam.login(
            user: username,
            password: password,
            guardCode: needsGuard ? guardCode : nil
        )
        switch result {
        case .success:
            dismiss()
        case .needsSteamGuard:
            needsGuard = true
            message = "Введите код Steam Guard (из приложения Steam или почты)."
        case .invalidPassword:
            message = "Неверный логин или пароль."
        case .rateLimited:
            message = "Слишком много попыток. Подождите и попробуйте снова."
        case .failed(let m):
            message = m.isEmpty ? "Не удалось войти." : m
        }
    }
}
