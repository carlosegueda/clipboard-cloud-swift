import AppKit
import SwiftUI

/// components/SettingsPanel.tsx
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordMessage: (ok: Bool, text: String)?
    @State private var passwordBusy = false

    @State private var clearConfirm = false
    @State private var clearBusy = false
    @State private var clearMessage: String?

    var body: some View {
        let loc = model.loc
        let status = model.status
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HardCard(padding: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            CardTitle(text: loc.t(.desktopMonitor), icon: "desktopcomputer")
                            MutedText(text: loc.t(.desktopMonitorBody))
                        }
                        Spacer()
                        Button {
                            model.setMonitoring(!status.monitoring)
                        } label: {
                            Label(
                                loc.t(status.monitoring ? .pauseMonitor : .resumeMonitor),
                                systemImage: status.monitoring ? "pause.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(HardButtonStyle(kind: .primary, compact: true))
                    }
                    .padding(.bottom, 12)

                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            Stat(icon: "waveform.path.ecg", label: loc.t(.monitorStatus),
                                 value: loc.t(status.monitoring ? .monitorActive : .monitorPaused))
                            Stat(icon: "clock", label: loc.t(.monitorInterval), value: "\(ClipboardPoller.pollIntervalMs) ms")
                        }
                        GridRow {
                            Stat(icon: "doc.on.clipboard", label: loc.t(.lastClipboard),
                                 value: status.lastCaptureAt.map(loc.relative) ?? "—")
                            Stat(icon: "camera", label: loc.t(.lastScreenshot),
                                 value: status.lastScreenshotAt.map(loc.relative) ?? "—")
                        }
                    }

                    if let error = status.lastError ?? status.lastScreenshotError {
                        Text(error).font(Theme.font(13.4)).foregroundStyle(Theme.danger).padding(.top, 10)
                    }

                    Button { model.ensureScreenshotAccess(force: true) } label: {
                        Label(loc.t(.menuScreenshotPermission), systemImage: "folder")
                    }
                    .buttonStyle(HardButtonStyle(compact: true))
                    .padding(.top, 14)
                }

                HardCard(padding: 16) {
                    CardTitle(text: loc.t(.accountDetails), icon: "person").padding(.bottom, 12)
                    HStack(spacing: 14) {
                        IconTile(systemImage: "person.fill", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "envelope").font(.system(size: 10))
                                Text(loc.t(.email))
                            }
                            .font(Theme.font(12))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.muted)
                            Text(model.session.viewer?.email ?? "—")
                                .font(Theme.font(14.5, .bold))
                                .textCase(.uppercase)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            MutedText(text: loc.entriesInHistory(model.history.items.count))
                        }
                    }
                }

                HardCard(padding: 16) {
                    CardTitle(text: loc.t(.language), icon: "globe").padding(.bottom, 4)
                    MutedText(text: loc.t(.languageSubtitle)).padding(.bottom, 12)
                    HStack(spacing: 14) {
                        ForEach(Lang.allCases) { lang in
                            Button(lang.name) { loc.lang = lang }
                                .buttonStyle(HardButtonStyle(kind: loc.lang == lang ? .primary : .secondary, compact: true))
                        }
                    }
                }

                HardCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        CardTitle(text: loc.t(.changePassword), icon: "key")
                        MutedText(text: "\(loc.t(.minChars)) \(loc.t(.encryptionPasswordNote))").padding(.bottom, 6)
                        FieldLabel(text: loc.t(.currentPassword))
                        HardField(placeholder: "", text: $currentPassword, secure: true, contentType: .password)
                            .padding(.bottom, 4)
                        FieldLabel(text: loc.t(.newPassword))
                        HardField(placeholder: "", text: $newPassword, secure: true, contentType: .newPassword)
                            .padding(.bottom, 4)
                        FieldLabel(text: loc.t(.confirmNewPassword))
                        HardField(placeholder: "", text: $confirmPassword, secure: true, contentType: .newPassword,
                                  onSubmit: changePassword)
                        if let passwordMessage {
                            Text(passwordMessage.text)
                                .font(Theme.font(13.6))
                                .textCase(.uppercase)
                                .foregroundStyle(passwordMessage.ok ? Theme.accent : Theme.danger)
                                .padding(.top, 4)
                        }
                        Button { changePassword() } label: {
                            Label(passwordBusy ? loc.t(.saving) : loc.t(.updatePassword), systemImage: "checkmark")
                        }
                        .buttonStyle(HardButtonStyle(kind: .primary))
                        .disabled(passwordBusy || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                        .padding(.top, 8)
                    }
                }

                HardCard(padding: 16) {
                    CardTitle(text: loc.t(.deleteData), icon: "trash", color: Theme.danger).padding(.bottom, 4)
                    MutedText(text: loc.t(.deleteDataBody)).padding(.bottom, 12)
                    if let clearMessage {
                        Text(clearMessage).font(Theme.font(13.6)).textCase(.uppercase).foregroundStyle(Theme.accent)
                            .padding(.bottom, 10)
                    }
                    HStack(spacing: 14) {
                        Button { clearData() } label: {
                            Label(
                                clearBusy ? loc.t(.deleting) : loc.t(clearConfirm ? .confirmDelete : .deleteAllHistory),
                                systemImage: "trash"
                            )
                        }
                        .buttonStyle(HardButtonStyle(kind: .danger, compact: true))
                        .disabled(clearBusy || model.history.items.isEmpty)
                        if clearConfirm && !clearBusy {
                            Button(loc.t(.cancel)) { clearConfirm = false }
                                .buttonStyle(HardButtonStyle(compact: true))
                        }
                    }
                }
            }
            .padding(.trailing, 5)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }

    private func changePassword() {
        let loc = model.loc
        passwordMessage = nil
        guard newPassword == confirmPassword else {
            passwordMessage = (false, loc.t(.passwordsMismatch))
            return
        }
        guard newPassword.count >= 8 else {
            passwordMessage = (false, loc.t(.passwordTooShort))
            return
        }
        passwordBusy = true
        Task {
            do {
                try await model.session.changePassword(current: currentPassword, new: newPassword)
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
                passwordMessage = (true, loc.t(.passwordUpdated))
            } catch {
                // Igual que la web: quitar el prefijo "...Error:" del mensaje de Convex.
                let raw = error.localizedDescription
                let cleaned = raw.range(of: "Error:", options: .backwards).map {
                    raw[$0.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                } ?? raw
                passwordMessage = (false, cleaned.isEmpty ? loc.t(.passwordFailed) : cleaned)
            }
            passwordBusy = false
        }
    }

    private func clearData() {
        guard clearConfirm else {
            clearConfirm = true
            return
        }
        let loc = model.loc
        clearBusy = true
        clearMessage = nil
        Task {
            if let deleted = await model.clearAll() {
                clearMessage = deleted == 0 ? loc.t(.nothingToDelete) : loc.deletedEntries(deleted)
                if deleted > 0 {
                    model.showToast(deleted == 1 ? loc.t(.oneEntryDeleted) : loc.deletedEntries(deleted))
                }
            } else {
                clearMessage = loc.t(.clearFailed)
            }
            clearConfirm = false
            clearBusy = false
        }
    }
}

/// components/AboutPanel.tsx, adaptado a la app de escritorio.
struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let loc = model.loc
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HardCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        BrandHeader(subtitle: "\(loc.t(.version)) \(version)")
                        Text(loc.t(.aboutBody)).font(Theme.font(14.5))
                        HStack(spacing: 10) {
                            IconTile(systemImage: "lock.shield.fill", size: 28)
                            Text(loc.t(.encryptionActiveNote))
                                .font(Theme.font(13.4))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel)
                        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                    }
                }

                HardCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        CardTitle(text: loc.t(.permissionsTitle), icon: "folder")
                        Text(loc.t(.permissionDesktop)).font(Theme.font(14))
                        Button { model.ensureScreenshotAccess(force: true) } label: {
                            Label(loc.t(.menuScreenshotPermission), systemImage: "folder")
                        }
                        .buttonStyle(HardButtonStyle(compact: true))
                        .padding(.top, 4)
                    }
                }

            }
            .padding(.trailing, 5)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }
}

/// Recuadro de estadística del monitor.
private struct Stat: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label)
            }
            .font(Theme.font(12))
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
            Text(value).font(Theme.font(15, .semibold)).textCase(.uppercase)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.field)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}
