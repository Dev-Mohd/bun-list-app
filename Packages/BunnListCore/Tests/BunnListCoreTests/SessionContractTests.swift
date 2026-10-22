import XCTest
@testable import BunnListCore

/// C03 — refresh-token rotation with reuse detection. Tokens are stored hashed; presenting an
/// already-rotated token is treated as theft and revokes the whole family.
final class SessionContractTests: XCTestCase {
    let account = "acct-1"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testRotationIssuesANewTokenEachTime() throws {
        var family = RefreshTokenFamily(accountID: account, initialToken: "t0", now: t0)
        let r1 = try family.rotate(presenting: "t0", now: at(10))
        XCTAssertNotEqual(r1.newToken, "t0")
        // The new token rotates to yet another (reuse of an old token is covered separately).
        let r2 = try family.rotate(presenting: r1.newToken, now: at(30))
        XCTAssertNotEqual(r2.newToken, r1.newToken)
    }

    func testReusingAnAlreadyRotatedTokenRevokesTheFamily() throws {
        var family = RefreshTokenFamily(accountID: account, initialToken: "t0", now: t0)
        let r1 = try family.rotate(presenting: "t0", now: at(10))
        _ = try family.rotate(presenting: r1.newToken, now: at(20))
        // "t0" was already rotated away — presenting it again is reuse.
        XCTAssertThrowsError(try family.rotate(presenting: "t0", now: at(30))) {
            XCTAssertEqual($0 as? AuthError, .refreshTokenReuseDetected)
        }
        XCTAssertTrue(family.isRevoked)
        // After revocation even the latest valid token is dead.
        XCTAssertThrowsError(try family.rotate(presenting: r1.newToken, now: at(40))) {
            XCTAssertEqual($0 as? AuthError, .sessionRevoked)
        }
    }

    func testTokensAreNotStoredInPlaintext() throws {
        let family = RefreshTokenFamily(accountID: account, initialToken: "super-secret", now: t0)
        XCTAssertFalse(family.debugStoredRepresentation.contains("super-secret"), "stored token must be a hash")
    }

    func testExpiredTokenIsRejected() throws {
        var family = RefreshTokenFamily(accountID: account, initialToken: "t0", now: t0)
        XCTAssertThrowsError(try family.rotate(presenting: "t0", now: at(RefreshTokenFamily.ttlSeconds + 1))) {
            XCTAssertEqual($0 as? AuthError, .refreshTokenExpired)
        }
    }
}

/// C03 — age gate (16+) and terms acceptance required before first publish.
final class AccountPolicyTests: XCTestCase {
    let gate = AgeGate(minimumAge: 16)
    let cal = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15

    func testAgeGateUsesTheConfiguredMinimum() {
        let sixteen = cal.date(byAdding: .year, value: -16, to: now)!
        let almost = cal.date(byAdding: .day, value: 1, to: cal.date(byAdding: .year, value: -16, to: now)!)!
        XCTAssertTrue(gate.meets(birthDate: sixteen, now: now))
        XCTAssertFalse(gate.meets(birthDate: almost, now: now), "one day short of 16 fails")
        XCTAssertEqual(gate.minimumAge, 16)
    }

    func testTermsMustBeAcceptedAtCurrentVersionBeforeFirstPublish() {
        var acceptance = TermsAcceptanceState(currentVersion: "2026-10-01")
        XCTAssertFalse(acceptance.mayPublish)
        acceptance.accept(version: "2025-01-01", at: now) // old version
        XCTAssertFalse(acceptance.mayPublish, "accepting an outdated version is not enough")
        acceptance.accept(version: "2026-10-01", at: now)
        XCTAssertTrue(acceptance.mayPublish)
    }
}
