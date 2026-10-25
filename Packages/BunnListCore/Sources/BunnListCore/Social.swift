import Foundation

// Public profiles and following (/api/v1/users/...). People are addressed by
// @username only.

public struct RemotePublicRecipe: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let methodCode: String
    public let lotNameAr: String?
}

public struct RemotePublicProfile: Codable, Equatable, Sendable {
    public let username: String
    public let displayName: String?
    public let bio: String?
    public let avatarUrl: String?
    public let points: Int
    public let followers: Int
    public let following: Int
    public let isFollowing: Bool
    public let isMe: Bool
    public let discoveries: [RemoteLot]
    public let recipes: [RemotePublicRecipe]
}

public struct RemotePerson: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: String { username }
    public let username: String
    public let displayName: String?
    public let avatarUrl: String?
}

public enum FollowList: String, Sendable { case followers, following }

extension CatalogAPIClient {
    private static func userPath(_ username: String) -> String {
        "/api/v1/users/" + (username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)
    }

    public func fetchUser(_ username: String, accessToken: String?) async throws -> RemotePublicProfile {
        let response = try await transport.send(HTTPRequest(method: .get, path: Self.userPath(username), bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemotePublicProfile.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func setFollowing(_ follow: Bool, username: String, accessToken: String) async throws {
        let response = try await transport.send(
            HTTPRequest(method: follow ? .post : .delete, path: Self.userPath(username) + "/follow", bearer: accessToken)
        )
        try Self.checkContract(response)
    }

    public func fetchFollowList(_ list: FollowList, username: String) async throws -> [RemotePerson] {
        let response = try await transport.send(HTTPRequest(method: .get, path: Self.userPath(username) + "/" + list.rawValue))
        try Self.checkContract(response)
        struct Wrapper: Decodable { let people: [RemotePerson] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).people }
        catch { throw AuthClientError.malformedResponse }
    }
}
