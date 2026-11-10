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
    /// «مبدع مؤسس» number; missing from older servers.
    public var founderNumber: Int? = nil
    /// The last Riyadh day they opened the app ("2026-11-10"); missing from older servers.
    public var lastActiveDay: String? = nil
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
    /// «مبدع مؤسس» number; missing from older servers.
    public var founderNumber: Int? = nil
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

/// Narrows the admin's user list.
public enum AdminUserFilter: String, CaseIterable, Sendable, Identifiable {
    case all, active, new, founders, suspended, admins
    public var id: String { rawValue }

    public var nameAr: String {
        switch self {
        case .all: return "الكل"
        case .active: return "نشطين هالأسبوع"
        case .new: return "جدد"
        case .founders: return "مؤسسين"
        case .suspended: return "موقوفين"
        case .admins: return "أدمن"
        }
    }
}

/// «اليوم», «أمس», «قبل ٥ أيام»: how long since an account last opened the app.
public enum AdminActivity {
    /// Whole days between two "yyyy-MM-dd" days; nil when either doesn't parse.
    public static func daysAgo(_ day: String?, today: String) -> Int? {
        guard let day else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let a = f.date(from: day), let b = f.date(from: today) else { return nil }
        return max(0, Int((b.timeIntervalSince(a) / 86_400).rounded()))
    }

    public static func label(_ day: String?, today: String) -> String {
        guard let days = daysAgo(day, today: today) else { return "ما فتح التطبيق" }
        switch days {
        case 0: return "نشط اليوم"
        case 1: return "أمس"
        case 2: return "قبل يومين"
        case 3...10: return "قبل \(days) أيام"
        default: return "قبل \(days) يوم"
        }
    }

    /// Today in Riyadh, in the server's day format.
    public static func riyadhToday(_ now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Riyadh")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }
}

/// The repeating notifications: a list sent one at a time every few days.
public struct RemoteRotation: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var body: String
        public var enabled: Bool
        public var sentCount: Int
        public var lastSentAt: String?

        public init(id: String, title: String, body: String, enabled: Bool = true, sentCount: Int = 0, lastSentAt: String? = nil) {
            self.id = id; self.title = title; self.body = body; self.enabled = enabled
            self.sentCount = sentCount; self.lastSentAt = lastSentAt
        }
    }

    public var enabled: Bool
    public var everyDays: Int
    public var audience: String
    public var lastRunAt: String?
    public var nextRunAt: String?
    public var nextItemId: String?
    public var items: [Item]

    /// What PUT takes. Ids the server didn't issue (new rows) are left out.
    public func payload(knownIDs: Set<String>) -> [String: Any] {
        ["enabled": enabled, "everyDays": everyDays, "audience": audience,
         "items": items.map { item -> [String: Any] in
             var row: [String: Any] = ["title": item.title, "body": item.body, "enabled": item.enabled]
             if knownIDs.contains(item.id) { row["id"] = item.id }
             return row
         }]
    }
}

/// Ready-made repeating notifications to start the list from.
public enum BroadcastTemplates {
    public static let all: [(title: String, body: String)] = [
        ("قهوة اليوم جاهزة؟", "افتح التحضير وخل BunnList يمشي معك خطوة خطوة."),
        ("وش في رفّك؟", "أضف القهوة اللي عندك وخذ وصفة تناسبها بالضبط."),
        ("محتار وش تشتري؟", "جاوب 4 أسئلة في «ساعدني أختار» ونرشح لك قهوة على ذوقك."),
        ("كيف طلعت آخر كوب؟", "قيّم تحضيرتك بضغطة، وبنضبط لك الطحنة للمرة الجاية."),
        ("جرّب وصفة بطل", "وصفات أبطال العالم موجودة في التحضير، جاهزة على قهوتك."),
        ("وش يشربون الناس؟", "ادخل المجتمع وشف تقييمات الأسبوع وشارك رأيك."),
    ]
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
    /// For someone gaming the points: wipes their points, streak and level back to zero.
    case resetPoints(reason: String)
    /// «مبدع مؤسس»: give the next number of 100, or take the badge back.
    case setFounder(Bool)

    var payload: [String: Any] {
        switch self {
        case let .suspend(reason, days): return ["action": "suspend", "reason": reason, "days": days.map { $0 as Any } ?? NSNull()]
        case .unsuspend: return ["action": "unsuspend"]
        case let .setAdmin(on): return ["action": "setAdmin", "admin": on]
        case let .resetPoints(reason): return ["action": "resetPoints", "reason": reason]
        case let .setFounder(on): return ["action": "setFounder", "founder": on]
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

    public func adminUsers(query: String, filter: AdminUserFilter = .all, accessToken: String) async throws -> [RemoteAdminUserRow] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+="))) ?? ""
        struct Wrapper: Decodable { let users: [RemoteAdminUserRow] }
        return try await get(Wrapper.self, "/api/v1/admin/users?q=\(q)&filter=\(filter.rawValue)", accessToken).users
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

    public func adminRotation(accessToken: String) async throws -> RemoteRotation {
        try await get(RemoteRotation.self, "/api/v1/admin/broadcasts/rotation", accessToken)
    }

    public func saveRotation(_ rotation: RemoteRotation, knownIDs: Set<String>, accessToken: String) async throws -> RemoteRotation {
        let data = (try? JSONSerialization.data(withJSONObject: rotation.payload(knownIDs: knownIDs))) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .put, path: "/api/v1/admin/broadcasts/rotation", body: data, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteRotation.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func sendBroadcast(title: String, body: String, audience: BroadcastAudience, accessToken: String) async throws -> RemoteBroadcastResult {
        try await post(RemoteBroadcastResult.self, "/api/v1/admin/broadcasts",
                       ["title": title, "body": body, "audience": audience.rawValue], accessToken)
    }
}
