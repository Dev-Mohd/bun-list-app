import Foundation

/// The app's home (/api/v1/home): trending this week, the community pulse, and
/// the caller's last brew for «كمّل من وين وقفت».
public struct RemoteHome: Decodable, Equatable, Sendable {
    public struct Trending: Decodable, Equatable, Sendable {
        public let lots: [RemoteTrendingLot]
        public let roasters: [RemoteTrendingRoaster]
        public let recipes: [RemoteTrendingRecipe]
    }

    public struct LastBrew: Decodable, Equatable, Sendable {
        public let lot: RemoteLot
        public let experience: RemoteExperience
    }

    public let trending: Trending
    public let pulse: [RemotePulseItem]
    public let lastBrew: LastBrew?
}

/// A trending coffee: the lot, its place, and why it's there.
public struct RemoteTrendingLot: Decodable, Equatable, Sendable, Identifiable {
    public let lot: RemoteLot
    public let rank: Int
    /// Places up (+) or down (−) since last week; nil = new on the list.
    public let move: Int?
    public let pinned: Bool
    /// "trend" earned this week, "added" topped up from the month's most added.
    public let reason: String
    public let brews: Int
    public let reviews: Int
    public let adds: Int
    public let recipes: Int

    public var id: String { lot.id }

    private enum Keys: String, CodingKey { case rank, move, pinned, reason, brews, reviews, adds, recipes }

    public init(from decoder: Decoder) throws {
        lot = try RemoteLot(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        rank = try c.decode(Int.self, forKey: .rank)
        move = try c.decodeIfPresent(Int.self, forKey: .move)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? "trend"
        brews = try c.decodeIfPresent(Int.self, forKey: .brews) ?? 0
        reviews = try c.decodeIfPresent(Int.self, forKey: .reviews) ?? 0
        adds = try c.decodeIfPresent(Int.self, forKey: .adds) ?? 0
        recipes = try c.decodeIfPresent(Int.self, forKey: .recipes) ?? 0
    }

    public init(lot: RemoteLot, rank: Int, move: Int?, pinned: Bool = false, reason: String = "trend",
                brews: Int = 0, reviews: Int = 0, adds: Int = 0, recipes: Int = 0) {
        self.lot = lot; self.rank = rank; self.move = move; self.pinned = pinned; self.reason = reason
        self.brews = brews; self.reviews = reviews; self.adds = adds; self.recipes = recipes
    }

    public var isTopUp: Bool { reason == "added" }

    /// Arabic counting: 1 and 2 have their own words, 3–10 take the plural, 11+ the singular.
    static func count(_ n: Int, _ one: String, _ two: String, _ few: String, _ many: String) -> String {
        switch n {
        case 1: return one
        case 2: return two
        case 3...10: return "\(n) \(few)"
        default: return "\(n) \(many)"
        }
    }

    /// "↑ ٣", "↓ ١", "جديد", or nil when unchanged or topped up.
    public var moveAr: String? {
        if isTopUp { return nil }
        guard let move else { return "جديد" }
        if move > 0 { return "↑ \(move)" }
        if move < 0 { return "↓ \(-move)" }
        return nil
    }

    /// Why it's here, as short chips: "١٢ تجربة", "٥ تقييمات", "+٩ أضافوها".
    public var reasonsAr: [String] {
        if isTopUp { return ["+\(adds) أضافوها هالشهر"] }
        var out: [String] = []
        if brews > 0 { out.append(Self.count(brews, "تجربة وحدة", "تجربتين", "تجارب", "تجربة")) }
        if reviews > 0 { out.append(Self.count(reviews, "تقييم واحد", "تقييمين", "تقييمات", "تقييم")) }
        if adds > 0 { out.append("+\(adds) أضافوها") }
        if recipes > 0 { out.append(Self.count(recipes, "وصفة وحدة", "وصفتين", "وصفات", "وصفة")) }
        return out
    }
}

public struct RemoteTrendingRoaster: Decodable, Equatable, Sendable, Identifiable {
    public let slug: String
    public let nameAr: String
    public let score: Double
    public let coffees: Int
    public let imageUrl: String?
    public var id: String { slug }
}

public struct RemoteTrendingRecipe: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let methodCode: String
    public let authorName: String
    public let lotNameAr: String?
    public let likes: Int
    public let brews: Int
}

public struct RemotePulseItem: Decodable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Decodable, Sendable { case brew, recipe, discovery }

    public let kind: Kind
    public let at: String
    public let name: String
    public let username: String?
    public let avatarUrl: String?
    public let lotSlug: String?
    public let lotNameAr: String?
    public let recipeId: String?
    public let recipeTitle: String?
    public let methodCode: String?
    public let stars: Int?
    public let note: String?

    public var id: String { "\(kind.rawValue)|\(username ?? name)|\(lotSlug ?? recipeId ?? "")|\(at)" }

    public var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: at) ?? ISO8601DateFormatter().date(from: at)
    }

    /// The line itself, e.g. "حضّرت نردوس بـ V60". The name goes before it.
    public var actionAr: String {
        let method = methodCode.flatMap { ReferenceCodes.brewMethod($0)?.nameAr } ?? ""
        switch kind {
        case .brew: return "حضّر \(lotNameAr ?? "قهوة")\(method.isEmpty ? "" : " بـ\(method)")"
        case .recipe: return "نشر وصفة «\(recipeTitle ?? "")»"
        case .discovery: return "اكتشف \(lotNameAr ?? "قهوة جديدة")"
        }
    }
}

/// The quick-browse tiles on the home.
public enum QuickBrowse: String, CaseIterable, Sendable {
    case fruity, chocolate, floral, iced, arabic, decaf

    public var titleAr: String {
        switch self {
        case .fruity: return "فواكه"
        case .chocolate: return "شوكولاتة"
        case .floral: return "زهري"
        case .iced: return "للمثلّج"
        case .arabic: return "قهوة عربية"
        case .decaf: return "بدون كافيين"
        }
    }

    /// The search filters it opens; nil for Arabic coffee, which opens «حضّر».
    public var filters: BrowseFilters? {
        var f = BrowseFilters()
        switch self {
        case .fruity: f.flavors = [.berry, .tropical, .stoneFruit, .citrus]
        case .chocolate: f.flavors = [.chocolate, .caramel, .nutty]
        case .floral: f.flavors = [.floral, .tea]
        case .iced: f.methods = ["COLD_BREW"]
        case .decaf: f.tags = ["decaf"]
        case .arabic: return nil
        }
        return f
    }
}

extension CatalogAPIClient {
    /// The home feed; with a token it adds the caller's last brew.
    public func fetchHome(accessToken: String?) async throws -> RemoteHome {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/home", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteHome.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Admins: pin a coffee to trending, hide it, or clear (nil).
    public func setTrending(lotID: String, mode: String?, accessToken: String) async throws {
        let body: [String: Any] = ["mode": mode.map { $0 as Any } ?? NSNull()]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .put, path: "/api/v1/admin/trending/\(lotID)", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }
}
