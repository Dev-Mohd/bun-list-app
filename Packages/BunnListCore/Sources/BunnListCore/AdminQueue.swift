import Foundation

// The admin's work queue (/api/v1/admin/queue): what waits for review and the
// published coffees missing details, counted, grouped by roaster, served one card
// at a time, with details read from the coffee's own description to offer.

public enum QueueKind: String, Sendable, Hashable {
    /// Suggestions waiting for review.
    case pending
    /// Published coffees missing origin, process or notes.
    case incomplete
    /// Every published coffee, to go over the photos roaster by roaster.
    case photos
}

public struct RemoteQueueCounts: Codable, Equatable, Sendable {
    public let pending: Int
    public let incomplete: Int
    public let noOrigin: Int
    public let noProcess: Int
    public let noNotes: Int
    public let noPhoto: Int
    public let reports: Int
    /// Published coffees (older servers leave it out).
    public let published: Int?
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
    /// The roaster's English name, when one is set.
    public let roasterNameEn: String?
    public let imageUrl: String?
    public let originName: String?
    public let originCode: String?
    public let process: String?
    public let roastLevel: String?
    public let flavorNotes: [String]
    public let descriptionAr: String?
    public let sourceUrl: String?
    public let missing: [Missing]
    /// A suggestion whose photo was edited or deleted, with the original kept to bring back.
    public let hasOriginalPhoto: Bool?
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
            "nameAr": card.name, "name": card.nameEn ?? "", "roasterNameAr": card.roasterName, "roasterName": card.roasterNameEn ?? "",
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

// MARK: Photo tools, bulk edit, roaster English name

/// Part of a photo to keep, as fractions of its width and height.
public struct PhotoCrop: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public static let whole = PhotoCrop(x: 0, y: 0, w: 1, h: 1)

    /// From insets (each 0–0.45) off the four sides.
    public init(top: Double, bottom: Double, leading: Double, trailing: Double) {
        let clamp = { (v: Double) in min(max(v, 0), 0.45) }
        x = clamp(leading); y = clamp(top)
        w = max(0.1, 1 - clamp(leading) - clamp(trailing)); h = max(0.1, 1 - clamp(top) - clamp(bottom))
    }

    var isWhole: Bool { x <= 0.001 && y <= 0.001 && w >= 0.999 && h >= 0.999 }
    var json: [String: Double] { ["x": x, "y": y, "w": w, "h": h] }
}

/// How a photo edit should go: how close to the backdrop colour still counts as backdrop, and the crop.
public struct PhotoEdit: Equatable, Sendable {
    /// 0–100.
    public var sensitivity: Double = 50
    public var crop: PhotoCrop = .whole
    /// False: crop and square only, the backdrop stays.
    public var removeBackground = true
    public init() {}

    func body(_ action: String, _ card: RemoteQueueCard) -> [String: Any] {
        var b: [String: Any] = ["action": action, "kind": card.kind.rawValue, "id": card.id,
                                "sensitivity": sensitivity.rounded(), "removeBackground": removeBackground]
        if !crop.isWhole { b["crop"] = crop.json }
        return b
    }
}

/// A cut done on the server but not saved: the JPEG to show, and a warning when it looks off.
public struct RemotePhotoPreview: Codable, Equatable, Sendable {
    public let imageBase64: String
    public let foreground: Double
    public let warningAr: String?
    public var imageData: Data? { Data(base64Encoded: imageBase64) }
}

/// A roaster-wide cut run: how many went, the ones left as they were (and why), and how many wait for the next run.
public struct RemoteRoasterCut: Codable, Equatable, Sendable {
    public let done: Int
    public let failed: [RemoteBulkReview.Failure]
    public let remaining: Int
}

/// What a bulk edit sets; nil leaves a field as it is.
public struct BulkEdit: Equatable, Sendable {
    public var originCode: String?
    public var process: String?
    public var roastLevel: RoastLevel?
    public var addNotes: [String] = []
    public init() {}

    public var isEmpty: Bool { originCode == nil && process == nil && roastLevel == nil && addNotes.isEmpty }

    public func payload() -> [String: Any] {
        var set: [String: Any] = [:]
        if let originCode {
            set["originCode"] = originCode
            set["originNameAr"] = ReferenceCodes.country(originCode)?.nameAr ?? originCode
        }
        if let process { set["process"] = process }
        if let roastLevel { set["roastLevel"] = roastLevel.rawValue }
        if !addNotes.isEmpty { set["addNotes"] = addNotes }
        return set
    }
}

extension CatalogAPIClient {
    private func adminPost<T: Decodable>(_ type: T.Type, _ path: String, _ body: [String: Any], _ token: String) async throws -> T {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: path, body: data, bearer: token))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    private struct PhotoURL: Decodable { let imageUrl: String? }

    /// Cuts (or crops) the card's photo on the server and returns it without saving.
    public func previewPhoto(_ card: RemoteQueueCard, _ edit: PhotoEdit, accessToken: String) async throws -> RemotePhotoPreview {
        try await adminPost(RemotePhotoPreview.self, "/api/v1/admin/photos", edit.body("preview", card), accessToken)
    }

    /// Saves the cut as the card's photo; returns a URL to show it.
    public func applyPhoto(_ card: RemoteQueueCard, _ edit: PhotoEdit, accessToken: String) async throws -> String? {
        try await adminPost(PhotoURL.self, "/api/v1/admin/photos", edit.body("apply", card), accessToken).imageUrl
    }

    public func deletePhoto(_ card: RemoteQueueCard, accessToken: String) async throws {
        _ = try await adminPost(PhotoURL.self, "/api/v1/admin/photos", ["action": "delete", "kind": card.kind.rawValue, "id": card.id], accessToken)
    }

    /// Brings back a suggestion's original photo; returns a URL to show it.
    public func restorePhoto(_ card: RemoteQueueCard, accessToken: String) async throws -> String? {
        try await adminPost(PhotoURL.self, "/api/v1/admin/photos", ["action": "restore", "kind": card.kind.rawValue, "id": card.id], accessToken).imageUrl
    }

    /// Lifts the backdrop off a roaster's photos not edited yet (its waiting suggestions, or its
    /// published coffees); repeat while `remaining` > 0.
    public func cutRoasterPhotos(_ roaster: String, kind: RemoteQueueCard.Kind = .submission, sensitivity: Double,
                                 accessToken: String) async throws -> RemoteRoasterCut {
        try await adminPost(RemoteRoasterCut.self, "/api/v1/admin/photos",
                            ["action": "roaster", "roaster": roaster, "kind": kind.rawValue, "sensitivity": sensitivity.rounded()], accessToken)
    }

    /// Sets the same details on many cards (all suggestions, or all published coffees); returns how many changed.
    public func bulkEdit(_ kind: RemoteQueueCard.Kind, ids: [String], _ edit: BulkEdit, accessToken: String) async throws -> Int {
        struct Updated: Decodable { let updated: Int }
        return try await adminPost(Updated.self, "/api/v1/admin/queue/bulk-edit",
                                   ["kind": kind.rawValue, "ids": ids, "set": edit.payload()], accessToken).updated
    }

    /// A roaster's English name, for its published record and all its suggestions; returns how many suggestions changed.
    public func setRoasterEnglishName(_ roasterAr: String, nameEn: String, accessToken: String) async throws -> Int {
        struct Renamed: Decodable { let roasters: Int; let suggestions: Int }
        return try await adminPost(Renamed.self, "/api/v1/admin/roasters/name", ["roasterAr": roasterAr, "nameEn": nameEn], accessToken).suggestions
    }
}

/// One run of «approve everything»: what went through, what didn't (and why), and how many are left.
public struct RemoteApproveAll: Codable, Equatable, Sendable {
    public let done: [String]
    public let failed: [RemoteBulkReview.Failure]
    public let remaining: Int
}

extension CatalogAPIClient {
    /// Publishes waiting suggestions as they stand (all, or one roaster's); call again while `remaining` > 0,
    /// passing the ids that failed so far in `skip`.
    public func approveAllSuggestions(roaster: String? = nil, skip: [String], accessToken: String) async throws -> RemoteApproveAll {
        var body: [String: Any] = ["skip": skip]
        if let roaster { body["roaster"] = roaster }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/submissions/approve-all", body: data, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteApproveAll.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}

// MARK: Duplicate coffees

/// One side of a likely duplicate.
public struct RemoteDuplicateSide: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let slug: String
    public let nameAr: String
    public let name: String
    public let imageUrl: String?
    public let originName: String?
    public let process: String
    public let flavorNotes: [String]
    /// People's reviews, brews, recipes and shelf entries on it.
    public let used: Int
}

/// Two published coffees of one roaster that look like the same coffee.
public struct RemoteDuplicatePair: Codable, Equatable, Sendable, Identifiable {
    public var id: String { a.id < b.id ? "\(a.id)|\(b.id)" : "\(b.id)|\(a.id)" }
    public let roaster: String
    public let score: Double
    public let a: RemoteDuplicateSide
    public let b: RemoteDuplicateSide
    /// The one the server suggests keeping.
    public let keepId: String

    public func other(than id: String) -> RemoteDuplicateSide { id == a.id ? b : a }
}

extension CatalogAPIClient {
    public func duplicatePairs(accessToken: String) async throws -> [RemoteDuplicatePair] {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/admin/duplicates", bearer: accessToken))
        try Self.checkContract(response)
        struct Wrapper: Decodable { let pairs: [RemoteDuplicatePair] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).pairs }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Merges `dropId` into `keepId` (details, people's records and its link move over).
    public func mergeDuplicate(keepId: String, dropId: String, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: ["keepId": keepId, "dropId": dropId])) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/duplicates/merge", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }

    /// Two different coffees: not offered as duplicates again.
    public func dismissDuplicate(_ pair: RemoteDuplicatePair, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: ["lotA": pair.a.id, "lotB": pair.b.id])) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/duplicates/dismiss", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }
}
