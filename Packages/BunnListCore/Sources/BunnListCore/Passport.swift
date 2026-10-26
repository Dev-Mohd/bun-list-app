import Foundation

/// "جواز القهوة" (/api/v1/me/passport): a stamp per origin someone has tasted
/// and badges with progress toward each.
public struct RemotePassport: Codable, Equatable, Sendable {
    public struct Stamp: Codable, Equatable, Sendable, Identifiable {
        public let code: String
        public let nameAr: String
        public let region: String?
        public let count: Int
        public let firstAt: String
        public var id: String { code }

        public var firstDate: Date? { ISO8601DateFormatter.withFraction.date(from: firstAt) ?? ISO8601DateFormatter().date(from: firstAt) }
    }

    public struct Badge: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let titleAr: String
        public let detailAr: String
        public let icon: String
        public let current: Int
        public let goal: Int
        public let earned: Bool

        public var progress: Double { goal > 0 ? min(1, Double(current) / Double(goal)) : 0 }
    }

    public let coffees: Int
    public let countries: Int
    public let regions: Int
    public let processes: Int
    public let stamps: [Stamp]
    public let badges: [Badge]

    public var earnedCount: Int { badges.filter(\.earned).count }

    /// Arabic names for the server's region codes.
    public static func regionNameAr(_ code: String?) -> String {
        switch code {
        case "africa": return "أفريقيا"
        case "americas": return "أمريكا اللاتينية"
        case "arabia": return "الجزيرة العربية"
        case "asia": return "آسيا"
        default: return "أخرى"
        }
    }
}

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

extension CatalogAPIClient {
    public func fetchPassport(accessToken: String) async throws -> RemotePassport {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/me/passport", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemotePassport.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
