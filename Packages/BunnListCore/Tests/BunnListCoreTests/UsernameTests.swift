import XCTest
@testable import BunnListCore

final class UsernameTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    func testRulesMatchTheServer() {
        XCTAssertEqual(UsernameRules.normalize("  @Mohd_Coffee "), "mohd_coffee")
        XCTAssertNil(UsernameRules.problem("mohd"))
        XCTAssertNil(UsernameRules.problem("m.coffee_1"))
        XCTAssertEqual(UsernameRules.problem("mo"), .tooShort)
        XCTAssertEqual(UsernameRules.problem(String(repeating: "a", count: 21)), .tooLong)
        XCTAssertEqual(UsernameRules.problem("1mohd"), .mustStartWithLetter)
        XCTAssertEqual(UsernameRules.problem("محمد"), .mustStartWithLetter)
        XCTAssertEqual(UsernameRules.problem("mo hd"), .invalidChars)
        XCTAssertEqual(UsernameRules.problem("mo..hd"), .invalidChars)
        XCTAssertEqual(UsernameRules.problem("mohd."), .invalidChars)
        XCTAssertEqual(UsernameRules.problem("admin"), .reserved)
    }

    func testCheckAndClaim() async throws {
        let transport = FakeTransport { req in
            req.method == .get
                ? HTTPResponse(status: 200, body: Data(#"{"username":"mohd","available":false,"problem":"taken"}"#.utf8))
                : HTTPResponse(status: 200, body: Data(#"{"username":"mohd"}"#.utf8))
        }
        let client = CatalogAPIClient(transport: transport)
        let check = try await client.checkUsername("Mohd", accessToken: "a")
        XCTAssertEqual(check.problem, .taken)
        XCTAssertEqual(transport.requests[0].path, "/api/v1/me/username?check=Mohd")
        let saved = try await client.setUsername("mohd", accessToken: "a")
        XCTAssertEqual(saved, "mohd")
        XCTAssertEqual(transport.requests[1].method, .put)
    }

    func testMeCarriesTheUsername() throws {
        let me = try JSONDecoder().decode(RemoteMe.self, from: Data(#"{"isAdmin":false,"discoveries":0,"username":"mohd"}"#.utf8))
        XCTAssertEqual(me.username, "mohd")
        let none = try JSONDecoder().decode(RemoteMe.self, from: Data(#"{"isAdmin":false,"discoveries":0,"username":null}"#.utf8))
        XCTAssertNil(none.username)
    }
}
