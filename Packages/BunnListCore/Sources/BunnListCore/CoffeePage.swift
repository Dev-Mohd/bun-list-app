import Foundation

/// Where to buy a coffee: the roaster's own product page, or a shop selling it.
public struct RemoteBuyLink: Codable, Equatable, Sendable {
    public let url: String
    public let host: String
    /// "roaster" or "store".
    public let kind: String
    public let storeNameAr: String?

    public init(url: String, host: String, kind: String, storeNameAr: String?) {
        self.url = url
        self.host = host
        self.kind = kind
        self.storeNameAr = storeNameAr
    }

    public var isRoasterStore: Bool { kind != "store" }
    public var title: String { isRoasterStore ? "اشترِ من المحمصة" : "اشترِها من \(storeNameAr ?? host)" }
    public var subtitle: String { isRoasterStore ? "\(host) · الموقع الرسمي" : "متجر يبيعها · \(host)" }
}

/// A roaster's own brew recipe, read from its product page.
public struct RemoteRoasterRecipe: Codable, Equatable, Sendable, Hashable {
    public let method: String
    /// "HOT" or "ICED"; missing from older servers (hot).
    public let serve: String?
    /// An xBloom recipe's share link; its numbers live on xBloom's page.
    public let link: String?
    public let tool: String?
    /// Nil only for an xBloom link.
    public let doseG: Double?
    public let waterMl: Int?
    public let tempC: Int?
    public let timeSec: Int?
    public let grind: String?
    public let ratio: Double?
    public let steps: [String]

    public init(method: String, serve: String? = nil, link: String? = nil, tool: String?, doseG: Double?, waterMl: Int?,
                tempC: Int?, timeSec: Int?, grind: String?, ratio: Double?, steps: [String]) {
        self.method = method
        self.serve = serve
        self.link = link
        self.tool = tool
        self.doseG = doseG
        self.waterMl = waterMl
        self.tempC = tempC
        self.timeSec = timeSec
        self.grind = grind
        self.ratio = ratio
        self.steps = steps
    }

    public var isIced: Bool { serve == "ICED" }
    public var isMachineLink: Bool { method == "XBLOOM" && link != nil }

    /// The tab label: "عين تايمور V60", "xBloom · بارد".
    public var label: String { (tool ?? methodNameAr) + (isIced ? " · بارد" : "") }

    public var methodNameAr: String {
        switch method {
        case "XBLOOM": return "xBloom"
        case "ESPRESSO": return "إسبريسو"
        case "CHEMEX": return "كيمكس"
        case "AEROPRESS": return "إيروبرس"
        default: return "تقطير V60"
        }
    }

    /// "2:15" for 135 seconds, "30 ث" under a minute.
    public static func clock(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) ث" : "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// 18 → "18", 18.5 → "18.5".
    public static func grams(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Where a coffee's notes lean, from chocolate and nuts (0) through caramel and
/// honey (0.5) to fruit and flowers (1). Worked out from the notes alone, so it
/// shows on coffees with no altitude, region or process. Earlier notes weigh more.
public enum TasteLean {
    static func weight(_ family: FlavorFamily) -> Double? {
        switch family {
        case .berry, .citrus, .stoneFruit, .tropical, .floral: return 1
        case .tea: return 0.9
        case .driedFruit: return 0.8
        case .honey, .caramel: return 0.5
        case .spice: return 0.2
        case .nutty: return 0.1
        case .chocolate: return 0
        case .other: return nil
        }
    }

    /// nil when no note has a family.
    public static func position(_ notes: [String]) -> Double? {
        var sum = 0.0, total = 0.0
        for (index, note) in notes.prefix(6).enumerated() {
            guard let value = weight(FlavorFamily.of(note)) else { continue }
            let w = 1.0 / Double(index + 1)
            sum += value * w
            total += w
        }
        return total > 0 ? sum / total : nil
    }
}

/// The fact tiles on a coffee page: only the ones with data. Origin always spans
/// the row; the rest pair up, and a tile left alone spans the row too, so a coffee
/// with missing details never shows an empty box.
public enum CoffeeFactTiles {
    public enum Kind: String, Sendable, Equatable { case origin, altitude, process, variety }

    public struct Tile: Equatable, Sendable {
        public let kind: Kind
        public let wide: Bool
    }

    public static func tiles(origin: String?, altitude: Int?, process: String?, variety: String?) -> [Tile] {
        var out: [Tile] = []
        if let origin, !origin.isEmpty { out.append(Tile(kind: .origin, wide: true)) }
        var halves: [Kind] = []
        if let altitude, altitude > 0 { halves.append(.altitude) }
        if let process, !process.isEmpty { halves.append(.process) }
        if let variety, !variety.trimmingCharacters(in: .whitespaces).isEmpty { halves.append(.variety) }
        for (index, kind) in halves.enumerated() {
            out.append(Tile(kind: kind, wide: halves.count % 2 == 1 && index == halves.count - 1))
        }
        return out
    }
}

extension RemoteLotDetail {
    public var factTiles: [CoffeeFactTiles.Tile] {
        CoffeeFactTiles.tiles(origin: originNameAr, altitude: altitudeMeters, process: processNameAr, variety: variety)
    }

    /// The brew method most people log for it, when anyone has.
    public var topCommunityMethod: RemoteLotCommunity.Method? {
        community?.methods.filter { $0.count > 0 }.max { $0.count < $1.count }
    }
}
