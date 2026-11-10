import XCTest
@testable import BunnListCore

final class BrewVoiceTests: XCTestCase {
    private let steps = [
        RemoteRecipeStep(kind: .bloom, addedWaterGrams: 45, seconds: 40),
        RemoteRecipeStep(kind: .swirl, seconds: 5),
        RemoteRecipeStep(kind: .pour, addedWaterGrams: 105, seconds: 30),
        RemoteRecipeStep(kind: .wait, seconds: 75),
    ]
    private var timeline: BrewTimeline { BrewTimeline(steps: steps) }

    func testStepLinesCarryTheScaleReading() {
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 0),
                       .step(index: 0, line: "تفتيح. صبّ لين 45 غرام", mood: .pour))
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 40), .step(index: 1, line: "حرّك القمع", mood: .act))
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 45), .step(index: 2, line: "صبّ لين 150 غرام", mood: .pour))
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 75),
                       .step(index: 3, line: "انتظر دقيقة و 15 ثانية", mood: .wait))
    }

    func testCountdownInTheLastThreeSecondsOfLongSteps() {
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 37), .count(3))
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 38), .count(2))
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 39), .count(1))
        XCTAssertNil(BrewVoice.cue(timeline: timeline, second: 36))
        // The five-second swirl is too short for one.
        for s in 41...44 { XCTAssertNil(BrewVoice.cue(timeline: timeline, second: s)) }
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 149), .count(1))
    }

    func testFinishesOnceAtTheEnd() {
        XCTAssertEqual(BrewVoice.cue(timeline: timeline, second: 150), .finished(line: "خلصت، بالعافية"))
        XCTAssertNil(BrewVoice.cue(timeline: timeline, second: 151))
        XCTAssertNil(BrewVoice.cue(timeline: BrewTimeline(steps: []), second: 0))
    }

    func testSpokenDurations() {
        XCTAssertEqual(BrewVoice.spokenDuration(30), "30 ثانية")
        XCTAssertEqual(BrewVoice.spokenDuration(5), "5 ثواني")
        XCTAssertEqual(BrewVoice.spokenDuration(60), "دقيقة")
        XCTAssertEqual(BrewVoice.spokenDuration(120), "دقيقتين")
        XCTAssertEqual(BrewVoice.spokenDuration(240), "4 دقايق")
        XCTAssertEqual(BrewVoice.spokenDuration(122), "دقيقتين و ثانيتين")
    }

    func testAdditionsAndPlainServe() {
        let ice = RemoteRecipeStep(kind: .serve, addedWaterGrams: 90, addition: "ice")
        XCTAssertEqual(BrewVoice.line(step: ice, pourTo: nil), "أضف 90 غرام ثلج")
        XCTAssertEqual(BrewVoice.line(step: RemoteRecipeStep(kind: .serve), pourTo: nil), "قدّم القهوة")
        XCTAssertEqual(BrewVoice.line(step: RemoteRecipeStep(kind: .press, seconds: 30), pourTo: nil), "اضغط بهدوء")
    }

    func testArabicCoffeeSpeaksItsStages() {
        let plan = BrewPlan(preset: BrewPreset.all.first { $0.id == "arabic-saudi" }!)
        let titles = BrewVoice.titles(plan: plan)
        XCTAssertEqual(titles.count, plan.steps.count)
        guard case let .step(_, line, mood)? = BrewVoice.cue(timeline: BrewTimeline(steps: plan.steps), second: 0, titles: titles) else {
            return XCTFail("no opening cue")
        }
        XCTAssertTrue(line.hasPrefix("سخّن الماء في الدلة"))
        XCTAssertNotEqual(mood, .pour)
        // Other methods keep the step kinds.
        let v60 = BrewPlan(preset: BrewPreset.all.first { $0.id == "v60-classic" }!)
        XCTAssertTrue(BrewVoice.titles(plan: v60).allSatisfy { $0 == nil })
    }

    func testEveryPresetStepHasALine() {
        for preset in BrewPreset.all {
            let plan = BrewPlan(preset: preset)
            let timeline = BrewTimeline(steps: plan.steps)
            let titles = BrewVoice.titles(plan: plan)
            for index in plan.steps.indices where (plan.steps[index].seconds ?? 0) > 0 {
                guard case let .step(i, line, _)? = BrewVoice.cue(timeline: timeline, second: timeline.start(of: index), titles: titles) else {
                    return XCTFail("\(preset.id) step \(index) has no cue")
                }
                XCTAssertEqual(i, index)
                XCTAssertFalse(line.isEmpty)
            }
        }
    }

    func testTonesAreDistinctAndValidWav() {
        let pour = BrewTone.samples(.pour), stop = BrewTone.samples(.wait)
        XCTAssertNotEqual(pour, stop)
        XCTAssertEqual(pour.first, 0)
        XCTAssertLessThan(abs(Int(pour.last ?? 0)), 400)
        let wav = BrewTone.wav(.done)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(wav.count, 44 + BrewTone.samples(.done).count * 2)
    }
}
