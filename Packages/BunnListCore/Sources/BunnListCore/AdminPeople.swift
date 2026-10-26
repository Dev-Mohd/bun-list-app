import Foundation

// The admin console's people (/api/v1/admin/users) and broadcasts
// (/api/v1/admin/broadcasts). Admin calls answer 403 for non-admins.

public struct RemoteAdminUserRow: Codable, Equatable, Sendable, Identifiable {
    public let accountId: String
    public let username: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let joinedAt: String
    public let isAdmin: Bool
    public let suspended: Bool
    public var id: String { accountId }

    public var shownName: String { displayName ?? username.map { "@" + $0 } ?? "بدون اسم" }
}

public struct RemoteAdminUser: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public let reviews: Int
        public let recipes: Int
        public let brews: Int
        public let discoveries: Int
        public let followers: Int
        public let following: Int
        public let reports: Int
    }

    public struct Suspension: Codable, Equatable, Sendable {
        public let reason: String
        public let until: String?
        public let createdAt: String
    }

    public struct Review: Codable, Equatable, Sendable, Hashable {
        public let lotNameAr: String
        public let rating: Int
        public let body: String?
        public let status: String
        public let createdAt: String
    }

    public let accountId: String
    public let username: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let joinedAt: String
    public let isAdmin: Bool
    public let suspended: Bool
    public let email: String?
    public let bio: String?
    public let points: Int
    public let lastActiveDay: String?
    public let counts: Counts
    public let suspension: Suspension?
    public let recentReviews: [Review]
}

public enum BroadcastAudience: String, CaseIterable, Sendable, Identifiable {
    case test, active30, all
    public var id: String { rawValue }

    public var nameAr: String {
        switch self {
        case .test: return "تجربة على جوالي"
        case .active30: return "النشطين آخر ٣٠ يوم"
        case .all: return "الكل"
        }
    }
}

public struct RemoteBroadcasts: Codable, Equatable, Sendable {
    public struct Audiences: Codable, Equatable, Sendable {
        public let all: Int
        public let active30: Int
    }

    public struct Sent: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let body: String
        public let audience: String
        public let accounts: Int
        public let delivered: Int
        public let createdAt: String
    }

    public let audiences: Audiences
    public let history: [Sent]
}

public struct RemoteBroadcastResult: Codable, Equatable, Sendable {
    public let accounts: Int
    public let delivered: Int
}

/// Admin actions on an account.
public enum AdminUserAction: Sendable, Equatable {
    /// `days` nil means until lifted.
    case suspend(reason: String, days: Int?)
    case unsuspend
    case setAdmin(Bool)

    var payload: [String: Any] {
        switch self {
        case let .suspend(reason, days): return ["action": "suspend", "reason": reason, "days": days.map { $0 as Any } ?? NSNull()]
        case .unsuspend: return ["action": "unsuspend"]
        case let .setAdmin(on): return ["action": "setAdmin", "admin": on]
        }
    }
}

extension CatalogAPIClient {
    private func get<T: Decodable>(_ type: T.Type, _ path: String, _ token: String) async throws -> T {
        let response = try await transport.send(HTTPRequest(method: .get, path: path, bearer: token))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    private func post<T: Decodable>(_ type: T.Type, _ path: String, _ body: [String: Any], _ token: String) async throws -> T {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: path, body: data, bearer: token))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func adminUsers(query: String, accessToken: String) async throws -> [RemoteAdminUserRow] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+="))) ?? ""
        struct Wrapper: Decodable { let users: [RemoteAdminUserRow] }
        return try await get(Wrapper.self, "/api/v1/admin/users?q=\(q)", accessToken).users
    }

    public func adminUser(id: String, accessToken: String) async throws -> RemoteAdminUser {
        try await get(RemoteAdminUser.self, "/api/v1/admin/users/\(id)", accessToken)
    }

    public func adminUserAction(id: String, _ action: AdminUserAction, accessToken: String) async throws -> RemoteAdminUser {
        try await post(RemoteAdminUser.self, "/api/v1/admin/users/\(id)", action.payload, accessToken)
    }

    public func adminBroadcasts(accessToken: String) async throws -> RemoteBroadcasts {
        try await get(RemoteBroadcasts.self, "/api/v1/admin/broadcasts", accessToken)
    }

    public func sendBroadcast(title: String, body: String, audience: BroadcastAudience, accessToken: String) async throws -> RemoteBroadcastResult {
        try await post(RemoteBroadcastResult.self, "/api/v1/admin/broadcasts",
                       ["title": title, "body": body, "audience": audience.rawValue], accessToken)
    }
}
