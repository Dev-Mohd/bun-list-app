import Foundation

// Taps on the site's download buttons (/api/v1/admin/site-clicks): totals by platform,
// by button and by day. Admins only.

public struct RemoteSiteClicks: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public let day: String
        public let count: Int
        public var id: String { day }
    }

    public let days: Int
    public let total: Int
    public let byPlatform: [String: Int]
    public let bySource: [String: Int]
    public let byDay: [Day]

    /// Rows for a breakdown, biggest first (ties by name so the order is stable).
    public static func sorted(_ counts: [String: Int]) -> [(key: String, count: Int)] {
        counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { (key: $0.key, count: $0.value) }
    }

    public static func platformAr(_ key: String) -> String {
        switch key {
        case "ios": return "iPhone (App Store)"
        case "android": return "Android (صفحة التثبيت)"
        case "apk": return "Android (تحميل الملف)"
        case "desktop": return "كمبيوتر"
        default: return key
        }
    }

    public static func sourceAr(_ key: String) -> String {
        switch key {
        case "hero": return "الزر الرئيسي أول الصفحة"
        case "bar": return "الشريط الثابت تحت"
        case "nav": return "زر «حمّل» فوق"
        case "champions": return "قسم وصفات الأبطال"
        case "closing": return "آخر الصفحة"
        case "qr": return "رمز QR"
        case "android-page": return "صفحة Android"
        case "direct": return "رابط مباشر"
        default: return key
        }
    }
}

extension CatalogAPIClient {
    public func adminSiteClicks(days: Int = 30, accessToken: String) async throws -> RemoteSiteClicks {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/admin/site-clicks?days=\(days)", bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteSiteClicks.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
