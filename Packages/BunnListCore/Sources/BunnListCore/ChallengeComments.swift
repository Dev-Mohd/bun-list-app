import Foundation

// «تحدي الأسبوع» (GET /api/v1/community/challenge, admin CRUD) and comments on
// brews and recipes (/api/v1/comments/...).

public struct RemoteChallenge: Codable, Equatable, Sendable, Identifiable {
    public struct Filters: Codable, Equatable, Sendable {
        public let originCode: String?
        public let process: String?
        public let roasterSlug: String?
        public let flavorFamily: String?

        public init(originCode: String? = nil, process: String? = nil, roasterSlug: String? = nil, flavorFamily: String? = nil) {
            self.originCode = originCode
            self.process = process
            self.roasterSlug = roasterSlug
            self.flavorFamily = flavorFamily
        }

        public var isEmpty: Bool { originCode == nil && process == nil && roasterSlug == nil && flavorFamily == nil }
    }

    public let id: String
    public let titleAr: String
    public let subtitleAr: String?
    public let emoji: String?
    /// brew | rate | collect
    public let action: String
    public let filters: Filters
    public let target: Int
    public let points: Int
    public let startsAt: String
    public let endsAt: String
    /// Admin list only.
    public var finished: Int? = nil

    public var actionAr: String {
        switch action {
        case "brew": return "حضّر"
        case "rate": return "قيّم"
        default: return "أضف لمجموعتك"
        }
    }

    /// «باقي ٣ أيام», «آخر يوم», «انتهى».
    public func timeLeftAr(now: Date = Date()) -> String {
        guard let end = ISODate.parse(endsAt) else { return "" }
        let seconds = end.timeIntervalSince(now)
        if seconds <= 0 { return "انتهى" }
        let days = Int(ceil(seconds / 86_400))
        switch days {
        case 1: return "آخر يوم"
        case 2: return "باقي يومين"
        case 3...10: return "باقي \(days) أيام"
        default: return "باقي \(days) يوم"
        }
    }

    /// The browse filters that list the coffees counting toward it.
    public var browseFilters: BrowseFilters {
        var f = BrowseFilters()
        if let o = filters.originCode { f.origins = [o] }
        if let p = filters.process { f.processes = [p] }
        if let r = filters.roasterSlug { f.roasters = [r] }
        if let fam = filters.flavorFamily.flatMap(FlavorFamily.init(rawValue:)) { f.flavors = [fam] }
        return f
    }
}

public struct RemoteChallengeState: Decodable, Equatable, Sendable {
    public struct Me: Decodable, Equatable, Sendable {
        public let progress: Int
        public let completed: Bool
        public let justCompleted: Bool
    }
    public let challenge: RemoteChallenge?
    public let participants: Int
    public let finished: Int
    public let me: Me?
}

/// What an admin fills in for a challenge.
public struct ChallengeDraft: Encodable, Equatable, Sendable {
    public var titleAr = ""
    public var subtitleAr = ""
    public var emoji = ""
    public var action = "brew"
    public var originCode: String?
    public var process: String?
    public var roasterSlug: String?
    public var flavorFamily: String?
    public var target = 1
    public var points = 50
    public var startsAt: Date
    public var endsAt: Date

    public init(now: Date = Date()) {
        startsAt = now
        endsAt = now.addingTimeInterval(7 * 86_400)
    }

    public init(_ c: RemoteChallenge) {
        titleAr = c.titleAr
        subtitleAr = c.subtitleAr ?? ""
        emoji = c.emoji ?? ""
        action = c.action
        originCode = c.filters.originCode
        process = c.filters.process
        roasterSlug = c.filters.roasterSlug
        flavorFamily = c.filters.flavorFamily
        target = c.target
        points = c.points
        startsAt = ISODate.parse(c.startsAt) ?? Date()
        endsAt = ISODate.parse(c.endsAt) ?? Date().addingTimeInterval(7 * 86_400)
    }

    public var isValid: Bool { titleAr.trimmingCharacters(in: .whitespaces).count >= 2 && endsAt > startsAt }

    private enum Keys: String, CodingKey {
        case titleAr, subtitleAr, emoji, action, originCode, process, roasterSlug, flavorFamily, target, points, startsAt, endsAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        let iso = ISO8601DateFormatter()
        try c.encode(titleAr.trimmingCharacters(in: .whitespaces), forKey: .titleAr)
        try c.encode(subtitleAr.isEmpty ? nil : subtitleAr, forKey: .subtitleAr)
        try c.encode(emoji.isEmpty ? nil : emoji, forKey: .emoji)
        try c.encode(action, forKey: .action)
        try c.encode(originCode, forKey: .originCode)
        try c.encode(process, forKey: .process)
        try c.encode(roasterSlug, forKey: .roasterSlug)
        try c.encode(flavorFamily, forKey: .flavorFamily)
        try c.encode(target, forKey: .target)
        try c.encode(points, forKey: .points)
        try c.encode(iso.string(from: startsAt), forKey: .startsAt)
        try c.encode(iso.string(from: endsAt), forKey: .endsAt)
    }
}

public enum CommentTarget: String, Sendable { case brew, recipe }

public struct RemoteComment: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let body: String
    public let createdAt: String
    public let name: String
    public let username: String?
    public let avatarUrl: String?
    public let isMine: Bool
    public let canDelete: Bool
}

public struct RemoteComments: Codable, Equatable, Sendable {
    public let comments: [RemoteComment]
    public let count: Int
}

extension RemotePulseItem {
    /// What its comments hang on, if it takes comments.
    public var commentTarget: (CommentTarget, String)? {
        switch kind {
        case .brew: return brewId.map { (.brew, $0) }
        case .recipe: return recipeId.map { (.recipe, $0) }
        case .discovery: return nil
        }
    }
}

extension CatalogAPIClient {
    private func decoded<T: Decodable>(_ type: T.Type, _ request: HTTPRequest) async throws -> T {
        let response = try await transport.send(request)
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    private func encodedBody<T: Encodable>(_ value: T) -> Data { (try? JSONEncoder().encode(value)) ?? Data() }

    public func fetchChallenge(accessToken: String?) async throws -> RemoteChallengeState {
        try await decoded(RemoteChallengeState.self, HTTPRequest(method: .get, path: "/api/v1/community/challenge", bearer: accessToken))
    }

    public func adminChallenges(accessToken: String) async throws -> [RemoteChallenge] {
        struct Wrapper: Decodable { let challenges: [RemoteChallenge] }
        return try await decoded(Wrapper.self, HTTPRequest(method: .get, path: "/api/v1/admin/challenges", bearer: accessToken)).challenges
    }

    public func createChallenge(_ draft: ChallengeDraft, accessToken: String) async throws -> RemoteChallenge {
        try await decoded(RemoteChallenge.self, HTTPRequest(method: .post, path: "/api/v1/admin/challenges", body: encodedBody(draft), bearer: accessToken))
    }

    public func updateChallenge(id: String, _ draft: ChallengeDraft, accessToken: String) async throws -> RemoteChallenge {
        try await decoded(RemoteChallenge.self, HTTPRequest(method: .patch, path: "/api/v1/admin/challenges/\(id)", body: encodedBody(draft), bearer: accessToken))
    }

    public func deleteChallenge(id: String, accessToken: String) async throws {
        let response = try await transport.send(HTTPRequest(method: .delete, path: "/api/v1/admin/challenges/\(id)", bearer: accessToken))
        try Self.checkContract(response)
    }

    public func fetchComments(_ target: CommentTarget, id: String, accessToken: String?) async throws -> RemoteComments {
        try await decoded(RemoteComments.self, HTTPRequest(method: .get, path: "/api/v1/comments/\(target.rawValue)/\(id)", bearer: accessToken))
    }

    public func postComment(_ target: CommentTarget, id: String, body: String, accessToken: String) async throws -> RemoteComment {
        try await decoded(RemoteComment.self, HTTPRequest(method: .post, path: "/api/v1/comments/\(target.rawValue)/\(id)",
                                                          body: encodedBody(["body": body]), bearer: accessToken))
    }

    public func deleteComment(id: String, accessToken: String) async throws {
        let response = try await transport.send(HTTPRequest(method: .delete, path: "/api/v1/comments/item/\(id)", bearer: accessToken))
        try Self.checkContract(response)
    }
}
