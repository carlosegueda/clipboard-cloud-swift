import Foundation

/// Cliente mínimo de la API HTTP de Convex (`POST /api/query|mutation|action`).
/// Las queries no son reactivas: la app vuelve a consultarlas mientras la ventana está abierta.
@MainActor
final class ConvexHTTPClient {
    /// Devuelve el JWT vigente; con `forceRefresh` lo renueva con el refresh token.
    typealias TokenProvider = @MainActor (_ forceRefresh: Bool) async throws -> String?

    let baseURL: URL
    var tokenProvider: TokenProvider?

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func query<Args: Encodable, Value: Decodable>(
        _ path: String, _ args: Args, as _: Value.Type = Value.self
    ) async throws -> Value {
        try await call("query", path, args, authenticated: true)
    }

    func mutation<Args: Encodable, Value: Decodable>(
        _ path: String, _ args: Args, as _: Value.Type = Value.self
    ) async throws -> Value {
        try await call("mutation", path, args, authenticated: true)
    }

    func action<Args: Encodable, Value: Decodable>(
        _ path: String, _ args: Args, as _: Value.Type = Value.self, authenticated: Bool = true
    ) async throws -> Value {
        try await call("action", path, args, authenticated: authenticated)
    }

    /// Sube bytes a una URL de `generateUploadUrl` y devuelve el storageId.
    func upload(_ body: Data, to uploadURL: URL) async throws -> String {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AppError("Upload failed (\(status))")
        }
        return try JSONDecoder().decode(UploadResponse.self, from: data).storageId
    }

    /// `generateUploadUrl` + subida: devuelve el storageId.
    func uploadToStorage(_ body: Data) async throws -> String {
        let uploadURLString: String = try await mutation("clipboard:generateUploadUrl", EmptyArgs())
        guard let uploadURL = URL(string: uploadURLString) else {
            throw AppError("URL de subida inválida")
        }
        return try await upload(body, to: uploadURL)
    }

    private func call<Args: Encodable, Value: Decodable>(
        _ kind: String, _ path: String, _ args: Args, authenticated: Bool
    ) async throws -> Value {
        let token = authenticated ? try await tokenProvider?(false) : nil
        var (status, data) = try await send(kind, path, args, token: token)
        // JWT vencido o revocado: renovar una vez y reintentar.
        if status == 401, authenticated, let refreshed = try await tokenProvider?(true) {
            (status, data) = try await send(kind, path, args, token: refreshed)
        }

        let envelope: Envelope<Value>
        do {
            envelope = try JSONDecoder().decode(Envelope<Value>.self, from: data)
        } catch {
            print("[convex] \(path) respuesta inesperada (\(status))", error)
            throw AppError("Convex \(path) falló (\(status))")
        }
        guard envelope.status == "success", let value = envelope.value else {
            throw ConvexServerError(message: envelope.errorMessage ?? "Convex \(path) falló")
        }
        return value
    }

    private func send<Args: Encodable>(
        _ kind: String, _ path: String, _ args: Args, token: String?
    ) async throws -> (Int, Data) {
        var request = URLRequest(url: baseURL.appending(path: "api/\(kind)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Call(path: path, args: args, format: "json"))
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private struct Call<Args: Encodable>: Encodable {
        let path: String
        let args: Args
        let format: String
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let status: String
        let value: Value?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey { case status, value, errorMessage }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(String.self, forKey: .status)
            errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
            // Se decodifica como `Value` (no `Value?`) para que un `null` legítimo
            // (p. ej. `users:viewer` sin sesión) llegue como `.some(nil)`.
            value = status == "success" ? try container.decode(Value.self, forKey: .value) : nil
        }
    }

    private struct UploadResponse: Decodable {
        let storageId: String
    }
}

/// La función de Convex respondió con error (no es un problema de red).
struct ConvexServerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct EmptyArgs: Encodable {}

/// Para resultados que no se usan (`null`, ids…): `as: Ignored?.self`.
struct Ignored: Decodable {
    init(from decoder: any Decoder) throws {}
}

/// Respuesta de `captureText` / `captureImage`.
struct CaptureResult: Decodable {
    let saved: Bool
    let reason: String?
}
