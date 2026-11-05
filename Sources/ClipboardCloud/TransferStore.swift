import Foundation
import Observation
import UniformTypeIdentifiers

/// Estado de Cloud Transfer. Vive fuera de las vistas para que una subida siga en
/// curso al cambiar de sección.
@MainActor
@Observable
final class TransferStore {
    enum Note: Equatable {
        case folderSkipped, tooMany(Int), tooLarge(Int), failed, quota, deleteFailed
    }

    private(set) var limits: TransferLimits?
    private(set) var pending: [TransferSource] = []
    private(set) var progress: Double?
    private(set) var result: TransferRecord?
    private(set) var note: Note?
    private(set) var accountTransfers: [TransferRecord] = []
    private(set) var localTransfers: [TransferRecord] = []

    @ObservationIgnored let client: TransferClient
    @ObservationIgnored private let session: Session
    @ObservationIgnored private var uploadTask: Task<Void, Never>?

    /// Con sesión, los enlaces viven en la cuenta; sin ella, solo en este Mac.
    var active: [TransferRecord] {
        session.state == .ready ? accountTransfers : localTransfers
    }

    var totalBytes: Int { pending.reduce(0) { $0 + $1.size } }
    var isUploading: Bool { progress != nil }

    init(client: TransferClient, session: Session) {
        self.client = client
        self.session = session
        localTransfers = Self.loadLocal()
    }

    func refresh() async {
        do {
            limits = try await client.limits()
            if session.state == .ready {
                accountTransfers = try await client.mine(dek: session.dek)
            } else {
                localTransfers = localTransfers.filter { $0.expiresAt > .now }
            }
        } catch {
            print("[transfer] refresh", error)
        }
    }

    /// Al cerrar sesión no debe quedar a la vista nada de la cuenta.
    func reset() {
        uploadTask?.cancel()
        pending = []
        result = nil
        note = nil
        accountTransfers = []
    }

    // MARK: - Selección

    func add(_ urls: [URL]) {
        guard let limits else { return }
        var sources: [TransferSource] = []
        var skippedFolder = false
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values?.isDirectory != true, let size = values?.fileSize else {
                skippedFolder = true
                continue
            }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            sources.append(TransferSource(url: url, name: url.lastPathComponent, size: size, mimeType: mimeType))
        }
        let room = max(0, limits.maxFiles - pending.count)
        pending += sources.prefix(room)
        note = sources.count > room ? .tooMany(limits.maxFiles) : skippedFolder ? .folderSkipped : nil
    }

    func removePending(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    // MARK: - Subida

    func startUpload(password: String) {
        guard let limits, !pending.isEmpty, !isUploading else { return }
        guard totalBytes <= limits.maxBytes else {
            note = .tooLarge(limits.maxBytes)
            return
        }
        note = nil
        progress = 0
        let files = pending
        // Un cierre de sesión a mitad de subida no debe asociarla a nadie.
        let dek = session.state == .ready ? session.dek : nil
        uploadTask = Task {
            do {
                let record = try await client.upload(
                    files: files,
                    password: password.isEmpty ? nil : password,
                    dek: dek,
                    chunkBytes: limits.chunkBytes
                ) { [weak self] sent, total in
                    self?.progress = total > 0 ? Double(sent) / Double(total) : 1
                }
                result = record
                pending = []
                if dek == nil {
                    localTransfers.insert(record, at: 0)
                    saveLocal()
                }
                await refresh()
            } catch is CancellationError {
                // El usuario canceló.
            } catch is TransferQuotaError {
                note = .quota
            } catch {
                if !Task.isCancelled {
                    print("[transfer] upload", error)
                    note = .failed
                }
            }
            progress = nil
        }
    }

    func cancelUpload() {
        uploadTask?.cancel()
    }

    func startOver() {
        result = nil
    }

    // MARK: - Enlaces

    func remove(_ record: TransferRecord) async {
        do {
            try await client.remove(slug: record.slug, ownerToken: record.ownerToken)
            localTransfers.removeAll { $0.slug == record.slug }
            saveLocal()
            if result?.slug == record.slug { result = nil }
            await refresh()
        } catch {
            print("[transfer] remove", error)
            note = .deleteFailed
        }
    }

    // MARK: - Persistencia sin cuenta

    // Los enlaces incluyen el secreto que da acceso: van al Llavero, no a UserDefaults.
    private static let keychainAccount = "transfers"

    private static func loadLocal() -> [TransferRecord] {
        guard let data = SessionStore.loadData(account: keychainAccount),
              let records = try? JSONDecoder().decode([TransferRecord].self, from: data) else { return [] }
        return records.filter { $0.expiresAt > .now }
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(localTransfers) else { return }
        SessionStore.saveData(data, account: Self.keychainAccount)
    }
}
