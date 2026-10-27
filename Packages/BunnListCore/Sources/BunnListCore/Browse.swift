import Foundation

/// The search tab's filters, sent to GET /api/v1/catalog/browse.
public struct BrowseFilters: Equatable, Sendable {
    public enum Sort: String, CaseIterable, Sendable {
        case ratingDesc = "rating_desc", ratingAsc = "rating_asc", newest, oldest, nameAsc = "name_asc", nameDesc = "name_desc"

        public var nameAr: String {
            switch self {
            case .ratingDesc: return "الأعلى تقييمًا"
            case .ratingAsc: return "الأقل تقييمًا"
            case .newest: return "الأحدث أولًا"
            case .oldest: return "الأقدم أولًا"
            case .nameAsc: return "الاسم (أ-ي)"
            case .nameDesc: return "الاسم (ي-أ)"
            }
        }
    }

    /// Which part of the catalog: everything, what I have, or what I don't have yet.
    public enum Shelf: String, CaseIterable, Sendable { case all, owned, missing }

    public var text = ""
    public var sort = Sort.ratingDesc
    public var origins: Set<String> = []
    public var roasters: Set<String> = []
    public var processes: Set<String> = []
    public var methods: Set<String> = []
    public var flavors: Set<FlavorFamily> = []
    /// Lot labels: "luxury", "infused", "decaf".
    public var tags: Set<String> = []
    public var shelf = Shelf.all
    public var favoritesOnly = false

    public init() {}

    /// Filters chosen in the sheet (not text, shelf or sort), for the badge on the filter button.
    public var activeCount: Int {
        origins.count + roasters.count + processes.count + methods.count + flavors.count + tags.count + (favoritesOnly ? 1 : 0)
    }

    /// Shelf and favorites need an account.
    public var needsAccount: Bool { shelf != .all || favoritesOnly }

    public func queryItems(offset: Int, limit: Int) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "sort", value: sort.rawValue)]
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.count >= 2 { items.append(URLQueryItem(name: "q", value: String(q.prefix(80)))) }
        func list(_ name: String, _ values: [String]) {
            if !values.isEmpty { items.append(URLQueryItem(name: name, value: values.sorted().joined(separator: ","))) }
        }
        list("origins", Array(origins))
        list("roasters", Array(roasters))
        list("processes", Array(processes))
        list("methods", Array(methods))
        list("flavors", flavors.map(\.rawValue))
        list("tags", Array(tags))
        if shelf != .all { items.append(URLQueryItem(name: "shelf", value: shelf.rawValue)) }
        if favoritesOnly { items.append(URLQueryItem(name: "favorites", value: "1")) }
        items.append(URLQueryItem(name: "offset", value: String(offset)))
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        return items
    }
}

extension FlavorFamily {
    public var nameAr: String {
        switch self {
        case .berry: return "توت وفواكه حمراء"
        case .citrus: return "حمضيات"
        case .stoneFruit: return "خوخ ومشمش"
        case .tropical: return "استوائي"
        case .driedFruit: return "فواكه مجففة"
        case .floral: return "زهري"
        case .chocolate: return "شوكولاتة"
        case .caramel: return "كراميل وسكري"
        case .nutty: return "مكسرات"
        case .spice: return "بهارات"
        case .tea: return "شاي وأعشاب"
        case .honey: return "عسل"
        case .other: return "أخرى"
        }
    }
}

public struct RemoteBrowsePage: Codable, Equatable, Sendable {
    public let lots: [RemoteLot]
    public let total: Int
}

public struct RemoteFacets: Codable, Equatable, Sendable {
    public struct Facet: Codable, Equatable, Sendable, Hashable, Identifiable {
        public var id: String { value }
        public let value: String
        public let labelAr: String
        public let count: Int
    }

    public let origins: [Facet]
    public let roasters: [Facet]
    public let processes: [Facet]
    public let methods: [Facet]
    public let flavors: [Facet]
}

extension CatalogAPIClient {
    public func browse(_ filters: BrowseFilters, offset: Int = 0, limit: Int = 40, accessToken: String?) async throws -> RemoteBrowsePage {
        var components = URLComponents()
        components.path = "/api/v1/catalog/browse"
        components.queryItems = filters.queryItems(offset: offset, limit: limit)
        // URLComponents leaves "+" and "," alone; both are fine for the server.
        let response = try await transport.send(HTTPRequest(method: .get, path: components.string ?? components.path, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteBrowsePage.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// GET /api/v1/catalog/top — the best-rated coffees.
    public func fetchTopRated() async throws -> [RemoteLot] {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/catalog/top"))
        try Self.checkContract(response)
        struct Wrapper: Decodable { let lots: [RemoteLot] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).lots }
        catch { throw AuthClientError.malformedResponse }
    }

    public func fetchFacets() async throws -> RemoteFacets {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/catalog/facets"))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteFacets.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
