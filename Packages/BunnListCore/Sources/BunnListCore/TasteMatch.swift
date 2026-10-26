import Foundation

/// "تناسبك ٨٧٪" (/api/v1/catalog/lots/[slug]/match): how well a coffee fits the
/// caller's own ratings, with reasons. `score` is nil until enough ratings.
public struct RemoteTasteMatch: Codable, Equatable, Sendable {
    public struct Reason: Codable, Equatable, Sendable, Hashable {
        public let positive: Bool
        public let text: String
    }

    public let score: Int?
    public let ratedCount: Int
    public let needed: Int
    public let reasons: [Reason]
    public let myRating: Int?

    /// A word for the score band.
    public var verdictAr: String? {
        guard let score else { return nil }
        switch score {
        case 85...: return "على ذوقك تمامًا"
        case 70..<85: return "تناسبك"
        case 50..<70: return "تستاهل تجربة"
        default: return "غالبًا مو على ذوقك"
        }
    }
}

extension CatalogAPIClient {
    public func fetchTasteMatch(slug: String, accessToken: String) async throws -> RemoteTasteMatch {
        let path = "/api/v1/catalog/lots/" + (slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug) + "/match"
        let response = try await transport.send(HTTPRequest(method: .get, path: path, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteTasteMatch.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
