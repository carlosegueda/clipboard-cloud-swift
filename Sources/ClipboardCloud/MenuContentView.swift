import AppKit
import SwiftUI

/// Menú de la barra (el menú del Tray en Electron).
struct MenuContentView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let loc = model.loc
        Button(loc.t(.menuShow)) {
            openWindow(id: "main")
            NSApp.activate()
        }

        Button(loc.t(.menuCopyLatest)) {
            Task { await model.copyLatest() }
        }
        .disabled(model.session.state != .ready)

        Divider()

        Button(loc.t(model.status.monitoring ? .menuPause : .menuResume)) {
            model.toggleMonitoring()
        }
        .disabled(model.session.state != .ready)

        Text(model.statusLabel)

        Button(loc.t(.menuScreenshotPermission)) {
            model.ensureScreenshotAccess(force: true)
        }

        Divider()

        Button(loc.t(.menuQuit)) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
