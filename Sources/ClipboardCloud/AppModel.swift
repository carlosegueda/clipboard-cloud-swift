import AppKit
import Observation
import UniformTypeIdentifiers

/// Estado global de la app: el proceso main de Electron (main.js) más la lógica
/// de app/page.tsx de la web.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let loc = Localizer()
    let session: Session
    let history: HistoryStore
    let friends: FriendsStore
    let poll: PollStore
    private(set) var status = MonitorStatus()
    private(set) var toast: String?

    @ObservationIgnored private let convex: ConvexHTTPClient
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let poller: ClipboardPoller
    @ObservationIgnored private let screenshots = ScreenshotWatcher()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var windowLoop: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private init() {
        let convex = ConvexHTTPClient(baseURL: AppConfig.convexURL)
        let session = Session(convex: convex)
        let deviceId = ConfigStore.deviceId
        self.convex = convex
        self.deviceId = deviceId
        self.session = session
        history = HistoryStore(convex: convex, session: session)
        friends = FriendsStore(convex: convex)
        poll = PollStore(convex: convex)
        poller = ClipboardPoller(convex: convex, deviceId: deviceId)

        session.onChange = { [weak self] in self?.sessionChanged() }
        poller.onStatus = { [weak self] in self?.refreshStatus() }
        poller.isAuthenticated = { [weak self] in self?.session.isSignedIn ?? false }
        poller.encryptionKey = { [weak self] in
            guard let self, self.session.state == .ready else { return nil }
            return self.session.dek
        }
        screenshots.onStatus = { [weak self] in self?.refreshStatus() }
        screenshots.canUpload = { [weak self] in
            guard let self else { return false }
            return self.session.state == .ready && poller.enabled
        }
        screenshots.upload = { [weak self] data, mimeType, contentHash, copiedAt, fileName in
            guard let self else { throw AppError("App cerrándose") }
            return try await poller.uploadImage(
                data, mimeType: mimeType, contentHash: contentHash,
                copiedAt: copiedAt, source: "screenshot", fileName: fileName
            )
        }
    }

    func start() {
        guard !started else { return }
        started = true

        let enabled = ConfigStore.monitoring
        poller.setEnabled(enabled)
        screenshots.setEnabled(enabled)
        poller.start()
        screenshots.start()
        Task { await session.restore() }

        // Sin bundle (`swift run`) los permisos son de Terminal: no tiene sentido avisar.
        if Bundle.main.bundleIdentifier != nil {
            ensureScreenshotAccess()
        }
    }

    // MARK: - Ventana

    /// Mientras la ventana está abierta se vuelve a consultar Convex cada pocos segundos
    /// (la web usaba queries reactivas por WebSocket).
    func setWindowVisible(_ visible: Bool) {
        windowLoop?.cancel()
        windowLoop = nil
        guard visible else { return }
        windowLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshData()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refreshData() async {
        guard session.state == .ready else { return }
        await history.refresh()
        await friends.refresh()
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { toast = nil }
        }
    }

    private func sessionChanged() {
        refreshStatus()
        switch session.state {
        case .ready:
            Task {
                // Reintentar capturas pendientes ahora que hay DEK.
                await screenshots.tick()
                await refreshData()
            }
        case .signedOut:
            history.reset()
            friends.reset()
        case .loading, .locked:
            break
        }
    }

    // MARK: - Historial

    func saveText(_ text: String) async -> Bool {
        do {
            guard let dek = session.dek else { throw AppError("Cifrado no desbloqueado") }
            _ = try await convex.mutation(
                "clipboard:saveText",
                SaveTextArgs(
                    text: try ClipCrypto.encryptText(text, with: dek),
                    source: "manual", deviceId: deviceId, encrypted: true, charCount: text.utf16.count
                ),
                as: Ignored?.self
            )
            showToast(loc.t(.textSaved))
            await history.refresh()
            return true
        } catch {
            print("[app] saveText", error)
            showToast(loc.t(.textSaveFailed))
            return false
        }
    }

    func saveFiles(_ files: [PendingFile]) async -> Bool {
        var savedImages = 0
        var savedDocs = 0
        do {
            guard let dek = session.dek else { throw AppError("Cifrado no desbloqueado") }
            for file in files {
                let storageId = try await convex.uploadToStorage(try ClipCrypto.encrypt(file.data, with: dek))
                _ = try await convex.mutation(
                    file.isImage ? "clipboard:saveImage" : "clipboard:saveFile",
                    SaveFileArgs(
                        storageId: storageId, source: "manual", deviceId: deviceId,
                        encrypted: true, mimeType: file.mimeType, fileName: file.name
                    ),
                    as: Ignored?.self
                )
                if file.isImage { savedImages += 1 } else { savedDocs += 1 }
            }
            if savedDocs == 0 {
                showToast(savedImages == 1 ? loc.t(.imageSaved) : loc.imagesSaved(savedImages))
            } else if savedImages == 0 {
                showToast(savedDocs == 1 ? loc.t(.fileSaved) : loc.filesSaved(savedDocs))
            } else {
                showToast(loc.itemsSaved(savedImages + savedDocs))
            }
            await history.refresh()
            return true
        } catch {
            print("[app] saveFiles", error)
            let saved = savedImages + savedDocs
            showToast(saved > 0 ? loc.partiallySaved(saved) : loc.t(.filesSaveFailed))
            await history.refresh()
            return false
        }
    }

    func remove(_ item: HistoryItem) async {
        do {
            _ = try await convex.mutation("clipboard:remove", ["id": item.id], as: Ignored?.self)
            await history.refresh()
        } catch {
            print("[app] remove", error)
            showToast(loc.t(.deleteFailed))
        }
    }

    /// Devuelve cuántas entradas se borraron, o nil si falló.
    func clearAll() async -> Int? {
        do {
            let result: ClearResult = try await convex.mutation("clipboard:clearAll", EmptyArgs())
            await history.refresh()
            return result.deleted
        } catch {
            print("[app] clearAll", error)
            return nil
        }
    }

    /// Re-cifra el item para cada amigo con su clave pública y se lo envía.
    /// Devuelve true si hay que cerrar el diálogo.
    func share(_ item: HistoryItem, with friends: [Friend]) async -> Bool {
        let recipients = friends.filter { $0.publicKey != nil }
        guard !recipients.isEmpty else { return false }

        var plain: Data?
        if item.type != .text {
            plain = try? await history.content(for: item.raw)
            guard plain != nil else {
                showToast(loc.t(.shareFailed))
                return false
            }
        }

        var sent = 0
        for friend in recipients {
            guard let publicKey = friend.publicKey else { continue }
            do {
                let (key, shareKey) = try ClipCrypto.createRecipientKey(publicKey: publicKey)
                let args: ShareArgs
                if item.type == .text {
                    args = ShareArgs(
                        friendId: friend.userId, type: "text",
                        text: try ClipCrypto.encryptText(item.text ?? "", with: key),
                        storageId: nil, shareKey: shareKey, charCount: item.charCount,
                        mimeType: nil, fileName: nil
                    )
                } else {
                    let storageId = try await convex.uploadToStorage(try ClipCrypto.encrypt(plain!, with: key))
                    args = ShareArgs(
                        friendId: friend.userId, type: item.type.rawValue, text: nil,
                        storageId: storageId, shareKey: shareKey, charCount: nil,
                        mimeType: item.raw.mimeType, fileName: item.raw.fileName
                    )
                }
                _ = try await convex.mutation("clipboard:shareToFriend", args, as: Ignored?.self)
                sent += 1
            } catch {
                print("[app] share", error)
            }
        }

        if sent == recipients.count {
            showToast(loc.sharedWith(sent))
            return true
        } else if sent > 0 {
            showToast(loc.sharePartial(sent, recipients.count))
            return true
        }
        showToast(loc.t(.shareFailed))
        return false
    }

    // MARK: - Portapapeles y archivos

    func copyText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Que el monitor no lo vuelva a subir.
        poller.ignoreHash(ClipCrypto.sha256Hex(Data(trimmed.utf8)))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        showToast(loc.t(.copiedToClipboard))
    }

    func copyImage(_ item: HistoryItem) async {
        do {
            let data = try await history.content(for: item.raw)
            guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                ?? NSImage(data: data)?.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) })?
                .representation(using: .png, properties: [:]) else {
                throw AppError("Imagen inválida")
            }
            poller.ignoreHash(ClipCrypto.sha256Hex(png))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
            showToast(loc.t(.imageCopied))
        } catch {
            print("[app] copyImage", error)
            showToast(loc.t(.imageCopyFailed))
        }
    }

    /// Copia al portapapeles la entrada más reciente del historial (menú de la barra).
    func copyLatest() async {
        await history.refresh()
        guard let item = history.items.first else {
            showToast(loc.t(.emptyTitle))
            return
        }
        switch item.type {
        case .text:
            if let text = item.text { copyText(text) }
        case .image:
            await copyImage(item)
        case .file:
            do {
                let url = try await writeTemp(item)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                showToast(loc.t(.copiedToClipboard))
            } catch {
                print("[app] copyFile", error)
                showToast(loc.t(.openFailed))
            }
        }
    }

    /// Abre la imagen/archivo descifrado con la app por defecto.
    func open(_ item: HistoryItem) async {
        do {
            NSWorkspace.shared.open(try await writeTemp(item))
        } catch {
            print("[app] open", error)
            showToast(loc.t(.openFailed))
        }
    }

    func download(_ item: HistoryItem) async {
        do {
            let data = try await history.content(for: item.raw)
            NSApp.activate()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = Self.fileName(for: item.raw)
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        } catch {
            print("[app] download", error)
            showToast(loc.t(.openFailed))
        }
    }

    /// Guarda el contenido descifrado en una carpeta temporal y devuelve su URL.
    private func writeTemp(_ item: HistoryItem) async throws -> URL {
        let data = try await history.content(for: item.raw)
        let folder = FileManager.default.temporaryDirectory.appending(path: item.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: Self.fileName(for: item.raw))
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileName(for item: ClipItem) -> String {
        if let fileName = item.fileName, !fileName.isEmpty { return fileName }
        let ext = item.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? "png"
        return "clipboard-\(item.createdAt.millis).\(ext)"
    }

    // MARK: - Monitor

    func setMonitoring(_ enabled: Bool) {
        poller.setEnabled(enabled)
        screenshots.setEnabled(enabled)
        ConfigStore.monitoring = enabled
        refreshStatus()
    }

    func toggleMonitoring() {
        setMonitoring(!poller.enabled)
    }

    /// Texto deshabilitado del menú con el estado de la sesión.
    var statusLabel: String {
        switch session.state {
        case .loading, .signedOut: return loc.t(.menuSignIn)
        case .locked: return loc.t(.menuUnlock)
        case .ready:
            guard let lastCaptureAt = status.lastCaptureAt else { return loc.t(.menuSessionActive) }
            return loc.menuLastCapture(lastCaptureAt.formatted(date: .omitted, time: .standard))
        }
    }

    func ensureScreenshotAccess(force: Bool = false) {
        let access = ScreenshotWatcher.probeAccess()
        if access.ok && !force { return }

        let pick = loc.pick
        NSApp.activate()
        let alert = NSAlert()
        if access.ok {
            alert.messageText = pick("Acceso a capturas activo", "Screenshot access enabled",
                                     "Acesso às capturas ativo", "Доступ к снимкам открыт")
            alert.informativeText = pick("Clipboard Cloud puede leer:", "Clipboard Cloud can read:",
                                         "O Clipboard Cloud pode ler:", "Clipboard Cloud может читать:")
                + "\n\n" + access.readable.joined(separator: "\n")
            alert.runModal()
            return
        }

        alert.alertStyle = .warning
        alert.messageText = pick("Clipboard Cloud no puede leer tus capturas", "Clipboard Cloud can't read your screenshots",
                                 "O Clipboard Cloud não consegue ler suas capturas", "Clipboard Cloud не может читать ваши снимки")
        alert.informativeText = pick("""
        Para subir las capturas de ⌘⇧3 / ⌘⇧4 necesita acceso a la carpeta donde se guardan.

        1. Abre Ajustes → Privacidad y seguridad → Archivos y carpetas
        2. En Clipboard Cloud, activa Escritorio
           (si no aparece, usa Acceso total al disco y añade la app con +)
        3. Reinicia Clipboard Cloud

        Las capturas que van directo al portapapeles (⌃⌘⇧4) funcionan sin este permiso.
        """, """
        To upload ⌘⇧3 / ⌘⇧4 screenshots it needs access to the folder where they are saved.

        1. Open Settings → Privacy & Security → Files and Folders
        2. Under Clipboard Cloud, enable Desktop
           (if it's not listed, use Full Disk Access and add the app with +)
        3. Restart Clipboard Cloud

        Screenshots sent straight to the clipboard (⌃⌘⇧4) work without this permission.
        """, """
        Para enviar as capturas de ⌘⇧3 / ⌘⇧4, ele precisa de acesso à pasta onde elas são salvas.

        1. Abra Ajustes → Privacidade e Segurança → Arquivos e Pastas
        2. Em Clipboard Cloud, ative Mesa
           (se não aparecer, use Acesso Total ao Disco e adicione o app com +)
        3. Reinicie o Clipboard Cloud

        As capturas que vão direto para a área de transferência (⌃⌘⇧4) funcionam sem essa permissão.
        """, """
        Чтобы загружать снимки ⌘⇧3 / ⌘⇧4, нужен доступ к папке, где они сохраняются.

        1. Откройте Настройки → Конфиденциальность и безопасность → Файлы и папки
        2. Для Clipboard Cloud включите «Рабочий стол»
           (если его нет, используйте «Полный доступ к диску» и добавьте приложение через +)
        3. Перезапустите Clipboard Cloud

        Снимки, которые сразу идут в буфер обмена (⌃⌘⇧4), работают без этого разрешения.
        """)
        alert.addButton(withTitle: pick("Abrir Ajustes", "Open Settings", "Abrir Ajustes", "Открыть Настройки"))
        alert.addButton(withTitle: pick("Después", "Later", "Depois", "Позже"))
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshStatus() {
        let previousCapture = status.lastCaptureAt
        status = MonitorStatus(
            monitoring: poller.enabled && poller.isRunning,
            lastCaptureAt: poller.lastCaptureAt,
            lastError: poller.lastError,
            lastScreenshotAt: screenshots.lastCaptureAt,
            lastScreenshotError: screenshots.lastError,
            screenshotAccessOK: screenshots.accessOK
        )
        // Algo nuevo capturado: actualizar el historial si se está viendo.
        if windowLoop != nil, status.lastCaptureAt != previousCapture {
            Task { await history.refresh() }
        }
    }
}

/// Estado combinado del poller y del vigilante de capturas.
struct MonitorStatus: Equatable {
    var monitoring = false
    var lastCaptureAt: Date?
    var lastError: String?
    var lastScreenshotAt: Date?
    var lastScreenshotError: String?
    var screenshotAccessOK = true
}

/// Archivo elegido en "Agregar", ya leído y listo para subir.
struct PendingFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let mimeType: String
    let isImage: Bool
}

private struct SaveTextArgs: Encodable {
    let text: String
    let source: String
    let deviceId: String
    let encrypted: Bool
    let charCount: Int
}

private struct SaveFileArgs: Encodable {
    let storageId: String
    let source: String
    let deviceId: String
    let encrypted: Bool
    let mimeType: String
    let fileName: String
}

private struct ShareArgs: Encodable {
    let friendId: String
    let type: String
    let text: String?
    let storageId: String?
    let shareKey: String
    let charCount: Int?
    let mimeType: String?
    let fileName: String?
}

private struct ClearResult: Decodable {
    let deleted: Int

    enum CodingKeys: String, CodingKey { case deleted }

    init(from decoder: any Decoder) throws {
        deleted = Int(try decoder.container(keyedBy: CodingKeys.self).decode(Double.self, forKey: .deleted))
    }
}
