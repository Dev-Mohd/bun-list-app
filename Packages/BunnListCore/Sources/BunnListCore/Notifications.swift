import Foundation

/// Which push notifications the account wants (/api/v1/me/notifications).
public struct RemoteNotificationSettings: Codable, Equatable, Sendable {
    public var newFollower: Bool
    public var submissionApproved: Bool
    public var submissionRejected: Bool

    public init(newFollower: Bool = true, submissionApproved: Bool = true, submissionRejected: Bool = true) {
        self.newFollower = newFollower
        self.submissionApproved = submissionApproved
        self.submissionRejected = submissionRejected
    }
}

public enum PushEnvironment: String, Sendable { case sandbox, production }

extension CatalogAPIClient {
    /// The APNs token as lowercase hex, the form the server stores.
    public static func hexToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public func registerDevice(token: String, environment: PushEnvironment, accessToken: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["token": token, "environment": environment.rawValue])
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/me/devices", body: body, bearer: accessToken))
        try Self.checkContract(response)
    }

    public func unregisterDevice(token: String, accessToken: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["token": token])
        let response = try await transport.send(HTTPRequest(method: .delete, path: "/api/v1/me/devices", body: body, bearer: accessToken))
        try Self.checkContract(response)
    }

    public func fetchNotificationSettings(accessToken: String) async throws -> RemoteNotificationSettings {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/me/notifications", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteNotificationSettings.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func saveNotificationSettings(_ settings: RemoteNotificationSettings, accessToken: String) async throws -> RemoteNotificationSettings {
        let body = try JSONEncoder().encode(settings)
        let response = try await transport.send(HTTPRequest(method: .patch, path: "/api/v1/me/notifications", body: body, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteNotificationSettings.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
