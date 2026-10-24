import XCTest
@testable import BunnListCore

final class BagScanTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    private let body = #"{"extraction":{"isCoffeeBag":true,"name":"Yirgacheffe Konga","nameAr":null,"roaster":"Camel Step","originCountry":"Ethiopia","originCountryAr":"إثيوبيا","originCountryCode":"ET","region":"Yirgacheffe","farm":null,"producer":null,"varieties":["Heirloom"],"process":"WASHED","processLabel":"Washed","roastLevel":"light","roastDate":"2026-10-01","altitudeMeters":2100,"flavorNotesAr":["ياسمين","ليمون"],"weightGrams":250,"recommendedBrewMethods":["V60"],"confidence":"high"},"matches":[{"id":"lot-1","slug":"konga","name":"Konga","nameAr":"كونغا","roasterNameAr":"كامل ستيب","originNameAr":"إثيوبيا","originCode":"ET","process":"WASHED","processLabel":"Washed","flavorNotes":[],"roastLevel":null,"averageRating":0,"reviewCount":0,"imageUrl":null}],"remainingToday":29}"#

    func testSendsTheJPEGAndDecodesTheResult() async throws {
        let transport = FakeTransport { [body] _ in HTTPResponse(status: 200, body: Data(body.utf8)) }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let result = try await CatalogAPIClient(transport: transport).scanBag(jpeg: jpeg, accessToken: "acc")
        XCTAssertEqual(result.extraction.roaster, "Camel Step")
        XCTAssertEqual(result.extraction.roastLevel, .light)
        XCTAssertEqual(result.matches.first?.slug, "konga")
        XCTAssertEqual(result.remainingToday, 29)

        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.path, "/api/v1/scan/bag")
        XCTAssertEqual(req.bearer, "acc")
        let sent = try XCTUnwrap((try? JSONSerialization.jsonObject(with: req.body ?? Data())) as? [String: Any])
        XCTAssertEqual(sent["imageBase64"] as? String, jpeg.base64EncodedString())
        XCTAssertEqual(sent["mediaType"] as? String, "image/jpeg")
    }

    func testDerivedValues() throws {
        let result = try JSONDecoder().decode(RemoteBagScanResult.self, from: Data(body.utf8))
        let e = result.extraction
        XCTAssertEqual(e.displayName, "Yirgacheffe Konga")
        let now = ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z")!
        XCTAssertEqual(e.daysSinceRoast(now: now), 14)
        XCTAssertTrue(e.suggestionNote.contains("النكهات: ياسمين، ليمون"))
        XCTAssertTrue(e.suggestionNote.contains("الارتفاع: 2100 م"))
    }

    func testLimitAndConfigErrorsMapToTheContract() async {
        for (status, expected) in [(429, APIError.rateLimited), (403, APIError.forbidden), (422, APIError.unprocessable)] {
            let transport = FakeTransport { _ in HTTPResponse(status: status, body: Data("{}".utf8)) }
            do {
                _ = try await CatalogAPIClient(transport: transport).scanBag(jpeg: Data([1]), accessToken: "a")
                XCTFail("expected \(expected)")
            } catch let error as APIError {
                XCTAssertEqual(error, expected)
            } catch {
                XCTFail("unexpected \(error)")
            }
        }
    }
}
