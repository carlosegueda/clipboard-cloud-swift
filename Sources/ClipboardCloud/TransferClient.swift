import CoreServices
import CryptoKit
import Foundation

/// Archivo elegido para enviar: se lee por trozos al subir, no entero en memoria.
struct TransferSource: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int
    let mimeType: String
}

/// Enlace creado desde este dispositivo o desde la cuenta.
struct TransferRecord: Codable, Identifiable, Sendable {
    let slug: String
    /// nil si el secreto de un enlace de la cuenta no se pudo descifrar.
    var link: String?
    /// Solo sin cuenta: con cuenta, la sesión basta para borrar.
    var ownerToken: String?
    let fileCount: Int
    let totalBytes: Int
    let expiresAt: Date
    let hasPassword: Bool

    var id: String { slug }
}

struct TransferLimits: Decodable, Sendable {
    let maxFiles: Int
    let maxBytes: Int
    let chunkBytes: Int

    enum CodingKeys: String, CodingKey { case maxFiles, maxBytes, chunkBytes }

    // Convex puede serializar los enteros como `20.0`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxFiles = Int(try container.decode(Double.self, forKey: .maxFiles))
        maxBytes = Int(try container.decode(Double.self, forKey: .maxBytes))
        chunkBytes = Int(try container.decode(Double.self, forKey: .chunkBytes))
    }
}

/// Se alcanzó el tope de enlaces activos o de espacio sin cuenta.
struct TransferQuotaError: Error {}

/// Transferencia abierta: ya se comprobó el acceso y se puede descargar.
struct OpenedTransfer: Sendable {
    struct Chunk: Decodable, Sendable {
        let fileIndex: Int
        let chunkIndex: Int
        let url: String?

        enum CodingKeys: String, CodingKey { case fileIndex, chunkIndex, url }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fileIndex = Int(try container.decode(Double.self, forKey: .fileIndex))
            chunkIndex = Int(try container.decode(Double.self, forKey: .chunkIndex))
            url = try container.decodeIfPresent(String.self, forKey: .url)
        }
    }

    let manifest: TransferCrypto.Manifest
    let chunks: [Chunk]
    let encKey: SymmetricKey
    let expiresAt: Date
}

enum TransferOpenResult: Sendable {
    case opened(OpenedTransfer)
    case missing
    /// Contraseña incorrecta (o enlace alterado).
    case denied
    case locked(until: Date)
}

/// Lo público de un enlace, antes de pedir la contraseña.
struct TransferInfo: Decodable, Sendable {
    let hasPassword: Bool
    let pwSalt: String?
}

/// API de `convex/transfers.ts`: cifra, sube por trozos, abre y descarga.
@MainActor
final class TransferClient {
    private static let uploadAttempts = 3

    private let convex: ConvexHTTPClient
    private let webAppURL: URL

    init(convex: ConvexHTTPClient, webAppURL: URL) {
        self.convex = convex
        self.webAppURL = webAppURL
    }

    func limits() async throws -> TransferLimits {
        try await convex.query("transfers:limits", EmptyArgs())
    }

    // MARK: - Subida

    /// Si falla o se cancela, borra lo ya subido. `dek` solo se pasa con sesión iniciada.
    func upload(
        files: [TransferSource],
        password: String?,
        dek: SymmetricKey?,
        chunkBytes: Int,
        onProgress: @escaping @MainActor (_ sent: Int, _ total: Int) -> Void
    ) async throws -> TransferRecord {
        let secretData = TransferCrypto.randomBytes(TransferCrypto.secretBytes)
        let secret = TransferCrypto.base64URL(secretData)
        let ownerToken = TransferCrypto.base64URL(TransferCrypto.randomBytes(TransferCrypto.secretBytes))
        let pwSalt = password == nil ? nil : ClipCrypto.generateSalt()
        let keys = try await Task.detached(priority: .userInitiated) {
            try TransferCrypto.deriveKeys(secret: secretData, password: password, pwSalt: pwSalt)
        }.value

        let manifest = TransferCrypto.Manifest(files: files.map { file in
            .init(
                name: file.name, size: file.size, type: file.mimeType,
                chunks: max(1, Int((Double(file.size) / Double(chunkBytes)).rounded(.up)))
            )
        })
        let totalBytes = files.reduce(0) { $0 + $1.size }

        let created: CreateResult = try await convex.mutation("transfers:create", CreateArgs(
            accessHash: TransferCrypto.hashToken(keys.accessToken),
            ownerHash: TransferCrypto.hashToken(ownerToken),
            pwSalt: pwSalt.map(TransferCrypto.base64URL),
            fileCount: files.count,
            chunkCount: manifest.files.reduce(0) { $0 + $1.chunks },
            plannedBytes: totalBytes,
            encLinkSecret: try dek.map { try ClipCrypto.encryptText(secret, with: $0) }
        ))
        guard created.status == "ok", let slug = created.slug else { throw TransferQuotaError() }

        do {
            var sent = 0
            onProgress(sent, totalBytes)
            for (fileIndex, file) in files.enumerated() {
                let chunks = manifest.files[fileIndex].chunks
                let scoped = file.url.startAccessingSecurityScopedResource()
                defer { if scoped { file.url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: file.url)
                defer { try? handle.close() }

                for chunkIndex in 0..<chunks {
                    try Task.checkCancellation()
                    let expected = min(chunkBytes, file.size - chunkIndex * chunkBytes)
                    let aad = TransferCrypto.chunkAad(fileIndex: fileIndex, chunkIndex: chunkIndex, chunkCount: chunks)
                    let encKey = keys.encKey
                    let packed = try await Task.detached(priority: .userInitiated) {
                        let plain = try handle.read(upToCount: chunkBytes) ?? Data()
                        // El archivo cambió desde que se eligió.
                        guard plain.count == expected else { throw AppError("El archivo cambió") }
                        return try TransferCrypto.seal(plain, with: encKey, aad: aad)
                    }.value
                    try await uploadChunk(
                        packed, slug: slug, ownerToken: ownerToken, fileIndex: fileIndex, chunkIndex: chunkIndex
                    )
                    sent += expected
                    onProgress(sent, totalBytes)
                }
            }

            let finalized: FinalizeResult = try await convex.mutation("transfers:finalize", FinalizeArgs(
                slug: slug, ownerToken: ownerToken,
                encManifest: try TransferCrypto.sealManifest(manifest, with: keys.encKey)
            ))
            return TransferRecord(
                slug: slug,
                link: TransferCrypto.link(webAppURL: webAppURL, slug: slug, secret: secret),
                ownerToken: ownerToken,
                fileCount: files.count,
                totalBytes: totalBytes,
                expiresAt: Date(millis: finalized.expiresAt),
                hasPassword: password != nil
            )
        } catch {
            // Tarea aparte: esta pudo cancelarse y arrastraría la limpieza. Si
            // tampoco se puede borrar, el cron elimina la subida abandonada.
            Task { try? await self.remove(slug: slug, ownerToken: ownerToken) }
            throw error
        }
    }

    private func uploadChunk(
        _ packed: Data, slug: String, ownerToken: String, fileIndex: Int, chunkIndex: Int
    ) async throws {
        var attempt = 1
        while true {
            do {
                let urlString: String = try await convex.mutation(
                    "transfers:generateChunkUploadUrl", OwnerArgs(slug: slug, ownerToken: ownerToken)
                )
                guard let url = URL(string: urlString) else { throw AppError("URL de subida inválida") }
                let storageId = try await convex.upload(packed, to: url)
                let result: AddChunkResult = try await convex.mutation("transfers:addChunk", AddChunkArgs(
                    slug: slug, ownerToken: ownerToken, fileIndex: fileIndex, chunkIndex: chunkIndex, storageId: storageId
                ))
                guard result.accepted else { throw AppError("Trozo rechazado") }
                return
            } catch {
                if Task.isCancelled || attempt >= Self.uploadAttempts { throw error }
                try await Task.sleep(for: .seconds(attempt))
                attempt += 1
            }
        }
    }

    // MARK: - Apertura

    func info(slug: String) async throws -> TransferInfo? {
        try await convex.query("transfers:info", SlugArgs(slug: slug), as: TransferInfo?.self)
    }

    func open(slug: String, secret: String, password: String?, info: TransferInfo) async throws -> TransferOpenResult {
        guard let secretData = TransferCrypto.data(base64URL: secret) else { return .denied }
        let pwSalt = info.pwSalt.flatMap(TransferCrypto.data(base64URL:))
        let keys = try await Task.detached(priority: .userInitiated) {
            try TransferCrypto.deriveKeys(secret: secretData, password: password, pwSalt: pwSalt)
        }.value

        let response: OpenResult = try await convex.mutation(
            "transfers:open", OpenArgs(slug: slug, accessToken: keys.accessToken)
        )
        switch response.status {
        case "ok":
            guard let encManifest = response.encManifest, let expiresAt = response.expiresAt else {
                throw AppError("Respuesta incompleta")
            }
            return .opened(OpenedTransfer(
                manifest: try TransferCrypto.openManifest(encManifest, with: keys.encKey),
                chunks: response.chunks ?? [],
                encKey: keys.encKey,
                expiresAt: Date(millis: expiresAt)
            ))
        case "denied":
            return .denied
        case "locked":
            return .locked(until: Date(millis: response.retryAt ?? 0))
        default:
            return .missing
        }
    }

    // MARK: - Descarga

    /// Escribe primero en un temporal de la misma carpeta: si algo falla, no queda
    /// un archivo a medias con el nombre final.
    func download(
        _ opened: OpenedTransfer, fileIndex: Int, to destination: URL,
        onProgress: @escaping @MainActor (_ received: Int) -> Void
    ) async throws {
        let file = opened.manifest.files[fileIndex]
        let fileManager = FileManager.default
        let partial = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).part")
        guard fileManager.createFile(atPath: partial.path, contents: nil) else {
            throw AppError("No se pudo escribir el archivo")
        }
        defer { try? fileManager.removeItem(at: partial) }

        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }

        var received = 0
        for chunkIndex in 0..<file.chunks {
            try Task.checkCancellation()
            guard let urlString = opened.chunks.first(where: {
                $0.fileIndex == fileIndex && $0.chunkIndex == chunkIndex
            })?.url, let url = URL(string: urlString) else {
                throw AppError("Falta un trozo del archivo")
            }
            let (packed, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AppError("Descarga fallida")
            }
            let aad = TransferCrypto.chunkAad(fileIndex: fileIndex, chunkIndex: chunkIndex, chunkCount: file.chunks)
            let encKey = opened.encKey
            let count = try await Task.detached(priority: .userInitiated) {
                let plain = try TransferCrypto.open(packed, with: encKey, aad: aad)
                try handle.write(contentsOf: plain)
                return plain.count
            }.value
            received += count
            onProgress(received)
        }
        guard received == file.size else { throw AppError("El archivo no coincide con el manifiesto") }

        try handle.close()
        try Self.markQuarantined(partial)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: partial, to: destination)
    }

    /// Como un navegador: el archivo viene de un desconocido, así que Gatekeeper
    /// debe revisarlo antes de que se pueda ejecutar.
    private static func markQuarantined(_ url: URL) throws {
        let properties: [String: Any] = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineAgentNameKey as String: "Clipboard Cloud",
        ]
        try (url as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey)
    }

    // MARK: - Enlaces activos

    func mine(dek: SymmetricKey?) async throws -> [TransferRecord] {
        let rows: [MineRow] = try await convex.query("transfers:mine", EmptyArgs())
        return rows.map { row in
            let secret = dek.flatMap { dek in
                row.encLinkSecret.flatMap { try? ClipCrypto.decryptText($0, with: dek) }
            }
            return TransferRecord(
                slug: row.slug,
                link: secret.map { TransferCrypto.link(webAppURL: webAppURL, slug: row.slug, secret: $0) },
                ownerToken: nil,
                fileCount: row.fileCount,
                totalBytes: row.totalBytes,
                expiresAt: Date(millis: row.expiresAt),
                hasPassword: row.hasPassword
            )
        }
    }

    func remove(slug: String, ownerToken: String?) async throws {
        _ = try await convex.mutation(
            "transfers:remove", RemoveArgs(slug: slug, ownerToken: ownerToken), as: Ignored?.self
        )
    }
}

extension Date {
    init(millis: Double) {
        self.init(timeIntervalSince1970: millis / 1000)
    }
}

// MARK: - Tipos de la API

private struct CreateArgs: Encodable {
    let accessHash: String
    let ownerHash: String
    let pwSalt: String?
    let fileCount: Int
    let chunkCount: Int
    let plannedBytes: Int
    let encLinkSecret: String?
}

private struct CreateResult: Decodable {
    let status: String
    let slug: String?
}

private struct OwnerArgs: Encodable {
    let slug: String
    let ownerToken: String
}

private struct AddChunkArgs: Encodable {
    let slug: String
    let ownerToken: String
    let fileIndex: Int
    let chunkIndex: Int
    let storageId: String
}

private struct AddChunkResult: Decodable {
    let accepted: Bool
}

private struct FinalizeArgs: Encodable {
    let slug: String
    let ownerToken: String
    let encManifest: String
}

private struct FinalizeResult: Decodable {
    let expiresAt: Double
}

private struct SlugArgs: Encodable {
    let slug: String
}

private struct OpenArgs: Encodable {
    let slug: String
    let accessToken: String
}

private struct OpenResult: Decodable {
    let status: String
    let encManifest: String?
    let expiresAt: Double?
    let retryAt: Double?
    let chunks: [OpenedTransfer.Chunk]?
}

private struct RemoveArgs: Encodable {
    let slug: String
    let ownerToken: String?
}

private struct MineRow: Decodable {
    let slug: String
    let encLinkSecret: String?
    let hasPassword: Bool
    let fileCount: Int
    let totalBytes: Int
    let expiresAt: Double

    enum CodingKeys: String, CodingKey {
        case slug, encLinkSecret, hasPassword, fileCount, totalBytes, expiresAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        encLinkSecret = try container.decodeIfPresent(String.self, forKey: .encLinkSecret)
        hasPassword = try container.decode(Bool.self, forKey: .hasPassword)
        fileCount = Int(try container.decode(Double.self, forKey: .fileCount))
        totalBytes = Int(try container.decode(Double.self, forKey: .totalBytes))
        expiresAt = try container.decode(Double.self, forKey: .expiresAt)
    }
}
