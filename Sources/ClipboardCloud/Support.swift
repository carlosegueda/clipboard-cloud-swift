import Foundation

/// URLs del backend. En desarrollo se pueden sobreescribir con variables de entorno
/// (equivalen a VITE_WEB_APP_URL / VITE_CONVEX_URL de la app Electron).
enum AppConfig {
    static let webAppURL = url(env: "CC_WEB_APP_URL", default: "https://cb.cosegueda.vip/")
    static let convexURL = url(env: "CC_CONVEX_URL", default: "https://dutiful-swordfish-420.convex.cloud")

    private static func url(env key: String, default fallback: String) -> URL {
        let value = ProcessInfo.processInfo.environment[key] ?? fallback
        return URL(string: value) ?? URL(string: fallback)!
    }
}

/// Port de configStore.js, sobre UserDefaults.
enum ConfigStore {
    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "deviceId") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "deviceId")
        return id
    }

    static var monitoring: Bool {
        get { UserDefaults.standard.object(forKey: "monitoring") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "monitoring") }
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension Date {
    /// Milisegundos desde epoch, como `Date.now()` en JS.
    var millis: Int { Int((timeIntervalSince1970 * 1000).rounded()) }
}
