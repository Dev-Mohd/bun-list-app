import XCTest
@testable import BunnListCore

final class PointsTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    func testPointsAndLeaderboardDecode() async throws {
        let transport = FakeTransport { req in
            req.path.hasPrefix("/api/v1/me/points")
                ? HTTPResponse(status: 200, body: Data(#"{"total":85,"week":30,"streak":4,"recent":[{"kind":"rate","points":10,"createdAt":"2026-10-26T09:00:00.000Z"}]}"#.utf8))
                : HTTPResponse(status: 200, body: Data(#"{"entries":[{"rank":1,"name":"Mohd","username":"mohd","avatarUrl":null,"points":85,"isMe":true}],"me":{"rank":1,"points":85}}"#.utf8))
        }
        let client = CatalogAPIClient(transport: transport)
        let points = try await client.fetchPoints(accessToken: "a")
        XCTAssertEqual(points.streak, 4)
        XCTAssertEqual(PointRules.titleAr(points.recent[0].kind), "تقيّم قهوة")
        let board = try await client.fetchLeaderboard(allTime: true, accessToken: nil)
        XCTAssertEqual(board.me?.rank, 1)
        XCTAssertEqual(transport.requests[1].path, "/api/v1/community/leaderboard?period=all&kind=points&limit=50")
        XCTAssertNil(transport.requests[1].bearer)
        _ = try await client.fetchLeaderboard(allTime: true, kind: .discoverers, limit: 3, accessToken: nil)
        XCTAssertEqual(transport.requests[2].path, "/api/v1/community/leaderboard?period=all&kind=discoverers&limit=3")
    }

    func testRulesTableMatchesTheServer() {
        let byKind = Dictionary(uniqueKeysWithValues: PointRules.table.map { ($0.kind, $0.points) })
        XCTAssertEqual(byKind, ["collect": 5, "rate": 10, "experience": 5, "recipe": 20, "discovery": 50, "streak7": 25])
    }
}
