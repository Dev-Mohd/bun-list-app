import Foundation

// The app's networking contract for the mobile auth endpoints, mirroring the server
// (`lib/mobile` in the bunnlist repo). The HTTP transport is injected so this stays
// pure Foundation and runs under `swift test` on Linux with a fake; the app target
// supplies a URLSession-backed transport. Contract statuses (401/403/409/422/429)
// become `APIError`; anything else becomes `AuthClientError`.

public struct HTTPRequest: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }
    public let method: Method
    public let path: String
    public let body: Data?
    public let bearer: String?

    public init(method: Method, path: String, body: Data? = nil, bearer: String? = nil) {
        self.method = method
        self.path = path
        self.body = body
        self.bearer = bearer
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Performs an HTTP request. The app provides a URLSession implementation; tests provide a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Client-only failures that are outside the agreed `APIError` contract.
public enum AuthClientError: Error, Equatable, Sendable {
    case server(status: Int)
    case malformedResponse
}

/// The tokens returned by exchange / email-verify / refresh. JSON keys match the server.
public struct AuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let accessExpiresInSeconds: Int
    public let accountID: String
    public let isNewAccount: Bool?

    public init(accessToken: String, refreshToken: String, accessExpiresInSeconds: Int, accountID: String, isNewAccount: Bool? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresInSeconds = accessExpiresInSeconds
        self.accountID = accountID
        self.isNewAccount = isNewAccount
    }

    enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, accessExpiresInSeconds
        case accountID = "accountId"
        case isNewAccount
    }
}

public struct AuthAPIClient: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    /// POST /api/v1/auth/exchange — trade a provider identity token (Apple/Google) for tokens.
    public func exchange(provider: String, credential: String, deviceID: String) async throws -> AuthTokens {
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/auth/exchange",
                        body: json(["provider": provider, "credential": credential, "deviceId": deviceID]))
        )
        try check(response)
        return try decode(AuthTokens.self, from: response.body)
    }

    /// POST /api/v1/auth/email/request — begin email login. Always neutral.
    public func requestEmailCode(email: String) async throws {
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/auth/email/request", body: json(["email": email]))
        )
        try check(response)
    }

    /// POST /api/v1/auth/email/verify — verify the code and receive tokens.
    public func verifyEmailCode(email: String, code: String, deviceID: String) async throws -> AuthTokens {
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/auth/email/verify",
                        body: json(["email": email, "code": code, "deviceId": deviceID]))
        )
        try check(response)
        return try decode(AuthTokens.self, from: response.body)
    }

    /// POST /api/v1/auth/refresh — rotate the refresh token.
    public func refresh(refreshToken: String) async throws -> AuthTokens {
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/auth/refresh", body: json(["refreshToken": refreshToken]))
        )
        try check(response)
        return try decode(AuthTokens.self, from: response.body)
    }

    /// POST /api/v1/account/delete — authenticated; permanently deletes the account.
    public func deleteAccount(accessToken: String) async throws {
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/account/delete", bearer: accessToken)
        )
        try check(response)
    }

    // MARK: - Helpers

    private func json(_ object: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func check(_ response: HTTPResponse) throws {
        switch response.status {
        case 200..<300: return
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 409: throw APIError.conflict
        case 422: throw APIError.unprocessable
        case 429: throw APIError.rateLimited
        default: throw AuthClientError.server(status: response.status)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AuthClientError.malformedResponse
        }
    }
}
