import AppKit
import SwiftUI

/// Ventana principal: equivale al BrowserWindow de Electron, pero con UI nativa.
struct MainWindowView: View {
    let model: AppModel

    var body: some View {
        RootView()
            .environment(model)
            // Mientras la ventana está abierta la app aparece en el Dock y en ⌘Tab.
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
                model.setWindowVisible(true)
            }
            .onDisappear {
                model.setWindowVisible(false)
                NSApp.setActivationPolicy(.accessory)
            }
    }
}
