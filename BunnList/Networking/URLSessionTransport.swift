import BunnListCore
import Foundation

/// The real HTTP transport backing `AuthAPIClient`, using URLSession. Kept out of
/// BunnListCore so the package stays Apple-free and Linux-testable.
struct URLSessionTransport: HTTPTransport {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = ServerConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: baseURL.absoluteString + request.path) else {
            throw AuthClientError.malformedResponse
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer = request.bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }
}
