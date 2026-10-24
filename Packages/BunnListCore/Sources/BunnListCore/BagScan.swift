import Foundation

// AI bag scan (POST /api/v1/scan/bag): the server has Claude read a bag photo and
// returns the label's fields plus matching published lots. Errors: 403 forbidden
// = AI not configured on the server, 429 = daily limit, 422 = unreadable photo.

public struct RemoteBagExtraction: Codable, Equatable, Sendable {
    public let isCoffeeBag: Bool
    public let name: String?
    public let nameAr: String?
    public let roaster: String?
    public let roasterAr: String?
    public let originCountry: String?
    public let originCountryAr: String?
    public let originCountryCode: String?
    public let region: String?
    public let farm: String?
    public let producer: String?
    public let varieties: [String]
    public let process: String?
    public let processLabel: String?
    public let roastLevel: RoastLevel?
    public let roastDate: String?
    public let altitudeMeters: Int?
    public let flavorNotesAr: [String]
    public let weightGrams: Int?
    public let recommendedBrewMethods: [String]
    public let confidence: String

    /// The best display name: Arabic first, else the Latin name as printed.
    public var displayName: String? { nameAr ?? name }
    public var displayRoaster: String? { roasterAr ?? roaster }

    /// Days since the printed roast date, if any.
    public func daysSinceRoast(now: Date = Date()) -> Int? {
        guard let roastDate else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: roastDate) else { return nil }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        return days >= 0 ? days : nil
    }

    /// A note for a coffee suggestion summarizing everything read from the bag.
    public var suggestionNote: String {
        var parts: [String] = []
        if let region { parts.append("المنطقة: \(region)") }
        if let farm { parts.append("المزرعة: \(farm)") }
        if let producer { parts.append("المنتج: \(producer)") }
        if !varieties.isEmpty { parts.append("الصنف: \(varieties.joined(separator: "، "))") }
        if let altitudeMeters { parts.append("الارتفاع: \(altitudeMeters) م") }
        if let roastDate { parts.append("تاريخ التحميص: \(roastDate)") }
        return parts.joined(separator: "\n")
    }
}

public struct RemoteBagScanResult: Codable, Equatable, Sendable {
    public let extraction: RemoteBagExtraction
    public let matches: [RemoteLot]
    public let remainingToday: Int
}

extension CatalogAPIClient {
    /// Sends one JPEG photo of a bag for AI reading. The server does not store it.
    public func scanBag(jpeg: Data, accessToken: String) async throws -> RemoteBagScanResult {
        let payload: [String: Any] = ["imageBase64": jpeg.base64EncodedString(), "mediaType": "image/jpeg"]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/scan/bag", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteBagScanResult.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}

/// A coffee suggestion for review (POST /api/v1/submissions). Arabic names are
/// required; Latin names, process, roast level and flavors are optional.
public struct CoffeeSuggestion: Equatable, Sendable {
    public var name: String
    public var nameEn: String
    public var roasterName: String
    public var roasterNameEn: String
    public var originName: String
    /// A `ReferenceCodes.processes` code.
    public var process: String?
    public var roastLevel: RoastLevel?
    public var flavorNotes: [String]
    public var note: String

    public init(name: String = "", nameEn: String = "", roasterName: String = "", roasterNameEn: String = "",
                originName: String = "", process: String? = nil, roastLevel: RoastLevel? = nil,
                flavorNotes: [String] = [], note: String = "") {
        self.name = name; self.nameEn = nameEn; self.roasterName = roasterName; self.roasterNameEn = roasterNameEn
        self.originName = originName; self.process = process; self.roastLevel = roastLevel
        self.flavorNotes = flavorNotes; self.note = note
    }

    /// Everything a bag scan read, in the matching fields.
    public init(scanned e: RemoteBagExtraction) {
        self.init(name: e.nameAr ?? e.name ?? "", nameEn: e.name ?? "",
                  roasterName: e.roasterAr ?? e.roaster ?? "", roasterNameEn: e.roaster ?? "",
                  originName: e.originCountryAr ?? e.originCountry ?? "",
                  process: e.process.flatMap { ReferenceCodes.process($0)?.code },
                  roastLevel: e.roastLevel, flavorNotes: e.flavorNotesAr, note: e.suggestionNote)
    }

    /// Splits "شوكولاتة، كراميل, توت" into separate notes.
    public static func notes(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "،" || $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var isComplete: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2 && roasterName.trimmingCharacters(in: .whitespaces).count >= 2
    }

    func payload() -> [String: Any] {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var body: [String: Any] = ["name": t(name), "roasterName": t(roasterName)]
        if !t(nameEn).isEmpty { body["nameEn"] = t(nameEn) }
        if !t(roasterNameEn).isEmpty { body["roasterNameEn"] = t(roasterNameEn) }
        if !t(originName).isEmpty { body["originName"] = t(originName) }
        if let process { body["process"] = process }
        if let roastLevel { body["roastLevel"] = roastLevel.rawValue }
        let notes = flavorNotes.map(t).filter { !$0.isEmpty }
        if !notes.isEmpty { body["flavorNotes"] = Array(notes.prefix(12)) }
        if !t(note).isEmpty { body["note"] = String(t(note).prefix(1000)) }
        return body
    }
}

extension CatalogAPIClient {
    /// Sends a suggestion for review; returns its id.
    public func submitCoffee(_ suggestion: CoffeeSuggestion, accessToken: String) async throws -> String {
        let data = (try? JSONSerialization.data(withJSONObject: suggestion.payload())) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/submissions", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Created: Decodable { let id: String }
        do { return try JSONDecoder().decode(Created.self, from: response.body).id }
        catch { throw AuthClientError.malformedResponse }
    }
}

extension CatalogAPIClient {
    /// Attaches the product photo (a cut-out JPEG ≤ 2 MB) to the caller's pending suggestion.
    public func uploadSuggestionPhoto(submissionID: String, jpeg: Data, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: ["imageBase64": jpeg.base64EncodedString()])) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .put, path: "/api/v1/submissions/\(submissionID)/photo", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
    }
}
