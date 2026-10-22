import XCTest
@testable import BunnListCore

/// C03 — server idempotency (spec test 22). Replaying a creation returns the same resource; the same
/// key with a different payload is a conflict; an expired response cache still resolves to the same
/// resource (the creation identity is permanent); a deleted resource is not recreated by an old retry.
final class IdempotencyContractTests: XCTestCase {
    let owner = "acct-1"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    private func key(_ k: String) -> IdempotencyKey {
        IdempotencyKey(ownerID: owner, operation: "createExperience", clientID: ClientID(string: k) ?? ClientID())
    }

    func testFirstCallReservesAndCompletes() throws {
        var store = IdempotencyStore()
        let k = key("11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(try store.begin(k, payloadHash: "h1", now: t0), .proceed)
        store.complete(k, resourceID: "exp-1", response: "created", now: t0)
        XCTAssertEqual(try store.begin(k, payloadHash: "h1", now: at(1)), .replay(resourceID: "exp-1", response: "created"))
    }

    func testSameKeyDifferentPayloadConflicts() throws {
        var store = IdempotencyStore()
        let k = key("22222222-2222-2222-2222-222222222222")
        _ = try store.begin(k, payloadHash: "h1", now: t0)
        store.complete(k, resourceID: "exp-2", response: "created", now: t0)
        XCTAssertThrowsError(try store.begin(k, payloadHash: "DIFFERENT", now: at(1))) {
            XCTAssertEqual($0 as? APIError, .conflict)
        }
    }

    func testExpiredResponseCacheStillResolvesToTheSameResource() throws {
        var store = IdempotencyStore()
        let k = key("33333333-3333-3333-3333-333333333333")
        _ = try store.begin(k, payloadHash: "h1", now: t0)
        store.complete(k, resourceID: "exp-3", response: "created", now: t0)
        // After the response cache TTL, the same key+payload returns the same resource id, not a new one.
        let outcome = try store.begin(k, payloadHash: "h1", now: at(IdempotencyStore.responseCacheTTLSeconds + 10))
        XCTAssertEqual(outcome, .replay(resourceID: "exp-3", response: nil), "identity persists; cached body may be gone")
    }

    func testDeletedResourceIsNotRecreatedByAnOldRetry() throws {
        var store = IdempotencyStore()
        let k = key("44444444-4444-4444-4444-444444444444")
        _ = try store.begin(k, payloadHash: "h1", now: t0)
        store.complete(k, resourceID: "exp-4", response: "created", now: t0)
        store.markDeleted(k)
        XCTAssertThrowsError(try store.begin(k, payloadHash: "h1", now: at(5))) {
            XCTAssertEqual($0 as? APIError, .conflict, "a tombstoned creation is not replayed into a new resource")
        }
    }

    func testConcurrentReserveOfTheSameKeyProceedsOnceThenReplays() throws {
        var store = IdempotencyStore()
        let k = key("55555555-5555-5555-5555-555555555555")
        XCTAssertEqual(try store.begin(k, payloadHash: "h1", now: t0), .proceed)
        // A second begin before completion must wait/replay, not proceed to a duplicate create.
        XCTAssertEqual(try store.begin(k, payloadHash: "h1", now: t0), .inProgress)
    }
}

/// C03 — API error model carries the HTTP status the client contract expects.
final class APIErrorTests: XCTestCase {
    func testStatusCodes() {
        XCTAssertEqual(APIError.unauthorized.status, 401)
        XCTAssertEqual(APIError.forbidden.status, 403)
        XCTAssertEqual(APIError.conflict.status, 409)
        XCTAssertEqual(APIError.unprocessable.status, 422)
        XCTAssertEqual(APIError.rateLimited.status, 429)
    }
}
