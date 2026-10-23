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

    public init(id: String, slug: String, name: String, nameAr: String, roasterNameAr: String,
                originNameAr: String?, originCode: String?, process: String, processLabel: String?,
                flavorNotes: [String], roastLevel: String?, averageRating: Double, reviewCount: Int, imageUrl: String?) {
        self.id = id; self.slug = slug; self.name = name; self.nameAr = nameAr
        self.roasterNameAr = roasterNameAr; self.originNameAr = originNameAr; self.originCode = originCode
        self.process = process; self.processLabel = processLabel; self.flavorNotes = flavorNotes
        self.roastLevel = roastLevel; self.averageRating = averageRating; self.reviewCount = reviewCount; self.imageUrl = imageUrl
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
}

public struct CatalogAPIClient: Sendable {
    private struct Feed: Decodable { let lots: [RemoteLot] }

    private let transport: HTTPTransport

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

    /// Maps the shared error contract (401/403/409/422/429) to APIError, other non-2xx to AuthClientError.
    private static func checkContract(_ response: HTTPResponse) throws {
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
