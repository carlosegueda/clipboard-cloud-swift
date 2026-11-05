import Foundation
import Security

/// Lo que la web guardaba en localStorage (tokens de Convex Auth y la DEK en caché),
/// guardado en el Llavero como un único elemento.
struct StoredSession: Codable {
    var token: String
    var refreshToken: String
    var dekUserId: String?
    var dek: String?
}

enum SessionStore {
    private static let service = "Clipboard Cloud"
    private static let account = "session"

    private static var baseQuery: [String: Any] { baseQuery(account: account) }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Solo en debug: `CC_EPHEMERAL_SESSION=1` no lee ni escribe el Llavero
    /// (para probar sin tocar la sesión real).
    private static var ephemeral: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CC_EPHEMERAL_SESSION"] == "1"
        #else
        false
        #endif
    }

    static func load() -> StoredSession? {
        guard let data = loadData(account: account) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    static func save(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        saveData(data, account: account)
    }

    static func loadData(account: String) -> Data? {
        guard !ephemeral else { return nil }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func saveData(_ data: Data, account: String) {
        guard !ephemeral else { return }
        let query = baseQuery(account: account)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            print("[session-store] keychain error", status)
        }
    }

    static func clear() {
        guard !ephemeral else { return }
        SecItemDelete(baseQuery as CFDictionary)
    }
}
