import XCTest
@testable import BunnListCore

final class LifecycleTests: XCTestCase {
    /// Spec test 25.
    func testUnpublishAndRepublishKeepIdentityAndNetReward() throws {
        var state = ContentState(kind: .experience)
        var ledger = EntitlementLedger(amount: 10)
        let steps: [ContentLifecycle] = [.published, .unpublished, .published, .unpublished, .published]
        for step in steps {
            try state.transition(to: step, expectedRevision: state.revision, requestKey: ClientID())
            ledger.apply(step)
        }
        XCTAssertEqual(ledger.entries, [10, -10, 10, -10, 10])
        XCTAssertEqual(ledger.net, 10, "cycles never exceed the original grant")
        XCTAssertTrue(state.isPubliclyVisible)
    }

    func testRepeatedRequestIsANoOpAndStaleRevisionIsRejected() throws {
        var state = ContentState(kind: .recipe)
        let key = ClientID()
        XCTAssertTrue(try state.transition(to: .published, expectedRevision: 0, requestKey: key))
        XCTAssertFalse(try state.transition(to: .published, expectedRevision: 0, requestKey: key), "same request key replays")
        XCTAssertEqual(state.revision, 1)
        XCTAssertThrowsError(try state.transition(to: .unpublished, expectedRevision: 0, requestKey: ClientID())) {
            XCTAssertEqual($0 as? LifecycleError, .staleRevision(expected: 0, actual: 1))
        }
    }

    func testDeletedIsFinal() throws {
        var state = ContentState(kind: .experience)
        try state.transition(to: .deleted, expectedRevision: 0, requestKey: ClientID())
        XCTAssertThrowsError(try state.transition(to: .published, expectedRevision: 1, requestKey: ClientID())) {
            XCTAssertEqual($0 as? LifecycleError, .deletedIsFinal)
        }
    }

    func testCommentsCannotBeUnpublishedAndDraftsCannotSkipPublishing() throws {
        var comment = ContentState(kind: .comment)
        try comment.transition(to: .published, expectedRevision: 0, requestKey: ClientID())
        XCTAssertThrowsError(try comment.transition(to: .unpublished, expectedRevision: 1, requestKey: ClientID())) {
            XCTAssertEqual($0 as? LifecycleError, .invalidTransition(from: .published, to: .unpublished))
        }
        try comment.transition(to: .deleted, expectedRevision: 1, requestKey: ClientID())
        var draft = ContentState(kind: .experience)
        XCTAssertThrowsError(try draft.transition(to: .unpublished, expectedRevision: 0, requestKey: ClientID()))
    }

    func testModerationHideBlocksRepublishingAndOwnerCannotLiftIt() throws {
        var state = ContentState(kind: .experience)
        try state.transition(to: .published, expectedRevision: 0, requestKey: ClientID())
        state.setModeration(.hidden)
        XCTAssertFalse(state.isPubliclyVisible)
        try state.transition(to: .unpublished, expectedRevision: state.revision, requestKey: ClientID())
        XCTAssertThrowsError(try state.transition(to: .published, expectedRevision: state.revision, requestKey: ClientID())) {
            XCTAssertEqual($0 as? LifecycleError, .hiddenByModeration)
        }
        XCTAssertEqual(state.moderation, .hidden)
    }
}

final class RankingTests: XCTestCase {
    private func votes(_ lot: String, stars: [Int], approved: Bool = true, known: Bool = true, visible: Bool = true) -> [RankingVote] {
        stars.map { RankingVote(lotID: LotID(lot), stars: $0, lotIsApproved: approved, lotSeasonIsKnown: known,
                                isPublishedAndVisible: visible) }
    }

    /// Spec test 19.
    func testBayesianScoreOrdersByConfidence() {
        XCTAssertEqual(RankingV1.score(average: 5, voters: 5, globalMean: 4), 4.2, accuracy: 1e-9)
        XCTAssertEqual(RankingV1.score(average: 4.8, voters: 200, globalMean: 4), 4.727, accuracy: 0.001)
    }

    func testRankingUsesThresholdTieBreaksAndShowsRawAverage() {
        // a: 5 votes of 5. b: 200 votes averaging 4.8 (160×5 + 40×4). Filler: 55 one-star votes on
        // 14 small lots (under 5 voters each) so the global mean C is exactly 4, as in spec test 19.
        var all = votes("a", stars: Array(repeating: 5, count: 5))
            + votes("b", stars: Array(repeating: 5, count: 160) + Array(repeating: 4, count: 40))
        for index in 0..<14 { all += votes("small-\(index)", stars: Array(repeating: 1, count: index < 13 ? 4 : 3)) }
        XCTAssertEqual(RankingV1.globalMean(all), 4, accuracy: 1e-9)
        let ranked = RankingV1.rank(all)
        XCTAssertEqual(ranked.map(\.lotID.rawValue), ["b", "a"], "small lots are not listed; b leads despite a lower raw average")
        XCTAssertEqual(ranked[0].score, 4.727, accuracy: 0.001)
        XCTAssertEqual(ranked[1].score, 4.2, accuracy: 1e-9)
        XCTAssertEqual(ranked[0].rawAverage, 4.8, accuracy: 1e-9)
        XCTAssertEqual(ranked[0].voterCount, 200)
    }

    /// Spec test 29.
    func testGlobalMeanExcludesUnknownPendingAndHiddenButIncludesSmallKnownLots() {
        let base = votes("known-small", stars: [4, 4])
        XCTAssertEqual(RankingV1.globalMean(base), 4)
        let noisy = base + votes("unknown", stars: [1, 1, 1, 1, 1, 1], known: false)
            + votes("pending", stars: [1, 1, 1], approved: false)
            + votes("hidden", stars: [1, 1], visible: false)
        XCTAssertEqual(RankingV1.globalMean(noisy), 4, "UNKNOWN, pending and hidden votes never move C")
        XCTAssertTrue(RankingV1.rank(votes("unknown", stars: Array(repeating: 5, count: 9), known: false)).isEmpty)
        XCTAssertEqual(RankingV1.globalMean([]), RankingV1.fallbackMean)
    }
}
