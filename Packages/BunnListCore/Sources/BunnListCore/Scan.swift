import Foundation

// MARK: Camera entry state

public enum CameraHardware: Equatable, Sendable {
    case available, unavailable
}

public enum CameraAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted
}

/// What the scan tab offers before capturing. Missing hardware is checked first: the app never
/// requests permission for a camera that is not there, and never shows a Settings link for it.
public enum ScanEntryState: Equatable, Sendable {
    case noCamera
    case needsPermission
    case permissionDenied
    case ready

    public static func resolve(hardware: CameraHardware, authorization: CameraAuthorization) -> ScanEntryState {
        guard hardware == .available else { return .noCamera }
        switch authorization {
        case .notDetermined: return .needsPermission
        case .authorized: return .ready
        case .denied, .restricted: return .permissionDenied
        }
    }

    /// Photo picking and manual entry stay available in every state.
    public var canCapture: Bool { self == .ready || self == .needsPermission }
    public var offersSettingsLink: Bool { self == .permissionDenied }
}

// MARK: Extraction

/// Editable fields read from a bag. Unknown values stay empty; nothing is guessed.
public struct ExtractedBagFields: Codable, Equatable, Sendable {
    public var productName: String
    public var roasterName: String
    public var originText: String
    public var processText: String
    public var seasonText: String

    public init(productName: String = "", roasterName: String = "", originText: String = "",
                processText: String = "", seasonText: String = "") {
        self.productName = productName
        self.roasterName = roasterName
        self.originText = originText
        self.processText = processText
        self.seasonText = seasonText
    }

    /// Name and roaster are the minimum before searching.
    public var hasMinimumFields: Bool {
        !productName.trimmingCharacters(in: .whitespaces).isEmpty
            && !roasterName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum ExtractionQuality: String, Codable, Sendable {
    case readable
    /// Too little was read; the user is guided to retake the photo or type the details.
    case weak
}

public struct ExtractionResult: Equatable, Sendable {
    public let fields: ExtractedBagFields
    public let quality: ExtractionQuality
    /// True for the bundled demo extractor; the UI must label the result as not read from the photo.
    public let isSample: Bool

    public init(fields: ExtractedBagFields, quality: ExtractionQuality, isSample: Bool) {
        self.fields = fields
        self.quality = quality
        self.isSample = isSample
    }
}

/// Reading text from a bag photo. The real server-side reader arrives in C05; it is a separate
/// service from matching.
public protocol BagTextExtracting: Sendable {
    func extract(imageData: Data) async throws -> ExtractionResult
}

/// C01 demo reader. It does not look at the image: it returns one sample product's details, labeled
/// as a sample, so the review → match flow can be exercised without a server.
public struct SampleBagExtractor: BagTextExtracting {
    let fields: ExtractedBagFields

    public init(fields: ExtractedBagFields) { self.fields = fields }

    public init(catalog: Catalog, productID: ProductID) {
        let product = catalog.product(productID)
        fields = ExtractedBagFields(productName: product?.nameAr ?? "",
                                    roasterName: product.flatMap { catalog.roaster($0.roasterID)?.nameAr } ?? "")
    }

    public func extract(imageData: Data) async throws -> ExtractionResult {
        ExtractionResult(fields: fields, quality: fields.hasMinimumFields ? .readable : .weak, isSample: true)
    }
}

// MARK: Matching

public struct ProductMatch: Equatable, Sendable {
    public let product: CoffeeProduct
    /// All lots of the product. Matching never chooses a season: the user picks one or «الموسم غير معروف».
    public let lots: [CoffeeLot]
}

public enum MatchOutcome: Equatable, Sendable {
    case candidates([ProductMatch])
    case notFound
}

public enum MatchError: Error, Equatable, Sendable {
    case missingNameOrRoaster
}

/// Matches reviewed fields against the catalog at product level. Candidates must match the roaster and
/// share a name token; the user confirms one. Nothing is merged by name alone.
public enum CatalogMatcher {
    public static func match(_ fields: ExtractedBagFields, in catalog: Catalog) throws -> MatchOutcome {
        guard fields.hasMinimumFields else { throw MatchError.missingNameOrRoaster }
        let nameTokens = Set(TextNormalizer.tokens(fields.productName))
        let roasterQuery = TextNormalizer.normalize(fields.roasterName)
        let scored = catalog.products.filter { $0.approval == .approved }.compactMap { product -> (Double, ProductMatch)? in
            guard let roaster = catalog.roaster(product.roasterID) else { return nil }
            let roasterNames = [roaster.nameAr, roaster.nameEn ?? ""].map(TextNormalizer.normalize).filter { !$0.isEmpty }
            guard roasterNames.contains(where: { $0.contains(roasterQuery) || roasterQuery.contains($0) }) else { return nil }
            let productTokens = Set(TextNormalizer.tokens(product.nameAr) + TextNormalizer.tokens(product.nameEn ?? ""))
            let overlap = Double(nameTokens.intersection(productTokens).count) / Double(max(nameTokens.count, 1))
            guard overlap > 0 else { return nil }
            return (overlap, ProductMatch(product: product, lots: catalog.lots(of: product.id)))
        }
        guard !scored.isEmpty else { return .notFound }
        let ordered = scored.sorted { a, b in a.0 != b.0 ? a.0 > b.0 : a.1.product.id < b.1.product.id }
        return .candidates(ordered.map(\.1))
    }
}

// MARK: Flow

/// Scan screen state. Each extraction/match carries a request token; a response that arrives after
/// cancel or after a newer request is ignored.
public struct ScanFlow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case extracting
        case review(fields: ExtractedBagFields, quality: ExtractionQuality, isSample: Bool)
        case results(fields: ExtractedBagFields, candidates: [ProductMatch])
        case notFound(fields: ExtractedBagFields)
        case failed(fields: ExtractedBagFields?)
    }

    public private(set) var phase: Phase = .idle
    private var currentToken: ClientID?

    public init() {}

    /// Starts reading a photo; returns the token the response must carry.
    public mutating func beginExtraction() -> ClientID {
        let token = ClientID()
        currentToken = token
        phase = .extracting
        return token
    }

    /// Manual entry skips extraction.
    public mutating func beginManualEntry() {
        currentToken = nil
        phase = .review(fields: ExtractedBagFields(), quality: .readable, isSample: false)
    }

    @discardableResult
    public mutating func receiveExtraction(_ result: Result<ExtractionResult, Error>, token: ClientID) -> Bool {
        guard token == currentToken, phase == .extracting else { return false }
        currentToken = nil
        switch result {
        case let .success(extraction):
            phase = .review(fields: extraction.fields, quality: extraction.quality, isSample: extraction.isSample)
        case .failure:
            phase = .failed(fields: nil)
        }
        return true
    }

    /// Runs matching on the reviewed (possibly edited) fields.
    public mutating func submitReview(_ fields: ExtractedBagFields, catalog: Catalog) throws {
        switch try CatalogMatcher.match(fields, in: catalog) {
        case let .candidates(candidates): phase = .results(fields: fields, candidates: candidates)
        case .notFound: phase = .notFound(fields: fields)
        }
    }

    /// Back to editing with the same fields (e.g. from results or not-found).
    public mutating func editAgain(_ fields: ExtractedBagFields) {
        currentToken = nil
        phase = .review(fields: fields, quality: .readable, isSample: false)
    }

    public mutating func cancel() {
        currentToken = nil
        phase = .idle
    }
}
