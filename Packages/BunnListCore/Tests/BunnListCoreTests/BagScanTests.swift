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

    private let body = #"{"extraction":{"isCoffeeBag":true,"name":"Yirgacheffe Konga","nameAr":null,"roaster":"Camel Step","roasterAr":"كامل ستيب","originCountry":"Ethiopia","originCountryAr":"إثيوبيا","originCountryCode":"ET","region":"Yirgacheffe","farm":null,"producer":null,"varieties":["Heirloom"],"process":"WASHED","processLabel":"Washed","roastLevel":"light","roastDate":"2026-10-01","altitudeMeters":2100,"flavorNotesAr":["ياسمين","ليمون"],"weightGrams":250,"recommendedBrewMethods":["V60"],"confidence":"high"},"matches":[{"id":"lot-1","slug":"konga","name":"Konga","nameAr":"كونغا","roasterNameAr":"كامل ستيب","originNameAr":"إثيوبيا","originCode":"ET","process":"WASHED","processLabel":"Washed","flavorNotes":[],"roastLevel":null,"averageRating":0,"reviewCount":0,"imageUrl":null}],"remainingToday":29}"#

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
        XCTAssertFalse(e.suggestionNote.contains("النكهات")) // flavors have their own field now
        XCTAssertEqual(e.displayRoaster, "كامل ستيب")
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

    func testSuggestionFromAScanFillsEveryField() async throws {
        let result = try JSONDecoder().decode(RemoteBagScanResult.self, from: Data(body.utf8))
        let s = CoffeeSuggestion(scanned: result.extraction)
        XCTAssertEqual(s.name, "Yirgacheffe Konga") // no Arabic name printed: falls back to Latin
        XCTAssertEqual(s.nameEn, "Yirgacheffe Konga")
        XCTAssertEqual(s.roasterName, "كامل ستيب")
        XCTAssertEqual(s.roasterNameEn, "Camel Step")
        XCTAssertEqual(s.originName, "إثيوبيا")
        XCTAssertEqual(s.process, "WASHED")
        XCTAssertEqual(s.roastLevel, .light)
        XCTAssertEqual(s.flavorNotes, ["ياسمين", "ليمون"])

        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(#"{"id":"sub-1"}"#.utf8)) }
        let id = try await CatalogAPIClient(transport: transport).submitCoffee(s, accessToken: "acc")
        XCTAssertEqual(id, "sub-1")
        let sent = try XCTUnwrap((try? JSONSerialization.jsonObject(with: transport.requests[0].body ?? Data())) as? [String: Any])
        XCTAssertEqual(sent["roasterNameEn"] as? String, "Camel Step")
        XCTAssertEqual(sent["process"] as? String, "WASHED")
        XCTAssertEqual(sent["flavorNotes"] as? [String], ["ياسمين", "ليمون"])
    }

    func testSplittingFlavorNotes() {
        XCTAssertEqual(CoffeeSuggestion.notes(from: "شوكولاتة غنية، كراميل, نهاية حلوة،"), ["شوكولاتة غنية", "كراميل", "نهاية حلوة"])
    }

    func testUploadingASuggestionPhoto() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(#"{"photoPath":"submissions/s1.jpg"}"#.utf8)) }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2])
        try await CatalogAPIClient(transport: transport).uploadSuggestionPhoto(submissionID: "s1", jpeg: jpeg, accessToken: "acc")
        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.method, .put)
        XCTAssertEqual(req.path, "/api/v1/submissions/s1/photo")
        let sent = (try? JSONSerialization.jsonObject(with: req.body ?? Data())) as? [String: Any]
        XCTAssertEqual(sent?["imageBase64"] as? String, jpeg.base64EncodedString())
    }
}
