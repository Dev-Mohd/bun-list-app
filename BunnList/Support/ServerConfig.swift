import Foundation

/// Where the app talks to the BunnList server. One place to change for staging vs production.
enum ServerConfig {
    /// Production deployment (Vercel). The mobile auth API lives under `/api/v1`.
    static let baseURL = URL(string: "https://bunnlist-fqdp.vercel.app")!
}
