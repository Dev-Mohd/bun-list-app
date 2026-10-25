import XCTest
@testable import BunnListCore

final class ProfileAPITests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    private let profileJSON = #"{"username":"mohd","displayName":"Mohd","bio":"قهوة","avatarUrl":"https://x/avatars/a.jpg","onboarded":false}"#

    func testMeDecodesProfileAndOlderServers() throws {
        let me = try JSONDecoder().decode(RemoteMe.self, from: Data(#"{"isAdmin":false,"discoveries":1,"username":"mohd","displayName":"Mohd","bio":null,"avatarUrl":null,"onboarded":false}"#.utf8))
        XCTAssertFalse(me.isOnboarded)
        XCTAssertEqual(me.displayName, "Mohd")
        let old = try JSONDecoder().decode(RemoteMe.self, from: Data(#"{"isAdmin":false,"discoveries":0,"username":null}"#.utf8))
        XCTAssertTrue(old.isOnboarded) // never pushes setup on an older server
    }

    func testProfileCalls() async throws {
        let transport = FakeTransport { [profileJSON] req in
            switch req.path {
            case "/api/v1/me/username/suggest": return HTTPResponse(status: 200, body: Data(#"{"username":"mohd42"}"#.utf8))
            case "/api/v1/me/onboarded": return HTTPResponse(status: 200, body: Data(#"{"onboarded":true}"#.utf8))
            default: return HTTPResponse(status: 200, body: Data(profileJSON.utf8))
            }
        }
        let client = CatalogAPIClient(transport: transport)
        let updated = try await client.updateProfile(displayName: "Mohd", bio: nil, accessToken: "a")
        XCTAssertEqual(updated.bio, "قهوة")
        let sent = (try? JSONSerialization.jsonObject(with: transport.requests[0].body ?? Data())) as? [String: Any]
        XCTAssertEqual(sent?["displayName"] as? String, "Mohd")
        XCTAssertNil(sent?["bio"])
        XCTAssertEqual(transport.requests[0].method, .patch)

        _ = try await client.uploadAvatar(jpeg: Data([0xFF, 0xD8, 0xFF]), accessToken: "a")
        XCTAssertEqual(transport.requests[1].path, "/api/v1/me/avatar")
        XCTAssertEqual(transport.requests[1].method, .put)

        let suggestion = try await client.suggestUsername(accessToken: "a")
        XCTAssertEqual(suggestion, "mohd42")
        try await client.markOnboarded(accessToken: "a")
        XCTAssertEqual(transport.requests.last?.method, .post)
    }

    func testSummaryDecodes() async throws {
        let body = #"{"collection":{"owned":2,"favorite":1,"wantsToTry":3,"tried":4},"recentBags":["https://x/a.jpg"],"discoveries":1,"submissions":2,"recipes":3,"experiences":4,"ratings":6,"taste":{"unlocked":true,"progress":5,"required":5,"averageRating":4.2,"topOrigins":[{"name":"إثيوبيا","count":3,"average":4.7}],"topProcesses":[{"name":"WASHED","count":2,"average":4.5}],"topFlavors":["ياسمين"],"favoriteMethod":"V60"}}"#
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(body.utf8)) }
        let summary = try await CatalogAPIClient(transport: transport).fetchProfileSummary(accessToken: "a")
        XCTAssertEqual(summary.collection.wantsToTry, 3)
        XCTAssertEqual(summary.taste.topOrigins.first?.name, "إثيوبيا")
        XCTAssertEqual(summary.taste.favoriteMethod, "V60")
        XCTAssertEqual(transport.requests.first?.path, "/api/v1/me/summary")
    }
}
