import Foundation

// «قوائمي»: named lists of coffees (/api/v1/me/lists, /api/v1/lists/[id],
// /api/v1/users/[username]/lists).

public struct RemoteListSummary: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let note: String?
    public let emoji: String?
    public let isPublic: Bool
    public let count: Int
    public let covers: [String]
    public let updatedAt: String
    /// With a coffee asked about: whether it's in this list.
    public var hasLot: Bool? = nil

    /// «٣ قهاوي», «قهوة وحدة», «فاضية».
    public var countLine: String { ListText.count(count) }
}

public struct RemoteListOwner: Codable, Equatable, Sendable {
    public let name: String
    public let username: String?
    public let avatarUrl: String?
}

public struct RemoteListLot: Codable, Equatable, Sendable, Identifiable {
    public var id: String { lot.id }
    public let lot: RemoteLot
    public let itemNote: String?
    public let addedAt: String

    private enum CodingKeys: String, CodingKey { case itemNote, addedAt }

    public init(from decoder: Decoder) throws {
        lot = try RemoteLot(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemNote = try c.decodeIfPresent(String.self, forKey: .itemNote)
        addedAt = try c.decodeIfPresent(String.self, forKey: .addedAt) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        try lot.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(itemNote, forKey: .itemNote)
        try c.encode(addedAt, forKey: .addedAt)
    }
}

public struct RemoteListPage: Codable, Equatable, Sendable {
    public let list: RemoteListSummary
    public let owner: RemoteListOwner
    public let isMine: Bool
    public let lots: [RemoteListLot]
}

public struct RemoteLists: Codable, Equatable, Sendable {
    public let lists: [RemoteListSummary]
}

public struct ListDraft: Equatable, Sendable {
    public var title: String
    public var note: String
    public var emoji: String
    public var isPublic: Bool

    public init(title: String = "", note: String = "", emoji: String = "☕", isPublic: Bool = true) {
        self.title = title; self.note = note; self.emoji = emoji; self.isPublic = isPublic
    }

    public init(_ list: RemoteListSummary) {
        self.init(title: list.title, note: list.note ?? "", emoji: list.emoji ?? "☕", isPublic: list.isPublic)
    }

    public static let maxTitle = 40
    public static let maxNote = 200
    public static let emojis = ["☕", "❤️", "⭐️", "🎁", "☀️", "🧊", "🌙", "🏠", "✈️", "🍓", "🍫", "🌸"]

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isValid: Bool { !trimmedTitle.isEmpty && trimmedTitle.count <= Self.maxTitle && note.count <= Self.maxNote }

    var body: [String: Any] {
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["title": trimmedTitle, "note": n.isEmpty ? NSNull() : n, "emoji": emoji, "isPublic": isPublic]
    }
}

public enum ListText {
    public static func count(_ n: Int) -> String {
        switch n {
        case 0: return "فاضية"
        case 1: return "قهوة وحدة"
        case 2: return "قهوتين"
        case 3...10: return "\(n.formatted()) قهاوي"
        default: return "\(n.formatted()) قهوة"
        }
    }
}

extension CatalogAPIClient {
    /// My lists; with a slug, `hasLot` says which ones hold that coffee.
    public func fetchMyLists(lotSlug: String? = nil, accessToken: String) async throws -> [RemoteListSummary] {
        var components = URLComponents()
        components.path = "/api/v1/me/lists"
        if let lotSlug { components.queryItems = [URLQueryItem(name: "lot", value: lotSlug)] }
        let r: RemoteLists = try await listsCall(.get, components.string ?? components.path, nil, accessToken)
        return r.lists
    }

    public func createList(_ draft: ListDraft, accessToken: String) async throws -> RemoteListSummary {
        try await listsCall(.post, "/api/v1/me/lists", draft.body, accessToken)
    }

    public func updateList(id: String, _ draft: ListDraft, accessToken: String) async throws -> RemoteListSummary {
        try await listsCall(.patch, "/api/v1/me/lists/\(id)", draft.body, accessToken)
    }

    public func deleteList(id: String, accessToken: String) async throws {
        let response = try await transport.send(HTTPRequest(method: .delete, path: "/api/v1/me/lists/\(id)", bearer: accessToken))
        try Self.checkContract(response)
    }

    /// Adds a coffee (optionally with a note) or takes it out.
    public func setListItem(listID: String, slug: String, add: Bool, note: String? = nil, accessToken: String) async throws -> RemoteListSummary {
        let path = "/api/v1/me/lists/\(listID)/items/\(slug)"
        if add {
            let body: [String: Any] = note.map { ["note": $0] } ?? [:]
            return try await listsCall(.put, path, body, accessToken)
        }
        return try await listsCall(.delete, path, nil, accessToken)
    }

    public func fetchList(id: String, accessToken: String?) async throws -> RemoteListPage {
        try await listsCall(.get, "/api/v1/lists/\(id)", nil, accessToken)
    }

    public func fetchUserLists(username: String, accessToken: String?) async throws -> [RemoteListSummary] {
        let r: RemoteLists = try await listsCall(.get, "/api/v1/users/\(username)/lists", nil, accessToken)
        return r.lists
    }

    private func listsCall<T: Decodable>(_ method: HTTPRequest.Method, _ path: String, _ body: [String: Any]?, _ token: String?) async throws -> T {
        let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let response = try await transport.send(HTTPRequest(method: method, path: path, body: data, bearer: token))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
