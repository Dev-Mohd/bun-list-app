import XCTest
@testable import BunnListCore

/// C03 — identity resolution and linking rules (spec test 8: identities are not linked by email alone).
final class AuthContractTests: XCTestCase {
    var directory = IdentityDirectory()

    private func apple(_ sub: String, email: String? = nil, relay: Bool = false) -> AuthIdentity {
        AuthIdentity(provider: .apple, subject: sub, email: email, emailIsPrivateRelay: relay)
    }
    private func google(_ sub: String, email: String?) -> AuthIdentity {
        AuthIdentity(provider: .google, subject: sub, email: email, emailIsPrivateRelay: false)
    }

    func testSameProviderSubjectResolvesToTheSameAccount() throws {
        let first = try directory.signIn(with: apple("apple-1", email: "a@me.com"))
        let again = try directory.signIn(with: apple("apple-1", email: "a@me.com"))
        XCTAssertEqual(first.accountID, again.accountID)
        XCTAssertTrue(first.isNewAccount, "the first sign-in creates the account")
        XCTAssertFalse(again.isNewAccount, "the second resolves to the same account")
    }

    func testTwoProvidersWithTheSameEmailDoNotMergeAutomatically() throws {
        let a = try directory.signIn(with: apple("apple-1", email: "same@me.com"))
        let g = try directory.signIn(with: google("google-1", email: "same@me.com"))
        XCTAssertNotEqual(a.accountID, g.accountID, "a shared email must not merge two providers")
    }

    func testApplePrivateRelayEmailIsNeverTreatedAsAGoogleEmail() throws {
        let a = try directory.signIn(with: apple("apple-2", email: "xyz@privaterelay.appleid.com", relay: true))
        let g = try directory.signIn(with: google("google-2", email: "xyz@privaterelay.appleid.com"))
        XCTAssertNotEqual(a.accountID, g.accountID)
    }

    func testLinkingRequiresAVerifiedSessionAndProofOfTheSecondIdentity() throws {
        let account = try directory.signIn(with: apple("apple-3", email: nil)).accountID
        let google = google("google-3", email: "g@me.com")
        // Unverified session is rejected.
        XCTAssertThrowsError(try directory.link(google, to: account, session: .unverified, proof: .verified(google))) {
            XCTAssertEqual($0 as? AuthError, .sessionNotVerified)
        }
        // Missing/Мmismatched proof of the second identity is rejected.
        XCTAssertThrowsError(try directory.link(google, to: account, session: .verified(account), proof: .missing)) {
            XCTAssertEqual($0 as? AuthError, .secondIdentityNotProven)
        }
        // Verified session + proof links it.
        try directory.link(google, to: account, session: .verified(account), proof: .verified(google))
        XCTAssertEqual(try directory.signIn(with: google).accountID, account, "the linked identity now resolves to that account")
    }

    func testAnIdentityAlreadyBoundElsewhereCannotBeLinked() throws {
        let accountA = try directory.signIn(with: apple("apple-A", email: nil)).accountID
        let other = google("google-X", email: "x@me.com")
        _ = try directory.signIn(with: other) // binds `other` to its own account
        XCTAssertThrowsError(try directory.link(other, to: accountA, session: .verified(accountA), proof: .verified(other))) {
            XCTAssertEqual($0 as? AuthError, .identityAlreadyLinked)
        }
    }
}

/// C03 — email one-time code: expiry, attempt cap, resend rate limit, and non-revealing responses.
final class EmailOTPTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testRequestResponseDoesNotRevealWhetherTheEmailExists() {
        var service = EmailOTPService(knownEmails: ["real@me.com"])
        let a = service.requestCode(email: "real@me.com", now: t0)
        let b = service.requestCode(email: "ghost@me.com", now: t0)
        XCTAssertEqual(a.acknowledgement, b.acknowledgement, "both return the same neutral acknowledgement")
    }

    func testCorrectCodeWithinWindowVerifies() throws {
        var service = EmailOTPService(knownEmails: [])
        let issued = service.requestCode(email: "a@me.com", now: t0)
        let code = try XCTUnwrap(issued.debugCode)
        XCTAssertEqual(try service.verify(email: "a@me.com", code: code, now: at(60)), .verified)
    }

    func testExpiredCodeIsRejected() throws {
        var service = EmailOTPService(knownEmails: [])
        let code = try XCTUnwrap(service.requestCode(email: "a@me.com", now: t0).debugCode)
        XCTAssertThrowsError(try service.verify(email: "a@me.com", code: code, now: at(EmailOTPService.ttlSeconds + 1))) {
            XCTAssertEqual($0 as? AuthError, .codeExpired)
        }
    }

    func testWrongCodeConsumesAttemptsAndLocksOut() throws {
        var service = EmailOTPService(knownEmails: [])
        _ = service.requestCode(email: "a@me.com", now: t0)
        for _ in 0..<EmailOTPService.maxAttempts {
            XCTAssertThrowsError(try service.verify(email: "a@me.com", code: "000000", now: at(10))) {
                XCTAssertEqual($0 as? AuthError, .codeIncorrect)
            }
        }
        XCTAssertThrowsError(try service.verify(email: "a@me.com", code: "000000", now: at(10))) {
            XCTAssertEqual($0 as? AuthError, .tooManyAttempts)
        }
    }

    func testResendIsRateLimited() {
        var service = EmailOTPService(knownEmails: [])
        _ = service.requestCode(email: "a@me.com", now: t0)
        let tooSoon = service.requestCode(email: "a@me.com", now: at(5))
        XCTAssertTrue(tooSoon.rateLimited, "a resend inside the cooldown is rate limited")
        let later = service.requestCode(email: "a@me.com", now: at(EmailOTPService.resendCooldownSeconds + 1))
        XCTAssertFalse(later.rateLimited)
    }
}
