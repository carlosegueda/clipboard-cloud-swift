import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// components/AddPanel.tsx
struct AddView: View {
    @Environment(AppModel.self) private var model
    let onSaved: () -> Void

    private static let maxFiles = 10
    private static let documentTypes: [String: String] = [
        "pdf": "application/pdf",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ]
    private static let allowedTypes: [UTType] = [.image] + documentTypes.keys.compactMap { UTType(filenameExtension: $0) }

    @State private var draft = ""
    @State private var pending: [PendingFile] = []
    @State private var note = ""
    @State private var busy = false
    @State private var picking = false

    var body: some View {
        let loc = model.loc
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HardCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel(text: loc.t(.text), icon: "textformat")
                        HardTextArea(placeholder: loc.t(.draftPlaceholder), text: $draft)
                            .frame(minHeight: 150)
                        HStack(spacing: 14) {
                            Button { saveText() } label: { Label(loc.t(.saveText), systemImage: "doc.on.clipboard") }
                                .buttonStyle(HardButtonStyle(kind: .primary))
                                .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button { picking = true } label: { Label(loc.t(.chooseFiles), systemImage: "square.and.arrow.up") }
                                .buttonStyle(HardButtonStyle())
                                .disabled(busy || pending.count >= Self.maxFiles)
                            Button { pasteFiles() } label: { Label(loc.t(.pasteFromClipboard), systemImage: "doc.on.clipboard") }
                                .buttonStyle(HardButtonStyle())
                                .disabled(busy || pending.count >= Self.maxFiles)
                        }
                        .padding(.top, 4)
                        MutedText(text: loc.t(.filesHint), size: 13.4)
                    }
                }

                if !note.isEmpty && pending.isEmpty {
                    MutedText(text: note, size: 13.4)
                }

                if !pending.isEmpty {
                    pendingCard
                }
            }
            .padding(.trailing, 5)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.allowedTypes, allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { addFiles(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            addFiles(urls)
            return true
        }
    }

    private var pendingCard: some View {
        let loc = model.loc
        return HardCard(inner: Theme.panel, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            IconTile(systemImage: "photo", size: 26)
                            CardTitle(text: loc.t(.confirmFiles))
                        }
                        MutedText(text: loc.selectedCount(pending.count, Self.maxFiles), size: 13.4)
                    }
                    Spacer()
                    Button { picking = true } label: { Label(loc.t(.addMore), systemImage: "plus") }
                        .buttonStyle(HardButtonStyle(compact: true))
                        .disabled(busy || pending.count >= Self.maxFiles)
                }
                if !note.isEmpty {
                    MutedText(text: note, size: 13.4)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(pending) { file in
                        PendingTile(file: file, disabled: busy) {
                            pending.removeAll { $0.id == file.id }
                        }
                    }
                }

                HStack(spacing: 14) {
                    Button { saveFiles() } label: { Label(loc.confirmUpload(pending.count), systemImage: "checkmark") }
                        .buttonStyle(HardButtonStyle(kind: .primary))
                        .disabled(busy)
                    Button {
                        pending = []
                        note = ""
                    } label: {
                        Label(loc.t(.cancel), systemImage: "xmark")
                    }
                    .buttonStyle(HardButtonStyle())
                    .disabled(busy)
                    if busy { ProgressView().controlSize(.small) }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Acciones

    private func saveText() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        busy = true
        Task {
            if await model.saveText(trimmed) {
                draft = ""
                onSaved()
            }
            busy = false
        }
    }

    private func saveFiles() {
        busy = true
        Task {
            if await model.saveFiles(pending) {
                pending = []
                note = ""
                onSaved()
            }
            busy = false
        }
    }

    /// Archivos copiados en Finder, o una imagen copiada (p. ej. ⌃⌘⇧4).
    private func pasteFiles() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            addFiles(urls)
            return
        }
        let png = pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff).flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        guard let png else {
            note = model.loc.t(.filesOnly)
            return
        }
        add([PendingFile(name: "pegada-\(Date().millis)-1.png", data: png, mimeType: "image/png", isImage: true)], skippedInvalid: 0)
    }

    private func addFiles(_ urls: [URL]) {
        var files: [PendingFile] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            let type = UTType(filenameExtension: ext)
            let isImage = type?.conforms(to: .image) ?? false
            guard isImage || Self.documentTypes[ext] != nil,
                  let data = try? Data(contentsOf: url) else { continue }
            let mimeType = Self.documentTypes[ext] ?? type?.preferredMIMEType ?? "application/octet-stream"
            files.append(PendingFile(name: url.lastPathComponent, data: data, mimeType: mimeType, isImage: isImage))
        }
        add(files, skippedInvalid: urls.count - files.count)
    }

    private func add(_ files: [PendingFile], skippedInvalid: Int) {
        guard !files.isEmpty else {
            note = model.loc.t(.filesOnly)
            return
        }
        let room = Self.maxFiles - pending.count
        guard room > 0 else {
            note = model.loc.maxFiles(Self.maxFiles)
            return
        }
        let accepted = Array(files.prefix(room))
        let skipped = files.count - accepted.count
        note = skipped > 0 ? model.loc.addedSome(accepted.count, skipped, Self.maxFiles) : ""
        pending += accepted
    }
}

/// Miniatura de un archivo pendiente de subir.
private struct PendingTile: View {
    let file: PendingFile
    let disabled: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if file.isImage, let image = NSImage(data: file.data) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.chip)
                }
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(Theme.font(11.8))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .background(Theme.panel)
        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) { Image(systemName: "xmark") }
                .buttonStyle(HardIconButtonStyle(color: Theme.danger))
                .disabled(disabled)
                .padding(6)
        }
    }
}
