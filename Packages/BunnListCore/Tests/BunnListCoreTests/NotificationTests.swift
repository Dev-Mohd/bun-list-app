import XCTest
@testable import BunnListCore

final class NotificationTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private(set) var requests: [HTTPRequest] = []
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return HTTPResponse(status: 200, body: Data(#"{"newFollower":false,"submissionApproved":true,"submissionRejected":true}"#.utf8))
        }
    }

    func testHexToken() {
        XCTAssertEqual(CatalogAPIClient.hexToken(Data([0x0a, 0xff, 0x01])), "0aff01")
    }

    func testClient() async throws {
        let transport = FakeTransport()
        let client = CatalogAPIClient(transport: transport)
        try await client.registerDevice(token: "ab", environment: .sandbox, accessToken: "a")
        let body = try JSONSerialization.jsonObject(with: transport.requests[0].body!) as? [String: String]
        XCTAssertEqual(body, ["token": "ab", "environment": "sandbox"])
        XCTAssertEqual(transport.requests[0].path, "/api/v1/me/devices")
        let settings = try await client.fetchNotificationSettings(accessToken: "a")
        XCTAssertFalse(settings.newFollower)
        _ = try await client.saveNotificationSettings(RemoteNotificationSettings(newFollower: true), accessToken: "a")
        XCTAssertEqual(transport.requests[2].method, .patch)
    }
}
