import SwiftUI

/// Contenido de la ventana: login, desbloqueo o la app (app/page.tsx).
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.session.state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    MutedText(text: model.loc.t(.loadingSession), size: 14.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                AuthView()
            case .locked:
                UnlockView()
            case .ready:
                MainView()
            }
        }
        .font(Theme.font())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .background(Theme.bg)
        // La web solo tiene tema claro (incluye la barra de título).
        .preferredColorScheme(.light)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                    Text(toast).squish()
                }
                .font(Theme.font(13.6, .medium))
                .textCase(.uppercase)
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.ink)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.toast)
    }
}

/// components/AuthScreen.tsx
struct AuthView: View {
    @Environment(AppModel.self) private var model
    @State private var signUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false

    var body: some View {
        let loc = model.loc
        AuthBackground {
            BrandHeader()
            Text(loc.t(signUp ? .signUpTitle : .signInTitle))
                .font(Theme.font(18.4, .bold))
                .textCase(.uppercase)
                .squish()
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: loc.t(.email), icon: "envelope")
                HardField(placeholder: "", text: $email, contentType: .username)
                    .padding(.bottom, 6)
                FieldLabel(text: loc.t(.password), icon: "key")
                HardField(
                    placeholder: "", text: $password, secure: true,
                    contentType: signUp ? .newPassword : .password, onSubmit: submit
                )
            }

            if !error.isEmpty {
                Text(error).font(Theme.font(14)).textCase(.uppercase).foregroundStyle(Theme.danger)
            }

            Button(action: submit) {
                Label(
                    busy ? loc.t(.wait) : loc.t(signUp ? .signUp : .signIn),
                    systemImage: signUp ? "person.badge.plus" : "arrow.right.to.line"
                )
            }
            .buttonStyle(HardButtonStyle(kind: .primary, fullWidth: true))
            .keyboardShortcut(.defaultAction)
            .disabled(busy || email.isEmpty || password.count < 8)
            .padding(.top, 4)

            HStack(spacing: 6) {
                Text(loc.t(signUp ? .haveAccount : .noAccount))
                    .font(Theme.font(14.4))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                Button(loc.t(signUp ? .signInNow : .createOne)) {
                    signUp.toggle()
                    error = ""
                }
                .buttonStyle(HardLinkStyle())
            }
            .padding(.top, 2)
        }
    }

    private func submit() {
        guard !busy, !email.isEmpty, password.count >= 8 else { return }
        error = ""
        busy = true
        Task {
            do {
                try await model.session.signIn(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password,
                    flow: signUp ? "signUp" : "signIn"
                )
            } catch {
                print("[auth]", error)
                self.error = model.loc.t(signUp ? .authErrorSignUp : .authErrorSignIn)
            }
            busy = false
        }
    }
}

/// components/UnlockEncryption.tsx
struct UnlockView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        let loc = model.loc
        AuthBackground {
            HStack(spacing: 8) {
                IconTile(systemImage: "lock.fill")
                Text(loc.t(.encryptionUnlockTitle))
                    .font(Theme.font(18.4, .bold))
                    .textCase(.uppercase)
                    .squish()
            }
            MutedText(text: loc.t(.encryptionUnlockBody), size: 14)

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: loc.t(.password), icon: "key")
                HardField(placeholder: "", text: $password, secure: true, contentType: .password, onSubmit: submit)
            }

            if failed || model.session.unlockError != nil {
                Text(loc.t(.encryptionUnlockFailed))
                    .font(Theme.font(14)).textCase(.uppercase).foregroundStyle(Theme.danger)
            }

            Button(action: submit) {
                Label(busy ? loc.t(.wait) : loc.t(.encryptionUnlock), systemImage: "lock.open")
            }
            .buttonStyle(HardButtonStyle(kind: .primary, fullWidth: true))
            .keyboardShortcut(.defaultAction)
            .disabled(busy || password.count < 8)

            Button(loc.t(.logout)) {
                Task { await model.session.signOut() }
            }
            .buttonStyle(HardLinkStyle(color: Theme.muted))
        }
    }

    private func submit() {
        guard !busy, password.count >= 8 else { return }
        failed = false
        busy = true
        Task {
            do {
                try await model.session.unlock(password: password)
                password = ""
            } catch {
                failed = true
            }
            busy = false
        }
    }
}

/// Logo + "CLIPBOARD CLOUD".
struct BrandHeader: View {
    var subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemImage: "doc.on.doc")
            VStack(alignment: .leading, spacing: 0) {
                Text("Clipboard Cloud")
                    .font(Theme.font(18.4, .bold))
                    .textCase(.uppercase)
                    .squish()
                if let subtitle {
                    Text(subtitle).font(Theme.font(12)).textCase(.uppercase).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

/// Fondo con degradado + tarjeta de doble marco centrada (pantallas sin sesión).
private struct AuthBackground<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HardCard(padding: 24, shadow: false) {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .frame(width: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Theme.bg
                RadialGradient(
                    colors: [Color(hex: 0xE8EAEE), Color(hex: 0xE8EAEE).opacity(0)],
                    center: UnitPoint(x: 0.1, y: 0), startRadius: 0, endRadius: 520
                )
            }
        }
    }
}
