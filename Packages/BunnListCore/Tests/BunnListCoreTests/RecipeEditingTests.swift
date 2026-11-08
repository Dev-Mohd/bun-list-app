import XCTest
@testable import BunnListCore

final class RecipeEditingTests: XCTestCase {
    private func base() -> RecipeDraft {
        var d = RecipeDraft()
        d.doseGrams = 15; d.hotWaterGrams = 250; d.waterTempC = 92
        return d
    }

    func testSimplePoursSplitWaterAfterBloom() {
        var d = base(); d.simplePours(3, bloom: true)
        XCTAssertTrue(d.hasBloom); XCTAssertEqual(d.pourCount, 3)
        XCTAssertEqual(d.steps.filter(\.kind.addsWater).compactMap(\.addedWaterGrams), [45, 68, 68, 69])
        XCTAssertEqual(d.startTimes, [0, 45, 75, 105, 135])
        XCTAssertEqual(d.totalSeconds, 195)
        XCTAssertFalse(d.waterMismatch)
        d.simplePours(2, bloom: false)
        XCTAssertEqual(d.steps.filter(\.kind.addsWater).compactMap(\.addedWaterGrams), [125, 125])
    }

    func testAddedAndScaleReading() {
        var d = base(); d.simplePours(3, bloom: true); d.setAdded(2, grams: 73)
        XCTAssertEqual(d.scaleBefore(2), 113)
        XCTAssertEqual(d.cumulativeWater[2], 186)
        XCTAssertEqual(d.steps[3].addedWaterGrams, 64)
        XCTAssertEqual(d.pouredGrams, 250)
    }

    func testMovingKeepsDurationsAndRecomputesStarts() {
        var d = base(); d.simplePours(2, bloom: true); d.addStep(.stir)
        let total = d.totalSeconds
        d.moveStep(from: 4, to: 1)
        XCTAssertEqual(d.steps[1].kind, .stir)
        XCTAssertEqual(d.startTimes, [0, 45, 55, 85, 115])
        XCTAssertEqual(d.totalSeconds, total)
    }

    func testMismatchFixesAndAdditions() {
        var d = base(); d.simplePours(3, bloom: true); d.hotWaterGrams = 260
        XCTAssertTrue(d.waterMismatch); XCTAssertEqual(d.waterShortfall, 10)
        var a = d; a.giveShortfallToLastPour(); XCTAssertEqual(a.pouredGrams, 260)
        var b = d; b.adoptPouredTotal(); XCTAssertEqual(b.hotWaterGrams, 250)
        var c = base(); c.simplePours(2, bloom: true); c.addStep(.dilute); c.addStep(.ice)
        XCTAssertEqual(c.dilutionGrams, 20); XCTAssertEqual(c.iceAddedGrams, 100)
        XCTAssertFalse(c.problems().contains(.waterOnNonPourStep))
        XCTAssertEqual(c.steps[c.steps.count - 2].titleAr, "تخفيف")
    }

    func testTemperatures() {
        var d = base(); d.simplePours(2, bloom: true); d.steps[1].tempC = 88
        XCTAssertEqual(d.stepTemp(1), 88); XCTAssertEqual(d.stepTemp(2), 92)
        XCTAssertEqual(d.prepLineAr, "جهّز الماء على 92°م")
        XCTAssertEqual(d.customTempsAr, "صبّة 1 على 88°")
        d.waterTempC = nil
        XCTAssertNil(d.prepLineAr)
    }
}
