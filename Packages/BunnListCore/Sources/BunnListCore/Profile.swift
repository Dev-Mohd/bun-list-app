import Foundation

// The signed-in account's profile and first-run setup (/api/v1/me/...).

public struct RemoteProfile: Codable, Equatable, Sendable {
    public let username: String?
    public let displayName: String?
    public let bio: String?
    public let avatarUrl: String?
    public let onboarded: Bool
    public let hideFromLeaderboard: Bool?
    /// What they picked at signup («وش تحب في قهوتك؟»); nil from older servers.
    public var tastePrefs: [String]? = nil
    public var brewPrefs: [String]? = nil
    /// «مبدع مؤسس» and their linked accounts; nil from older servers.
    public var founder: FounderBadge? = nil
    public var socials: Socials? = nil
}

/// The signup taste question: flavour families and how they brew. The catalog's
/// «لك» order puts coffees close to these first.
public enum TastePrefs {
    public static let families: [FlavorFamily] = [.berry, .citrus, .stoneFruit, .tropical, .floral, .chocolate, .caramel, .nutty, .spice, .tea, .honey, .driedFruit]

    public struct Brew: Equatable, Sendable, Identifiable {
        public var id: String { code }
        public let code: String
        public let nameAr: String
        public let symbol: String
    }

    public static let brews: [Brew] = [
        .init(code: "V60", nameAr: "V60", symbol: "drop.fill"),
        .init(code: "ESPRESSO", nameAr: "إسبريسو", symbol: "cup.and.saucer.fill"),
        .init(code: "CHEMEX", nameAr: "كيمكس", symbol: "flask.fill"),
        .init(code: "AEROPRESS", nameAr: "إيروبرس", symbol: "arrow.down.to.line"),
        .init(code: "FRENCH_PRESS", nameAr: "فرنش برس", symbol: "mug.fill"),
        .init(code: "COLD_BREW", nameAr: "كولد برو", symbol: "snowflake"),
    ]
}

public enum ProfileRules {
    public static let maxDisplayName = 40
    public static let maxBio = 160
}

extension CatalogAPIClient {
    /// Sets the display name and/or bio; nil leaves a field unchanged, "" clears the bio.
    public func updateProfile(displayName: String?, bio: String?, hideFromLeaderboard: Bool? = nil,
                              accessToken: String) async throws -> RemoteProfile {
        var body: [String: Any] = [:]
        if let hideFromLeaderboard { body["hideFromLeaderboard"] = hideFromLeaderboard }
        if let displayName { body["displayName"] = displayName }
        if let bio { body["bio"] = bio }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .patch, path: "/api/v1/me/profile", body: data, bearer: accessToken)
        )
        return try Self.decodeProfile(response)
    }

    /// Saves the signup taste picks (flavour family codes and brew method codes).
    public func updateTastePrefs(families: [FlavorFamily], brews: [String], accessToken: String) async throws -> RemoteProfile {
        let body: [String: Any] = [
            "tastePrefs": families.filter { $0 != .other }.map(\.rawValue),
            "brewPrefs": brews,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .patch, path: "/api/v1/me/profile", body: data, bearer: accessToken)
        )
        return try Self.decodeProfile(response)
    }

    /// Uploads a square JPEG (≤ 2 MB) as the profile picture.
    public func uploadAvatar(jpeg: Data, accessToken: String) async throws -> RemoteProfile {
        let data = (try? JSONSerialization.data(withJSONObject: ["imageBase64": jpeg.base64EncodedString()])) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .put, path: "/api/v1/me/avatar", body: data, bearer: accessToken)
        )
        return try Self.decodeProfile(response)
    }

    public func removeAvatar(accessToken: String) async throws -> RemoteProfile {
        let response = try await transport.send(HTTPRequest(method: .delete, path: "/api/v1/me/avatar", bearer: accessToken))
        return try Self.decodeProfile(response)
    }

    /// A valid, free username to pre-fill first-run setup.
    public func suggestUsername(accessToken: String) async throws -> String {
        let response = try await transport.send(
            HTTPRequest(method: .get, path: "/api/v1/me/username/suggest", bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Suggestion: Decodable { let username: String }
        do { return try JSONDecoder().decode(Suggestion.self, from: response.body).username }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Records that first-run setup is done (or skipped) for this account.
    public func markOnboarded(accessToken: String) async throws {
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/me/onboarded", bearer: accessToken))
        try Self.checkContract(response)
    }

    private static func decodeProfile(_ response: HTTPResponse) throws -> RemoteProfile {
        try checkContract(response)
        do { return try JSONDecoder().decode(RemoteProfile.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}

/// Everything the profile tab shows (/api/v1/me/summary).
public struct RemoteProfileSummary: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public let owned: Int
        public let favorite: Int
        public let wantsToTry: Int
        public let tried: Int
    }

    public struct TasteGroup: Codable, Equatable, Sendable, Hashable {
        public let name: String
        public let count: Int
        public let average: Double
    }

    public struct Taste: Codable, Equatable, Sendable {
        public let unlocked: Bool
        public let progress: Int
        public let required: Int
        public let averageRating: Double?
        public let topOrigins: [TasteGroup]
        public let topProcesses: [TasteGroup]
        public let topFlavors: [String]
        public let favoriteMethod: String?
    }

    public let collection: Counts
    public let recentBags: [String]
    public let discoveries: Int
    public let submissions: Int
    public let recipes: Int
    public let experiences: Int
    public let ratings: Int
    /// Missing from older servers.
    public let followers: Int?
    public let following: Int?
    /// People waiting to follow a private account. Missing from older servers.
    public let followRequests: Int?
    public let taste: Taste
}

extension CatalogAPIClient {
    public func fetchProfileSummary(accessToken: String) async throws -> RemoteProfileSummary {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/me/summary", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteProfileSummary.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
