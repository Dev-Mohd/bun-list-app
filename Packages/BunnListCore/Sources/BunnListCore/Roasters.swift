import Foundation

// Roaster pages (/api/v1/catalog/roasters...) and the producing-countries map
// (/api/v1/catalog/origins).

public struct RemoteShare: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let count: Int
}

public struct RemoteRoasterCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String { slug }
    public let slug: String
    public let nameAr: String
    public let name: String
    public let cityAr: String?
    public let lots: Int
    /// Reviews-weighted; 0 without reviews.
    public let averageRating: Double
    public let reviews: Int
    public let images: [String]
    public let followers: Int
}

public struct RemoteRoasterList: Codable, Equatable, Sendable {
    public let roasters: [RemoteRoasterCard]
    /// Slugs the caller follows.
    public let following: [String]
}

public struct RemoteRoasterPage: Codable, Equatable, Sendable {
    public let roaster: RemoteRoasterCard
    public var isFollowing: Bool
    public let origins: [RemoteShare]
    public let processes: [RemoteShare]
    /// FlavorFamily raw values.
    public let families: [RemoteShare]
    public let topRated: [RemoteLot]
    public let newest: [RemoteLot]
    public let lots: [RemoteLot]

    /// The families as whole percents of the shown ones (adding up to 100).
    public var familyShares: [(family: FlavorFamily, percent: Int)] {
        let known = families.compactMap { s in FlavorFamily(rawValue: s.key).map { ($0, s.count) } }
        let percents = LotCommunityStats.percentages(known.map(\.1))
        return zip(known, percents).map { ($0.0, $1) }.filter { $0.percent > 0 }
    }
}

public struct RemoteFollowState: Codable, Equatable, Sendable {
    public let following: Bool
    public let followers: Int
}

public struct RemoteOrigin: Codable, Equatable, Sendable, Identifiable {
    public var id: String { code }
    public let code: String
    public let nameAr: String
    public let nameEn: String?
    public let lots: Int
    public let roasters: Int
    public let averageRating: Double
    public let families: [RemoteShare]
    public let processes: [RemoteShare]
    public let regions: [String]
    /// Coffees from here they collected or rated; nil signed out.
    public let tried: Int?

    public var coordinate: OriginCentroids.Point? { OriginCentroids.point(code) }
}

public struct RemoteOrigins: Codable, Equatable, Sendable {
    public let origins: [RemoteOrigin]
    public let triedCountries: Int?

    /// «جرّبت من ٣ دول من ٢٣».
    public var progressLine: String? {
        guard let tried = triedCountries else { return nil }
        let all = origins.filter { $0.coordinate != nil }.count
        return "جرّبت من \(tried.formatted()) \(tried == 1 ? "دولة" : "دول") من \(all.formatted())"
    }
}

/// Where to put each producing country on the map (a point inside its coffee areas).
public enum OriginCentroids {
    public struct Point: Equatable, Sendable { public let lat: Double; public let lon: Double }

    private static let table: [String: (Double, Double)] = [
        "CO": (4.6, -75.6), "ET": (7.0, 38.6), "BR": (-19.5, -45.5), "CR": (9.9, -84.0), "SV": (13.8, -89.2),
        "YE": (15.3, 43.9), "UG": (1.0, 32.4), "ID": (-2.5, 112.0), "SA": (18.2, 42.5), "GT": (14.8, -91.0),
        "PE": (-9.2, -75.2), "PA": (8.8, -82.4), "IN": (12.4, 75.7), "RW": (-1.9, 29.9), "CN": (22.8, 100.9),
        "HN": (14.6, -87.6), "MX": (17.0, -96.7), "KE": (-0.4, 37.0), "TH": (19.9, 99.8), "NI": (13.0, -85.9),
        "PG": (-6.1, 145.4), "EC": (-1.8, -78.5), "MM": (21.0, 96.5), "TZ": (-3.4, 37.3), "BI": (-3.4, 29.9),
        "VN": (12.7, 108.2), "JM": (18.1, -76.7), "BO": (-16.3, -67.7), "CD": (-1.7, 29.2), "MW": (-11.4, 33.9),
        "ZM": (-10.3, 31.2), "LA": (15.1, 106.3), "PH": (16.4, 120.6), "DO": (19.0, -70.7), "HT": (18.9, -72.3),
        "TL": (-8.8, 125.6), "US": (19.6, -155.5), "CU": (20.0, -76.0), "VE": (8.6, -71.1), "CM": (5.9, 10.2),
    ]

    public static func point(_ code: String) -> Point? {
        table[code.uppercased()].map { Point(lat: $0.0, lon: $0.1) }
    }
}

extension CatalogAPIClient {
    public func fetchRoasters(accessToken: String?) async throws -> RemoteRoasterList {
        try await getJSON("/api/v1/catalog/roasters", accessToken: accessToken)
    }

    public func fetchRoaster(slug: String, accessToken: String?) async throws -> RemoteRoasterPage {
        try await getJSON("/api/v1/catalog/roasters/\(slug)", accessToken: accessToken)
    }

    public func setRoasterFollow(slug: String, follow: Bool, accessToken: String) async throws -> RemoteFollowState {
        let response = try await transport.send(
            HTTPRequest(method: follow ? .put : .delete, path: "/api/v1/catalog/roasters/\(slug)/follow", bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteFollowState.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func fetchOrigins(accessToken: String?) async throws -> RemoteOrigins {
        try await getJSON("/api/v1/catalog/origins", accessToken: accessToken)
    }

    private func getJSON<T: Decodable>(_ path: String, accessToken: String?) async throws -> T {
        let response = try await transport.send(HTTPRequest(method: .get, path: path, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
