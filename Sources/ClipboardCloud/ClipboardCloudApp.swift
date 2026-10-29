import AppKit
import SwiftUI

@main
struct ClipboardCloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        MenuBarExtra("Clipboard Cloud", systemImage: "doc.on.clipboard") {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Clipboard Cloud", id: "main") {
            MainWindowView(model: model)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 900, height: 760)
        .defaultLaunchBehavior(.presented)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Arranca solo en la menubar, salvo que la ventana ya se haya abierto.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.setActivationPolicy(.accessory)
        }
        AppModel.shared.start()
    }
}
