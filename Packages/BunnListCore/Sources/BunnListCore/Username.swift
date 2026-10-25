import Foundation

// Public @usernames (GET/PUT /api/v1/me/username). The rules mirror the server's so
// the app can explain a problem while the user types; the server stays the judge
// of availability.

public enum UsernameProblem: String, Codable, Equatable, Sendable {
    case tooShort = "too_short"
    case tooLong = "too_long"
    case mustStartWithLetter = "must_start_with_letter"
    case invalidChars = "invalid_chars"
    case reserved
    case taken

    public var messageAr: String {
        switch self {
        case .tooShort: return "٣ أحرف على الأقل"
        case .tooLong: return "٢٠ حرف كحد أقصى"
        case .mustStartWithLetter: return "يبدأ بحرف إنجليزي"
        case .invalidChars: return "حروف إنجليزية صغيرة وأرقام و _ و . فقط"
        case .reserved: return "هذا الاسم محجوز"
        case .taken: return "الاسم مستخدم، جرّب غيره"
        }
    }
}

public enum UsernameRules {
    private static let reserved: Set<String> = [
        "admin", "administrator", "support", "help", "bunnlist", "bunn", "official", "root", "system",
        "moderator", "mod", "staff", "team", "null", "undefined", "me", "settings", "api",
    ]

    public static func normalize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix("@") { s.removeFirst() }
        return s.lowercased()
    }

    public static func problem(_ username: String) -> UsernameProblem? {
        if username.count < 3 { return .tooShort }
        if username.count > 20 { return .tooLong }
        guard let first = username.unicodeScalars.first, ("a"..."z").contains(first) else { return .mustStartWithLetter }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")
        if !username.unicodeScalars.allSatisfy(allowed.contains) || username.contains("..") || username.hasSuffix(".") {
            return .invalidChars
        }
        if reserved.contains(username) { return .reserved }
        return nil
    }
}

public struct RemoteUsernameCheck: Codable, Equatable, Sendable {
    public let username: String
    public let available: Bool
    public let problem: UsernameProblem?
}

extension CatalogAPIClient {
    public func checkUsername(_ candidate: String, accessToken: String) async throws -> RemoteUsernameCheck {
        let q = candidate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let response = try await transport.send(
            HTTPRequest(method: .get, path: "/api/v1/me/username?check=\(q)", bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteUsernameCheck.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    /// Claims the username; `APIError.conflict` when someone else has it.
    public func setUsername(_ username: String, accessToken: String) async throws -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["username": username])) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .put, path: "/api/v1/me/username", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        struct Saved: Decodable { let username: String }
        do { return try JSONDecoder().decode(Saved.self, from: response.body).username }
        catch { throw AuthClientError.malformedResponse }
    }
}
