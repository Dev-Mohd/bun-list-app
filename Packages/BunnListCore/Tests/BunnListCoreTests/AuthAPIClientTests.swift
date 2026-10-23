import XCTest
@testable import BunnListCore

/// C03 (app side) — the networking client's request shape and status→error mapping,
/// exercised with a fake transport so no real network is touched.
final class AuthAPIClientTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    private func body(_ request: HTTPRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any] ?? [:]
    }

    func testVerifyEmailSendsCorrectRequestAndDecodesTokens() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: ["accessToken": "acc.jwt", "refreshToken": "sess.secret", "accessExpiresInSeconds": 900, "accountId": "acct-1", "isNewAccount": true]) ) }
        let client = AuthAPIClient(transport: transport)

        let tokens = try await client.verifyEmailCode(email: "a@b.com", code: "123456", deviceID: "dev-1")

        XCTAssertEqual(tokens.accessToken, "acc.jwt")
        XCTAssertEqual(tokens.refreshToken, "sess.secret")
        XCTAssertEqual(tokens.accountID, "acct-1")
        XCTAssertEqual(tokens.isNewAccount, true)

        let req = transport.requests.first!
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.path, "/api/v1/auth/email/verify")
        XCTAssertEqual(body(req)["email"] as? String, "a@b.com")
        XCTAssertEqual(body(req)["code"] as? String, "123456")
        XCTAssertEqual(body(req)["deviceId"] as? String, "dev-1")
    }

    func testRequestEmailCodePostsEmail() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: ["ok": true])) }
        let client = AuthAPIClient(transport: transport)
        try await client.requestEmailCode(email: "a@b.com")
        let req = transport.requests.first!
        XCTAssertEqual(req.path, "/api/v1/auth/email/request")
        XCTAssertEqual(body(req)["email"] as? String, "a@b.com")
    }

    func testRefreshDecodesTokensAndSendsRefreshToken() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: ["accessToken": "a2", "refreshToken": "r2", "accessExpiresInSeconds": 900, "accountId": "acct-1"])) }
        let client = AuthAPIClient(transport: transport)
        let tokens = try await client.refresh(refreshToken: "sess.old")
        XCTAssertEqual(tokens.refreshToken, "r2")
        XCTAssertNil(tokens.isNewAccount)
        XCTAssertEqual(body(transport.requests.first!)["refreshToken"] as? String, "sess.old")
    }

    func testDeleteAccountSendsBearer() async throws {
        let transport = FakeTransport { _ in HTTPResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: ["ok": true])) }
        let client = AuthAPIClient(transport: transport)
        try await client.deleteAccount(accessToken: "acc.jwt")
        let req = transport.requests.first!
        XCTAssertEqual(req.path, "/api/v1/account/delete")
        XCTAssertEqual(req.bearer, "acc.jwt")
    }

    func testWrongCodeMapsTo401Unauthorized() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 401, body: Data("{\"error\":\"unauthorized\",\"reason\":\"code_invalid\"}".utf8)) }
        let client = AuthAPIClient(transport: transport)
        await XCTAssertThrowsErrorAsync(try await client.verifyEmailCode(email: "a@b.com", code: "000000", deviceID: "d")) { error in
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testTooManyAttemptsMapsTo429RateLimited() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 429, body: Data("{\"error\":\"rateLimited\"}".utf8)) }
        let client = AuthAPIClient(transport: transport)
        await XCTAssertThrowsErrorAsync(try await client.verifyEmailCode(email: "a@b.com", code: "000000", deviceID: "d")) { error in
            XCTAssertEqual(error as? APIError, .rateLimited)
        }
    }

    func testServerErrorMapsToClientServerError() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 500, body: Data("boom".utf8)) }
        let client = AuthAPIClient(transport: transport)
        await XCTAssertThrowsErrorAsync(try await client.refresh(refreshToken: "x")) { error in
            XCTAssertEqual(error as? AuthClientError, .server(status: 500))
        }
    }
}

// Small async throwing-assert helper (XCTAssertThrowsError has no async overload).
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error to be thrown", file: file, line: line)
    } catch {
        handler(error)
    }
}
