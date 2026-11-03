import Foundation

// «تحديثات BunnList» (posts from the team, with comments) and the suggestions /
// experiences inbox, where the team replies.

public struct RemoteUpdate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let author: String
    public let createdAt: String
    public let commentCount: Int

    public init(id: String, title: String, body: String, author: String, createdAt: String, commentCount: Int) {
        self.id = id; self.title = title; self.body = body; self.author = author
        self.createdAt = createdAt; self.commentCount = commentCount
    }
}

public enum FeedbackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case suggestion, experience, problem
    public var id: String { rawValue }
    public var nameAr: String {
        switch self {
        case .suggestion: return "اقتراح"
        case .experience: return "تجربة"
        case .problem: return "مشكلة"
        }
    }
    public var symbol: String {
        switch self {
        case .suggestion: return "lightbulb.fill"
        case .experience: return "heart.text.square.fill"
        case .problem: return "exclamationmark.bubble.fill"
        }
    }
    public var placeholder: String {
        switch self {
        case .suggestion: return "وش تبي نضيف أو نغيّر؟ محمصة، قهوة، ميزة…"
        case .experience: return "احكِ لنا عن تجربتك مع التطبيق أو مع قهوة جرّبتها."
        case .problem: return "وش صار؟ وفي أي شاشة؟"
        }
    }
}

public struct RemoteFeedback: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let body: String
    public let createdAt: String
    public let reply: String?
    public let repliedAt: String?
    // Inbox only (admins).
    public let name: String?
    public let username: String?
    public let avatarUrl: String?
    public let isRead: Bool?

    public var feedbackKind: FeedbackKind { FeedbackKind(rawValue: kind) ?? .suggestion }
    public var isAnswered: Bool { reply != nil }
}

public struct RemoteFeedbackInbox: Codable, Equatable, Sendable {
    public let items: [RemoteFeedback]
    public let open: Int
    public init(items: [RemoteFeedback], open: Int) { self.items = items; self.open = open }
}

public struct UpdateDraft: Codable, Equatable, Sendable {
    public var title: String
    public var body: String
    public var notify: Bool
    public init(title: String = "", body: String = "", notify: Bool = false) {
        self.title = title; self.body = body; self.notify = notify
    }

    public var isReady: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && body.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }
}

extension CatalogAPIClient {
    private func send<T: Decodable>(_ type: T.Type, _ request: HTTPRequest) async throws -> T {
        let response = try await transport.send(request)
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    private func json<T: Encodable>(_ value: T) -> Data { (try? JSONEncoder().encode(value)) ?? Data() }

    public func fetchUpdates(accessToken: String?) async throws -> [RemoteUpdate] {
        struct Wrapper: Decodable { let updates: [RemoteUpdate] }
        return try await send(Wrapper.self, HTTPRequest(method: .get, path: "/api/v1/updates", bearer: accessToken)).updates
    }

    public func postUpdate(_ draft: UpdateDraft, accessToken: String) async throws -> RemoteUpdate {
        struct Wrapper: Decodable { let update: RemoteUpdate }
        return try await send(Wrapper.self, HTTPRequest(method: .post, path: "/api/v1/admin/updates", body: json(draft), bearer: accessToken)).update
    }

    public func deleteUpdate(id: String, accessToken: String) async throws {
        let response = try await transport.send(HTTPRequest(method: .delete, path: "/api/v1/admin/updates/\(id)", bearer: accessToken))
        try Self.checkContract(response)
    }

    public func fetchMyFeedback(accessToken: String) async throws -> [RemoteFeedback] {
        struct Wrapper: Decodable { let items: [RemoteFeedback] }
        return try await send(Wrapper.self, HTTPRequest(method: .get, path: "/api/v1/feedback", bearer: accessToken)).items
    }

    public func sendFeedback(kind: FeedbackKind, body: String, accessToken: String) async throws -> RemoteFeedback {
        try await send(RemoteFeedback.self, HTTPRequest(method: .post, path: "/api/v1/feedback",
                                                       body: json(["kind": kind.rawValue, "body": body]), bearer: accessToken))
    }

    public func feedbackInbox(all: Bool, accessToken: String) async throws -> RemoteFeedbackInbox {
        try await send(RemoteFeedbackInbox.self, HTTPRequest(method: .get, path: "/api/v1/admin/feedback?filter=\(all ? "all" : "open")", bearer: accessToken))
    }

    public func replyFeedback(id: String, reply: String, accessToken: String) async throws -> RemoteFeedback {
        try await send(RemoteFeedback.self, HTTPRequest(method: .post, path: "/api/v1/admin/feedback/\(id)/reply",
                                                       body: json(["reply": reply]), bearer: accessToken))
    }
}
