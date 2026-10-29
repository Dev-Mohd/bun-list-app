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
    /// nil when the owner keeps it from you.
    public let followers: Int?
    public let following: Int?
    /// Their discoveries and recipes are private to you. Missing from older servers.
    public let activityHidden: Bool?
    public let isFollowing: Bool
    public let isMe: Bool
    /// A private account; `requested` means you asked to follow. Missing from older servers.
    public let isPrivate: Bool?
    public let requested: Bool?
    public let discoveries: [RemoteLot]
    public let recipes: [RemotePublicRecipe]
}

public struct RemotePerson: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: String { username }
    public let username: String
    public let displayName: String?
    public let avatarUrl: String?
}

public enum FollowList: String, Sendable, Identifiable {
    case followers, following
    public var id: String { rawValue }
}

/// Who may see a part of your public profile.
public enum ProfileVisibility: String, Codable, CaseIterable, Sendable {
    case everyone, followers, me

    public var nameAr: String {
        switch self {
        case .everyone: return "الجميع"
        case .followers: return "متابعيني"
        case .me: return "أنا فقط"
        }
    }
}

/// The parts of a public profile with their own visibility.
public enum PrivacyPart: String, CaseIterable, Sendable {
    case followers, following, activity

    public var titleAr: String {
        switch self {
        case .followers: return "من يشوف متابعيني"
        case .following: return "من يشوف اللي أتابعهم"
        case .activity: return "من يشوف اكتشافاتي ووصفاتي"
        }
    }

    var field: String { rawValue + "Visibility" }
}

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

    public func setVisibility(_ part: PrivacyPart, to visibility: ProfileVisibility, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: [part.field: visibility.rawValue])) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .patch, path: "/api/v1/me/profile", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }

    /// Follows (a private account: asks to) or unfollows (withdraws the request).
    @discardableResult
    public func setFollowing(_ follow: Bool, username: String, accessToken: String) async throws -> FollowState {
        let response = try await transport.send(
            HTTPRequest(method: follow ? .post : .delete, path: Self.userPath(username) + "/follow", bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Result: Decodable { let following: Bool; let requested: Bool? }
        let result = try? JSONDecoder().decode(Result.self, from: response.body)
        return FollowState(following: result?.following ?? follow, requested: result?.requested ?? false)
    }

    /// Throws `APIError.forbidden` when the owner keeps the list from you.
    public func fetchFollowList(_ list: FollowList, username: String, accessToken: String? = nil) async throws -> [RemotePerson] {
        let response = try await transport.send(
            HTTPRequest(method: .get, path: Self.userPath(username) + "/" + list.rawValue, bearer: accessToken))
        try Self.checkContract(response)
        struct Wrapper: Decodable { let people: [RemotePerson] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).people }
        catch { throw AuthClientError.malformedResponse }
    }
}
