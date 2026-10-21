import XCTest
@testable import BunnListCore

final class CollectionTests: XCTestCase {
    var catalog: Catalog!
    let alice = OwnerID.guest(UUID())
    let bob = OwnerID.guest(UUID())
    let guji2024 = LotID("sample:lot/guji-2024")
    let guji2025 = LotID("sample:lot/guji-2025")
    let gujiUnknown = LotID("sample:lot/guji-unknown")
    let huila = LotID("sample:lot/huila-unknown")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws { catalog = try Catalog.bundledSample() }

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    // MARK: Basic collection rules

    func testCollectOnceThenAlreadyOwnedWithStableClientID() throws {
        var book = CollectionBook()
        let entryID = ClientID()
        XCTAssertEqual(try book.collect(huila, owner: alice, catalog: catalog, operationID: ClientID(), newEntryID: entryID, now: t0),
                       .collected(firstTime: true))
        XCTAssertEqual(try book.collect(huila, owner: alice, catalog: catalog, operationID: ClientID(), now: at(1)), .alreadyOwned)
        XCTAssertEqual(book.entries.count, 1)
        XCTAssertEqual(book.entry(owner: alice, lot: huila)?.clientID, entryID)
        XCTAssertEqual(book.firstCollectionEvents.count, 1)
    }

    func testRetryingTheSameOperationReturnsTheStoredOutcomeAndDifferentPayloadIsRejected() throws {
        var book = CollectionBook()
        let op = ClientID()
        let first = try book.collect(huila, owner: alice, catalog: catalog, operationID: op, now: t0)
        let retry = try book.collect(huila, owner: alice, catalog: catalog, operationID: op, now: at(5))
        XCTAssertEqual(first, retry, "a retry is answered from the stored outcome, not re-evaluated")
        XCTAssertEqual(book.entries.count, 1)
        XCTAssertThrowsError(try book.collect(guji2024, owner: alice, catalog: catalog, operationID: op, now: at(6))) {
            XCTAssertEqual($0 as? CollectionError, .operationPayloadMismatch(op))
        }
    }

    func testRemoveThenRecollectIsNotAFirstCollection() throws {
        var book = CollectionBook()
        _ = try book.collect(huila, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        let id = book.entry(owner: alice, lot: huila)?.clientID
        try book.removeFromOwned(huila, owner: alice, now: at(1))
        XCTAssertTrue(book.activeEntries(owner: alice).isEmpty)
        XCTAssertEqual(try book.collect(huila, owner: alice, catalog: catalog, operationID: ClientID(), now: at(2)),
                       .collected(firstTime: false))
        XCTAssertEqual(book.entry(owner: alice, lot: huila)?.clientID, id, "re-collecting is an upsert on the same identity")
        XCTAssertEqual(book.entry(owner: alice, lot: huila)?.firstCollectedAt, t0)
        XCTAssertEqual(book.firstCollectionEvents.count, 1)
    }

    func testStatesAreIndependent() throws {
        var book = CollectionBook()
        try book.setWantsToTry(true, lot: huila, owner: alice, catalog: catalog, now: t0)
        var entry = try XCTUnwrap(book.entry(owner: alice, lot: huila))
        XCTAssertFalse(entry.isOwned)
        XCTAssertTrue(entry.wantsToTry)
        try book.setFavorite(true, lot: huila, owner: alice, catalog: catalog, now: at(1))
        _ = try book.collect(huila, owner: alice, catalog: catalog, operationID: ClientID(), now: at(2))
        try book.removeFromOwned(huila, owner: alice, now: at(3))
        entry = try XCTUnwrap(book.entry(owner: alice, lot: huila))
        XCTAssertFalse(entry.isOwned)
        XCTAssertTrue(entry.isFavorite)
        XCTAssertTrue(entry.wantsToTry)
        XCTAssertTrue(entry.isActive)
        XCTAssertEqual(book.entries.count, 1)
    }

    func testRatingMarksTriedButNotOwnedAndKeepsOneVote() throws {
        var book = CollectionBook()
        _ = try book.rate(huila, stars: 4, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        _ = try book.rate(huila, stars: 2, owner: alice, catalog: catalog, operationID: ClientID(), now: at(1))
        XCTAssertEqual(book.ratings.count, 1)
        XCTAssertEqual(book.rating(owner: alice, lot: huila)?.stars, 2)
        let entry = try XCTUnwrap(book.entry(owner: alice, lot: huila))
        XCTAssertFalse(entry.isOwned)
        XCTAssertEqual(entry.triedAt, t0)
        XCTAssertThrowsError(try book.rate(huila, stars: 6, owner: alice, catalog: catalog, operationID: ClientID(), now: t0))
    }

    func testStaleRevisionIsRejected() throws {
        var book = CollectionBook()
        _ = try book.collect(huila, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        let revision = try XCTUnwrap(book.entry(owner: alice, lot: huila)).revision
        try book.setFavorite(true, lot: huila, owner: alice, catalog: catalog, expectedRevision: revision, now: at(1))
        XCTAssertThrowsError(try book.setFavorite(false, lot: huila, owner: alice, catalog: catalog,
                                                  expectedRevision: revision, now: at(2))) {
            XCTAssertEqual($0 as? CollectionError, .staleRevision(expected: revision, actual: revision + 1))
        }
    }

    // MARK: Spec test 14 — seasons are never matched automatically

    func testTwoSeasonsAndUnknownStayDistinct() throws {
        var book = CollectionBook()
        _ = try book.collect(guji2024, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        XCTAssertEqual(try book.collect(guji2025, owner: alice, catalog: catalog, operationID: ClientID(), now: at(1)),
                       .collected(firstTime: true), "two known seasons of one product are separate lots without any question")
        XCTAssertEqual(Set(book.activeEntries(owner: alice).map(\.lotID)), [guji2024, guji2025])
    }

    // MARK: Spec test 26 — same-bag declaration

    func testKnownSeasonAfterUnknownRequiresDecision() throws {
        var book = CollectionBook()
        _ = try book.collect(gujiUnknown, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        XCTAssertThrowsError(try book.collect(guji2025, owner: alice, catalog: catalog, operationID: ClientID(), now: at(1))) {
            XCTAssertEqual($0 as? CollectionError, .needsBagDecision(BagConflict(productID: ProductID("sample:product/guji"),
                requestedLot: guji2025, existingLots: [gujiUnknown], direction: .unknownToKnown)))
        }
        XCTAssertNil(book.entry(owner: alice, lot: guji2025), "a request without the answer changes nothing")
    }

    func testSameBagMovesTheRecordWithoutANewFirstCollection() throws {
        var book = CollectionBook()
        let entryID = ClientID()
        _ = try book.collect(gujiUnknown, owner: alice, catalog: catalog, operationID: ClientID(), newEntryID: entryID, now: t0)
        try book.setNote("كيس من الرياض", lot: gujiUnknown, owner: alice, now: at(1))
        let outcome = try book.collect(guji2025, owner: alice, catalog: catalog, decision: .sameBag,
                                       operationID: ClientID(), now: at(2))
        XCTAssertEqual(outcome, .transferredFromUnknown(gujiUnknown))
        XCTAssertNil(book.entry(owner: alice, lot: gujiUnknown))
        let moved = try XCTUnwrap(book.entry(owner: alice, lot: guji2025))
        XCTAssertEqual(moved.clientID, entryID, "clientID is stable across the move")
        XCTAssertEqual(moved.firstCollectedAt, t0)
        XCTAssertEqual(moved.note, "كيس من الرياض")
        XCTAssertEqual(book.firstCollectionEvents.count, 1, "no new first collection")

        // Removing and re-collecting either lot of the pair never reopens the first-collection reward.
        try book.removeFromOwned(guji2025, owner: alice, now: at(3))
        XCTAssertEqual(try book.collect(guji2025, owner: alice, catalog: catalog, operationID: ClientID(), now: at(4)),
                       .collected(firstTime: false))
    }

    func testDistinctBagRecordsTheDeclarationAndCollectsNormally() throws {
        var book = CollectionBook()
        _ = try book.collect(gujiUnknown, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        let op = ClientID()
        XCTAssertEqual(try book.collect(guji2025, owner: alice, catalog: catalog, decision: .distinctBag, operationID: op, now: at(1)),
                       .collected(firstTime: true))
        XCTAssertEqual(book.assignmentEvents.last?.kind, .distinctBag(requested: guji2025, existing: [gujiUnknown]))
        XCTAssertEqual(Set(book.activeEntries(owner: alice).map(\.lotID)), [gujiUnknown, guji2025])
        // A retry of the same operation does not ask again and does not add another declaration.
        XCTAssertEqual(try book.collect(guji2025, owner: alice, catalog: catalog, decision: .distinctBag, operationID: op, now: at(2)),
                       .collected(firstTime: true))
        XCTAssertEqual(book.assignmentEvents.count, 1)
    }

    func testReverseOrderUnknownAfterKnownSeason() throws {
        var book = CollectionBook()
        _ = try book.collect(guji2024, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        XCTAssertThrowsError(try book.collect(gujiUnknown, owner: alice, catalog: catalog, operationID: ClientID(), now: at(1))) {
            guard case let .needsBagDecision(conflict)? = $0 as? CollectionError else { return XCTFail("\($0)") }
            XCTAssertEqual(conflict.direction, .knownToUnknown)
        }
        XCTAssertEqual(try book.collect(gujiUnknown, owner: alice, catalog: catalog, decision: .sameBag,
                                        operationID: ClientID(), now: at(2)), .keptKnownSeason([guji2024]))
        XCTAssertNil(book.entry(owner: alice, lot: gujiUnknown), "same bag keeps the known season and collects nothing")
        XCTAssertEqual(book.firstCollectionEvents.count, 1)
    }

    func testRatingAfterUnknownCollectionAlsoAsks() throws {
        var book = CollectionBook()
        _ = try book.collect(gujiUnknown, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        XCTAssertThrowsError(try book.rate(guji2025, stars: 5, owner: alice, catalog: catalog, operationID: ClientID(), now: at(1)))
        XCTAssertEqual(try book.rate(guji2025, stars: 5, owner: alice, catalog: catalog, decision: .sameBag,
                                     operationID: ClientID(), now: at(2)), .transferredFromUnknown(gujiUnknown))
        XCTAssertEqual(book.ratings.count, 1)
        XCTAssertEqual(book.rating(owner: alice, lot: guji2025)?.stars, 5)
        XCTAssertEqual(book.entry(owner: alice, lot: guji2025)?.isOwned, true)
    }

    // MARK: Spec test 23 — «تحديد موسم سجلي»

    func testSeasonAssignmentMovesOnlyTheOwnersRecordsAndKeepsTheNewestVote() throws {
        var book = CollectionBook()
        _ = try book.collect(gujiUnknown, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        _ = try book.rate(gujiUnknown, stars: 3, owner: alice, catalog: catalog, operationID: ClientID(), now: at(1))
        _ = try book.collect(gujiUnknown, owner: bob, catalog: catalog, operationID: ClientID(), now: at(1))
        _ = try book.rate(gujiUnknown, stars: 5, owner: bob, catalog: catalog, operationID: ClientID(), now: at(1))
        // Alice also has an older vote on the target season (from a distinct-bag answer earlier).
        _ = try book.rate(guji2024, stars: 1, owner: alice, catalog: catalog, decision: .distinctBag,
                          operationID: ClientID(), now: at(0.5))

        let op = ClientID()
        try book.assignSeason(owner: alice, from: gujiUnknown, to: guji2024, moveCollection: true, moveRating: true,
                              catalog: catalog, operationID: op, now: at(10))
        XCTAssertEqual(book.rating(owner: alice, lot: guji2024)?.stars, 3, "the most recently updated vote is kept")
        XCTAssertNil(book.rating(owner: alice, lot: gujiUnknown))
        XCTAssertEqual(book.ratings.filter { $0.ownerID == alice }.count, 1)
        XCTAssertNotNil(book.assignmentEvents.last?.replacedRatingClientID)
        XCTAssertEqual(book.entry(owner: alice, lot: guji2024)?.isOwned, true)
        XCTAssertEqual(book.rating(owner: bob, lot: gujiUnknown)?.stars, 5, "other users stay on UNKNOWN")
        XCTAssertEqual(book.entry(owner: bob, lot: gujiUnknown)?.isOwned, true)
        XCTAssertEqual(book.firstCollectionEvents.filter { $0.ownerID == alice }.count, 1)

        let snapshot = book
        try book.assignSeason(owner: alice, from: gujiUnknown, to: guji2024, moveCollection: true, moveRating: true,
                              catalog: catalog, operationID: op, now: at(11))
        XCTAssertEqual(book, snapshot, "retrying the same operation changes nothing")
    }

    func testSeasonAssignmentValidation() throws {
        var book = CollectionBook()
        XCTAssertThrowsError(try book.assignSeason(owner: alice, from: gujiUnknown, to: guji2024, moveCollection: true,
                                                   moveRating: true, catalog: catalog, operationID: ClientID(), now: t0)) {
            XCTAssertEqual($0 as? CollectionError, .nothingToMove)
        }
        XCTAssertThrowsError(try book.assignSeason(owner: alice, from: guji2024, to: guji2025, moveCollection: true,
                                                   moveRating: true, catalog: catalog, operationID: ClientID(), now: t0)) {
            XCTAssertEqual($0 as? CollectionError, .sourceIsNotUnknownSeason)
        }
        XCTAssertThrowsError(try book.assignSeason(owner: alice, from: huila, to: guji2025, moveCollection: true,
                                                   moveRating: true, catalog: catalog, operationID: ClientID(), now: t0)) {
            XCTAssertEqual($0 as? CollectionError, .notSameProduct)
        }
    }

    func testPartialSelectionLeavesTheRestOnUnknown() throws {
        var book = CollectionBook()
        _ = try book.collect(gujiUnknown, owner: alice, catalog: catalog, operationID: ClientID(), now: t0)
        _ = try book.rate(gujiUnknown, stars: 4, owner: alice, catalog: catalog, operationID: ClientID(), now: at(1))
        try book.assignSeason(owner: alice, from: gujiUnknown, to: guji2025, moveCollection: true, moveRating: false,
                              catalog: catalog, operationID: ClientID(), now: at(2))
        XCTAssertEqual(book.entry(owner: alice, lot: guji2025)?.isOwned, true)
        XCTAssertEqual(book.rating(owner: alice, lot: gujiUnknown)?.stars, 4, "the unselected vote stays on UNKNOWN")
    }
}
