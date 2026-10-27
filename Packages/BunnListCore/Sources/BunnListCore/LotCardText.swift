import Foundation

extension FlavorFamily {
    /// The family that colors a coffee's card: its first note with a family, or
    /// `.other` when no note has one.
    public static func dominant(_ notes: [String]) -> FlavorFamily {
        notes.lazy.map(of).first { $0 != .other } ?? .other
    }
}

extension ReferenceCodes {
    /// The flag emoji for an ISO country code; nil for blends and anything not
    /// two letters.
    public static func flag(_ code: String?) -> String? {
        guard let code = code?.uppercased(), code.count == 2, code != "XB",
              code.unicodeScalars.allSatisfy({ ("A"..."Z").contains(Character($0)) }) else { return nil }
        return code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
    }
}

extension RemoteLot {
    /// One glanceable line for a card: "🇪🇹 لاهوائية · خوخ، أناناس".
    public var cardLine: String {
        let notes = flavorNotes.prefix(2).joined(separator: "، ")
        let head = [ReferenceCodes.flag(originCode), processNameAr].compactMap { $0 }.joined(separator: " ")
        return [head, notes].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension FlavorFamily {
    /// The distinct families in a coffee's notes, in order, for the card's flavor
    /// strip; at most `limit`.
    public static func spectrum(_ notes: [String], limit: Int = 4) -> [FlavorFamily] {
        var seen: [FlavorFamily] = []
        for family in notes.map(of) where family != .other && !seen.contains(family) {
            seen.append(family)
            if seen.count == limit { break }
        }
        return seen
    }
}

/// Match scores for many cards (/api/v1/catalog/match): empty, with `needed`
/// ratings to go, until the account has rated enough.
public struct RemoteMatchScores: Codable, Equatable, Sendable {
    public let scores: [String: Int]
    public let needed: Int
}

extension CatalogAPIClient {
    public func fetchMatchScores(slugs: [String], accessToken: String) async throws -> RemoteMatchScores {
        let list = slugs.prefix(60).joined(separator: ",")
        let q = list.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+="))) ?? ""
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/catalog/match?slugs=\(q)", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteMatchScores.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
