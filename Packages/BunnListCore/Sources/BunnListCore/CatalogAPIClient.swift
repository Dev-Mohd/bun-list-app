import Foundation

// Read-only catalog feed client for the app, matching GET /api/v1/catalog/lots.
// Pure Foundation over the injected HTTPTransport, so it runs under `swift test`.

/// One published coffee lot as the server sends it. Display-oriented, Arabic-first.
public struct RemoteLot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let slug: String
    public let name: String
    public let nameAr: String
    public let roasterNameAr: String
    public let originNameAr: String?
    public let originCode: String?
    public let process: String
    public let processLabel: String?
    public let flavorNotes: [String]
    public let roastLevel: String?
    public let averageRating: Double
    public let reviewCount: Int
    public let imageUrl: String?
    /// Who discovered it (home feed only; nil elsewhere and for catalog additions).
    public let discoveredBy: String?

    public init(id: String, slug: String, name: String, nameAr: String, roasterNameAr: String,
                originNameAr: String?, originCode: String?, process: String, processLabel: String?,
                flavorNotes: [String], roastLevel: String?, averageRating: Double, reviewCount: Int, imageUrl: String?,
                discoveredBy: String? = nil) {
        self.id = id; self.slug = slug; self.name = name; self.nameAr = nameAr
        self.roasterNameAr = roasterNameAr; self.originNameAr = originNameAr; self.originCode = originCode
        self.process = process; self.processLabel = processLabel; self.flavorNotes = flavorNotes
        self.roastLevel = roastLevel; self.averageRating = averageRating; self.reviewCount = reviewCount; self.imageUrl = imageUrl
        self.discoveredBy = discoveredBy
    }
}

/// Per-brew-method rating summary for a lot.
public struct RemoteBrewStat: Codable, Equatable, Sendable, Identifiable {
    public var id: String { method }
    public let method: String
    public let averageRating: Double
    public let reviewCount: Int
    public let wouldBuyAgain: Int

    public init(method: String, averageRating: Double, reviewCount: Int, wouldBuyAgain: Int) {
        self.method = method; self.averageRating = averageRating
        self.reviewCount = reviewCount; self.wouldBuyAgain = wouldBuyAgain
    }
}

/// A single published lot with its full detail (GET /api/v1/catalog/lots/[slug]).
public struct RemoteLotDetail: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let slug: String
    public let name: String
    public let nameAr: String
    public let roasterNameAr: String
    public let originNameAr: String?
    public let originCode: String?
    public let process: String
    public let processLabel: String?
    public let flavorNotes: [String]
    public let roastLevel: String?
    public let averageRating: Double
    public let reviewCount: Int
    public let imageUrl: String?
    public let descriptionAr: String?
    public let regionAr: String?
    public let variety: String?
    public let recommendedBrewMethods: [String]
    public let brewStats: [RemoteBrewStat]
    /// The account whose suggestion became this lot, while that account exists.
    public let discoveredBy: String?
    /// Their @username, for opening their profile.
    public let discoveredByUsername: String?
    /// Who discovered it, with their public note. Missing from older servers.
    public let discoverer: RemoteDiscoverer?
    /// How people use it. Missing from older servers.
    public let community: RemoteLotCommunity?
    /// Labels such as "luxury"; missing from older servers.
    public let tags: [RemoteLotTag]?
}

public struct RemoteLotTag: Codable, Equatable, Sendable, Hashable {
    public let tag: String
    public let note: String?
}

public struct RemoteDiscoverer: Codable, Equatable, Sendable {
    public let name: String
    public let username: String?
    public let avatarUrl: String?
    public let note: String?
}

public struct RemoteLotCommunity: Codable, Equatable, Sendable {
    public struct Method: Codable, Equatable, Sendable, Hashable {
        public let method: String
        public let count: Int
    }

    public let collectors: Int
    public let brewers: Int
    public let methods: [Method]
}

public struct CatalogAPIClient: Sendable {
    private struct Feed: Decodable { let lots: [RemoteLot] }

    let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    /// GET /api/v1/catalog/lots — the published lots, or empty if none are published yet.
    public func fetchLots() async throws -> [RemoteLot] {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/catalog/lots"))
        guard (200..<300).contains(response.status) else {
            throw AuthClientError.server(status: response.status)
        }
        do {
            return try JSONDecoder().decode(Feed.self, from: response.body).lots
        } catch {
            throw AuthClientError.malformedResponse
        }
    }

    /// GET /api/v1/catalog/search?q=... — search published lots (name / roaster).
    /// Newest community discoveries for the home screen (public).
    public func fetchDiscoveries() async throws -> [RemoteLot] {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/catalog/discoveries"))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(Feed.self, from: response.body).lots }
        catch { throw AuthClientError.malformedResponse }
    }

    public func searchLots(query: String) async throws -> [RemoteLot] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/catalog/search?q=\(encoded)"))
        guard (200..<300).contains(response.status) else {
            throw AuthClientError.server(status: response.status)
        }
        struct Wrapper: Decodable { let lots: [RemoteLot] }
        do {
            return try JSONDecoder().decode(Wrapper.self, from: response.body).lots
        } catch {
            throw AuthClientError.malformedResponse
        }
    }

    /// GET /api/v1/catalog/lots/[slug] — one lot's full detail.
    public func fetchLotDetail(slug: String) async throws -> RemoteLotDetail {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/catalog/lots/\(slug)"))
        guard (200..<300).contains(response.status) else {
            throw AuthClientError.server(status: response.status)
        }
        do {
            return try JSONDecoder().decode(RemoteLotDetail.self, from: response.body)
        } catch {
            throw AuthClientError.malformedResponse
        }
    }

    /// GET /api/v1/catalog/lots/[slug]/reviews — public: the lot's published reviews.
    /// A token adds which reviews you marked helpful.
    public func fetchReviews(slug: String, accessToken: String? = nil) async throws -> [RemoteReview] {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/catalog/lots/\(slug)/reviews", bearer: accessToken))
        guard (200..<300).contains(response.status) else {
            throw AuthClientError.server(status: response.status)
        }
        struct Wrapper: Decodable { let reviews: [RemoteReview] }
        do {
            return try JSONDecoder().decode(Wrapper.self, from: response.body).reviews
        } catch {
            throw AuthClientError.malformedResponse
        }
    }

    /// POST /api/v1/catalog/lots/[slug]/review — create/update the caller's review.
    /// Contract statuses map to APIError (401 so the caller can refresh + retry).
    public func submitReview(
        slug: String, accessToken: String,
        rating: Int, brewMethod: String, wouldBuyAgain: Bool, body: String?
    ) async throws -> RemoteReviewResult {
        var payload: [String: Any] = ["rating": rating, "brewMethod": brewMethod, "wouldBuyAgain": wouldBuyAgain]
        if let body, !body.isEmpty { payload["body"] = body }
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/catalog/lots/\(slug)/review", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do {
            return try JSONDecoder().decode(RemoteReviewResult.self, from: response.body)
        } catch {
            throw AuthClientError.malformedResponse
        }
    }

    /// GET /api/v1/catalog/lots/[slug]/review — the caller's existing review, or nil.
    public func fetchMyReview(slug: String, accessToken: String) async throws -> RemoteMyReview? {
        let response = try await transport.send(
            HTTPRequest(method: .get, path: "/api/v1/catalog/lots/\(slug)/review", bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Wrapper: Decodable { let review: RemoteMyReview? }
        do {
            return try JSONDecoder().decode(Wrapper.self, from: response.body).review
        } catch {
            throw AuthClientError.malformedResponse
        }
    }

    /// GET /api/v1/catalog/lots/[slug]/collection — the caller's flags for one lot.
    public func fetchCollectionFlags(slug: String, accessToken: String) async throws -> RemoteCollectionFlags {
        let response = try await transport.send(
            HTTPRequest(method: .get, path: "/api/v1/catalog/lots/\(slug)/collection", bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteCollectionFlags.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// PUT /api/v1/catalog/lots/[slug]/collection — set the caller's flags for one lot.
    public func updateCollectionFlags(
        slug: String, accessToken: String,
        owned: Bool, favorite: Bool, wantsToTry: Bool, tried: Bool
    ) async throws -> RemoteCollectionFlags {
        let payload: [String: Any] = ["owned": owned, "favorite": favorite, "wantsToTry": wantsToTry, "tried": tried]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .put, path: "/api/v1/catalog/lots/\(slug)/collection", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteCollectionFlags.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// GET /api/v1/collection — the caller's whole collection.
    public func fetchCollection(accessToken: String) async throws -> [RemoteCollectionItem] {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/collection", bearer: accessToken))
        try Self.checkContract(response)
        struct Wrapper: Decodable { let entries: [RemoteCollectionItem] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).entries }
        catch { throw AuthClientError.malformedResponse }
    }

    /// POST /api/v1/submissions — suggest a new coffee for review. Returns its id.
    public func submitCoffee(
        name: String, roasterName: String, originName: String?, note: String?, accessToken: String
    ) async throws -> String {
        var payload: [String: Any] = ["name": name, "roasterName": roasterName]
        if let originName, !originName.isEmpty { payload["originName"] = originName }
        if let note, !note.isEmpty { payload["note"] = note }
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/submissions", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Created: Decodable { let id: String }
        do {
            return try JSONDecoder().decode(Created.self, from: response.body).id
        } catch {
            throw AuthClientError.malformedResponse
        }
    }

    /// Maps the shared error contract (401/403/409/422/429) to APIError, other non-2xx to AuthClientError.
    /// The caller's non-deleted brew experiences for a lot, newest brew first.
    public func fetchMyExperiences(slug: String, accessToken: String) async throws -> [RemoteExperience] {
        let response = try await transport.send(
            HTTPRequest(method: .get, path: "/api/v1/catalog/lots/\(slug)/experiences", bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Wrapper: Decodable { let experiences: [RemoteExperience] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).experiences }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Create, or edit by `clientID` (idempotent). `publish` also publishes a draft.
    public func saveExperience(
        slug: String, accessToken: String, clientID: String,
        methodCode: String, stars: Int, brewedAt: Date, note: String, publish: Bool, log: BrewLogEntry? = nil
    ) async throws -> RemoteExperience {
        var payload: [String: Any] = [
            "clientId": clientID, "methodCode": methodCode, "stars": stars,
            "brewedAt": ISO8601DateFormatter().string(from: brewedAt), "note": note, "publish": publish,
        ]
        payload.merge(log?.payload ?? [:]) { current, _ in current }
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/catalog/lots/\(slug)/experiences", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteExperience.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Publish / unpublish / delete. An invalid transition is `APIError.conflict`.
    public func changeExperienceState(
        id: String, to state: RemoteExperience.State, accessToken: String
    ) async throws -> RemoteExperience {
        let data = (try? JSONSerialization.data(withJSONObject: ["state": state.rawValue])) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .patch, path: "/api/v1/experiences/\(id)", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteExperience.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    static func checkContract(_ response: HTTPResponse) throws {
        switch response.status {
        case 200..<300: return
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 409: throw APIError.conflict
        case 422: throw APIError.unprocessable
        case 429: throw APIError.rateLimited
        default: throw AuthClientError.server(status: response.status)
        }
    }
}

/// A published review of a lot by someone, for display.
public struct RemoteReview: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let rating: Int
    public let brewMethod: String
    public let wouldBuyAgain: Bool
    public let body: String?
    public let authorName: String
    public let createdAt: String
    /// Missing from older servers.
    public let helpfulCount: Int?
    public let markedHelpful: Bool?
    public let isMine: Bool?
    public let authorUsername: String?
}

/// The caller's review of a lot.
public struct RemoteMyReview: Codable, Equatable, Sendable {
    public let rating: Int
    public let brewMethod: String
    public let wouldBuyAgain: Bool
    public let body: String?

    public init(rating: Int, brewMethod: String, wouldBuyAgain: Bool, body: String?) {
        self.rating = rating; self.brewMethod = brewMethod; self.wouldBuyAgain = wouldBuyAgain; self.body = body
    }
}

/// The server's response after saving a review: updated aggregates + the saved review.
public struct RemoteReviewResult: Codable, Equatable, Sendable {
    public let averageRating: Double
    public let reviewCount: Int
    public let review: RemoteMyReview
}

/// The caller's collection flags for one lot.
public struct RemoteCollectionFlags: Codable, Equatable, Sendable {
    public let owned: Bool
    public let favorite: Bool
    public let wantsToTry: Bool
    public let tried: Bool

    public init(owned: Bool, favorite: Bool, wantsToTry: Bool, tried: Bool) {
        self.owned = owned; self.favorite = favorite; self.wantsToTry = wantsToTry; self.tried = tried
    }
}

/// One lot in the caller's collection (flags + enough to display it).
public struct RemoteCollectionItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { lotId }
    public let lotId: String
    public let slug: String
    public let nameAr: String
    public let roasterNameAr: String
    public let originNameAr: String?
    public let originCode: String?
    /// The bag picture, when the lot has one (older servers omit it).
    public let imageUrl: String?
    public let owned: Bool
    public let favorite: Bool
    public let wantsToTry: Bool
    public let tried: Bool
}

/// One of the caller's brew experiences on a server lot. Its stars rate this
/// attempt only, never the lot average.
public struct RemoteExperience: Codable, Equatable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable { case draft, published, unpublished, deleted }

    public let id: String
    public let clientId: String
    public let methodCode: String
    public let stars: Int
    public let brewedAt: String
    public let note: String
    public let state: State
    public let revision: Int
    /// What «حضّر» logged with it; nil for experiences written elsewhere.
    public let log: BrewLogEntry?

    public init(id: String, clientId: String, methodCode: String, stars: Int,
                brewedAt: String, note: String, state: State, revision: Int, log: BrewLogEntry? = nil) {
        self.id = id; self.clientId = clientId; self.methodCode = methodCode; self.stars = stars
        self.brewedAt = brewedAt; self.note = note; self.state = state; self.revision = revision; self.log = log
    }

    /// `brewedAt` parsed (server sends ISO-8601 with milliseconds).
    public var brewedDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: brewedAt) ?? ISO8601DateFormatter().date(from: brewedAt)
    }
}

extension RemoteLot {
    /// The process in Arabic: the lot's own label, else the name of its code ("OTHER" shows nothing).
    public var processNameAr: String? { ProcessText.name(label: processLabel, code: process) }
}

extension RemoteLotDetail {
    public var processNameAr: String? { ProcessText.name(label: processLabel, code: process) }
}

enum ProcessText {
    static func name(label: String?, code: String) -> String? {
        if let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty { return label }
        guard code != "OTHER" else { return nil }
        return ReferenceCodes.process(code)?.nameAr
    }
}
