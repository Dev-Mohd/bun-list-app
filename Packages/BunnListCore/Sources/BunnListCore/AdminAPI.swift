import Foundation

// The signed-in account's own status (/api/v1/me, /api/v1/submissions) and the
// admin review of coffee suggestions (/api/v1/admin/submissions). Admin calls
// answer 403 for non-admins.

public struct RemoteMe: Codable, Equatable, Sendable {
    public let isAdmin: Bool
    public let discoveries: Int
    /// The account's public handle, without "@"; nil until chosen.
    public let username: String?
    public let displayName: String?
    public let bio: String?
    public let avatarUrl: String?
    /// Missing from older servers; treated as done so they never show first-run setup.
    public let onboarded: Bool?
    public let hideFromLeaderboard: Bool?
    /// Missing from older servers (then everyone).
    public let followersVisibility: ProfileVisibility?
    public let followingVisibility: ProfileVisibility?
    public let activityVisibility: ProfileVisibility?
    /// «مطحنتي» (a guide grinder id). Missing from older servers.
    public let grinderId: String?

    public var isOnboarded: Bool { onboarded ?? true }

    public func visibility(of part: PrivacyPart) -> ProfileVisibility {
        switch part {
        case .followers: return followersVisibility ?? .everyone
        case .following: return followingVisibility ?? .everyone
        case .activity: return activityVisibility ?? .everyone
        }
    }
}

public struct RemoteMySubmission: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let roasterName: String
    public let status: String
    public let lotSlug: String?
    public let reviewNote: String?
    public let hasPhoto: Bool
    public let createdAt: String
}

public struct RemoteAdminSubmission: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let status: String
    public let name: String
    public let nameEn: String?
    public let roasterName: String
    public let roasterNameEn: String?
    public let originName: String?
    public let process: String?
    public let roastLevel: String?
    public let flavorNotes: [String]
    public let note: String?
    /// Shown with the coffee once approved. Missing from older servers.
    public let publicNote: String?
    public let photoUrl: String?
    public let authorName: String?
    public let approvedLotSlug: String?
    public let reviewNote: String?
    public let createdAt: String
    /// Batch imports: the source page, extraction confidence (0-1) and labels. Missing from older servers.
    public let sourceUrl: String?
    public let sourceConfidence: Double?
    public let tags: [String]?
}

/// Labels on a lot: "luxury", "infused", "decaf".
public enum LotTagText {
    public static func nameAr(_ tag: String) -> String {
        switch tag {
        case "luxury": return "فاخرة"
        case "infused": return "منقوعة"
        case "decaf": return "منزوعة الكافيين"
        default: return tag
        }
    }
}

public struct RemoteImportResult: Codable, Equatable, Sendable {
    public let created: Int
    public let alreadyImported: Int
    public let alreadyInCatalog: Int
    /// Product photos uploaded; missing from older servers.
    public let photos: Int?
}

/// What the admin confirms to publish a lot. Pre-filled from the suggestion. The
/// Latin names may stay empty: the server writes them.
public struct ApprovalForm: Equatable, Sendable {
    public var nameAr: String
    public var name: String
    public var roasterNameAr: String
    public var roasterName: String
    public var originCode: String?
    public var originNameAr: String
    public var process: String?
    public var roastLevel: RoastLevel?
    public var flavorNotes: [String]
    public var descriptionAr: String

    public init(_ s: RemoteAdminSubmission) {
        nameAr = s.name
        name = s.nameEn ?? ""
        roasterNameAr = s.roasterName
        roasterName = s.roasterNameEn ?? ""
        let origin = s.originName.flatMap(Self.country(matching:))
        originCode = origin?.code
        originNameAr = origin?.nameAr ?? s.originName ?? ""
        process = s.process.flatMap { ReferenceCodes.process($0)?.code }
        roastLevel = s.roastLevel.flatMap(RoastLevel.init(rawValue:))
        flavorNotes = s.flavorNotes
        descriptionAr = ""
    }

    /// Finds a reference country by Arabic or English name or alias.
    public static func country(matching text: String) -> ReferenceEntry? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        return ReferenceCodes.countries.first { entry in
            entry.nameAr == t || entry.nameEn?.lowercased() == t || entry.aliases.contains(t) || entry.code.lowercased() == t
        }
    }

    public var missingFields: [String] {
        var missing: [String] = []
        if nameAr.trimmingCharacters(in: .whitespaces).count < 2 { missing.append("الاسم بالعربي") }
        if roasterNameAr.trimmingCharacters(in: .whitespaces).count < 2 { missing.append("المحمصة بالعربي") }
        if originCode == nil { missing.append("المنشأ") }
        if process == nil { missing.append("المعالجة") }
        return missing
    }

    func payload() -> [String: Any] {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var body: [String: Any] = [
            "nameAr": t(nameAr), "name": t(name), "roasterNameAr": t(roasterNameAr), "roasterName": t(roasterName),
            "originCode": originCode ?? "", "originNameAr": t(originNameAr), "process": process ?? "",
            "flavorNotes": flavorNotes.map(t).filter { !$0.isEmpty },
        ]
        if let roastLevel { body["roastLevel"] = roastLevel.rawValue }
        if !t(descriptionAr).isEmpty { body["descriptionAr"] = t(descriptionAr) }
        return body
    }
}

/// What a bulk review did: the ids that went through, and the rest with why.
public struct RemoteBulkReview: Codable, Equatable, Sendable {
    public struct Failure: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let reason: String
        public init(id: String, name: String, reason: String) {
            self.id = id; self.name = name; self.reason = reason
        }
    }
    public let done: [String]
    public let failed: [Failure]
}

extension CatalogAPIClient {
    public func fetchMe(accessToken: String) async throws -> RemoteMe {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/me", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteMe.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func fetchMySubmissions(accessToken: String) async throws -> [RemoteMySubmission] {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/submissions", bearer: accessToken))
        try Self.checkContract(response)
        struct Wrapper: Decodable { let submissions: [RemoteMySubmission] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).submissions }
        catch { throw AuthClientError.malformedResponse }
    }

    /// `status` is PENDING, APPROVED or REJECTED.
    public func adminSubmissions(status: String, accessToken: String) async throws -> [RemoteAdminSubmission] {
        let response = try await transport.send(
            HTTPRequest(method: .get, path: "/api/v1/admin/submissions?status=\(status)", bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Wrapper: Decodable { let submissions: [RemoteAdminSubmission] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).submissions }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Publishes the lot; returns its slug.
    public func approveSubmission(id: String, form: ApprovalForm, accessToken: String) async throws -> String {
        let data = (try? JSONSerialization.data(withJSONObject: form.payload())) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/admin/submissions/\(id)/approve", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Approved: Decodable { let lotSlug: String }
        do { return try JSONDecoder().decode(Approved.self, from: response.body).lotSlug }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Adds a bundled batch of coffees as pending suggestions (admins only). Safe to repeat.
    public func importBatch(_ batch: String, accessToken: String) async throws -> RemoteImportResult {
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/admin/import/\(batch)", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteImportResult.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Approves (each as it stands) or rejects several suggestions at once; the
    /// ones that didn't go through come back with a reason in Arabic.
    public func bulkReview(ids: [String], approve: Bool, reason: String? = nil, accessToken: String) async throws -> RemoteBulkReview {
        var body: [String: Any] = ["ids": ids, "action": approve ? "approve" : "reject"]
        if let reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty { body["reason"] = reason }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/admin/submissions/bulk", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteBulkReview.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func rejectSubmission(id: String, reason: String?, accessToken: String) async throws {
        var body: [String: Any] = [:]
        if let reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty { body["reason"] = reason }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/admin/submissions/\(id)/reject", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
    }
}
