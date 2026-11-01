import XCTest
@testable import BunnListCore

final class ListsTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    private static let summary = #"{"id":"L1","title":"للضيوف","note":null,"emoji":"☕","isPublic":true,"count":2,"covers":["https://x/a.png"],"updatedAt":"2026-11-01T10:00:00.000Z","hasLot":true}"#
    private static let page = #"{"list":\#(summary),"owner":{"name":"Mohd","username":"mohd","avatarUrl":null},"isMine":false,"lots":[{"id":"1","slug":"guji","name":"Guji","nameAr":"قوجي","roasterNameAr":"ر","originNameAr":null,"originCode":null,"process":"NATURAL","processLabel":null,"flavorNotes":[],"roastLevel":null,"averageRating":4,"reviewCount":1,"imageUrl":null,"itemNote":"حلوة باردة","addedAt":"2026-11-01T10:00:00.000Z"}]}"#

    func testDecodesPageWithItemNotes() throws {
        let page = try JSONDecoder().decode(RemoteListPage.self, from: Data(Self.page.utf8))
        XCTAssertEqual(page.lots.first?.lot.slug, "guji")
        XCTAssertEqual(page.lots.first?.itemNote, "حلوة باردة")
        XCTAssertEqual(page.list.hasLot, true)
        XCTAssertEqual(page.list.countLine, "قهوتين")
    }

    func testCountWords() {
        XCTAssertEqual(ListText.count(0), "فاضية")
        XCTAssertEqual(ListText.count(1), "قهوة وحدة")
        XCTAssertEqual(ListText.count(5), "\(5.formatted()) قهاوي")
        XCTAssertEqual(ListText.count(14), "\(14.formatted()) قهوة")
    }

    func testDraftValidation() {
        XCTAssertFalse(ListDraft(title: "   ").isValid)
        XCTAssertTrue(ListDraft(title: "قهاوي الصيف").isValid)
        XCTAssertFalse(ListDraft(title: String(repeating: "ق", count: 41)).isValid)
    }

    func testCalls() async throws {
        let transport = FakeTransport { req in
            if req.path.hasPrefix("/api/v1/me/lists?") || req.path == "/api/v1/me/lists" && req.method == .get {
                return HTTPResponse(status: 200, body: Data(#"{"lists":[\#(ListsTests.summary)]}"#.utf8))
            }
            return HTTPResponse(status: 200, body: Data(ListsTests.summary.utf8))
        }
        let client = CatalogAPIClient(transport: transport)
        let mine = try await client.fetchMyLists(lotSlug: "guji", accessToken: "a")
        XCTAssertEqual(mine.first?.id, "L1")
        XCTAssertEqual(transport.requests[0].path, "/api/v1/me/lists?lot=guji")

        _ = try await client.createList(ListDraft(title: " للضيوف ", note: " "), accessToken: "a")
        let sent = (try? JSONSerialization.jsonObject(with: transport.requests[1].body ?? Data())) as? [String: Any]
        XCTAssertEqual(sent?["title"] as? String, "للضيوف")
        XCTAssertTrue(sent?["note"] is NSNull)

        _ = try await client.setListItem(listID: "L1", slug: "guji", add: true, accessToken: "a")
        XCTAssertEqual(transport.requests[2].method, .put)
        XCTAssertEqual(transport.requests[2].path, "/api/v1/me/lists/L1/items/guji")
        _ = try await client.setListItem(listID: "L1", slug: "guji", add: false, accessToken: "a")
        XCTAssertEqual(transport.requests[3].method, .delete)
    }

    func testSharedListLinks() {
        XCTAssertEqual(SharedLink.listID(from: URL(string: "https://bunnlist.com/lists/clx9abc")!), "clx9abc")
        XCTAssertNil(SharedLink.listID(from: URL(string: "https://bunnlist.com/coffees/clx9abc")!))
        XCTAssertNil(SharedLink.listID(from: URL(string: "https://evil.com/lists/x")!))
        XCTAssertEqual(SharedLink.listURL("L1").absoluteString, "https://bunnlist.com/lists/L1")
    }

    func testReviewCommentCount() throws {
        let json = #"{"id":"r","rating":5,"brewMethod":"V60","wouldBuyAgain":true,"body":null,"authorName":"م","createdAt":"x","helpfulCount":0,"markedHelpful":false,"isMine":false,"authorUsername":"m","commentCount":3}"#
        XCTAssertEqual(try JSONDecoder().decode(RemoteReview.self, from: Data(json.utf8)).commentCount, 3)
        XCTAssertEqual(CommentTarget.review.rawValue, "review")
    }
}
