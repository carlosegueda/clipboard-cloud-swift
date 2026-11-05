import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// components/TransferPanel.tsx, más un campo para abrir enlaces recibidos
/// (en la web esto lo resuelve abrir el enlace en el navegador).
struct TransferView: View {
    @Environment(AppModel.self) private var model
    /// El login ya presenta la app sin cuenta; con sesión el texto es otro.
    var signedIn = false

    @State private var password = ""
    @State private var picking = false
    @State private var dropTargeted = false
    @State private var receivedLink = ""
    @State private var receiving: ReceivedLink?
    @State private var badLink = false

    private static let minPasswordLength = 4

    var body: some View {
        let loc = model.loc
        let store = model.transfers
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HardCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                IconTile(systemImage: "paperplane.fill")
                                Text("Cloud Transfer")
                                    .font(Theme.font(18.4, .bold))
                                    .textCase(.uppercase)
                                    .squish()
                            }
                            MutedText(text: loc.t(signedIn ? .transferLedeAccount : .transferLede), size: 14)
                        }
                        if let result = store.result {
                            resultSection(result)
                        } else {
                            composer
                        }
                    }
                }
                receiveCard
                if !store.active.isEmpty {
                    activeCard
                }
            }
            .padding(.trailing, 5)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { store.add(urls) }
        }
        .task(id: model.session.state == .ready) { await store.refresh() }
        // Solo al terminar bien: si la subida falla, reintentar sin ella crearía
        // un enlace desprotegido sin que el usuario lo note.
        .onChange(of: store.result?.slug) { _, slug in
            if slug != nil { password = "" }
        }
        .sheet(item: $receiving) { link in
            TransferReceiveView(link: link)
        }
    }

    // MARK: - Enviar

    private var passwordTooShort: Bool {
        !password.isEmpty && password.count < Self.minPasswordLength
    }

    private var composer: some View {
        let loc = model.loc
        let store = model.transfers
        return VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 10) {
                Text(loc.t(.transferDrop))
                    .font(Theme.font(14.5, .semibold))
                    .textCase(.uppercase)
                    .squish()
                Button { picking = true } label: {
                    Label(loc.t(.transferChoose), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(HardButtonStyle())
                .disabled(store.isUploading || store.limits == nil)
                if let limits = store.limits {
                    MutedText(text: loc.transferLimits(limits.maxFiles, Self.size(limits.maxBytes)), size: 12.5)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(dropTargeted ? Theme.chip : Theme.panel)
            .overlay(Rectangle().strokeBorder(.black, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .dropDestination(for: URL.self) { urls, _ in
                guard !store.isUploading else { return false }
                store.add(urls)
                return true
            } isTargeted: { dropTargeted = $0 }

            if !store.pending.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.pending) { file in
                        HStack(spacing: 8) {
                            Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(Theme.accent)
                            Text(file.name)
                                .font(Theme.font(13.6))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(Self.size(file.size)).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                            Button { store.removePending(file.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Theme.danger)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isUploading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.field)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: loc.t(.transferPasswordLabel), icon: "key")
                HardField(placeholder: "", text: $password, secure: true, contentType: .newPassword)
                    .disabled(store.isUploading)
                MutedText(text: loc.t(passwordTooShort ? .transferPasswordShort : .transferPasswordHint), size: 12)
            }

            if let note = store.note {
                Text(message(for: note))
                    .font(Theme.font(13.6))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                Button {
                    store.startUpload(password: password)
                } label: {
                    if let progress = store.progress {
                        Label(loc.transferUploading(Int((progress * 100).rounded())), systemImage: "arrow.up.circle")
                    } else {
                        Label(loc.t(.transferCreate), systemImage: "paperplane")
                    }
                }
                .buttonStyle(HardButtonStyle(kind: .primary))
                .disabled(store.isUploading || store.pending.isEmpty || passwordTooShort)

                if store.isUploading {
                    Button { store.cancelUpload() } label: { Label(loc.t(.cancel), systemImage: "xmark") }
                        .buttonStyle(HardButtonStyle())
                } else if !store.pending.isEmpty {
                    Text(Self.size(store.totalBytes)).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func resultSection(_ result: TransferRecord) -> some View {
        let loc = model.loc
        return VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: loc.t(.transferReady), icon: "link")
            Text(result.link ?? "")
                .font(Theme.mono(12))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.field)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
            if let link = result.link {
                TransferLinkActions(link: link)
            }
            MutedText(text: summary(result, includeSize: false), size: 12.8)
            Button { model.transfers.startOver() } label: {
                Label(loc.t(.transferNew), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(HardButtonStyle())
        }
    }

    // MARK: - Recibir

    private var receiveCard: some View {
        let loc = model.loc
        return HardCard(inner: Theme.panel, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: loc.t(.transferOpenLink), icon: "arrow.down.circle")
                HStack(spacing: 10) {
                    HardField(placeholder: loc.t(.transferLinkPlaceholder), text: $receivedLink, onSubmit: openLink)
                    Button(action: openLink) { Text(loc.t(.transferUnlock)).squish() }
                        .buttonStyle(HardButtonStyle())
                        .disabled(receivedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if badLink {
                    Text(loc.t(.transferBadLink))
                        .font(Theme.font(13))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
    }

    private func openLink() {
        guard let parsed = TransferCrypto.parseLink(receivedLink) else {
            badLink = true
            return
        }
        badLink = false
        receivedLink = ""
        receiving = ReceivedLink(slug: parsed.slug, secret: parsed.secret)
    }

    // MARK: - Enlaces activos

    private var activeCard: some View {
        let loc = model.loc
        let store = model.transfers
        return HardCard(inner: Theme.panel, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(text: loc.t(.transferActive))
                ForEach(store.active) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        MutedText(text: summary(record, includeSize: true), size: 12.5)
                        HStack(spacing: 10) {
                            if let link = record.link {
                                TransferLinkActions(link: link)
                            }
                            Button {
                                Task { await store.remove(record) }
                            } label: {
                                Label(loc.t(.transferDelete), systemImage: "trash")
                            }
                            .buttonStyle(HardButtonStyle(kind: .danger, compact: true))
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                }
            }
        }
    }

    private func summary(_ record: TransferRecord, includeSize: Bool) -> String {
        let loc = model.loc
        var parts: [String] = []
        if includeSize {
            parts.append(loc.transferFileCount(record.fileCount))
            parts.append(Self.size(record.totalBytes))
        }
        parts.append(loc.transferExpires(at: record.expiresAt))
        if record.hasPassword { parts.append(loc.t(.transferHasPassword)) }
        return parts.joined(separator: " · ")
    }

    private func message(for note: TransferStore.Note) -> String {
        let loc = model.loc
        return switch note {
        case .folderSkipped: loc.t(.transferFolderSkipped)
        case let .tooMany(limit): loc.transferTooMany(limit)
        case let .tooLarge(limit): loc.transferTooLarge(Self.size(limit))
        case .failed: loc.t(.transferFailed)
        case .quota: loc.t(.transferQuota)
        case .deleteFailed: loc.t(.transferDeleteFailed)
        }
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

/// components/TransferLinkActions.tsx
struct TransferLinkActions: View {
    @Environment(AppModel.self) private var model
    let link: String

    var body: some View {
        let loc = model.loc
        HStack(spacing: 10) {
            Button { model.copyText(link) } label: {
                Label(loc.t(.transferCopyLink), systemImage: "doc.on.doc")
            }
            .buttonStyle(HardButtonStyle(compact: true))
            if let url = URL(string: link) {
                ShareLink(item: url) {
                    Label(loc.t(.share), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(HardButtonStyle(compact: true))
            }
        }
    }
}

struct ReceivedLink: Identifiable {
    let slug: String
    let secret: String
    var id: String { slug }
}

/// app/t/[slug]/page.tsx
struct TransferReceiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let link: ReceivedLink

    private enum Phase {
        case loading
        case missing
        case password(TransferInfo)
        case opened(OpenedTransfer)
    }

    @State private var phase: Phase = .loading
    @State private var password = ""
    @State private var opening = false
    @State private var error: String?
    /// Porcentaje por archivo mientras se descarga.
    @State private var progress: [Int: Int] = [:]

    var body: some View {
        let loc = model.loc
        HardModal(title: "Cloud Transfer", subtitle: loc.t(.transferReceiveTitle), onClose: { dismiss() }) {
            switch phase {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    MutedText(text: loc.t(.wait), size: 14)
                }
                if let error { errorText(error) }
            case .missing:
                Text(loc.t(.transferMissingTitle))
                    .font(Theme.font(15, .bold)).textCase(.uppercase).squish()
                MutedText(text: loc.t(.transferMissingBody), size: 13.4)
            case let .password(info):
                FieldLabel(text: loc.t(.transferProtected), icon: "lock.fill")
                HardField(placeholder: "", text: $password, secure: true, contentType: .password) {
                    unlock(info)
                }
                if let error { errorText(error) }
                Button { unlock(info) } label: {
                    Label(opening ? loc.t(.wait) : loc.t(.transferUnlock), systemImage: "lock.open")
                }
                .buttonStyle(HardButtonStyle(kind: .primary, fullWidth: true))
                .keyboardShortcut(.defaultAction)
                .disabled(opening || password.isEmpty)
            case let .opened(opened):
                openedContent(opened)
            }
        }
        .frame(width: 540)
        .task { await load() }
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(13.6))
            .textCase(.uppercase)
            .foregroundStyle(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func openedContent(_ opened: OpenedTransfer) -> some View {
        let loc = model.loc
        let files = opened.manifest.files
        let busy = !progress.isEmpty
        MutedText(
            text: [
                loc.transferFileCount(files.count),
                TransferView.size(files.reduce(0) { $0 + $1.size }),
                loc.transferExpires(at: opened.expiresAt),
            ].joined(separator: " · "),
            size: 12.8
        )
        ScrollView {
            VStack(spacing: 6) {
                ForEach(files.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(Theme.accent)
                        Text(files[index].name)
                            .font(Theme.font(13.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(TransferView.size(files[index].size)).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                        Button { saveOne(opened, index) } label: {
                            if let percent = progress[index] {
                                Label(loc.transferDownloading(percent), systemImage: "arrow.down.circle")
                            } else {
                                Label(loc.t(.transferDownload), systemImage: "arrow.down.to.line")
                            }
                        }
                        .buttonStyle(HardButtonStyle(compact: true))
                        .disabled(busy)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.field)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                }
            }
            .padding(.trailing, 5)
            .padding(.bottom, 5)
        }
        .frame(maxHeight: 280)
        if let error { errorText(error) }
        if files.count > 1 {
            Button { saveAll(opened) } label: {
                Label(loc.t(.transferDownloadAll), systemImage: "arrow.down.to.line")
            }
            .buttonStyle(HardButtonStyle(kind: .primary))
            .disabled(busy)
        }
    }

    // MARK: - Acciones

    private func load() async {
        do {
            guard let info = try await model.transfers.client.info(slug: link.slug) else {
                phase = .missing
                return
            }
            if info.hasPassword {
                phase = .password(info)
            } else {
                await open(info, password: nil)
            }
        } catch {
            print("[transfer] info", error)
            self.error = model.loc.t(.transferOpenFailed)
        }
    }

    private func unlock(_ info: TransferInfo) {
        guard !opening, !password.isEmpty else { return }
        Task { await open(info, password: password) }
    }

    private func open(_ info: TransferInfo, password: String?) async {
        let loc = model.loc
        opening = true
        error = nil
        defer { opening = false }
        do {
            switch try await model.transfers.client.open(
                slug: link.slug, secret: link.secret, password: password, info: info
            ) {
            case let .opened(opened):
                phase = .opened(opened)
            case .missing:
                phase = .missing
            case .denied:
                error = loc.t(info.hasPassword ? .transferWrongPassword : .transferOpenFailed)
            case let .locked(until):
                error = loc.transferLocked(max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up))))
            }
        } catch {
            print("[transfer] open", error)
            self.error = loc.t(.transferOpenFailed)
        }
    }

    private func saveOne(_ opened: OpenedTransfer, _ index: Int) {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = TransferCrypto.safeFileName(opened.manifest.files[index].name)
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { _ = await download(opened, index, to: url) }
    }

    private func saveAll(_ opened: OpenedTransfer) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            for index in opened.manifest.files.indices {
                let url = Self.uniqueURL(
                    in: folder, name: TransferCrypto.safeFileName(opened.manifest.files[index].name)
                )
                guard await download(opened, index, to: url) else { return }
            }
        }
    }

    private func download(_ opened: OpenedTransfer, _ index: Int, to url: URL) async -> Bool {
        let size = opened.manifest.files[index].size
        error = nil
        progress[index] = 0
        defer { progress[index] = nil }
        do {
            try await model.transfers.client.download(opened, fileIndex: index, to: url) { received in
                progress[index] = size > 0 ? Int((Double(received) / Double(size) * 100).rounded()) : 100
            }
            return true
        } catch {
            print("[transfer] download", error)
            self.error = model.loc.t(.transferDownloadFailed)
            return false
        }
    }

    /// Al guardar varios de golpe no hay panel que confirme sobrescribir.
    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var candidate = folder.appending(path: name)
        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var copy = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            copy += 1
            candidate = folder.appending(path: ext.isEmpty ? "\(stem) \(copy)" : "\(stem) \(copy).\(ext)")
        }
        return candidate
    }
}
