import Foundation
import Observation

/// `clipboard:list` + descifrado (useDecryptedItems en la web).
@MainActor
@Observable
final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    private(set) var loaded = false

    @ObservationIgnored private let convex: ConvexHTTPClient
    @ObservationIgnored private let session: Session
    /// Imágenes/archivos ya descargados y descifrados, por id.
    @ObservationIgnored private var contents: [String: Data] = [:]

    init(convex: ConvexHTTPClient, session: Session) {
        self.convex = convex
        self.session = session
    }

    func refresh() async {
        guard session.state == .ready else { return }
        do {
            let raw: [ClipItem] = try await convex.query("clipboard:list", EmptyArgs())
            guard session.state == .ready else { return }
            items = raw.map(prepare)
            let ids = Set(raw.map(\.id))
            contents = contents.filter { ids.contains($0.key) }
            loaded = true
        } catch {
            print("[history] refresh failed", error)
        }
    }

    func reset() {
        items = []
        contents = [:]
        loaded = false
    }

    /// Bytes descifrados de una imagen o archivo.
    func content(for item: ClipItem) async throws -> Data {
        if let cached = contents[item.id] { return cached }
        guard let url = item.imageUrl.flatMap(URL.init(string:)) else {
            throw AppError("Sin contenido")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError("No se pudo descargar la imagen cifrada")
        }
        let plain = item.encrypted == true
            ? try ClipCrypto.decrypt(data, with: try session.key(forShareKey: item.shareKey))
            : data
        contents[item.id] = plain
        return plain
    }

    private func prepare(_ item: ClipItem) -> HistoryItem {
        if item.shareKey != nil, !session.shareReady {
            return HistoryItem(raw: item, decryptPending: true)
        }
        guard item.type == .text else { return HistoryItem(raw: item) }

        guard let text = item.text, item.encrypted == true || ClipCrypto.looksEncrypted(text) else {
            return HistoryItem(raw: item, text: item.text)
        }
        do {
            let key = try session.key(forShareKey: item.shareKey)
            return HistoryItem(raw: item, text: try ClipCrypto.decryptText(text, with: key))
        } catch {
            print("[history] decrypt failed", item.id, error)
            return HistoryItem(raw: item, decryptError: true)
        }
    }
}

/// `friends:list` + `friends:requests`
@MainActor
@Observable
final class FriendsStore {
    private(set) var friends: [Friend]?
    private(set) var requests: FriendRequests?

    @ObservationIgnored private let convex: ConvexHTTPClient

    init(convex: ConvexHTTPClient) {
        self.convex = convex
    }

    var incomingCount: Int { requests?.incoming.count ?? 0 }

    func refresh() async {
        do {
            async let friends: [Friend] = convex.query("friends:list", EmptyArgs())
            async let requests: FriendRequests = convex.query("friends:requests", EmptyArgs())
            (self.friends, self.requests) = try await (friends, requests)
        } catch {
            print("[friends] refresh failed", error)
        }
    }

    func reset() {
        friends = nil
        requests = nil
    }

    func invite(email: String) async throws -> InviteResult {
        let result: InviteResult = try await convex.mutation("friends:invite", ["email": email])
        await refresh()
        return result
    }

    func accept(_ requestId: String) async throws {
        try await run("friends:accept", ["requestId": requestId])
    }

    func decline(_ requestId: String) async throws {
        try await run("friends:decline", ["requestId": requestId])
    }

    func cancel(_ requestId: String) async throws {
        try await run("friends:cancel", ["requestId": requestId])
    }

    func remove(_ friendId: String) async throws {
        try await run("friends:remove", ["friendId": friendId])
    }

    private func run(_ path: String, _ args: [String: String]) async throws {
        _ = try await convex.mutation(path, args, as: Ignored?.self)
        await refresh()
    }
}

/// Encuesta del sidebar (`poll:*`).
@MainActor
@Observable
final class PollStore {
    private(set) var myVote: Int?
    private(set) var results: PollResults?
    private(set) var loaded = false

    @ObservationIgnored private let convex: ConvexHTTPClient

    init(convex: ConvexHTTPClient) {
        self.convex = convex
    }

    func refresh() async {
        do {
            async let myVote: Double? = convex.query("poll:myVote", EmptyArgs())
            async let results: PollResults = convex.query("poll:results", EmptyArgs())
            let (vote, counts) = try await (myVote, results)
            self.myVote = vote.map { Int($0) }
            self.results = counts
            loaded = true
        } catch {
            print("[poll] refresh failed", error)
        }
    }

    func vote(_ option: Int) async throws {
        _ = try await convex.mutation("poll:vote", ["option": option], as: Ignored?.self)
        await refresh()
    }
}
