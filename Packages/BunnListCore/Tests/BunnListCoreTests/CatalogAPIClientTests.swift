import XCTest
@testable import BunnListCore

/// C04 (app side) — the read-only catalog feed client decodes the server DTO and
/// maps non-2xx to an error, exercised with a fake transport.
final class CatalogAPIClientTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    func testFetchLotsDecodesTheFeedAndCallsTheRightPath() async throws {
        let body = """
        {"lots":[{"id":"lot-1","slug":"yirgacheffe-natural","name":"Yirgacheffe Natural","nameAr":"يرجاتشيف طبيعي","roasterNameAr":"كامل ستيب","originNameAr":"إثيوبيا","originCode":"ET","process":"NATURAL","processLabel":"Natural","flavorNotes":["فراولة","ياسمين"],"roastLevel":"فاتح","averageRating":4.5,"reviewCount":12,"imageUrl":null}]}
        """
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(body.utf8)) }
        let client = CatalogAPIClient(transport: transport)

        let lots = try await client.fetchLots()

        XCTAssertEqual(lots.count, 1)
        XCTAssertEqual(lots[0].nameAr, "يرجاتشيف طبيعي")
        XCTAssertEqual(lots[0].roasterNameAr, "كامل ستيب")
        XCTAssertEqual(lots[0].averageRating, 4.5, accuracy: 0.001)
        XCTAssertNil(lots[0].imageUrl)
        XCTAssertEqual(transport.requests.first?.path, "/api/v1/catalog/lots")
        XCTAssertEqual(transport.requests.first?.method, .get)
    }

    func testEmptyFeedIsAllowed() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(#"{"lots":[]}"#.utf8)) }
        let lots = try await CatalogAPIClient(transport: transport).fetchLots()
        XCTAssertTrue(lots.isEmpty)
    }

    func testServerErrorThrows() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 500, body: Data("boom".utf8)) }
        let client = CatalogAPIClient(transport: transport)
        await XCTAssertThrowsErrorAsync(try await client.fetchLots()) { error in
            XCTAssertEqual(error as? AuthClientError, .server(status: 500))
        }
    }
}
