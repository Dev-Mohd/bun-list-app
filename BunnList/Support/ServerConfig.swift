import Foundation

/// Where the app talks to the BunnList server. One place to change for staging vs production.
enum ServerConfig {
    /// Production (Vercel, on the bunnlist.com domain). The mobile API lives under
    /// `/api/v1`; shared coffee links use the same domain.
    static let baseURL = URL(string: "https://bunnlist.com")!
}
