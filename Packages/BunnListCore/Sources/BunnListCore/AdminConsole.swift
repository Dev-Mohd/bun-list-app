import Foundation

// The admin console (/api/v1/admin/overview, /admin/lots, /admin/reports) and
// "بلّغ" (/api/v1/reports). Admin calls answer 403 for non-admins.

public struct RemoteAdminOverview: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public let day: String
        public let active: Int
        public let newUsers: Int
        public var id: String { day }
    }

    public let users: Int
    public let newUsers7d: Int
    public let activeToday: Int
    public let reviews7d: Int
    public let recipes7d: Int
    public let brews7d: Int
    public let scans7d: Int
    public let lots: Int
    public let pendingSubmissions: Int
    public let openReports: Int
    public let series: [Day]
}

public struct RemoteAdminLotRow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let slug: String
    public let nameAr: String
    public let name: String
    public let roasterNameAr: String
    public let originCode: String?
    public let originNameAr: String?
    public let imageUrl: String?
    public let published: Bool
    public let reviewCount: Int
}

public struct RemoteAdminLot: Codable, Equatable, Sendable {
    public let id: String
    public let slug: String
    public let nameAr: String
    public let name: String
    public let roasterNameAr: String
    public let originCode: String?
    public let originNameAr: String?
    public let imageUrl: String?
    public let published: Bool
    public let reviewCount: Int
    public let process: String
    public let processLabel: String?
    public let roastLevel: String?
    public let flavorNotes: [String]
    public let region: String?
    public let variety: String?
    public let altitudeMeters: Int?
    public let descriptionAr: String?
    public let tags: [String]
    /// Home trending override: "pin", "hide" or nil (automatic).
    public let trending: String?
}

public enum AdminLotFilter: String, CaseIterable, Sendable {
    case all, hidden, noPhoto, noNotes

    public var nameAr: String {
        switch self {
        case .all: return "الكل"
        case .hidden: return "مخفية"
        case .noPhoto: return "بلا صورة"
        case .noNotes: return "بلا نكهات"
        }
    }
}

/// The edit form for a lot; `changes(from:)` sends only what differs.
public struct AdminLotForm: Equatable, Sendable {
    public var nameAr: String
    public var name: String
    public var process: String
    public var processLabel: String
    public var roastLevel: String
    public var flavorNotes: [String]
    public var originCode: String?
    public var originNameAr: String
    public var region: String
    public var variety: String
    public var altitude: String
    public var descriptionAr: String
    public var published: Bool
    public var tags: Set<String>

    public init(_ lot: RemoteAdminLot) {
        nameAr = lot.nameAr; name = lot.name; process = lot.process; processLabel = lot.processLabel ?? ""
        roastLevel = lot.roastLevel ?? ""; flavorNotes = lot.flavorNotes; originCode = lot.originCode
        originNameAr = lot.originNameAr ?? ""; region = lot.region ?? ""; variety = lot.variety ?? ""
        altitude = lot.altitudeMeters.map(String.init) ?? ""; descriptionAr = lot.descriptionAr ?? ""
        published = lot.published; tags = Set(lot.tags)
    }

    private static func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func nullable(_ s: String) -> Any { t(s).isEmpty ? NSNull() : t(s) }

    public func changes(from lot: RemoteAdminLot) -> [String: Any] {
        let original = AdminLotForm(lot)
        var body: [String: Any] = [:]
        if Self.t(nameAr) != original.nameAr { body["nameAr"] = Self.t(nameAr) }
        if Self.t(name) != original.name { body["name"] = Self.t(name) }
        if process != original.process { body["process"] = process }
        if Self.t(processLabel) != original.processLabel { body["processLabel"] = Self.nullable(processLabel) }
        if Self.t(roastLevel) != original.roastLevel { body["roastLevel"] = Self.nullable(roastLevel) }
        let notes = flavorNotes.map(Self.t).filter { !$0.isEmpty }
        if notes != original.flavorNotes { body["flavorNotes"] = notes }
        if let originCode, originCode != original.originCode {
            body["originCode"] = originCode
            body["originNameAr"] = Self.t(originNameAr)
        }
        if Self.t(region) != original.region { body["region"] = Self.nullable(region) }
        if Self.t(variety) != original.variety { body["variety"] = Self.nullable(variety) }
        if Self.t(altitude) != original.altitude { body["altitudeMeters"] = Int(Self.t(altitude)).map { $0 as Any } ?? NSNull() }
        if Self.t(descriptionAr) != original.descriptionAr { body["descriptionAr"] = Self.nullable(descriptionAr) }
        if published != original.published { body["published"] = published }
        if tags != original.tags { body["tags"] = tags.sorted() }
        return body
    }
}

public enum ReportTarget: String, Sendable { case review, recipe, note, profile }

public enum ReportReason: String, CaseIterable, Sendable, Identifiable {
    case spam, offensive, wrong, other
    public var id: String { rawValue }

    public var nameAr: String {
        switch self {
        case .spam: return "إزعاج أو إعلان"
        case .offensive: return "مسيء أو غير لائق"
        case .wrong: return "معلومات غلط"
        case .other: return "سبب آخر"
        }
    }

    public static func nameAr(_ raw: String) -> String { ReportReason(rawValue: raw)?.nameAr ?? raw }
}

public struct RemoteAdminReport: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let targetType: String
    public let targetId: String
    public let reason: String
    public let details: String?
    public let status: String
    public let createdAt: String
    public let reporterName: String?
    public let ownerName: String?
    public let title: String
    public let text: String?
    public let sameTargetCount: Int
}

extension CatalogAPIClient {
    private func decode<T: Decodable>(_ type: T.Type, _ request: HTTPRequest) async throws -> T {
        let response = try await transport.send(request)
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func adminOverview(accessToken: String) async throws -> RemoteAdminOverview {
        try await decode(RemoteAdminOverview.self, HTTPRequest(method: .get, path: "/api/v1/admin/overview", bearer: accessToken))
    }

    public func adminLots(query: String, filter: AdminLotFilter, accessToken: String) async throws -> [RemoteAdminLotRow] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+="))) ?? ""
        struct Wrapper: Decodable { let lots: [RemoteAdminLotRow] }
        return try await decode(Wrapper.self, HTTPRequest(
            method: .get, path: "/api/v1/admin/lots?q=\(q)&filter=\(filter.rawValue)", bearer: accessToken
        )).lots
    }

    public func adminLot(id: String, accessToken: String) async throws -> RemoteAdminLot {
        try await decode(RemoteAdminLot.self, HTTPRequest(method: .get, path: "/api/v1/admin/lots/\(id)", bearer: accessToken))
    }

    public func updateAdminLot(id: String, changes: [String: Any], accessToken: String) async throws -> RemoteAdminLot {
        let data = (try? JSONSerialization.data(withJSONObject: changes)) ?? Data()
        return try await decode(RemoteAdminLot.self, HTTPRequest(method: .patch, path: "/api/v1/admin/lots/\(id)", body: data, bearer: accessToken))
    }

    /// Removes a lot nobody has used yet; `APIError.conflict` when it has reviews,
    /// brews or recipes (hide it instead).
    public func deleteAdminLot(id: String, accessToken: String) async throws {
        let response = try await transport.send(HTTPRequest(method: .delete, path: "/api/v1/admin/lots/\(id)", bearer: accessToken))
        try Self.checkContract(response)
    }

    /// Replaces the lot's picture; returns its new URL.
    public func replaceAdminLotPhoto(id: String, jpeg: Data, accessToken: String) async throws -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["imageBase64": jpeg.base64EncodedString()])) ?? Data()
        struct Result: Decodable { let imageUrl: String }
        return try await decode(Result.self, HTTPRequest(
            method: .post, path: "/api/v1/admin/lots/\(id)/photo", body: data, bearer: accessToken
        )).imageUrl
    }

    /// `closed` lists dismissed and removed ones.
    public func adminReports(closed: Bool, accessToken: String) async throws -> [RemoteAdminReport] {
        struct Wrapper: Decodable { let reports: [RemoteAdminReport] }
        return try await decode(Wrapper.self, HTTPRequest(
            method: .get, path: "/api/v1/admin/reports?status=\(closed ? "closed" : "open")", bearer: accessToken
        )).reports
    }

    /// `remove` hides the content; either way all open reports on it close.
    public func resolveReport(id: String, remove: Bool, accessToken: String) async throws {
        let data = (try? JSONSerialization.data(withJSONObject: ["action": remove ? "remove" : "dismiss"])) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/reports/\(id)", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }

    /// "بلّغ". A profile's `targetID` is its username; a note's is the lot id.
    public func report(_ target: ReportTarget, id targetID: String, reason: ReportReason, details: String?,
                       accessToken: String) async throws {
        var body: [String: Any] = ["targetType": target.rawValue, "targetId": targetID, "reason": reason.rawValue]
        if let details, !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["details"] = details }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/reports", body: data, bearer: accessToken))
        try Self.checkContract(response)
    }
}
