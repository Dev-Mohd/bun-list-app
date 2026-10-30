import Foundation

// The admin's work queue (/api/v1/admin/queue): what waits for review and the
// published coffees missing details, counted, grouped by roaster, served one card
// at a time, with details read from the coffee's own description to offer.

public enum QueueKind: String, Sendable, Hashable {
    /// Suggestions waiting for review.
    case pending
    /// Published coffees missing origin, process or notes.
    case incomplete
}

public struct RemoteQueueCounts: Codable, Equatable, Sendable {
    public let pending: Int
    public let incomplete: Int
    public let noOrigin: Int
    public let noProcess: Int
    public let noNotes: Int
    public let noPhoto: Int
    public let reports: Int
}

public struct RemoteRoasterGroup: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String { roaster }
    public let roaster: String
    public let count: Int
    public let noOrigin: Int
    public let noProcess: Int
    public let noNotes: Int
    public let noPhoto: Int
    public let imageUrl: String?

    /// Coffees missing at least one detail can't exceed the count; this is the worst of them.
    public var gaps: Int { max(noOrigin, noProcess, noNotes) }
}

public struct RemoteQueueCard: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case submission, lot }
    public enum Missing: String, Codable, Sendable { case origin, process, notes, photo }

    public let kind: Kind
    public let id: String
    public let name: String
    public let nameEn: String?
    public let roasterName: String
    public let imageUrl: String?
    public let originName: String?
    public let originCode: String?
    public let process: String?
    public let roastLevel: String?
    public let flavorNotes: [String]
    public let descriptionAr: String?
    public let sourceUrl: String?
    public let missing: [Missing]
}

/// What the description says; nil (or empty) for what it doesn't.
public struct RemoteDetailSuggestion: Codable, Equatable, Sendable {
    public let process: String?
    public let originCode: String?
    public let originNameAr: String?
    public let flavorNotes: [String]
    public let roastLevel: RoastLevel?

    public init(process: String?, originCode: String?, originNameAr: String?, flavorNotes: [String], roastLevel: RoastLevel?) {
        self.process = process; self.originCode = originCode; self.originNameAr = originNameAr
        self.flavorNotes = flavorNotes; self.roastLevel = roastLevel
    }

    public var isEmpty: Bool { process == nil && originCode == nil && flavorNotes.isEmpty && roastLevel == nil }
}

/// The admin's answers for one card, starting from what it has.
public struct QueueEdit: Equatable, Sendable {
    public let card: RemoteQueueCard
    public var originCode: String?
    public var originNameAr: String
    public var process: String?
    public var flavorNotes: [String]
    public var roastLevel: RoastLevel?

    public init(_ card: RemoteQueueCard) {
        self.card = card
        let origin = card.originCode.flatMap(ReferenceCodes.country) ?? card.originName.flatMap(ApprovalForm.country(matching:))
        originCode = origin?.code == "XB" ? nil : origin?.code
        originNameAr = originCode == nil ? "" : origin?.nameAr ?? card.originName ?? ""
        process = card.process == "OTHER" ? nil : card.process.flatMap { ReferenceCodes.process($0)?.code }
        flavorNotes = card.flavorNotes
        roastLevel = card.roastLevel.flatMap(RoastLevel.init(rawValue:)) ?? RoastLevel.allCases.first { $0.nameAr == card.roastLevel }
    }

    public mutating func setOrigin(code: String?) {
        originCode = code
        originNameAr = code.flatMap(ReferenceCodes.country)?.nameAr ?? ""
    }

    /// Takes one suggested detail (or all of them).
    public mutating func apply(_ s: RemoteDetailSuggestion) {
        if let p = s.process { process = p }
        if let code = s.originCode { originCode = code; originNameAr = ReferenceCodes.country(code)?.nameAr ?? s.originNameAr ?? code }
        if !s.flavorNotes.isEmpty { flavorNotes = s.flavorNotes }
        if let r = s.roastLevel { roastLevel = r }
    }

    /// Still missing after the admin's answers.
    public var stillMissing: [RemoteQueueCard.Missing] {
        var out: [RemoteQueueCard.Missing] = []
        if originCode == nil { out.append(.origin) }
        if process == nil { out.append(.process) }
        if flavorNotes.isEmpty { out.append(.notes) }
        return out
    }

    /// For a suggestion: publish with what's set. No origin is a blend, no process "other".
    public func approvalPayload() -> [String: Any] {
        var body: [String: Any] = [
            "nameAr": card.name, "name": card.nameEn ?? "", "roasterNameAr": card.roasterName, "roasterName": "",
            "originCode": originCode ?? "XB", "originNameAr": originCode == nil ? "مزيج" : originNameAr,
            "process": process ?? "OTHER", "flavorNotes": flavorNotes,
        ]
        if let roastLevel { body["roastLevel"] = roastLevel.rawValue }
        return body
    }

    /// For a published coffee: only what changed.
    public func lotChanges() -> [String: Any] {
        let start = QueueEdit(card)
        var body: [String: Any] = [:]
        if originCode != start.originCode, let originCode { body["originCode"] = originCode; body["originNameAr"] = originNameAr }
        if process != start.process, let process { body["process"] = process }
        if flavorNotes != start.flavorNotes { body["flavorNotes"] = flavorNotes }
        if roastLevel != start.roastLevel, let roastLevel { body["roastLevel"] = roastLevel.nameAr }
        return body
    }
}

extension CatalogAPIClient {
    private func queueGet<T: Decodable>(_ type: T.Type, _ path: String, _ token: String) async throws -> T {
        let response = try await transport.send(HTTPRequest(method: .get, path: path, bearer: token))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func queueCounts(accessToken: String) async throws -> RemoteQueueCounts {
        try await queueGet(RemoteQueueCounts.self, "/api/v1/admin/queue", accessToken)
    }

    public func queueRoasters(_ kind: QueueKind, accessToken: String) async throws -> [RemoteRoasterGroup] {
        struct Wrapper: Decodable { let roasters: [RemoteRoasterGroup] }
        return try await queueGet(Wrapper.self, "/api/v1/admin/queue/roasters?kind=\(kind.rawValue)", accessToken).roasters
    }

    public func queueItems(_ kind: QueueKind, roaster: String?, accessToken: String) async throws -> [RemoteQueueCard] {
        var path = "/api/v1/admin/queue/items?kind=\(kind.rawValue)"
        if let roaster {
            path += "&roaster=" + (roaster.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+="))) ?? "")
        }
        struct Wrapper: Decodable { let items: [RemoteQueueCard] }
        return try await queueGet(Wrapper.self, path, accessToken).items
    }

    public func suggestDetails(for card: RemoteQueueCard, accessToken: String) async throws -> RemoteDetailSuggestion {
        let data = (try? JSONSerialization.data(withJSONObject: ["kind": card.kind.rawValue, "id": card.id])) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/queue/suggest", body: data, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteDetailSuggestion.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Publishes a waiting suggestion with the admin's answers; returns the lot's slug.
    public func approve(_ edit: QueueEdit, accessToken: String) async throws -> String {
        let data = (try? JSONSerialization.data(withJSONObject: edit.approvalPayload())) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/admin/submissions/\(edit.card.id)/approve", body: data, bearer: accessToken))
        try Self.checkContract(response)
        struct Approved: Decodable { let lotSlug: String }
        do { return try JSONDecoder().decode(Approved.self, from: response.body).lotSlug }
        catch { throw AuthClientError.malformedResponse }
    }
}
