import XCTest
@testable import BunnListCore

final class SocialTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    func testProfileFollowAndLists() async throws {
        let transport = FakeTransport { req in
            if req.path == "/api/v1/users/mohd" {
                return HTTPResponse(status: 200, body: Data(#"{"username":"mohd","displayName":"Mohd","bio":null,"avatarUrl":null,"points":85,"followers":3,"following":1,"isFollowing":false,"isMe":false,"discoveries":[],"recipes":[{"id":"r1","title":"صباحية","methodCode":"V60","lotNameAr":null}]}"#.utf8))
            }
            if req.path.hasSuffix("/followers") {
                return HTTPResponse(status: 200, body: Data(#"{"people":[{"username":"badr","displayName":null,"avatarUrl":null}]}"#.utf8))
            }
            return HTTPResponse(status: 200, body: Data(#"{"following":true}"#.utf8))
        }
        let client = CatalogAPIClient(transport: transport)
        let profile = try await client.fetchUser("mohd", accessToken: "a")
        XCTAssertEqual(profile.followers, 3)
        XCTAssertEqual(profile.recipes.first?.title, "صباحية")

        try await client.setFollowing(true, username: "mohd", accessToken: "a")
        XCTAssertEqual(transport.requests[1].method, .post)
        XCTAssertEqual(transport.requests[1].path, "/api/v1/users/mohd/follow")
        try await client.setFollowing(false, username: "mohd", accessToken: "a")
        XCTAssertEqual(transport.requests[2].method, .delete)

        let people = try await client.fetchFollowList(.followers, username: "mohd")
        XCTAssertEqual(people.first?.username, "badr")
    }
}
