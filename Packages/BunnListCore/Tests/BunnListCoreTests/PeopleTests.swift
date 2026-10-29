import XCTest
@testable import BunnListCore

final class PeopleTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    func testFollowingAPrivateAccountComesBackAsARequest() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(#"{"following":false,"requested":true}"#.utf8)) }
        let state = try await CatalogAPIClient(transport: transport).setFollowing(true, username: "sara", accessToken: "t")
        XCTAssertEqual(state, .requested)
        XCTAssertEqual(state.buttonAr, "طلبت المتابعة")
        XCTAssertEqual(transport.requests.first?.path, "/api/v1/users/sara/follow")
    }

    func testSearchDecodesCardsAndEscapesTheQuery() async throws {
        let transport = FakeTransport { _ in
            HTTPResponse(status: 200, body: Data(#"{"people":[{"username":"sara","displayName":"سارة","avatarUrl":null,"isPrivate":true,"isFollowing":false,"requested":true,"reasonAr":null}]}"#.utf8))
        }
        let people = try await CatalogAPIClient(transport: transport).searchPeople("@سارة", accessToken: nil)
        XCTAssertEqual(people.first?.followState, .requested)
        let path = try XCTUnwrap(transport.requests.first?.path)
        XCTAssertTrue(path.hasPrefix("/api/v1/users/search?q="))
        XCTAssertFalse(path.contains("@"))
    }

    func testShelvesDecodeWithCounts() async throws {
        let transport = FakeTransport { _ in
            HTTPResponse(status: 200, body: Data(#"{"counts":{"owned":2,"tried":5,"favorite":1,"wantsToTry":0},"coffees":[{"lotId":"l1","slug":"a","nameAr":"أ","roasterNameAr":"ر","originNameAr":null,"originCode":null,"imageUrl":null,"owned":false,"favorite":true,"wantsToTry":false,"tried":true}]}"#.utf8))
        }
        let shelf = try await CatalogAPIClient(transport: transport).personCoffees("sara", shelf: .favorite, accessToken: nil)
        XCTAssertEqual(shelf.counts[.tried], 5)
        XCTAssertTrue(CoffeeShelf.favorite.contains(try XCTUnwrap(shelf.coffees.first)))
        XCTAssertEqual(transport.requests.first?.path, "/api/v1/users/sara/coffees?shelf=favorite")
    }

    func testHiddenShelvesAreForbidden() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 403, body: Data(#"{"error":"forbidden","reason":"hidden_by_owner"}"#.utf8)) }
        do {
            _ = try await CatalogAPIClient(transport: transport).personCoffees("sara", shelf: .owned, accessToken: "t")
            XCTFail("expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAnsweringARequestSendsTheChoice() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        try await CatalogAPIClient(transport: transport).answerFollowRequest(username: "badr", accept: true, accessToken: "t")
        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.path, "/api/v1/me/follow-requests/badr")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.body ?? Data()) as? [String: Any])
        XCTAssertEqual(body["accept"] as? Bool, true)
    }
}
