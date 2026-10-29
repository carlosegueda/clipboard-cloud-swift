import CommonCrypto
import CryptoKit
import Foundation

/// Mismo esquema que la web (lib/crypto.ts):
/// - AES-256-GCM con `iv(12) || ciphertext || tag(16)`, y los textos como `cc1.<base64>`.
/// - DEK aleatoria envuelta con una KEK derivada de la contraseña (PBKDF2-SHA256, 310 000 iteraciones).
/// - Compartir: ECDH P-256 + HKDF-SHA256 ("cc-share-v1") -> AES-GCM.
enum ClipCrypto {
    static let textPrefix = "cc1."
    private static let pbkdf2Iterations: UInt32 = 310_000
    private static let saltBytes = 16
    private static let shareInfo = Data("cc-share-v1".utf8)

    // MARK: - DEK

    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Importa una DEK en crudo (base64).
    static func importKey(base64: String) throws -> SymmetricKey {
        guard let raw = Data(base64Encoded: base64), raw.count == 32 else {
            throw AppError("Clave de cifrado inválida")
        }
        return SymmetricKey(data: raw)
    }

    static func exportKey(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    // MARK: - AES-GCM

    static func encrypt(_ plain: Data, with key: SymmetricKey) throws -> Data {
        // `combined` es nonce(12) || ciphertext || tag: idéntico al empaquetado de WebCrypto.
        guard let combined = try AES.GCM.seal(plain, using: key).combined else {
            throw AppError("No se pudo cifrar")
        }
        return combined
    }

    static func decrypt(_ packed: Data, with key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: packed), using: key)
    }

    static func encryptText(_ text: String, with key: SymmetricKey) throws -> String {
        textPrefix + (try encrypt(Data(text.utf8), with: key)).base64EncodedString()
    }

    static func decryptText(_ ciphertext: String, with key: SymmetricKey) throws -> String {
        guard ciphertext.hasPrefix(textPrefix),
              let packed = Data(base64Encoded: String(ciphertext.dropFirst(textPrefix.count))),
              let text = String(data: try decrypt(packed, with: key), encoding: .utf8) else {
            throw AppError("Texto no cifrado con el formato esperado")
        }
        return text
    }

    static func looksEncrypted(_ text: String?) -> Bool {
        text?.hasPrefix(textPrefix) ?? false
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Contraseña -> KEK -> DEK envuelta

    static func generateSalt() -> Data {
        Data((0..<saltBytes).map { _ in UInt8.random(in: .min ... .max) })
    }

    /// PBKDF2 es lento a propósito: llamarlo fuera del hilo principal.
    static func deriveKek(password: String, salt: Data) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(password.utf8)
        let status = salt.withUnsafeBytes { saltBuffer in
            passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                    passwordBytes.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    pbkdf2Iterations,
                    &derived,
                    derived.count
                )
            }
        }
        guard status == kCCSuccess else { throw AppError("No se pudo derivar la clave") }
        return SymmetricKey(data: derived)
    }

    static func wrap(_ dek: SymmetricKey, with kek: SymmetricKey) throws -> String {
        try encrypt(dek.withUnsafeBytes { Data($0) }, with: kek).base64EncodedString()
    }

    static func unwrap(_ wrappedBase64: String, with kek: SymmetricKey) throws -> SymmetricKey {
        guard let packed = Data(base64Encoded: wrappedBase64) else {
            throw AppError("Wrapped DEK inválida")
        }
        return SymmetricKey(data: try decrypt(packed, with: kek))
    }

    // MARK: - Compartir entre amigos

    typealias SharePrivateKey = P256.KeyAgreement.PrivateKey

    /// Clave pública en formato "raw" de WebCrypto (punto sin comprimir, 65 bytes).
    static func exportPublicKey(_ key: P256.KeyAgreement.PublicKey) -> String {
        key.x963Representation.base64EncodedString()
    }

    static func importPublicKey(_ rawBase64: String) throws -> P256.KeyAgreement.PublicKey {
        guard let raw = Data(base64Encoded: rawBase64) else { throw AppError("Clave pública inválida") }
        return try P256.KeyAgreement.PublicKey(x963Representation: raw)
    }

    /// Cifra la clave privada (PKCS#8) con la DEK del usuario.
    static func encryptPrivateKey(_ key: SharePrivateKey, with dek: SymmetricKey) throws -> String {
        try encrypt(key.derRepresentation, with: dek).base64EncodedString()
    }

    static func decryptPrivateKey(_ encryptedBase64: String, with dek: SymmetricKey) throws -> SharePrivateKey {
        guard let packed = Data(base64Encoded: encryptedBase64) else {
            throw AppError("Clave privada inválida")
        }
        return try SharePrivateKey(derRepresentation: try decrypt(packed, with: dek))
    }

    static func deriveShareKey(
        privateKey: SharePrivateKey,
        publicKey: P256.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
            .hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: shareInfo, outputByteCount: 32)
    }

    /// Clave para un destinatario: par efímero + su clave pública. `shareKey` es la
    /// pública efímera, con la que el destinatario deriva la misma clave.
    static func createRecipientKey(publicKey: String) throws -> (key: SymmetricKey, shareKey: String) {
        let ephemeral = SharePrivateKey()
        let key = try deriveShareKey(privateKey: ephemeral, publicKey: try importPublicKey(publicKey))
        return (key, exportPublicKey(ephemeral.publicKey))
    }
}
