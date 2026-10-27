import XCTest
@testable import BunnListCore

final class BrewSceneTests: XCTestCase {
    private func plan(_ id: String) -> BrewPlan { BrewPlan(preset: BrewPreset.all.first { $0.id == id }!) }

    func testSceneKindPerMethod() {
        XCTAssertEqual(BrewSceneKind.of(plan("v60-classic")), .pourOver(iced: false))
        XCTAssertEqual(BrewSceneKind.of(plan("v60-iced")), .pourOver(iced: true))
        XCTAssertEqual(BrewSceneKind.of(plan("aeropress-classic")), .aeropress)
        XCTAssertEqual(BrewSceneKind.of(plan("espresso-classic")), .espresso)
        XCTAssertEqual(BrewSceneKind.of(plan("arabic-saudi")), .arabic)
        XCTAssertEqual(BrewSceneKind.of(plan("chemex-classic")), .none)
    }

    func testReadyBeforeStartAndDoneAfter() {
        let p = plan("v60-classic")
        XCTAssertEqual(BrewScene.state(plan: p, elapsed: 0, started: false).stage, .ready)
        let done = BrewScene.state(plan: p, elapsed: 999, started: true)
        XCTAssertEqual(done.stage, .done)
        XCTAssertEqual(done.drained, 1)
    }

    func testBloomPoursQuicklyThenWaits() {
        let p = plan("v60-classic") // bloom 45 g over 45 s, of 250 g
        let early = BrewScene.state(plan: p, elapsed: 9, started: true)
        XCTAssertEqual(early.stage, .bloom)
        XCTAssertEqual(early.poured, 45.0 / 250 * 0.5, accuracy: 0.001)
        let late = BrewScene.state(plan: p, elapsed: 30, started: true)
        XCTAssertEqual(late.poured, 45.0 / 250, accuracy: 0.001)
        XCTAssertEqual(late.secondsToNext ?? 0, 15, accuracy: 0.001)
    }

    func testDrainNeverExceedsPouredAndStandingWaterRisesThenFalls() {
        let p = plan("v60-classic")
        var peak = 0.0
        for t in stride(from: 0.0, through: 175, by: 1) {
            let s = BrewScene.state(plan: p, elapsed: t, started: true)
            XCTAssertLessThanOrEqual(s.drained, s.poured + 1e-9)
            peak = max(peak, s.standing)
        }
        XCTAssertGreaterThan(peak, 0.2)
        XCTAssertLessThan(BrewScene.state(plan: p, elapsed: 174, started: true).standing, 0.05)
    }

    func testCueInLastThreeSeconds() {
        let p = plan("v60-classic")
        XCTAssertTrue(BrewScene.state(plan: p, elapsed: 43, started: true).isCueing)
        XCTAssertFalse(BrewScene.state(plan: p, elapsed: 30, started: true).isCueing)
    }

    func testArabicStagesFollowTheirOrder() {
        let p = plan("arabic-saudi")
        let stages = [0.0, 190, 400, 805, 900, 950].map { BrewScene.state(plan: p, elapsed: $0, started: true).stage }
        XCTAssertEqual(stages, [.heat, .addCoffee, .simmer, .addCardamom, .settle, .serve])
        XCTAssertEqual(BrewScene.state(plan: p, elapsed: 400, started: true).titleAr, "على نار هادية")
    }

    func testArabicIsAKnownMethodWithoutAdvisorWarnings() {
        XCTAssertEqual(ReferenceCodes.brewMethod("ARABIC")?.nameAr, "قهوة عربية")
        var draft = RecipeDraft()
        draft.apply(BrewPreset.all.first { $0.id == "arabic-saudi" }!)
        XCTAssertEqual(BrewAdvisor.tips(for: draft), [])
    }
}
