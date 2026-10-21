import Foundation

public enum ApprovalStatus: String, Codable, Sendable {
    case pending, approved, rejected, disabled
}

public enum OriginType: String, Codable, Sendable {
    case singleCountry = "SINGLE_COUNTRY"
    case multiCountry = "MULTI_COUNTRY"
    case unknown = "UNKNOWN"
}

/// Origin is recorded explicitly; it is never inferred from a product name.
public struct Origin: Codable, Hashable, Sendable {
    public let type: OriginType
    /// ISO 3166-1 alpha-2 codes, matching `OriginCountry.isoCode` in the existing server schema.
    public let countryCodes: [String]

    public init(type: OriginType, countryCodes: [String]) {
        self.type = type
        self.countryCodes = countryCodes
    }

    var isConsistent: Bool {
        switch type {
        case .singleCountry: return countryCodes.count == 1
        case .multiCountry: return Set(countryCodes).count >= 2
        case .unknown: return countryCodes.isEmpty
        }
    }
}

/// A lot is either a known season/harvest or the single shared "season unknown" container of its product.
public enum LotSeason: Codable, Hashable, Sendable {
    case known(label: String?, harvestYear: Int?)
    case unknown

    public var isUnknown: Bool { self == .unknown }
}

public struct Roaster: Codable, Hashable, Identifiable, Sendable {
    public let id: RoasterID
    public let nameAr: String
    public let nameEn: String?
    public let cityAr: String?
}

/// The stable marketing identity inside a roaster. Seasons are separate lots.
public struct CoffeeProduct: Codable, Hashable, Identifiable, Sendable {
    public let id: ProductID
    public let roasterID: RoasterID
    public let nameAr: String
    public let nameEn: String?
    public let origin: Origin
    public let processCode: String?
    public let flavorCodes: [String]
    public let recommendedBrewMethods: [String]
    public let approval: ApprovalStatus
}

/// «محصول» in the UI. Collection, rating and experiences attach to a lot.
public struct CoffeeLot: Codable, Hashable, Identifiable, Sendable {
    public let id: LotID
    public let productID: ProductID
    public let season: LotSeason
    public let roastBatchCode: String?
    /// For the UNKNOWN lot this always equals the product's approval (it is created with the product).
    public let approval: ApprovalStatus
}

public enum CatalogError: Error, Equatable, Sendable {
    case duplicateID(String)
    case missingRoaster(ProductID)
    case missingProduct(LotID)
    case inconsistentOrigin(ProductID)
    case unknownCode(String)
    case missingUnknownLot(ProductID)
    case duplicateUnknownLot(ProductID)
    case unknownLotApprovalMismatch(LotID)
    case knownSeasonWithoutLabel(LotID)
    case mixedSampleAndRealIDs
}

public struct Catalog: Codable, Equatable, Sendable {
    /// Human label shown wherever demo data is visible («دليل تجريبي»).
    public let label: String
    public let roasters: [Roaster]
    public let products: [CoffeeProduct]
    public let lots: [CoffeeLot]

    public init(label: String, roasters: [Roaster], products: [CoffeeProduct], lots: [CoffeeLot]) throws {
        self.label = label
        self.roasters = roasters
        self.products = products
        self.lots = lots
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(label: container.decode(String.self, forKey: .label),
                      roasters: container.decode([Roaster].self, forKey: .roasters),
                      products: container.decode([CoffeeProduct].self, forKey: .products),
                      lots: container.decode([CoffeeLot].self, forKey: .lots))
    }

    public var isSample: Bool { products.allSatisfy { $0.id.isSample } }

    public func roaster(_ id: RoasterID) -> Roaster? { roasters.first { $0.id == id } }
    public func product(_ id: ProductID) -> CoffeeProduct? { products.first { $0.id == id } }
    public func lot(_ id: LotID) -> CoffeeLot? { lots.first { $0.id == id } }

    /// Known seasons first (newest harvest first), then the shared UNKNOWN lot.
    public func lots(of productID: ProductID) -> [CoffeeLot] {
        lots.filter { $0.productID == productID }.sorted { a, b in
            switch (a.season, b.season) {
            case (.unknown, .known): return false
            case (.known, .unknown): return true
            case let (.known(_, yearA), .known(_, yearB)) where yearA != yearB: return (yearA ?? 0) > (yearB ?? 0)
            default: return a.id < b.id
            }
        }
    }

    public func unknownLot(of productID: ProductID) -> CoffeeLot? {
        lots.first { $0.productID == productID && $0.season.isUnknown }
    }

    private func validate() throws {
        var seen = Set<String>()
        for id in roasters.map({ "roaster:" + $0.id.rawValue }) + products.map({ "product:" + $0.id.rawValue })
            + lots.map({ "lot:" + $0.id.rawValue }) {
            guard seen.insert(id).inserted else { throw CatalogError.duplicateID(id) }
        }
        let allIDs = roasters.map(\.id.isSample) + products.map(\.id.isSample) + lots.map(\.id.isSample)
        if Set(allIDs).count > 1 { throw CatalogError.mixedSampleAndRealIDs }

        for product in products {
            guard roaster(product.roasterID) != nil else { throw CatalogError.missingRoaster(product.id) }
            guard product.origin.isConsistent else { throw CatalogError.inconsistentOrigin(product.id) }
            for code in product.origin.countryCodes where ReferenceCodes.country(code) == nil {
                throw CatalogError.unknownCode(code)
            }
            if let code = product.processCode, ReferenceCodes.process(code) == nil { throw CatalogError.unknownCode(code) }
            for code in product.flavorCodes where ReferenceCodes.flavor(code) == nil { throw CatalogError.unknownCode(code) }
            for code in product.recommendedBrewMethods where ReferenceCodes.brewMethod(code) == nil {
                throw CatalogError.unknownCode(code)
            }
            let unknownLots = lots.filter { $0.productID == product.id && $0.season.isUnknown }
            // The server creates exactly one UNKNOWN lot when it approves a product (and a pending
            // one with a pending product); rejected/disabled products keep theirs for history.
            if unknownLots.isEmpty { throw CatalogError.missingUnknownLot(product.id) }
            if unknownLots.count > 1 { throw CatalogError.duplicateUnknownLot(product.id) }
            if unknownLots[0].approval != product.approval {
                throw CatalogError.unknownLotApprovalMismatch(unknownLots[0].id)
            }
        }
        for lot in lots {
            guard product(lot.productID) != nil else { throw CatalogError.missingProduct(lot.id) }
            if case let .known(label, year) = lot.season, (label ?? "").isEmpty, year == nil {
                throw CatalogError.knownSeasonWithoutLabel(lot.id)
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case label, roasters, products, lots }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(roasters, forKey: .roasters)
        try container.encode(products, forKey: .products)
        try container.encode(lots, forKey: .lots)
    }
}

extension Catalog {
    /// The bundled demo catalog (`fixtures.json`). Its IDs live in the `sample:` namespace.
    public static func bundledSample() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: bundledSampleURL()))
    }

    public static func bundledSampleURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "fixtures", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
