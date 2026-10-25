import Foundation

// The signed-in account's profile and first-run setup (/api/v1/me/...).

public struct RemoteProfile: Codable, Equatable, Sendable {
    public let username: String?
    public let displayName: String?
    public let bio: String?
    public let avatarUrl: String?
    public let onboarded: Bool
}

public enum ProfileRules {
    public static let maxDisplayName = 40
    public static let maxBio = 160
}

extension CatalogAPIClient {
    /// Sets the display name and/or bio; nil leaves a field unchanged, "" clears the bio.
    public func updateProfile(displayName: String?, bio: String?, accessToken: String) async throws -> RemoteProfile {
        var body: [String: Any] = [:]
        if let displayName { body["displayName"] = displayName }
        if let bio { body["bio"] = bio }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .patch, path: "/api/v1/me/profile", body: data, bearer: accessToken)
        )
        return try Self.decodeProfile(response)
    }

    /// Uploads a square JPEG (≤ 2 MB) as the profile picture.
    public func uploadAvatar(jpeg: Data, accessToken: String) async throws -> RemoteProfile {
        let data = (try? JSONSerialization.data(withJSONObject: ["imageBase64": jpeg.base64EncodedString()])) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .put, path: "/api/v1/me/avatar", body: data, bearer: accessToken)
        )
        return try Self.decodeProfile(response)
    }

    public func removeAvatar(accessToken: String) async throws -> RemoteProfile {
        let response = try await transport.send(HTTPRequest(method: .delete, path: "/api/v1/me/avatar", bearer: accessToken))
        return try Self.decodeProfile(response)
    }

    /// A valid, free username to pre-fill first-run setup.
    public func suggestUsername(accessToken: String) async throws -> String {
        let response = try await transport.send(
            HTTPRequest(method: .get, path: "/api/v1/me/username/suggest", bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Suggestion: Decodable { let username: String }
        do { return try JSONDecoder().decode(Suggestion.self, from: response.body).username }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Records that first-run setup is done (or skipped) for this account.
    public func markOnboarded(accessToken: String) async throws {
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/me/onboarded", bearer: accessToken))
        try Self.checkContract(response)
    }

    private static func decodeProfile(_ response: HTTPResponse) throws -> RemoteProfile {
        try checkContract(response)
        do { return try JSONDecoder().decode(RemoteProfile.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
