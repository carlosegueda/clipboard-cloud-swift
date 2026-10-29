import SwiftUI

/// components/HistoryTimeline.tsx
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    let onShare: (HistoryItem) -> Void
    let onGoAdd: () -> Void

    private enum Filter: Hashable { case all, text, image, file }

    @State private var filter: Filter = .all
    @State private var query = ""

    private var filteredItems: [HistoryItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.history.items.filter { item in
            switch filter {
            case .all: break
            case .text: if item.type != .text { return false }
            case .image: if item.type != .image { return false }
            case .file: if item.type != .file { return false }
            }
            guard !q.isEmpty else { return true }
            if item.raw.sharedByEmail?.lowercased().contains(q) == true { return true }
            if item.type == .text { return item.text?.lowercased().contains(q) ?? false }
            if item.raw.fileName?.lowercased().contains(q) == true { return true }
            return sourceLabel(item.raw.source).lowercased().contains(q)
        }
    }

    var body: some View {
        let loc = model.loc
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom) {
                    HardTabs(tabs: [
                        .init(id: Filter.all, label: loc.t(.filterAll)),
                        .init(id: Filter.text, label: loc.t(.filterText)),
                        .init(id: Filter.image, label: loc.t(.filterImages)),
                        .init(id: Filter.file, label: loc.t(.filterFiles)),
                    ], selection: $filter)
                    Spacer()
                    SearchField(text: $query, placeholder: loc.t(.searchPlaceholder))
                        .frame(maxWidth: 280)
                        .padding(.bottom, 8)
                }

                if !model.history.loaded {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        MutedText(text: loc.t(.loadingHistory), size: 14.5)
                    }
                    .padding(.top, 16)
                } else if filteredItems.isEmpty {
                    EmptyBox(icon: "doc.on.clipboard", title: loc.t(.emptyTitle), message: loc.t(.emptyBody)) {
                        Button(action: onGoAdd) { Label(loc.t(.addNow), systemImage: "plus") }
                            .buttonStyle(HardButtonStyle(kind: .primary))
                    }
                } else {
                    HardCard(padding: 0) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                HistoryRow(item: item, onShare: { onShare(item) })
                                if index < filteredItems.count - 1 {
                                    Rectangle().fill(.black).frame(height: 1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 5)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }
}

private struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.muted)
            TextField("", text: $text, prompt: Text(placeholder.uppercased()).foregroundStyle(Theme.muted.opacity(0.7)))
                .textFieldStyle(.plain)
                .font(Theme.font(14))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white)
        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
    }
}

private func sourceLabel(_ source: ItemSource?) -> String {
    switch source {
    case .auto: "Clipboard"
    case .manual: "Manual"
    case .screenshot: "Screenshot"
    case nil: "—"
    }
}

private func sourceIcon(_ source: ItemSource?) -> String {
    switch source {
    case .auto: "doc.on.clipboard"
    case .manual: "plus"
    case .screenshot: "camera"
    case nil: "doc"
    }
}

/// Etiqueta corta de archivo (lib/files.ts fileLabel).
func fileLabel(mimeType: String?, fileName: String?) -> String {
    let ext = fileName.map { URL(fileURLWithPath: $0).pathExtension.uppercased() } ?? ""
    if mimeType == "application/pdf" || ext == "PDF" { return "PDF" }
    if mimeType?.contains("wordprocessingml") == true || ext == "DOCX" { return "DOCX" }
    if mimeType?.contains("spreadsheetml") == true || ext == "XLSX" { return "XLSX" }
    return ext.isEmpty ? "FILE" : ext
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let item: HistoryItem
    let onShare: () -> Void

    @State private var copied = false
    @State private var expanded = false

    private let collapsedLimit = 600

    var body: some View {
        let loc = model.loc
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 10) {
                if item.raw.shareKey != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill").font(.system(size: 11))
                        Text(loc.receivedFrom(item.raw.sharedByEmail ?? loc.t(.unknownUser))).lineLimit(1)
                    }
                    .font(Theme.font(12, .semibold))
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.chip)
                    .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                }

                if item.decryptPending {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        MutedText(text: loc.t(.decryptPending), size: 13.4)
                    }
                } else if item.decryptError {
                    Text(loc.t(.decryptFailed))
                        .font(Theme.font(13.4))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel)
                        .overlay(Rectangle().strokeBorder(Theme.danger, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                } else {
                    switch item.type {
                    case .text: textBody
                    case .image: ItemImage(item: item.raw)
                    case .file: fileBody
                    }
                }

                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
    }

    private var header: some View {
        let loc = model.loc
        return HStack(spacing: 0) {
            switch item.type {
            case .text:
                HeaderSegment(icon: "textformat", text: loc.t(.textType), bold: true)
                HeaderSegment(icon: "doc.plaintext", text: "\(item.charCount) \(loc.t(.chars))")
            case .image:
                HeaderSegment(icon: "photo", text: loc.t(.imageType), bold: true)
                HeaderSegment(icon: sourceIcon(item.raw.source), text: sourceLabel(item.raw.source))
            case .file:
                HeaderSegment(icon: "doc", text: loc.t(.fileType), bold: true)
                HeaderSegment(icon: "doc.text", text: fileLabel(mimeType: item.raw.mimeType, fileName: item.raw.fileName))
            }
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 11))
                Text(loc.relative(item.raw.createdAt)).textCase(.uppercase)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(loc.detailed(item.raw.createdAt))
        }
        .font(Theme.font(12.5))
        .foregroundStyle(.white)
        .background(Theme.accent)
    }

    @ViewBuilder private var textBody: some View {
        let text = item.text ?? ""
        let long = text.count > collapsedLimit
        VStack(alignment: .leading, spacing: 6) {
            Text(long && !expanded ? String(text.prefix(collapsedLimit)) + "…" : text)
                .font(Theme.mono(13.4))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.panel)
                .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
            if long {
                Button(model.loc.t(expanded ? .seeLess : .seeMore)) { expanded.toggle() }
                    .buttonStyle(HardLinkStyle())
            }
        }
    }

    private var fileBody: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.raw.fileName ?? fileLabel(mimeType: item.raw.mimeType, fileName: nil))
                    .font(Theme.font(14.5, .semibold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.middle)
                MutedText(text: fileLabel(mimeType: item.raw.mimeType, fileName: item.raw.fileName), size: 12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Theme.panel)
        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
    }

    private var footer: some View {
        let loc = model.loc
        let usable = !item.decryptError && !item.decryptPending
        return HStack(spacing: 14) {
            if item.type == .text, usable, let text = item.text {
                Button {
                    model.copyText(text)
                    flashCopied()
                } label: {
                    Label(copied ? loc.t(.copied) : loc.t(.copy), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(HardButtonStyle(compact: true))
            }
            if item.type == .image, usable {
                Button {
                    Task {
                        await model.copyImage(item)
                        flashCopied()
                    }
                } label: {
                    Label(copied ? loc.t(.copied) : loc.t(.copy), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(HardButtonStyle(compact: true))
                Button { Task { await model.open(item) } } label: {
                    Label(loc.t(.open), systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(HardButtonStyle(compact: true))
            }
            if item.type == .file, usable {
                Button { Task { await model.download(item) } } label: {
                    Label(loc.t(.download), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(HardButtonStyle(compact: true))
            }
            if usable, item.type != .text || item.text != nil {
                Button(action: onShare) { Label(loc.t(.share), systemImage: "square.and.arrow.up") }
                    .buttonStyle(HardButtonStyle(compact: true))
            }
            Button { Task { await model.remove(item) } } label: {
                Label(loc.t(.delete), systemImage: "trash")
            }
            .buttonStyle(HardButtonStyle(kind: .danger, compact: true))

            Spacer(minLength: 0)
            Text(loc.detailed(item.raw.createdAt))
                .font(Theme.font(12))
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }

    private func flashCopied() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// Segmento de la barra de cabecera de una entrada, con la diagonal de la web.
private struct HeaderSegment: View {
    let icon: String
    let text: String
    var bold = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).textCase(.uppercase).lineLimit(1)
        }
        .fontWeight(bold ? .semibold : .regular)
        .padding(.leading, 16)
        .padding(.trailing, 28)
        .padding(.vertical, 7)
        .overlay(alignment: .trailing) {
            DiagonalLine()
                .stroke(Color(hex: 0xE6E6E6), lineWidth: 1.5)
                .frame(width: 20)
        }
    }
}

private struct DiagonalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
    }
}

/// Descarga y descifra la imagen al aparecer en pantalla.
private struct ItemImage: View {
    @Environment(AppModel.self) private var model
    let item: ClipItem

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
            } else if failed {
                Text(model.loc.t(.decryptFailed))
                    .font(Theme.font(13.4)).textCase(.uppercase).foregroundStyle(Theme.danger)
                    .padding(12)
            } else {
                ProgressView().controlSize(.small).frame(height: 80).frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 420)
        .background(Theme.panel)
        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
        .task(id: item.id) {
            do {
                let data = try await model.history.content(for: item)
                image = NSImage(data: data)
                failed = image == nil
            } catch {
                print("[history] image", item.id, error)
                failed = true
            }
        }
    }
}
