import Foundation

/// Port de screenshotWatcher.js: vigila las carpetas donde macOS guarda las capturas (⌘⇧3/4).
/// Las que van al portapapeles (⌃⌘⇧3/4) las atrapa ClipboardPoller.
@MainActor
final class ScreenshotWatcher {
    typealias Uploader = @MainActor (
        _ data: Data, _ mimeType: String, _ contentHash: String, _ copiedAt: Date, _ fileName: String
    ) async throws -> CaptureResult

    private static let pollInterval: Duration = .seconds(2)
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic"]
    /// Ventana para considerar un archivo "nuevo" si aún no estaba en `seen`.
    private static let newFileMaxAge: TimeInterval = 120
    private static let screenshotNamePattern =
        #"captura\s+de\s+pantalla|screenshot|screen\s*shot|screen\s*clipping|captura"#

    var onStatus: () -> Void = {}
    var canUpload: () -> Bool = { false }
    var upload: Uploader?

    private(set) var enabled = true
    private(set) var dirs: [URL] = []
    private(set) var lastCaptureAt: Date?
    private(set) var lastError: String?
    private(set) var accessOK = true
    /// path -> mtime de archivos ya subidos (o ignorados por viejos).
    private var seen: [String: Date] = [:]
    /// Paths pendientes de reintento (sesión/cifrado no listos o error transitorio).
    private(set) var pending: Set<String> = []
    private var busy = false
    private var loop: Task<Void, Never>?
    private var sources: [String: DispatchSourceFileSystemObject] = [:]

    var isRunning: Bool { loop != nil }

    func start() {
        dirs = Self.screenshotDirs()
        let access = Self.probeAccess()
        accessOK = access.ok
        if !access.ok {
            lastError = "Sin permiso para leer Escritorio/Imágenes. Actívalo en Ajustes del Sistema → Privacidad → Archivos y carpetas (o Disco completo) para Clipboard Cloud."
            print("[screenshot-watcher] folder access blocked", access.blocked)
        }
        primeSeen()
        refreshSources()
        if loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.tick()
                    try? await Task.sleep(for: Self.pollInterval)
                }
            }
        }
        onStatus()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        for source in sources.values { source.cancel() }
        sources.removeAll()
        onStatus()
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        onStatus()
    }

    func tick() async {
        guard enabled, !busy else { return }

        dirs = Self.screenshotDirs()
        refreshSources()

        // Mantener pendientes hasta que haya sesión + cifrado.
        guard canUpload(), let upload else {
            for candidate in collectCandidates() { pending.insert(candidate.path) }
            return
        }

        let candidates = collectCandidates()
        guard !candidates.isEmpty else { return }

        busy = true
        defer {
            busy = false
            onStatus()
        }

        for candidate in candidates {
            let path = candidate.path
            guard await Self.waitForStableFile(path) else {
                pending.insert(path)
                continue
            }

            let data: Data
            do {
                data = try Data(contentsOf: URL(fileURLWithPath: path))
            } catch {
                lastError = error.localizedDescription
                pending.insert(path)
                continue
            }
            guard !data.isEmpty else {
                pending.insert(path)
                continue
            }

            let result: CaptureResult
            do {
                result = try await upload(
                    data,
                    Self.contentType(for: path),
                    ClipCrypto.sha256Hex(data),
                    candidate.mtime,
                    (path as NSString).lastPathComponent
                )
            } catch {
                lastError = error.localizedDescription
                print("[screenshot-watcher] upload error", path, error)
                pending.insert(path)
                continue
            }

            if result.saved || result.reason == "duplicate" {
                seen[path] = candidate.mtime
                pending.remove(path)
                if result.saved {
                    lastCaptureAt = Date()
                    lastError = nil
                }
                continue
            }

            // unauthenticated / encryption_locked / otros → reintentar
            pending.insert(path)
            if let reason = result.reason, reason != "encryption_locked", reason != "unauthenticated" {
                lastError = reason
            }
        }
    }

    // MARK: - Carpetas

    /// Reacciona al instante cuando cambia una carpeta (equivale a fs.watch).
    private func refreshSources() {
        let wanted = Set(dirs.map(\.path))
        for (path, source) in sources where !wanted.contains(path) {
            source.cancel()
            sources[path] = nil
        }
        for dir in dirs where sources[dir.path] == nil {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: .write, queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in await self?.tick() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources[dir.path] = source
        }
    }

    private func primeSeen() {
        for dir in dirs {
            for path in Self.files(in: dir) {
                if let mtime = Self.screenshotMTime(path) { seen[path] = mtime }
            }
        }
    }

    private struct Candidate {
        let path: String
        let mtime: Date
    }

    private func collectCandidates() -> [Candidate] {
        var found: [String: Date] = [:]
        let now = Date()

        for path in pending {
            guard let mtime = Self.screenshotMTime(path) else {
                pending.remove(path)
                continue
            }
            if let previous = seen[path], previous >= mtime {
                pending.remove(path)
                continue
            }
            found[path] = mtime
        }

        for dir in dirs {
            for path in Self.files(in: dir) {
                guard let mtime = Self.screenshotMTime(path) else { continue }
                if let previous = seen[path] {
                    if previous >= mtime { continue }
                } else if now.timeIntervalSince(mtime) > Self.newFileMaxAge {
                    seen[path] = mtime
                    continue
                }
                found[path] = max(found[path] ?? mtime, mtime)
            }
        }

        return found.map(Candidate.init).sorted { $0.mtime < $1.mtime }
    }

    // MARK: - Helpers

    private static var cachedScreenshotLocation: URL?

    /// `defaults read com.apple.screencapture location`, o el Escritorio.
    private static func macScreenshotLocation() -> URL {
        if let cachedScreenshotLocation { return cachedScreenshotLocation }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let location = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location")
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? home.appending(path: "Desktop")
        cachedScreenshotLocation = location
        return location
    }

    private static func candidateDirs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var unique: [URL] = []
        for dir in [macScreenshotLocation(), home.appending(path: "Desktop"), home.appending(path: "Pictures/Screenshots")]
        where !unique.contains(where: { $0.standardizedFileURL.path == dir.standardizedFileURL.path }) {
            unique.append(dir)
        }
        return unique
    }

    static func screenshotDirs() -> [URL] {
        candidateDirs().filter { dir in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Prueba lectura real (TCC): la carpeta puede existir y aun así fallar el listado.
    static func probeAccess() -> (ok: Bool, readable: [String], blocked: [String]) {
        var readable: [String] = []
        var blocked: [String] = []
        for dir in screenshotDirs() {
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                readable.append(dir.path)
            } catch {
                blocked.append(dir.path)
            }
        }
        return (!readable.isEmpty, readable, blocked)
    }

    private static func files(in dir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        // Los ocultos son temporales de screencapture antes de renombrarse.
        return names.filter { !$0.hasPrefix(".") }.map { dir.appending(path: $0).path }
    }

    /// mtime si `path` es un archivo que parece una captura de pantalla.
    private static func screenshotMTime(_ path: String) -> Date? {
        guard looksLikeScreenshot(path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        return attributes[.modificationDate] as? Date
    }

    private static func looksLikeScreenshot(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        if url.deletingLastPathComponent().lastPathComponent.lowercased() == "screenshots" { return true }
        return url.lastPathComponent.range(
            of: screenshotNamePattern, options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func contentType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "heic": "image/heic"
        default: "image/png"
        }
    }

    private static func waitForStableFile(_ path: String, attempts: Int = 10) async -> Bool {
        var lastSize: Int64 = -1
        for attempt in 0..<attempts {
            if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber {
                if size.int64Value > 0, size.int64Value == lastSize { return true }
                lastSize = size.int64Value
            }
            if attempt < attempts - 1 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return lastSize > 0
    }
}
