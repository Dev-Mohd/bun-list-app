import XCTest
@testable import BunnListCore

final class GrinderGuideTests: XCTestCase {
    private func grinder(_ extra: String) throws -> RemoteGrinder {
        let json = #"{"id":"g","brand":"Comandante","model":"C40","variant":"MK4","category":"hand","rangeMin":0,"rangeMax":40,"clicksPerRotation":12,"zeroGuideAr":null,"notesAr":null,"sources":[],"imageUrl":null,"imageCredit":null,"published":true,\#(extra)}"#
        return try JSONDecoder().decode(RemoteGrinder.self, from: Data(json.utf8))
    }

    func testTextAndSearch() throws {
        let g = try grinder(#""adjustment":"clicks","micronsPerStep":30"#)
        XCTAssertEqual(g.title, "C40 · MK4")
        XCTAssertEqual(g.rangeAr, "0–40 كليك")
        XCTAssertEqual(g.categoryAr, "يدوية")
        XCTAssertTrue(g.matches("coman"))
        XCTAssertFalse(g.matches("niche"))
        let pending = try grinder(#""adjustment":null,"micronsPerStep":null"#)
        XCTAssertNil(pending.rangeAr)
        XCTAssertFalse(pending.hasSpecs)
    }

    func testConversionNeedsVerifiedMicrons() throws {
        let plan = BrewPlan(preset: BrewPreset.all[0])
        XCTAssertNil(plan.approximateClicks(on: try grinder(#""adjustment":"clicks","micronsPerStep":30"#)), "presets carry no microns")
        let json = #"{"id":"r","clientId":"c","title":"t","methodCode":"V60","temperature":"hot","lot":null,"doseGrams":15,"hotWaterGrams":250,"iceGrams":null,"yieldGrams":null,"waterTempC":94,"grinder":"","grindSetting":"","grindMicrons":720,"notes":"","steps":[],"version":1,"state":"published","authorName":"م","isMine":true}"#
        let recipePlan = BrewPlan(recipe: try JSONDecoder().decode(RemoteRecipe.self, from: Data(json.utf8)))
        XCTAssertEqual(recipePlan.approximateClicks(on: try grinder(#""adjustment":"clicks","micronsPerStep":30"#)), 24)
        XCTAssertNil(recipePlan.approximateClicks(on: try grinder(#""adjustment":"clicks","micronsPerStep":null"#)))
    }
}
