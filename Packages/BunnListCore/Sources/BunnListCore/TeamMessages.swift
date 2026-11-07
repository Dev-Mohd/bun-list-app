import Foundation

// «رسائل BunnList»: one-way messages from the team to one account, signed «فريق BunnList».

public struct RemoteTeamMessage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let body: String
    public let createdAt: String
    public let read: Bool
}

public struct RemoteTeamMessages: Codable, Equatable, Sendable {
    public let messages: [RemoteTeamMessage]
    public let unread: Int
}

/// What a message is about; picks its icon and the suggested text.
public enum TeamMessageKind: String, CaseIterable, Sendable {
    case general, warning, pointsReset, suspension, good

    public var nameAr: String {
        switch self {
        case .general: return "رسالة"
        case .warning: return "تنبيه"
        case .pointsReset: return "تصفير النقاط"
        case .suspension: return "إيقاف"
        case .good: return "خبر حلو"
        }
    }

    public var symbol: String {
        switch self {
        case .general: return "envelope.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .pointsReset: return "arrow.counterclockwise.circle.fill"
        case .suspension: return "hand.raised.fill"
        case .good: return "sparkles"
        }
    }
}

/// A suggested message the admin edits before sending (after a points reset or a suspension, or from «راسله»).
public struct TeamMessageDraft: Equatable, Sendable {
    public var kind: TeamMessageKind
    public var title: String
    public var body: String

    public static func suggested(_ kind: TeamMessageKind, name: String?, reason: String? = nil, days: Int? = nil) -> TeamMessageDraft {
        let hello = name.map { "هلا \($0)،\n\n" } ?? "هلا،\n\n"
        let why = reason.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        switch kind {
        case .pointsReset:
            return .init(kind: kind, title: "صفّرنا نقاطك",
                         body: hello + "لاحظنا نشاط ما يتوافق مع نظام النقاط\(why.map { " (\($0))" } ?? "")، فصفّرنا نقاطك وسلسلتك. تقدر تبدأ من جديد: النقاط على التجربة الحقيقية، التقييم الصادق والملاحظات المفيدة.\n\nشكرًا لتفهّمك ☕")
        case .suspension:
            let period = days.map { $0 == 1 ? "يوم" : $0 == 7 ? "أسبوع" : $0 == 30 ? "شهر" : "\($0) يوم" }
            return .init(kind: kind, title: "أوقفنا النشر مؤقتًا",
                         body: hello + "أوقفنا النشر في حسابك \(period.map { "لمدة \($0)" } ?? "لين نراجعه")\(why.map { " بسبب: \($0)" } ?? "").\nتقدر تتصفح التطبيق وتحضّر عادي، بس ما تقدر تنشر تقييمات أو وصفات أو تعليقات خلال هالفترة.\n\nإذا تشوف إن فيه خطأ، راسلنا من «صندوق اقتراحاتك».")
        case .warning:
            return .init(kind: kind, title: "تنبيه بسيط",
                         body: hello + "لاحظنا \(why ?? "محتوى ما يناسب المجتمع")، ونتمنى تنتبه له المرة الجاية عشان يبقى BunnList مكان مريح للكل.\n\nشكرًا لك ☕")
        case .good:
            return .init(kind: kind, title: "خبر حلو ✨", body: hello + "\(why ?? "شكرًا على مساهمتك في المجتمع!")\n\nفريق BunnList يشكرك ☕")
        case .general:
            return .init(kind: kind, title: "", body: hello)
        }
    }
}

extension CatalogAPIClient {
    public func teamMessages(accessToken: String) async throws -> RemoteTeamMessages {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/me/messages", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteTeamMessages.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func markTeamMessagesRead(accessToken: String) async throws {
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/me/messages/read", body: Data("{}".utf8), bearer: accessToken))
        try Self.checkContract(response)
    }

    public func adminTeamMessages(userID: String, accessToken: String) async throws -> [RemoteTeamMessage] {
        struct Wrapper: Decodable { let messages: [RemoteTeamMessage] }
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/admin/users/\(userID)/messages", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).messages }
        catch { throw AuthClientError.malformedResponse }
    }

    public func sendTeamMessage(userID: String, _ draft: TeamMessageDraft, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: ["kind": draft.kind.rawValue, "title": draft.title, "body": draft.body])) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/users/\(userID)/messages", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }
}
