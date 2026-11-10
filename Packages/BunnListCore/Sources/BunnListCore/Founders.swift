import Foundation

// «مبدع مؤسس»: the first 100 creators get a numbered, permanent badge, and only they can
// show their accounts elsewhere on their profile and recipes (/api/v1/founders,
// PATCH /api/v1/me/profile { socials }).

/// A founder's number, shown as «#07».
public struct FounderBadge: Codable, Equatable, Hashable, Sendable {
    public let number: Int
    public init(number: Int) { self.number = number }

    public var label: String { Self.label(number) }
    public static func label(_ number: Int) -> String { "#" + (number < 10 ? "0\(number)" : "\(number)") }
}

/// The networks a founder can link.
public enum SocialNetwork: String, CaseIterable, Codable, Sendable, Identifiable {
    case tiktok, instagram, youtube, x
    public var id: String { rawValue }

    public var nameAr: String {
        switch self {
        case .tiktok: return "تيك توك"
        case .instagram: return "إنستقرام"
        case .youtube: return "يوتيوب"
        case .x: return "إكس"
        }
    }

    /// Two letters for the small tile (we don't draw the networks' logos).
    public var mark: String {
        switch self {
        case .tiktok: return "TT"
        case .instagram: return "IG"
        case .youtube: return "YT"
        case .x: return "X"
        }
    }

    public func url(for handle: String) -> URL? {
        switch self {
        case .tiktok: return URL(string: "https://www.tiktok.com/@\(handle)")
        case .instagram: return URL(string: "https://www.instagram.com/\(handle)")
        case .youtube: return URL(string: "https://www.youtube.com/@\(handle)")
        case .x: return URL(string: "https://x.com/\(handle)")
        }
    }

    /// The handle from what someone typed: "@name", "name" or a profile link; nil when it isn't one.
    /// Mirrors the server's check so the form can say what's wrong before saving.
    public func handle(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hosts: [String]
        switch self {
        case .tiktok: hosts = ["tiktok.com/@", "tiktok.com/"]
        case .instagram: hosts = ["instagram.com/"]
        case .youtube: hosts = ["youtube.com/@", "youtube.com/c/", "youtube.com/user/", "youtube.com/"]
        case .x: hosts = ["x.com/", "twitter.com/"]
        }
        let lower = text.lowercased()
        for host in hosts {
            if let range = lower.range(of: host) {
                text = String(text[range.upperBound...])
                break
            }
        }
        while text.hasPrefix("@") { text.removeFirst() }
        text = String(text.split(whereSeparator: { "/?#".contains($0) }).first ?? "")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let max = self == .x ? 15 : 30
        guard !text.isEmpty, text.count <= max, text.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return text
    }
}

/// A founder's accounts elsewhere, as handles.
public struct Socials: Codable, Equatable, Hashable, Sendable {
    public var tiktok: String?
    public var instagram: String?
    public var youtube: String?
    public var x: String?

    public init(tiktok: String? = nil, instagram: String? = nil, youtube: String? = nil, x: String? = nil) {
        self.tiktok = tiktok; self.instagram = instagram; self.youtube = youtube; self.x = x
    }

    public subscript(network: SocialNetwork) -> String? {
        get {
            switch network {
            case .tiktok: return tiktok
            case .instagram: return instagram
            case .youtube: return youtube
            case .x: return x
            }
        }
        set {
            switch network {
            case .tiktok: tiktok = newValue
            case .instagram: instagram = newValue
            case .youtube: youtube = newValue
            case .x: x = newValue
            }
        }
    }

    /// One linked account.
    public struct Link: Equatable, Hashable, Sendable, Identifiable {
        public let network: SocialNetwork
        public let handle: String
        public var id: String { network.rawValue }
        public var url: URL? { network.url(for: handle) }
    }

    /// The linked networks in a fixed order, with their handles.
    public var linked: [Link] {
        SocialNetwork.allCases.compactMap { n in self[n].flatMap { $0.isEmpty ? nil : Link(network: n, handle: $0) } }
    }

    public var isEmpty: Bool { linked.isEmpty }
}

/// How many founder badges are given, of the limit (100).
public struct FounderStats: Codable, Equatable, Sendable {
    public let limit: Int
    public let taken: Int
    public let remaining: Int

    public init(limit: Int, taken: Int, remaining: Int) {
        self.limit = limit; self.taken = taken; self.remaining = remaining
    }

    public var progress: Double { limit > 0 ? min(1, Double(taken) / Double(limit)) : 0 }
    public var isFull: Bool { remaining <= 0 }
}

extension CatalogAPIClient {
    public func fetchFounderStats() async throws -> FounderStats {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/founders"))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(FounderStats.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Founders only: sets or clears linked accounts. Each value is a handle or link; "" clears it.
    /// The server answers 403 (founders_only) for everyone else and 422 (invalid_<network>) for a bad handle.
    public func updateSocials(_ values: [SocialNetwork: String], accessToken: String) async throws -> RemoteProfile {
        var socials: [String: Any] = [:]
        for (network, value) in values { socials[network.rawValue] = value }
        let data = (try? JSONSerialization.data(withJSONObject: ["socials": socials])) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .patch, path: "/api/v1/me/profile", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteProfile.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
