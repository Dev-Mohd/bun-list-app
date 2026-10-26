import Foundation

/// Which push notifications the account wants (/api/v1/me/notifications).
public struct RemoteNotificationSettings: Codable, Equatable, Sendable {
    public var newFollower: Bool
    public var submissionApproved: Bool
    public var submissionRejected: Bool
    public var reviewHelpful: Bool
    public var recipeLiked: Bool
    public var weeklySummary: Bool
    /// News from the BunnList team.
    public var announcements: Bool

    public init(newFollower: Bool = true, submissionApproved: Bool = true, submissionRejected: Bool = true,
                reviewHelpful: Bool = true, recipeLiked: Bool = true, weeklySummary: Bool = true,
                announcements: Bool = true) {
        self.newFollower = newFollower
        self.submissionApproved = submissionApproved
        self.submissionRejected = submissionRejected
        self.reviewHelpful = reviewHelpful
        self.recipeLiked = recipeLiked
        self.weeklySummary = weeklySummary
        self.announcements = announcements
    }

    private enum CodingKeys: String, CodingKey {
        case newFollower, submissionApproved, submissionRejected, reviewHelpful, recipeLiked, weeklySummary, announcements
    }

    /// Kinds an older server doesn't send count as on.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) throws -> Bool { try c.decodeIfPresent(Bool.self, forKey: key) ?? true }
        self.init(newFollower: try flag(.newFollower), submissionApproved: try flag(.submissionApproved),
                  submissionRejected: try flag(.submissionRejected), reviewHelpful: try flag(.reviewHelpful),
                  recipeLiked: try flag(.recipeLiked), weeklySummary: try flag(.weeklySummary),
                  announcements: try flag(.announcements))
    }
}

/// What can be liked: a review ("مفيد") or a recipe ("أعجبني").
public enum LikeTarget: String, Sendable { case review, recipe }

public struct RemoteLikeState: Codable, Equatable, Sendable {
    public let count: Int
    public let liked: Bool

    public init(count: Int, liked: Bool) {
        self.count = count
        self.liked = liked
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

    public func setLike(_ liked: Bool, on target: LikeTarget, id: String, accessToken: String) async throws -> RemoteLikeState {
        let path = "/api/v1/likes/\(target.rawValue)/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)
        let response = try await transport.send(HTTPRequest(method: liked ? .post : .delete, path: path, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteLikeState.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
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
