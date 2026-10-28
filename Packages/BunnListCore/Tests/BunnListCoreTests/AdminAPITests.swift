import XCTest
@testable import BunnListCore

final class AdminAPITests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    private let submissionJSON = #"{"id":"s1","status":"PENDING","name":"سويت بلند","nameEn":"Sweet Blend","roasterName":"ثري بين","roasterNameEn":"3 Bean Coffee Roastery","originName":"اثيوبيا","process":"WASHED","roastLevel":"medium","flavorNotes":["شوكولاتة"],"note":null,"photoUrl":"https://x/signed","authorName":"محمد","approvedLotSlug":null,"reviewNote":null,"createdAt":"2026-10-25T00:00:00.000Z"}"#

    func testApprovalFormPrefillsAndMapsTheOriginAlias() throws {
        let s = try JSONDecoder().decode(RemoteAdminSubmission.self, from: Data(submissionJSON.utf8))
        var form = ApprovalForm(s)
        XCTAssertEqual(form.originCode, "ET") // "اثيوبيا" is an alias of إثيوبيا
        XCTAssertEqual(form.originNameAr, "إثيوبيا")
        XCTAssertEqual(form.process, "WASHED")
        XCTAssertEqual(form.roastLevel, .medium)
        XCTAssertEqual(form.missingFields, [])
        form.name = "" // optional: written by the server
        form.roasterName = ""
        form.originCode = nil
        XCTAssertEqual(form.missingFields, ["المنشأ"])
    }

    func testApproveAndRejectCallTheAdminEndpoints() async throws {
        let s = try JSONDecoder().decode(RemoteAdminSubmission.self, from: Data(submissionJSON.utf8))
        let transport = FakeTransport { req in
            req.path.hasSuffix("/approve")
                ? HTTPResponse(status: 200, body: Data(#"{"lotSlug":"3-bean-sweet-blend"}"#.utf8))
                : HTTPResponse(status: 200, body: Data(#"{"ok":true}"#.utf8))
        }
        let client = CatalogAPIClient(transport: transport)
        let slug = try await client.approveSubmission(id: "s1", form: ApprovalForm(s), accessToken: "adm")
        XCTAssertEqual(slug, "3-bean-sweet-blend")
        let body = try XCTUnwrap((try? JSONSerialization.jsonObject(with: transport.requests[0].body ?? Data())) as? [String: Any])
        XCTAssertEqual(body["originCode"] as? String, "ET")
        XCTAssertEqual(body["roasterName"] as? String, "3 Bean Coffee Roastery")

        try await client.rejectSubmission(id: "s1", reason: "مكررة", accessToken: "adm")
        XCTAssertEqual(transport.requests[1].path, "/api/v1/admin/submissions/s1/reject")
    }

    func testBulkReviewSendsIdsAndReadsFailures() async throws {
        let transport = FakeTransport { _ in
            HTTPResponse(status: 200, body: Data(#"{"done":["s1"],"failed":[{"id":"s2","name":"غريبة","reason":"بلد المنشأ غير معروف"}]}"#.utf8))
        }
        let result = try await CatalogAPIClient(transport: transport).bulkReview(ids: ["s1", "s2"], approve: true, accessToken: "adm")
        XCTAssertEqual(result.done, ["s1"])
        XCTAssertEqual(result.failed.first?.name, "غريبة")
        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.path, "/api/v1/admin/submissions/bulk")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.body ?? Data()) as? [String: Any])
        XCTAssertEqual(body["action"] as? String, "approve")
        XCTAssertEqual(body["ids"] as? [String], ["s1", "s2"])
    }

    func testDeletingAUsedLotIsAConflict() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 409, body: Data(#"{"error":"conflict","reason":"lot_in_use"}"#.utf8)) }
        do {
            try await CatalogAPIClient(transport: transport).deleteAdminLot(id: "L1", accessToken: "adm")
            XCTFail("expected conflict")
        } catch let error as APIError {
            XCTAssertEqual(error, .conflict)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(transport.requests.first?.method, .delete)
    }

    func testNonAdminsGetForbidden() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 403, body: Data(#"{"error":"forbidden"}"#.utf8)) }
        do {
            _ = try await CatalogAPIClient(transport: transport).adminSubmissions(status: "PENDING", accessToken: "u")
            XCTFail("expected forbidden")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testMeAndMySubmissionsDecode() async throws {
        let transport = FakeTransport { req in
            req.path == "/api/v1/me"
                ? HTTPResponse(status: 200, body: Data(#"{"isAdmin":true,"discoveries":2}"#.utf8))
                : HTTPResponse(status: 200, body: Data(#"{"submissions":[{"id":"s1","name":"ق","roasterName":"م","status":"APPROVED","lotSlug":"q","reviewNote":null,"hasPhoto":true,"createdAt":"2026-10-25T00:00:00.000Z"}]}"#.utf8))
        }
        let client = CatalogAPIClient(transport: transport)
        let me = try await client.fetchMe(accessToken: "a")
        XCTAssertTrue(me.isAdmin)
        XCTAssertEqual(me.discoveries, 2)
        let mine = try await client.fetchMySubmissions(accessToken: "a")
        XCTAssertEqual(mine.first?.lotSlug, "q")
    }
}
