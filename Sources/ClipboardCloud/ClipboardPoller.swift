import AppKit
import CryptoKit
import Foundation

/// Port de clipboardPoller.js: cada 3 s lee el portapapeles, lo cifra con la DEK
/// y lo sube a Convex.
@MainActor
final class ClipboardPoller {
    nonisolated static let pollIntervalMs = 3000

    var onStatus: () -> Void = {}
    /// La sesión nativa decide si hay usuario y DEK.
    var isAuthenticated: () -> Bool = { false }
    var encryptionKey: () -> SymmetricKey? = { nil }
    private(set) var enabled = true
    private(set) var lastCaptureAt: Date?
    private(set) var lastError: String?

    private let convex: ConvexHTTPClient
    private let deviceId: String
    private var loop: Task<Void, Never>?
    private var busy = false
    private var lastLocalHash: String?
    private var ignoreHashes: Set<String> = []
    /// changeCount ya procesado: evita releer (y convertir a PNG) el mismo contenido en cada tick.
    private var handledChangeCount: Int?

    var isRunning: Bool { loop != nil }

    init(convex: ConvexHTTPClient, deviceId: String) {
        self.convex = convex
        self.deviceId = deviceId
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .milliseconds(Self.pollIntervalMs))
            }
        }
        onStatus()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        onStatus()
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        onStatus()
    }

    /// Ignora un contenido que escribió la propia app (p. ej. "Copiar" en el historial).
    func ignoreHash(_ hash: String) {
        ignoreHashes.insert(hash)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.pollIntervalMs * 2))
            self?.ignoreHashes.remove(hash)
        }
    }

    func tick() async {
        // Espera a que se desbloquee el cifrado (misma DEK que el historial).
        guard enabled, !busy, isAuthenticated(), let dek = encryptionKey() else { return }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != handledChangeCount else { return }

        guard let snapshot = Self.readSnapshot(pasteboard), snapshot.hash != lastLocalHash else {
            handledChangeCount = changeCount
            return
        }
        if ignoreHashes.contains(snapshot.hash) {
            lastLocalHash = snapshot.hash
            handledChangeCount = changeCount
            return
        }

        busy = true
        defer {
            busy = false
            onStatus()
        }
        let copiedAt = Date()

        do {
            let result: CaptureResult
            switch snapshot {
            case let .text(text, hash):
                result = try await convex.mutation(
                    "clipboard:captureText",
                    CaptureTextArgs(
                        text: try ClipCrypto.encryptText(text, with: dek),
                        contentHash: hash,
                        copiedAt: copiedAt.millis,
                        deviceId: deviceId,
                        encrypted: true,
                        charCount: text.utf16.count
                    )
                )
            case let .image(png, hash):
                result = try await uploadImage(
                    png, mimeType: "image/png", contentHash: hash,
                    copiedAt: copiedAt, source: "auto", fileName: nil
                )
            }
            lastLocalHash = snapshot.hash
            handledChangeCount = changeCount
            if result.saved {
                lastCaptureAt = copiedAt
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
            print("[clipboard-poller]", error)
        }
    }

    func uploadImage(
        _ data: Data,
        mimeType: String,
        contentHash: String,
        copiedAt: Date,
        source: String,
        fileName: String?
    ) async throws -> CaptureResult {
        guard isAuthenticated() else { return CaptureResult(saved: false, reason: "unauthenticated") }
        guard let dek = encryptionKey() else { return CaptureResult(saved: false, reason: "encryption_locked") }

        let storageId = try await convex.uploadToStorage(try ClipCrypto.encrypt(data, with: dek))
        return try await convex.mutation(
            "clipboard:captureImage",
            CaptureImageArgs(
                storageId: storageId,
                contentHash: contentHash,
                copiedAt: copiedAt.millis,
                source: source,
                deviceId: deviceId,
                encrypted: true,
                mimeType: mimeType,
                fileName: fileName
            )
        )
    }

    // MARK: - Lectura del portapapeles

    private enum Snapshot {
        case text(String, hash: String)
        case image(Data, hash: String)

        var hash: String {
            switch self {
            case let .text(_, hash), let .image(_, hash): hash
            }
        }
    }

    private static func readSnapshot(_ pasteboard: NSPasteboard) -> Snapshot? {
        // Los archivos copiados en Finder traen su icono como imagen: no se suben como captura.
        let isFileCopy = pasteboard.types?.contains(.fileURL) ?? false
        if !isFileCopy, let png = pngData(from: pasteboard) {
            return .image(png, hash: ClipCrypto.sha256Hex(png))
        }

        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return .text(text, hash: ClipCrypto.sha256Hex(Data(text.utf8)))
        }
        return nil
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

private struct CaptureTextArgs: Encodable {
    let text: String
    let contentHash: String
    let copiedAt: Int
    let deviceId: String
    let encrypted: Bool
    let charCount: Int
}

private struct CaptureImageArgs: Encodable {
    let storageId: String
    let contentHash: String
    let copiedAt: Int
    let source: String
    let deviceId: String
    let encrypted: Bool
    let mimeType: String
    let fileName: String?
}
