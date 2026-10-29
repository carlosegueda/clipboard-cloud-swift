import Foundation

/// `users:viewer`
struct Viewer: Decodable, Equatable {
    let id: String
    let email: String?
    let encSalt: String?
    let wrappedDek: String?
    let publicKey: String?
    let encPrivateKey: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", email, encSalt, wrappedDek, publicKey, encPrivateKey
    }
}

enum ItemType: String, Decodable {
    case text, image, file
}

enum ItemSource: String, Decodable {
    case auto, manual, screenshot
}

/// Un elemento de `clipboard:list`.
struct ClipItem: Decodable, Identifiable, Equatable {
    let id: String
    let type: ItemType
    let text: String?
    let imageUrl: String?
    let createdAt: Date
    let source: ItemSource?
    let charCount: Int?
    let encrypted: Bool?
    let mimeType: String?
    let fileName: String?
    let shareKey: String?
    let sharedByEmail: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", type, text, imageUrl, createdAt, source, charCount
        case encrypted, mimeType, fileName, shareKey, sharedByEmail
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(ItemType.self, forKey: .type)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        createdAt = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .createdAt) / 1000)
        source = try? c.decodeIfPresent(ItemSource.self, forKey: .source)
        charCount = try c.decodeIfPresent(Double.self, forKey: .charCount).map { Int($0) }
        encrypted = try c.decodeIfPresent(Bool.self, forKey: .encrypted)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        shareKey = try c.decodeIfPresent(String.self, forKey: .shareKey)
        sharedByEmail = try c.decodeIfPresent(String.self, forKey: .sharedByEmail)
    }
}

/// Elemento del historial ya preparado para mostrar (el texto descifrado).
/// Imágenes y archivos se descargan y descifran al mostrarse (HistoryStore.content).
struct HistoryItem: Identifiable, Equatable {
    let raw: ClipItem
    var text: String?
    var decryptError = false
    /// Compartido por un amigo cuya clave privada aún se está preparando.
    var decryptPending = false

    var id: String { raw.id }
    var type: ItemType { raw.type }
    var charCount: Int { raw.charCount ?? text?.utf16.count ?? 0 }
}

/// `friends:list`
struct Friend: Decodable, Identifiable, Equatable {
    let userId: String
    let email: String?
    let publicKey: String?
    let since: Date

    var id: String { userId }

    enum CodingKeys: String, CodingKey { case userId, email, publicKey, since }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        publicKey = try c.decodeIfPresent(String.self, forKey: .publicKey)
        since = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .since) / 1000)
    }
}

/// `friends:requests`
struct FriendRequests: Decodable, Equatable {
    struct Request: Decodable, Identifiable, Equatable {
        let id: String
        let email: String?
        let createdAt: Date
        /// Solo en las enviadas: si el invitado ya tiene cuenta.
        let registered: Bool?

        enum CodingKeys: String, CodingKey { case id = "_id", email, createdAt, registered }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            email = try c.decodeIfPresent(String.self, forKey: .email)
            createdAt = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .createdAt) / 1000)
            registered = try c.decodeIfPresent(Bool.self, forKey: .registered)
        }
    }

    let incoming: [Request]
    let outgoing: [Request]
}

/// `friends:invite`
struct InviteResult: Decodable {
    let ok: Bool
    /// "pending" | "accepted"
    let status: String?
    /// "invalidEmail" | "self" | "alreadyFriends" | "alreadyInvited"
    let reason: String?
}

/// `poll:results`
struct PollResults: Decodable, Equatable {
    let counts: [Int]
    let total: Int

    enum CodingKeys: String, CodingKey { case counts, total }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counts = try c.decode([Double].self, forKey: .counts).map { Int($0) }
        total = Int(try c.decode(Double.self, forKey: .total))
    }
}
