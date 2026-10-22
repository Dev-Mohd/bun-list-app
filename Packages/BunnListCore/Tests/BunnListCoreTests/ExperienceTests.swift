import XCTest
@testable import BunnListCore

/// C02 — experiences are independent entities; their stars never feed the lot's rating average.
final class ExperienceTests: XCTestCase {
    let alice = OwnerID.guest(UUID())
    let bob = OwnerID.guest(UUID())
    let lot = LotID("sample:lot/guji-2025")
    let other = LotID("sample:lot/huila-unknown")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    // MARK: Lot rating stats — spec test 3

    func testLotAverageAndCountComeFromPublishedVotesOnly() {
        let votes = [
            RatingVote(clientID: ClientID(), ownerID: alice, lotID: lot, stars: 5, updatedAt: t0),
            RatingVote(clientID: ClientID(), ownerID: bob, lotID: lot, stars: 3, updatedAt: t0),
            RatingVote(clientID: ClientID(), ownerID: alice, lotID: other, stars: 1, updatedAt: t0),
        ]
        let stats = LotStats.rating(for: lot, votes: votes)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.average, 4.0)
        XCTAssertEqual(LotStats.rating(for: LotID("sample:lot/nyeri-unknown"), votes: votes).average, nil)
        XCTAssertEqual(LotStats.rating(for: LotID("sample:lot/nyeri-unknown"), votes: votes).count, 0)
    }

    func testExperienceStarsDoNotEnterTheLotAverage() throws {
        var book = ExperienceBook()
        // Two experiences on the lot, 5 and 1 stars.
        _ = try book.add(owner: alice, lot: lot, methodCode: "V60", stars: 5, brewedAt: t0, now: t0, publish: true)
        _ = try book.add(owner: alice, lot: lot, methodCode: "ESPRESSO", stars: 1, brewedAt: at(1), now: at(1), publish: true)
        // One rating vote of 3.
        let votes = [RatingVote(clientID: ClientID(), ownerID: alice, lotID: lot, stars: 3, updatedAt: t0)]
        let stats = LotStats.rating(for: lot, votes: votes)
        XCTAssertEqual(stats.average, 3.0, "experience stars must not move the lot average")
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(book.published(owner: alice, lot: lot).count, 2)
    }

    // MARK: Multiple experiences — spec test 3

    func testMultipleExperiencesForTheSameLotAreIndependent() throws {
        var book = ExperienceBook()
        let a = try book.add(owner: alice, lot: lot, methodCode: "V60", stars: 4, brewedAt: t0, now: t0, publish: true)
        let b = try book.add(owner: alice, lot: lot, methodCode: "CHEMEX", stars: 2, brewedAt: at(1), now: at(1), publish: true)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(book.all(owner: alice).count, 2)
        // Deleting one leaves the other and does not touch any rating.
        try book.setLifecycle(a, owner: alice, to: .deleted, now: at(2))
        XCTAssertEqual(book.published(owner: alice, lot: lot).map(\.clientID), [b])
    }

    func testStarsOutsideOneToFiveAreRejected() {
        var book = ExperienceBook()
        XCTAssertThrowsError(try book.add(owner: alice, lot: lot, methodCode: "V60", stars: 0, brewedAt: t0, now: t0))
        XCTAssertThrowsError(try book.add(owner: alice, lot: lot, methodCode: "V60", stars: 6, brewedAt: t0, now: t0))
        XCTAssertThrowsError(try book.add(owner: alice, lot: lot, methodCode: "NOT_A_METHOD", stars: 3, brewedAt: t0, now: t0))
    }

    // MARK: Lifecycle — spec test 25 applied to experiences

    func testUnpublishAndRepublishKeepIdentityAndDeleteIsFinal() throws {
        var book = ExperienceBook()
        let id = try book.add(owner: alice, lot: lot, methodCode: "V60", stars: 5, brewedAt: t0, now: t0, publish: true)
        XCTAssertTrue(book.experience(id, owner: alice)!.lifecycle.isPubliclyVisible)
        try book.setLifecycle(id, owner: alice, to: .unpublished, now: at(1))
        XCTAssertTrue(book.published(owner: alice, lot: lot).isEmpty)
        try book.setLifecycle(id, owner: alice, to: .published, now: at(2))
        XCTAssertEqual(book.published(owner: alice, lot: lot).map(\.clientID), [id], "clientID is stable across republish")
        try book.setLifecycle(id, owner: alice, to: .deleted, now: at(3))
        XCTAssertThrowsError(try book.setLifecycle(id, owner: alice, to: .published, now: at(4)))
    }

    func testNonOwnerCannotEditOrDeleteAnExperience() throws {
        var book = ExperienceBook()
        let id = try book.add(owner: alice, lot: lot, methodCode: "V60", stars: 5, brewedAt: t0, now: t0, publish: true)
        XCTAssertThrowsError(try book.setLifecycle(id, owner: bob, to: .deleted, now: at(1))) {
            XCTAssertEqual($0 as? ExperienceError, .notOwner)
        }
        XCTAssertThrowsError(try book.setNote(id, owner: bob, note: "x", now: at(1)))
    }

    // MARK: Brew stats — unique individuals per method, not slices of a pie

    func testBrewStatsCountDistinctOwnersPerMethod() throws {
        var book = ExperienceBook()
        _ = try book.add(owner: alice, lot: lot, methodCode: "V60", stars: 4, brewedAt: t0, now: t0, publish: true)
        _ = try book.add(owner: alice, lot: lot, methodCode: "V60", stars: 5, brewedAt: at(1), now: at(1), publish: true)
        _ = try book.add(owner: bob, lot: lot, methodCode: "V60", stars: 3, brewedAt: at(2), now: at(2), publish: true)
        _ = try book.add(owner: bob, lot: lot, methodCode: "ESPRESSO", stars: 2, brewedAt: at(3), now: at(3), publish: true)
        // A draft (unpublished) must not count.
        _ = try book.add(owner: alice, lot: lot, methodCode: "CHEMEX", stars: 1, brewedAt: at(4), now: at(4), publish: false)
        let counts = LotStats.brewMethodParticipants(for: lot, in: book)
        XCTAssertEqual(counts["V60"], 2, "two distinct people, not three experiences")
        XCTAssertEqual(counts["ESPRESSO"], 1)
        XCTAssertNil(counts["CHEMEX"], "a draft is not public and is not counted")
        // The counts are per-method participation and intentionally do not sum to the people total.
        XCTAssertEqual(counts.values.reduce(0, +), 3)
    }
}
