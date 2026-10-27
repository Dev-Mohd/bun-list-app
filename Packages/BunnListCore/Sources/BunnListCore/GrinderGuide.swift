import Foundation

/// A grinder in the guide (/api/v1/grinders). Specs are nil until verified from
/// the maker's own sources, which travel with them.
public struct RemoteGrinder: Codable, Equatable, Hashable, Sendable, Identifiable {
    public struct Source: Codable, Equatable, Hashable, Sendable {
        public let label: String
        public let url: String
        public init(label: String, url: String) { self.label = label; self.url = url }
    }

    public let id: String
    public let brand: String
    public let model: String
    public let variant: String?
    public let category: String
    public let adjustment: String?
    public let rangeMin: Double?
    public let rangeMax: Double?
    public let clicksPerRotation: Int?
    public let micronsPerStep: Double?
    public let zeroGuideAr: String?
    public let notesAr: String?
    public let sources: [Source]
    public let imageUrl: String?
    public let imageCredit: String?
    public let published: Bool

    public var title: String { variant.map { "\(model) · \($0)" } ?? model }
    public var categoryAr: String { Self.categoryAr(category) }

    /// "٠–٤٠ كليك", "بدون درجات", or nil when the range isn't verified yet.
    public var rangeAr: String? {
        switch adjustment {
        case "timer": return "بالوقت (بدون درجات طحن)"
        case "stepless": return range.map { "\($0) · بدون درجات" } ?? "بدون درجات"
        case "clicks":
            if let range { return "\(range) كليك" }
            return clicksPerRotation.map { "\($0) كليك في اللفة" } ?? "كليكات"
        case "stepped": return range.map { "\($0) درجة" } ?? "بدرجات"
        default: return nil
        }
    }

    public var hasSpecs: Bool { adjustment != nil }

    private var range: String? {
        guard let rangeMin, let rangeMax else { return nil }
        return "\(Self.n(rangeMin))–\(Self.n(rangeMax))"
    }

    private static func n(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    public static let categories = ["hand", "electric", "single_dose", "built_in", "espresso", "commercial"]

    public static func categoryAr(_ code: String) -> String {
        switch code {
        case "hand": return "يدوية"
        case "electric": return "كهربائية للبيت"
        case "single_dose": return "جرعة وحدة"
        case "built_in": return "داخل مكينة القهوة"
        case "espresso": return "لمحضّري الإسبريسو"
        case "commercial": return "تجارية"
        default: return code
        }
    }

    public static let adjustments = ["clicks", "stepped", "stepless", "timer"]

    public static func adjustmentAr(_ code: String) -> String {
        switch code {
        case "clicks": return "كليكات"
        case "stepped": return "أرقام بدرجات"
        case "stepless": return "بدون درجات"
        case "timer": return "بالوقت فقط"
        default: return code
        }
    }

    /// Search across brand, model and variant, case-insensitively.
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return "\(brand) \(model) \(variant ?? "")".lowercased().contains(q)
    }
}

extension BrewPlan {
    /// Clicks on a guide grinder for this recipe's grind, when the recipe recorded
    /// microns and the grinder's microns per step are verified. Approximate.
    public func approximateClicks(on grinder: RemoteGrinder?) -> Int? {
        guard let grinder, let per = grinder.micronsPerStep, per > 0, let grindMicrons, grinder.adjustment != "timer" else { return nil }
        return Int((Double(grindMicrons) / per).rounded())
    }
}

extension CatalogAPIClient {
    private func decodeGrinders(_ request: HTTPRequest) async throws -> [RemoteGrinder] {
        let response = try await transport.send(request)
        try Self.checkContract(response)
        struct Wrapper: Decodable { let grinders: [RemoteGrinder] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).grinders }
        catch { throw AuthClientError.malformedResponse }
    }

    public func fetchGrinders() async throws -> [RemoteGrinder] {
        try await decodeGrinders(HTTPRequest(method: .get, path: "/api/v1/grinders"))
    }

    public func adminGrinders(accessToken: String) async throws -> [RemoteGrinder] {
        try await decodeGrinders(HTTPRequest(method: .get, path: "/api/v1/admin/grinders", bearer: accessToken))
    }

    /// Adds bundled grinders missing from the guide and fills specs nobody entered
    /// yet; returns how many grinders were added and how many got specs.
    public func seedGrinders(accessToken: String) async throws -> (created: Int, specs: Int) {
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/grinders/seed", bearer: accessToken))
        try Self.checkContract(response)
        struct Result: Decodable { let created: Int; let specs: Int? }
        do {
            let r = try JSONDecoder().decode(Result.self, from: response.body)
            return (r.created, r.specs ?? 0)
        } catch { throw AuthClientError.malformedResponse }
    }

    public func updateGrinder(id: String, changes: [String: Any], accessToken: String) async throws -> RemoteGrinder {
        let data = (try? JSONSerialization.data(withJSONObject: changes)) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .patch, path: "/api/v1/admin/grinders/\(id)", body: data, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteGrinder.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func replaceGrinderPhoto(id: String, jpeg: Data, accessToken: String) async throws -> RemoteGrinder {
        let data = (try? JSONSerialization.data(withJSONObject: ["imageBase64": jpeg.base64EncodedString()])) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/grinders/\(id)/photo", body: data, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteGrinder.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// «مطحنتي»; nil clears it.
    public func setMyGrinder(_ id: String?, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: ["grinderId": id.map { $0 as Any } ?? NSNull()])) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .put, path: "/api/v1/me/grinder", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }
}
