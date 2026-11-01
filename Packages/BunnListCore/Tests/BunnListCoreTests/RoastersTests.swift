import XCTest
@testable import BunnListCore

final class RoastersTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    private let lot = #"{"id":"1","slug":"guji","name":"Guji","nameAr":"قوجي","roasterNameAr":"ر","roasterSlug":"r","originNameAr":"إثيوبيا","originCode":"ET","process":"NATURAL","processLabel":null,"flavorNotes":["توت"],"roastLevel":null,"averageRating":4.5,"reviewCount":2,"imageUrl":null}"#
    private var card: String { #"{"slug":"r","nameAr":"ر","name":"R","cityAr":null,"lots":3,"averageRating":4.4,"reviews":9,"images":[],"followers":2}"# }

    func testDecodesRoasterPageAndShares() throws {
        let json = #"{"roaster":\#(card),"isFollowing":true,"origins":[{"key":"إثيوبيا","count":2}],"processes":[],"families":[{"key":"berry","count":3},{"key":"floral","count":1},{"key":"nope","count":5}],"topRated":[\#(lot)],"newest":[],"lots":[\#(lot)]}"#
        let page = try JSONDecoder().decode(RemoteRoasterPage.self, from: Data(json.utf8))
        XCTAssertTrue(page.isFollowing)
        XCTAssertEqual(page.lots.first?.roasterSlug, "r")
        XCTAssertEqual(page.familyShares.map(\.family), [.berry, .floral])
        XCTAssertEqual(page.familyShares.map(\.percent), [75, 25])
    }

    func testOlderLotsHaveNoRoasterSlug() throws {
        let old = lot.replacingOccurrences(of: #""roasterSlug":"r","#, with: "")
        XCTAssertNil(try JSONDecoder().decode(RemoteLot.self, from: Data(old.utf8)).roasterSlug)
    }

    func testOriginsProgressAndCentroids() throws {
        let json = #"{"origins":[{"code":"ET","nameAr":"إثيوبيا","nameEn":null,"lots":2,"roasters":1,"averageRating":4.5,"families":[],"processes":[],"regions":["قوجي"],"tried":1},{"code":"ZZ","nameAr":"؟","nameEn":null,"lots":1,"roasters":1,"averageRating":0,"families":[],"processes":[],"regions":[],"tried":0}],"triedCountries":1}"#
        let origins = try JSONDecoder().decode(RemoteOrigins.self, from: Data(json.utf8))
        XCTAssertNotNil(origins.origins[0].coordinate)
        XCTAssertNil(origins.origins[1].coordinate)
        XCTAssertEqual(origins.progressLine, "جرّبت من \(1.formatted()) دولة من \(1.formatted())")
    }

    func testFollowCalls() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(#"{"following":true,"followers":3}"#.utf8)) }
        let client = CatalogAPIClient(transport: transport)
        let state = try await client.setRoasterFollow(slug: "r", follow: true, accessToken: "a")
        XCTAssertEqual(state, RemoteFollowState(following: true, followers: 3))
        XCTAssertEqual(transport.requests[0].method, .put)
        _ = try await client.setRoasterFollow(slug: "r", follow: false, accessToken: "a")
        XCTAssertEqual(transport.requests[1].method, .delete)
        XCTAssertEqual(transport.requests[1].path, "/api/v1/catalog/roasters/r/follow")
    }
}
