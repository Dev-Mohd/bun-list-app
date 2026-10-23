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

    func testFetchLotDetailDecodesAndCallsSlugPath() async throws {
        let body = """
        {"id":"lot-1","slug":"yirgacheffe-natural","name":"Yirgacheffe Natural","nameAr":"يرجاتشيف طبيعي","roasterNameAr":"كامل ستيب","originNameAr":"إثيوبيا","originCode":"ET","process":"NATURAL","processLabel":"Natural","flavorNotes":["فراولة"],"roastLevel":null,"averageRating":4.5,"reviewCount":2,"imageUrl":null,"descriptionAr":"وصف","regionAr":"يرجاتشيف","variety":"Heirloom","recommendedBrewMethods":["V60"],"brewStats":[{"method":"V60","averageRating":4.8,"reviewCount":5,"wouldBuyAgain":4}]}
        """
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(body.utf8)) }
        let detail = try await CatalogAPIClient(transport: transport).fetchLotDetail(slug: "yirgacheffe-natural")
        XCTAssertEqual(detail.descriptionAr, "وصف")
        XCTAssertEqual(detail.variety, "Heirloom")
        let stat = try XCTUnwrap(detail.brewStats.first)
        XCTAssertEqual(stat.method, "V60")
        XCTAssertEqual(stat.averageRating, 4.8, accuracy: 0.001)
        XCTAssertEqual(transport.requests.first?.path, "/api/v1/catalog/lots/yirgacheffe-natural")
    }

    func testSubmitReviewSendsBearerAndBodyAndDecodesResult() async throws {
        let responseBody = #"{"averageRating":4.5,"reviewCount":3,"review":{"rating":5,"brewMethod":"V60","wouldBuyAgain":true,"body":"ممتاز"}}"#
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(responseBody.utf8)) }
        let client = CatalogAPIClient(transport: transport)

        let result = try await client.submitReview(slug: "yirgacheffe-natural", accessToken: "acc.jwt",
                                                    rating: 5, brewMethod: "V60", wouldBuyAgain: true, body: "ممتاز")
        XCTAssertEqual(result.averageRating, 4.5, accuracy: 0.001)
        XCTAssertEqual(result.reviewCount, 3)
        XCTAssertEqual(result.review.rating, 5)

        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.path, "/api/v1/catalog/lots/yirgacheffe-natural/review")
        XCTAssertEqual(req.bearer, "acc.jwt")
        let sent = (try? JSONSerialization.jsonObject(with: req.body ?? Data())) as? [String: Any]
        XCTAssertEqual(sent?["rating"] as? Int, 5)
        XCTAssertEqual(sent?["brewMethod"] as? String, "V60")
        XCTAssertEqual(sent?["wouldBuyAgain"] as? Bool, true)
        XCTAssertEqual(sent?["body"] as? String, "ممتاز")
    }

    func testSubmitReviewMapsUnauthorizedForRefresh() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 401, body: Data(#"{"error":"unauthorized"}"#.utf8)) }
        let client = CatalogAPIClient(transport: transport)
        await XCTAssertThrowsErrorAsync(
            try await client.submitReview(slug: "s", accessToken: "expired", rating: 4, brewMethod: "V60", wouldBuyAgain: false, body: nil)
        ) { error in
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testFetchMyReviewReturnsNilWhenNone() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(#"{"review":null}"#.utf8)) }
        let review = try await CatalogAPIClient(transport: transport).fetchMyReview(slug: "s", accessToken: "acc.jwt")
        XCTAssertNil(review)
    }

    func testUpdateCollectionSendsFlagsAndBearer() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(#"{"owned":true,"favorite":false,"wantsToTry":true,"tried":false}"#.utf8)) }
        let client = CatalogAPIClient(transport: transport)
        let flags = try await client.updateCollectionFlags(slug: "s", accessToken: "acc.jwt",
                                                           owned: true, favorite: false, wantsToTry: true, tried: false)
        XCTAssertTrue(flags.owned)
        XCTAssertTrue(flags.wantsToTry)
        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.method, .put)
        XCTAssertEqual(req.path, "/api/v1/catalog/lots/s/collection")
        XCTAssertEqual(req.bearer, "acc.jwt")
        let sent = (try? JSONSerialization.jsonObject(with: req.body ?? Data())) as? [String: Any]
        XCTAssertEqual(sent?["owned"] as? Bool, true)
        XCTAssertEqual(sent?["wantsToTry"] as? Bool, true)
    }

    func testFetchCollectionDecodesEntries() async throws {
        let body = #"{"entries":[{"lotId":"l1","slug":"s1","nameAr":"قهوة","roasterNameAr":"محمصة","owned":true,"favorite":false,"wantsToTry":false,"tried":true}]}"#
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(body.utf8)) }
        let items = try await CatalogAPIClient(transport: transport).fetchCollection(accessToken: "acc.jwt")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.slug, "s1")
        XCTAssertEqual(items.first?.tried, true)
    }

    func testFetchReviewsDecodesList() async throws {
        let body = #"{"reviews":[{"id":"r1","rating":5,"brewMethod":"V60","wouldBuyAgain":true,"body":"لذيذ","authorName":"محمد","createdAt":"2026-01-02T03:04:05.000Z"},{"id":"r2","rating":3,"brewMethod":"ESPRESSO","wouldBuyAgain":false,"body":null,"authorName":"مستخدم","createdAt":"2026-01-01T00:00:00.000Z"}]}"#
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(body.utf8)) }
        let reviews = try await CatalogAPIClient(transport: transport).fetchReviews(slug: "yirgacheffe-natural")
        XCTAssertEqual(reviews.count, 2)
        XCTAssertEqual(reviews[0].authorName, "محمد")
        XCTAssertEqual(reviews[0].rating, 5)
        XCTAssertNil(reviews[1].body)
        XCTAssertEqual(transport.requests.first?.path, "/api/v1/catalog/lots/yirgacheffe-natural/reviews")
    }

    func testServerErrorThrows() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 500, body: Data("boom".utf8)) }
        let client = CatalogAPIClient(transport: transport)
        await XCTAssertThrowsErrorAsync(try await client.fetchLots()) { error in
            XCTAssertEqual(error as? AuthClientError, .server(status: 500))
        }
    }
}
