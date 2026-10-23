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
}
