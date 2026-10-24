import XCTest
@testable import BunnListCore

final class BrewGuideTests: XCTestCase {
    private func draft(_ preset: BrewPreset) -> RecipeDraft {
        var d = RecipeDraft()
        d.title = preset.nameAr
        d.apply(preset)
        return d
    }

    func testEveryPresetIsPublishableAsIs() {
        for preset in BrewPreset.all {
            XCTAssertEqual(draft(preset).problems(), [], preset.id)
        }
    }

    func testEveryPresetSitsInsideItsOwnTypicalRanges() {
        for preset in BrewPreset.all {
            XCTAssertEqual(BrewAdvisor.tips(for: draft(preset)), [], preset.id)
        }
    }

    func testPresetRatiosMatchTheirSummaries() {
        let classic = draft(BrewPreset.all.first { $0.id == "v60-classic" }!)
        XCTAssertEqual(classic.ratio ?? 0, 16.67, accuracy: 0.01)
        XCTAssertEqual(classic.totalSeconds, 175)
        let fourSix = draft(BrewPreset.all.first { $0.id == "v60-46" }!)
        XCTAssertEqual(fourSix.ratio, 15)
        XCTAssertEqual(fourSix.totalSeconds, 210)
        let espresso = draft(BrewPreset.all.first { $0.id == "espresso-classic" }!)
        XCTAssertEqual(espresso.ratio, 2)
    }

    func testApplyingAPresetKeepsTitleAndCoffee() {
        var d = RecipeDraft(lot: RemoteRecipeLot(slug: "s", nameAr: "ق", roasterNameAr: "م"))
        d.title = "صباحي"
        d.apply(BrewPreset.presets(for: "CHEMEX")[0])
        XCTAssertEqual(d.title, "صباحي")
        XCTAssertEqual(d.lot?.slug, "s")
        XCTAssertEqual(d.methodCode, "CHEMEX")
    }

    func testAdvisorFlagsCommonMistakes() {
        var d = draft(BrewPreset.all.first { $0.id == "v60-classic" }!)
        d.waterTempC = 80
        d.steps[0].seconds = 15
        d.steps[0].addedWaterGrams = 20
        d.steps[1].addedWaterGrams = 130 // keep pours = 250
        d.roastLevel = .dark
        d.restDays = 2
        let tips = BrewAdvisor.tips(for: d)
        XCTAssertTrue(tips.contains(.waterTooCool))
        XCTAssertTrue(tips.contains(.shortBloom))
        XCTAssertTrue(tips.contains(.smallBloom))
        XCTAssertTrue(tips.contains(.veryFreshBeans))
        XCTAssertFalse(tips.contains(.darkRoastHot)) // 80°C is already low
    }

    func testAdvisorFlagsRatioAndTime() {
        var d = draft(BrewPreset.all.first { $0.id == "v60-classic" }!)
        d.applyRatio(12)
        d.steps[4].seconds = 400
        let tips = BrewAdvisor.tips(for: d)
        XCTAssertTrue(tips.contains(.ratioStrong(typical: 14...18)))
        XCTAssertTrue(tips.contains(.slowBrew(typical: 120...240)))
    }

    func testTimelineWalksThroughSteps() {
        let preset = BrewPreset.all.first { $0.id == "v60-classic" }!
        let timeline = BrewTimeline(steps: preset.steps)
        XCTAssertEqual(timeline.totalSeconds, 175)

        let start = timeline.position(at: 0)
        XCTAssertEqual(start.stepIndex, 0)
        XCTAssertEqual(start.secondsLeftInStep, 45)
        XCTAssertEqual(start.pourTo, 45)

        let second = timeline.position(at: 50)
        XCTAssertEqual(second.stepIndex, 1)
        XCTAssertEqual(second.secondsLeftInStep, 25)
        XCTAssertEqual(second.pourTo, 150)

        let waiting = timeline.position(at: 120)
        XCTAssertEqual(waiting.stepIndex, 4)
        XCTAssertNil(waiting.pourTo)

        XCTAssertTrue(timeline.position(at: 175).isFinished)
        XCTAssertEqual(timeline.start(of: 2), 75)
    }

    func testTimelineSkipsUntimedSteps() {
        let timeline = BrewTimeline(steps: [
            .init(kind: .pour, addedWaterGrams: 100, seconds: 10),
            .init(kind: .wait),
            .init(kind: .serve, seconds: 5),
        ])
        XCTAssertEqual(timeline.position(at: 10).stepIndex, 2)
        XCTAssertTrue(BrewTimeline(steps: []).position(at: 0).isFinished)
    }

    func testExtractionYieldAndWaterTips() {
        var d = draft(BrewPreset.all.first { $0.id == "v60-classic" }!) // 15 g → 250 g
        XCTAssertEqual(d.beverageGrams, 220)                            // 250 − 2 × 15
        d.beverageTds = 1.35
        XCTAssertEqual(d.extractionYield ?? 0, 19.8, accuracy: 0.01)    // 1.35 × 220 ÷ 15
        XCTAssertEqual(BrewAdvisor.tips(for: d), [])

        d.beverageTds = 1.0
        XCTAssertTrue(BrewAdvisor.tips(for: d).contains(.underExtracted))
        XCTAssertTrue(BrewAdvisor.tips(for: d).contains(.beverageTdsOutside(typical: 1.15...1.45)))

        d.beverageTds = nil
        d.waterTdsPpm = 40
        XCTAssertEqual(BrewAdvisor.tips(for: d), [.waterTooSoft])
        d.waterTdsPpm = 300
        XCTAssertEqual(BrewAdvisor.tips(for: d), [.waterTooHard])
    }

    func testEspressoYieldUsesTheShotWeight() {
        var d = draft(BrewPreset.all.first { $0.id == "espresso-classic" }!) // 18 → 36
        d.beverageTds = 9
        XCTAssertEqual(d.extractionYield ?? 0, 18, accuracy: 0.01)
        XCTAssertEqual(BrewAdvisor.tips(for: d), [])
    }

    func testChoosingAMilkDrinkFillsTypicalMilk() {
        var d = draft(BrewPreset.all.first { $0.id == "espresso-classic" }!)
        d.setMilkDrink(.flatWhite)
        XCTAssertEqual(d.milkGrams, 120)
        d.milkType = .oat
        d.setMilkDrink(nil)
        XCTAssertNil(d.milkGrams)
        XCTAssertNil(d.milkType)
    }
}
