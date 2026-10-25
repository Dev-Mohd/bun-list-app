import Foundation

// Points, streaks and the leaderboard (/api/v1/me/points, /api/v1/community/leaderboard).
// The server keeps the ledger; the app only shows it.

public struct RemotePoints: Codable, Equatable, Sendable {
    public struct Reward: Codable, Equatable, Sendable, Hashable {
        public let kind: String
        public let points: Int
        public let createdAt: String
    }

    public let total: Int
    public let week: Int
    public let streak: Int
    public let recent: [Reward]
}

public struct RemoteLeaderboard: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable, Hashable {
        public let rank: Int
        public let name: String
        public let username: String?
        public let avatarUrl: String?
        public let points: Int
        public let isMe: Bool
    }

    public struct Me: Codable, Equatable, Sendable {
        public let rank: Int
        public let points: Int
    }

    public let entries: [Entry]
    public let me: Me?
}

public enum PointRules {
    /// What each reward is called, and how many points it gives, for "كيف أجمع النقاط؟".
    public static let table: [(kind: String, titleAr: String, points: Int, noteAr: String)] = [
        ("collect", "تضيف قهوة لمجموعتك", 5, "مرة لكل قهوة"),
        ("rate", "تقيّم قهوة", 10, "مرة لكل قهوة"),
        ("experience", "تسجّل تجربة تحضير", 5, "٣ مرات باليوم"),
        ("recipe", "تنشر وصفة", 20, "مرة لكل وصفة"),
        ("discovery", "اقتراحك ينقبل (اكتشاف)", 50, ""),
        ("streak7", "سلسلة ٧ أيام", 25, "كل أسبوع متواصل"),
    ]

    public static func titleAr(_ kind: String) -> String {
        table.first { $0.kind == kind }?.titleAr ?? kind
    }
}

extension CatalogAPIClient {
    public func fetchPoints(accessToken: String) async throws -> RemotePoints {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/me/points", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemotePoints.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// `allTime` false = the last 7 days. The token, when given, adds the caller's own rank.
    public func fetchLeaderboard(allTime: Bool, accessToken: String?) async throws -> RemoteLeaderboard {
        let response = try await transport.send(HTTPRequest(
            method: .get, path: "/api/v1/community/leaderboard?period=\(allTime ? "all" : "week")", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteLeaderboard.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
