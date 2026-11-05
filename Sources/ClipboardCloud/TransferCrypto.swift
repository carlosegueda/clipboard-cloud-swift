import CryptoKit
import Foundation

/// Formato de las transferencias por enlace, compatible con lib/transfer.ts de la web:
/// cualquier cambio aquí debe replicarse allí.
///
/// Enlace: `<web>/t/<slug>#<secreto>`. El fragmento no llega al servidor. De secreto +
/// contraseña (si hay) salen, con HKDF, la clave de cifrado y el token de acceso.
enum TransferCrypto {
    static let secretBytes = 32
    private static let encInfo = "cc-transfer-v1-enc"
    private static let accessInfo = "cc-transfer-v1-access"
    private static let manifestAad = "cc-transfer-v1:manifest"

    struct Keys: Sendable {
        let encKey: SymmetricKey
        let accessToken: String
    }

    struct Manifest: Codable, Sendable {
        struct File: Codable, Sendable {
            let name: String
            let size: Int
            let type: String
            let chunks: Int
        }

        var v = 1
        let files: [File]
    }

    // MARK: - Claves

    /// Con contraseña corre PBKDF2, que es lento a propósito: llamarlo fuera del hilo principal.
    static func deriveKeys(secret: Data, password: String?, pwSalt: Data?) throws -> Keys {
        var ikm = secret
        if let password, let pwSalt {
            // NFC: la misma contraseña escrita en otro sistema da los mismos bytes.
            let stretched = try ClipCrypto.deriveKek(
                password: password.precomposedStringWithCanonicalMapping, salt: pwSalt
            )
            ikm.append(stretched.withUnsafeBytes { Data($0) })
        }
        let key = SymmetricKey(data: ikm)
        return Keys(
            encKey: hkdf(key, info: encInfo),
            accessToken: base64URL(hkdf(key, info: accessInfo).withUnsafeBytes { Data($0) })
        )
    }

    private static func hkdf(_ ikm: SymmetricKey, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: Data(), info: Data(info.utf8), outputByteCount: 32
        )
    }

    static func hashToken(_ token: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(token.utf8))))
    }

    static func randomBytes(_ count: Int) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }

    // MARK: - AES-GCM

    /// `iv(12) || ciphertext || tag(16)`, el mismo empaquetado que el resto de la app.
    static func seal(_ plain: Data, with key: SymmetricKey, aad: String) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key, authenticating: Data(aad.utf8)).combined else {
            throw AppError("No se pudo cifrar")
        }
        return combined
    }

    static func open(_ packed: Data, with key: SymmetricKey, aad: String) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: packed), using: key, authenticating: Data(aad.utf8))
    }

    /// Ata cada trozo a su posición: el servidor no puede reordenarlos ni mezclarlos.
    static func chunkAad(fileIndex: Int, chunkIndex: Int, chunkCount: Int) -> String {
        "cc-transfer-v1:chunk:\(fileIndex):\(chunkIndex):\(chunkCount)"
    }

    static func sealManifest(_ manifest: Manifest, with key: SymmetricKey) throws -> String {
        base64URL(try seal(try JSONEncoder().encode(manifest), with: key, aad: manifestAad))
    }

    static func openManifest(_ encManifest: String, with key: SymmetricKey) throws -> Manifest {
        guard let packed = data(base64URL: encManifest) else { throw AppError("Manifiesto inválido") }
        let manifest = try JSONDecoder().decode(
            Manifest.self, from: try open(packed, with: key, aad: manifestAad)
        )
        guard manifest.v == 1 else { throw AppError("Manifiesto no compatible") }
        return manifest
    }

    // MARK: - Base64URL

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64URL value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    // MARK: - Enlaces y nombres

    static func link(webAppURL: URL, slug: String, secret: String) -> String {
        let base = webAppURL.absoluteString.hasSuffix("/")
            ? webAppURL.absoluteString : webAppURL.absoluteString + "/"
        return "\(base)t/\(slug)#\(secret)"
    }

    static func parseLink(_ text: String) -> (slug: String, secret: String)? {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let secret = components.fragment, !secret.isEmpty else { return nil }
        let path = components.path.split(separator: "/")
        guard path.count >= 2, path[path.count - 2] == "t" else { return nil }
        return (String(path[path.count - 1]), secret)
    }

    /// El nombre lo eligió el remitente: nunca debe poder salir de la carpeta de destino.
    static func safeFileName(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:").union(.controlCharacters))
            .joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return trimmed.isEmpty ? "file" : trimmed
    }
}
