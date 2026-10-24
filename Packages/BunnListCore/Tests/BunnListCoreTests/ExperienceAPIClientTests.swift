import XCTest
@testable import BunnListCore

/// Server brew experiences: list / save / lifecycle change, with a fake transport.
final class ExperienceAPIClientTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    private let one = #"{"id":"e1","clientId":"c1","methodCode":"V60","stars":4,"brewedAt":"2026-10-24T08:00:00.000Z","note":"حلاوة","state":"published","revision":1,"updatedAt":"2026-10-24T09:00:00.000Z"}"#

    func testFetchDecodesListAndSendsBearer() async throws {
        let body = #"{"experiences":["# + one + "]}"
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: Data(body.utf8)) }
        let list = try await CatalogAPIClient(transport: transport).fetchMyExperiences(slug: "s", accessToken: "acc")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].state, .published)
        XCTAssertEqual(list[0].note, "حلاوة")
        XCTAssertNotNil(list[0].brewedDate)
        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.path, "/api/v1/catalog/lots/s/experiences")
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(req.bearer, "acc")
    }

    func testSavePostsTheExperience() async throws {
        let transport = FakeTransport { [one] _ in HTTPResponse(status: 200, body: Data(one.utf8)) }
        let saved = try await CatalogAPIClient(transport: transport).saveExperience(
            slug: "s", accessToken: "acc", clientID: "c1", methodCode: "V60", stars: 4,
            brewedAt: Date(timeIntervalSince1970: 0), note: "حلاوة", publish: true)
        XCTAssertEqual(saved.id, "e1")
        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.method, .post)
        let sent = try XCTUnwrap((try? JSONSerialization.jsonObject(with: req.body ?? Data())) as? [String: Any])
        XCTAssertEqual(sent["clientId"] as? String, "c1")
        XCTAssertEqual(sent["stars"] as? Int, 4)
        XCTAssertEqual(sent["publish"] as? Bool, true)
        XCTAssertEqual(sent["brewedAt"] as? String, "1970-01-01T00:00:00Z")
    }

    func testStateChangePatchesAndMapsConflict() async throws {
        let ok = FakeTransport { [one] _ in HTTPResponse(status: 200, body: Data(one.utf8)) }
        _ = try await CatalogAPIClient(transport: ok).changeExperienceState(id: "e1", to: .unpublished, accessToken: "acc")
        let req = try XCTUnwrap(ok.requests.first)
        XCTAssertEqual(req.method, .patch)
        XCTAssertEqual(req.path, "/api/v1/experiences/e1")
        let sent = (try? JSONSerialization.jsonObject(with: req.body ?? Data())) as? [String: Any]
        XCTAssertEqual(sent?["state"] as? String, "unpublished")

        let conflict = FakeTransport { _ in HTTPResponse(status: 409, body: Data(#"{"error":"conflict"}"#.utf8)) }
        do {
            _ = try await CatalogAPIClient(transport: conflict).changeExperienceState(id: "e1", to: .published, accessToken: "acc")
            XCTFail("expected conflict")
        } catch let error as APIError {
            XCTAssertEqual(error, .conflict)
        }
    }
}
