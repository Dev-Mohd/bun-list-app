import Foundation

/// Minimum and latest app builds (/api/v1/app/config): below the minimum the app must update.
public struct RemoteAppConfig: Codable, Equatable, Sendable {
    public struct Platform: Codable, Equatable, Sendable {
        public let minBuild: Int
        public let latestBuild: Int
        public let storeUrl: String
    }
    public let ios: Platform
    public let android: Platform
    public let updateMessageAr: String

    public enum Verdict: Equatable, Sendable { case ok, suggested, required }

    /// What this build should do. 0 on the server means nothing is asked.
    public static func verdict(build: Int, platform: Platform) -> Verdict {
        if platform.minBuild > 0 && build < platform.minBuild { return .required }
        if platform.latestBuild > 0 && build < platform.latestBuild { return .suggested }
        return .ok
    }
}

extension CatalogAPIClient {
    public func appConfig() async throws -> RemoteAppConfig {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/app/config"))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteAppConfig.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
