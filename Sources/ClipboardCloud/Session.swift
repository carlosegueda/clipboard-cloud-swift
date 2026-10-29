import CryptoKit
import Foundation
import Observation

/// Sesión de Convex Auth + cifrado: equivale a ConvexAuthProvider y EncryptionProvider de la web.
@MainActor
@Observable
final class Session {
    enum State {
        case loading
        case signedOut
        /// Con sesión, pero sin la DEK (hay que pedir la contraseña).
        case locked
        case ready
    }

    private(set) var state: State = .loading
    private(set) var viewer: Viewer?
    private(set) var unlockError: String?
    /// true cuando la clave privada para recibir compartidos está lista.
    private(set) var shareReady = false

    @ObservationIgnored private(set) var dek: SymmetricKey?
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let convex: ConvexHTTPClient
    @ObservationIgnored private var stored: StoredSession?
    @ObservationIgnored private var refreshTask: Task<String?, any Error>?
    @ObservationIgnored private var sharePrivateKey: ClipCrypto.SharePrivateKey?
    @ObservationIgnored private var shareKeys: [String: SymmetricKey] = [:]

    var isSignedIn: Bool { stored != nil }

    init(convex: ConvexHTTPClient) {
        self.convex = convex
        convex.tokenProvider = { [weak self] forceRefresh in
            try await self?.accessToken(forceRefresh: forceRefresh)
        }
    }

    /// Recupera la sesión guardada en el Llavero al arrancar.
    func restore() async {
        stored = SessionStore.load()
        guard stored != nil else {
            setState(.signedOut)
            return
        }
        // Sin red, se reintenta hasta poder cargar el usuario.
        while stored != nil {
            do {
                try await loadViewer(password: nil)
                return
            } catch {
                print("[session] restore failed, retrying", error)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - Auth

    /// `flow`: "signIn" | "signUp"
    func signIn(email: String, password: String, flow: String) async throws {
        let result: SignInResult = try await convex.action(
            "auth:signIn",
            SignInArgs(provider: "password", params: .init(email: email, password: password, flow: flow)),
            authenticated: false
        )
        guard let tokens = result.tokens else { throw AppError("No se pudo iniciar sesión") }
        stored = StoredSession(token: tokens.token, refreshToken: tokens.refreshToken)
        SessionStore.save(stored!)
        setState(.loading)
        do {
            // Como la web (stashPendingPassword): la contraseña del login desbloquea el cifrado.
            try await loadViewer(password: password)
        } catch {
            endSession()
            throw error
        }
    }

    func signOut() async {
        if stored != nil {
            _ = try? await convex.action("auth:signOut", EmptyArgs(), as: Ignored?.self)
        }
        endSession()
    }

    /// Cambia la contraseña y, si hay DEK, la vuelve a envolver con la nueva.
    func changePassword(current: String, new: String) async throws {
        var encSalt: String?
        var wrappedDek: String?
        if let viewer, let dek, let oldSalt = viewer.encSalt.flatMap({ Data(base64Encoded: $0) }),
           let oldWrapped = viewer.wrappedDek {
            do {
                // Verifica que la contraseña actual abre la DEK.
                _ = try ClipCrypto.unwrap(oldWrapped, with: try await Self.deriveKek(current, oldSalt))
                let newSalt = ClipCrypto.generateSalt()
                wrappedDek = try ClipCrypto.wrap(dek, with: try await Self.deriveKek(new, newSalt))
                encSalt = newSalt.base64EncodedString()
            } catch {
                // Igual que la web: el servidor rechazará la contraseña actual.
                print("[session] rewrap failed", error)
            }
        }

        _ = try await convex.action(
            "users:changePassword",
            ChangePasswordArgs(currentPassword: current, newPassword: new, encSalt: encSalt, wrappedDek: wrappedDek),
            as: Ignored?.self
        )
        if let viewer = try? await convex.query("users:viewer", EmptyArgs(), as: Viewer?.self) {
            self.viewer = viewer
        }
    }

    // MARK: - Cifrado

    func unlock(password: String) async throws {
        unlockError = nil
        do {
            try await unlockWithPassword(password)
        } catch {
            unlockError = error.localizedDescription
            setState(.locked)
            throw error
        }
    }

    /// Clave para descifrar: la DEK propia, o la derivada vía ECDH si el item fue compartido.
    func key(forShareKey shareKey: String?) throws -> SymmetricKey {
        guard let shareKey else {
            guard let dek else { throw AppError("Cifrado no desbloqueado") }
            return dek
        }
        if let cached = shareKeys[shareKey] { return cached }
        guard let sharePrivateKey else { throw AppError("Claves para compartir no listas") }
        let key = try ClipCrypto.deriveShareKey(
            privateKey: sharePrivateKey, publicKey: try ClipCrypto.importPublicKey(shareKey)
        )
        shareKeys[shareKey] = key
        return key
    }

    private func loadViewer(password: String?) async throws {
        let viewer: Viewer? = try await convex.query("users:viewer", EmptyArgs())
        guard stored != nil else { return }
        guard let viewer else {
            endSession()
            return
        }
        self.viewer = viewer

        if stored?.dekUserId == viewer.id, let cached = stored?.dek,
           let key = try? ClipCrypto.importKey(base64: cached) {
            activate(key)
        } else if let password {
            do {
                try await unlockWithPassword(password)
            } catch {
                unlockError = error.localizedDescription
                setState(.locked)
            }
        } else {
            setState(.locked)
        }
    }

    private func unlockWithPassword(_ password: String) async throws {
        guard let viewer else { throw AppError("No hay sesión") }
        if let encSalt = viewer.encSalt, let wrappedDek = viewer.wrappedDek,
           let salt = Data(base64Encoded: encSalt) {
            let kek = try await Self.deriveKek(password, salt)
            do {
                activate(try ClipCrypto.unwrap(wrappedDek, with: kek))
            } catch {
                throw AppError("Contraseña incorrecta o clave corrupta")
            }
        } else {
            // Primera vez: crear la DEK y guardarla envuelta con la contraseña.
            let salt = ClipCrypto.generateSalt()
            let key = ClipCrypto.generateKey()
            let wrapped = try ClipCrypto.wrap(key, with: try await Self.deriveKek(password, salt))
            _ = try await convex.mutation(
                "users:saveEncryptionMaterial",
                EncryptionMaterialArgs(encSalt: salt.base64EncodedString(), wrappedDek: wrapped),
                as: Ignored?.self
            )
            activate(key)
        }
    }

    private func activate(_ key: SymmetricKey) {
        dek = key
        stored?.dekUserId = viewer?.id
        stored?.dek = ClipCrypto.exportKey(key)
        if let stored { SessionStore.save(stored) }
        unlockError = nil
        setState(.ready)
        Task { await prepareShareKeys() }
    }

    /// Par ECDH para recibir items compartidos: se descifra la privada con la DEK
    /// o, si el usuario aún no tiene, se crea una.
    private func prepareShareKeys() async {
        guard let dek, var viewer else { return }
        do {
            if viewer.publicKey == nil || viewer.encPrivateKey == nil {
                let pair = ClipCrypto.SharePrivateKey()
                _ = try await convex.mutation(
                    "users:saveShareKeys",
                    ShareKeysArgs(
                        publicKey: ClipCrypto.exportPublicKey(pair.publicKey),
                        encPrivateKey: try ClipCrypto.encryptPrivateKey(pair, with: dek)
                    ),
                    as: Ignored?.self
                )
                // Otro dispositivo pudo haberlas creado primero: usar las del servidor.
                guard let refreshed = try await convex.query("users:viewer", EmptyArgs(), as: Viewer?.self) else { return }
                viewer = refreshed
                self.viewer = refreshed
            }
            guard let encPrivateKey = viewer.encPrivateKey else { return }
            sharePrivateKey = try ClipCrypto.decryptPrivateKey(encPrivateKey, with: dek)
            shareKeys = [:]
            shareReady = true
        } catch {
            print("[session] No se pudieron preparar las claves para compartir", error)
        }
    }

    private static func deriveKek(_ password: String, _ salt: Data) async throws -> SymmetricKey {
        try await Task.detached(priority: .userInitiated) {
            try ClipCrypto.deriveKek(password: password, salt: salt)
        }.value
    }

    // MARK: - Tokens

    private func accessToken(forceRefresh: Bool) async throws -> String? {
        guard let stored else { return nil }
        if !forceRefresh, !Self.isExpiring(stored.token) { return stored.token }
        if let refreshTask { return try await refreshTask.value }

        let task = Task { try await refreshTokens() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func refreshTokens() async throws -> String? {
        guard let refreshToken = stored?.refreshToken else { return nil }
        let result: SignInResult
        do {
            result = try await convex.action(
                "auth:signIn", RefreshArgs(refreshToken: refreshToken), authenticated: false
            )
        } catch is ConvexServerError {
            // El servidor rechazó el refresh token (vencido o ya usado). Los errores
            // de red sí se propagan para reintentar sin perder la sesión.
            endSession()
            return nil
        }
        guard let tokens = result.tokens else {
            // Refresh token vencido o revocado: hay que volver a iniciar sesión.
            endSession()
            return nil
        }
        stored?.token = tokens.token
        stored?.refreshToken = tokens.refreshToken
        if let stored { SessionStore.save(stored) }
        return tokens.token
    }

    /// true si el JWT vence en menos de un minuto.
    private static func isExpiring(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return true }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double else { return true }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow < 60
    }

    private func endSession() {
        SessionStore.clear()
        stored = nil
        viewer = nil
        dek = nil
        sharePrivateKey = nil
        shareKeys = [:]
        shareReady = false
        unlockError = nil
        setState(.signedOut)
    }

    private func setState(_ next: State) {
        state = next
        onChange()
    }
}

private struct SignInArgs: Encodable {
    struct Params: Encodable {
        let email: String
        let password: String
        let flow: String
    }

    let provider: String
    let params: Params
}

private struct RefreshArgs: Encodable {
    let refreshToken: String
}

private struct SignInResult: Decodable {
    struct Tokens: Decodable {
        let token: String
        let refreshToken: String
    }

    let tokens: Tokens?
}

private struct EncryptionMaterialArgs: Encodable {
    let encSalt: String
    let wrappedDek: String
}

private struct ShareKeysArgs: Encodable {
    let publicKey: String
    let encPrivateKey: String
}

private struct ChangePasswordArgs: Encodable {
    let currentPassword: String
    let newPassword: String
    let encSalt: String?
    let wrappedDek: String?
}
