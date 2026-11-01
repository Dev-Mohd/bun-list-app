import Foundation

// The signed-in home (GET /api/v1/me/for-you) and what «مجموعتي» works out from
// the collection on its own: counts, the taste spread and the month's recap.

public struct RemoteForYou: Decodable, Equatable, Sendable {
    public struct DailyPick: Decodable, Equatable, Sendable {
        public let lot: RemoteLot
        /// 0–100 once they rated enough coffees.
        public let score: Int?
        public let reason: String
    }

    public struct Resume: Decodable, Equatable, Sendable, Identifiable {
        public var id: String { lot.id }
        public let lot: RemoteLot
        public let since: String
    }

    public struct RoasterNews: Decodable, Equatable, Sendable, Identifiable {
        public struct Lot: Decodable, Equatable, Sendable, Identifiable {
            public var id: String { slug }
            public let slug: String
            public let nameAr: String
            public let imageUrl: String?
            public let publishedAt: String
        }
        public var id: String { roasterNameAr }
        public let roasterNameAr: String
        /// Newest first.
        public let lots: [Lot]
    }

    public struct FriendsDrinking: Decodable, Equatable, Sendable, Identifiable {
        public var id: String { lot.id }
        public let lot: RemoteLot
        public let names: [String]
        public let people: Int

        /// «سارة ونورة و٤ غيرهم جرّبوها هالأسبوع».
        public var line: String {
            let shown = names.prefix(2)
            let rest = people - shown.count
            var who = shown.joined(separator: " و")
            if rest > 0 { who += " و\(rest) غيرهم" }
            return people == 1 ? "\(who) جرّبها هالأسبوع" : "\(who) جرّبوها هالأسبوع"
        }
    }

    public let dailyPick: DailyPick?
    public let resume: [Resume]
    public let roasterNews: [RoasterNews]
    public let friendsDrinking: [FriendsDrinking]

    public var isEmpty: Bool { dailyPick == nil && resume.isEmpty && roasterNews.isEmpty && friendsDrinking.isEmpty }
}

extension CatalogAPIClient {
    /// GET /api/v1/me/for-you.
    public func fetchForYou(accessToken: String) async throws -> RemoteForYou {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/me/for-you", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteForYou.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}

public enum ISODate {
    public static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// «اليوم», «أمس», «من ٣ أيام», «من أسبوعين»...
    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        switch days {
        case 0: return "اليوم"
        case 1: return "أمس"
        case 2: return "من يومين"
        case 3...10: return "من \(days) أيام"
        case 11...13: return "من \(days) يوم"
        case 14...20: return "من أسبوعين"
        case 21...59: return "من \(days / 7) أسابيع"
        default: return "من \(days / 30) شهور"
        }
    }
}

extension RemoteForYou.RoasterNews {
    /// How many of its new coffees came after `lastSeen` (all of them when never opened).
    public func unseen(since lastSeen: Date?) -> Int {
        guard let lastSeen else { return lots.count }
        return lots.filter { (ISODate.parse($0.publishedAt) ?? .distantPast) > lastSeen }.count
    }
}

/// What «مجموعتي» shows above the bags, worked out from the collection alone.
public struct CollectionInsights: Equatable, Sendable {
    public struct Share: Equatable, Sendable {
        public let family: FlavorFamily
        /// Whole percent; the shown shares add up to 100.
        public let percent: Int
    }

    public struct Recap: Equatable, Sendable {
        public let coffees: Int
        public let newCountries: Int
        public let topNote: String?
    }

    public let coffees: Int
    public let countryCodes: [String]
    public let roasters: Int
    public let shares: [Share]
    /// This month's additions; nil when nothing was added this month.
    public let recap: Recap?

    public init(items: [RemoteCollectionItem], now: Date = Date(), calendar: Calendar = .init(identifier: .gregorian)) {
        coffees = items.count
        var codes: [String] = []
        for code in items.compactMap({ $0.originCode?.uppercased() }) where code != "XB" && !codes.contains(code) {
            codes.append(code)
        }
        countryCodes = codes
        roasters = Set(items.map(\.roasterNameAr).filter { !$0.isEmpty }).count

        var counts: [FlavorFamily: Int] = [:]
        for note in items.flatMap({ $0.flavorNotes ?? [] }) {
            let family = FlavorFamily.of(note)
            if family != .other { counts[family, default: 0] += 1 }
        }
        let top = counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.rawValue < $1.key.rawValue) }.prefix(5)
        let percents = LotCommunityStats.percentages(top.map(\.value))
        shares = zip(top, percents).map { Share(family: $0.key, percent: $1) }.filter { $0.percent > 0 }

        let thisMonth = items.filter { item in
            guard let date = ISODate.parse(item.savedAt) else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
        if thisMonth.isEmpty {
            recap = nil
        } else {
            let before = Set(items.filter { !thisMonth.contains($0) }.compactMap { $0.originCode?.uppercased() })
            let fresh = Set(thisMonth.compactMap { $0.originCode?.uppercased() }).subtracting(before).subtracting(["XB"])
            let notes = thisMonth.flatMap { $0.flavorNotes ?? [] }
            let topNote = Dictionary(grouping: notes, by: { $0 }).max { $0.value.count < $1.value.count || ($0.value.count == $1.value.count && $0.key > $1.key) }?.key
            recap = Recap(coffees: thisMonth.count, newCountries: fresh.count, topNote: topNote)
        }
    }
}
