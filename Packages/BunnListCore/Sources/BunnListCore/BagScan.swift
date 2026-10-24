import Foundation

// AI bag scan (POST /api/v1/scan/bag): the server has Claude read a bag photo and
// returns the label's fields plus matching published lots. Errors: 403 forbidden
// = AI not configured on the server, 429 = daily limit, 422 = unreadable photo.

public struct RemoteBagExtraction: Codable, Equatable, Sendable {
    public let isCoffeeBag: Bool
    public let name: String?
    public let nameAr: String?
    public let roaster: String?
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

    /// The best display name: Arabic when printed, else the printed name.
    public var displayName: String? { nameAr ?? name }

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
        if let process = processLabel ?? process { parts.append("المعالجة: \(process)") }
        if let altitudeMeters { parts.append("الارتفاع: \(altitudeMeters) م") }
        if !flavorNotesAr.isEmpty { parts.append("النكهات: \(flavorNotesAr.joined(separator: "، "))") }
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
