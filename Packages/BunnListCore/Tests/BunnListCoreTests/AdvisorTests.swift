import XCTest
@testable import BunnListCore

final class AdvisorTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private(set) var requests: [HTTPRequest] = []
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return HTTPResponse(status: 200, body: Data(#"{"understood":{"chips":["توت"]},"picks":[{"lot":{"id":"1","slug":"guji","name":"Guji","nameAr":"قوجي","roasterNameAr":"ر","originNameAr":null,"originCode":null,"process":"NATURAL","processLabel":null,"flavorNotes":["توت"],"roastLevel":null,"averageRating":4.5,"reviewCount":2,"imageUrl":null},"score":94,"reason":"توت · تنفع V60","tag":"الأنسب لك"}]}"#.utf8))
        }
    }

    func testMilkOnlyAfterEspresso() {
        var a = AdvisorAnswers()
        a.method = .v60
        XCTAssertFalse(a.steps.contains(.milk))
        a.method = .espresso
        XCTAssertEqual(a.steps, [.mood, .method, .milk, .flavors, .serve, .adventure, .text])
        a.mood = .calm; a.serve = .iced
        XCTAssertFalse(a.isComplete)
        a.milk = true
        XCTAssertTrue(a.isComplete)
    }

    func testRequestBodyAndDecode() async throws {
        var a = AdvisorAnswers()
        a.mood = .calm; a.method = .v60; a.milk = true; a.serve = .iced; a.adventure = 0.834
        a.families = [.floral, .berry]; a.text = "  توت بدون مرارة "
        let transport = FakeTransport()
        let result = try await CatalogAPIClient(transport: transport).advise(a, accessToken: nil)
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: transport.requests[0].body ?? Data()) as? [String: Any])
        XCTAssertEqual(sent["mood"] as? String, "calm")
        XCTAssertEqual(sent["families"] as? [String], ["berry", "floral"])
        XCTAssertNil(sent["milk"]) // not espresso
        XCTAssertEqual(sent["serve"] as? String, "ICED")
        XCTAssertEqual(sent["adventure"] as? Double, 0.83)
        XCTAssertEqual(sent["text"] as? String, "توت بدون مرارة")
        XCTAssertEqual(result.picks.first?.score, 94)
        XCTAssertEqual(result.understood?.chips, ["توت"])
    }
}
