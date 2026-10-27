import XCTest
@testable import BunnListCore

final class BrewPlanTests: XCTestCase {
    private func recipe(_ id: String, method: String = "V60", lot: String? = "nardos", mine: Bool, likes: Int? = nil,
                        state: String = "published") throws -> RemoteRecipe {
        let lotJSON = lot.map { #"{"slug":"\#($0)","nameAr":"ق","roasterNameAr":"م"}"# } ?? "null"
        let json = #"{"id":"\#(id)","clientId":"c\#(id)","title":"\#(id)","methodCode":"\#(method)","temperature":"hot","lot":\#(lotJSON),"doseGrams":15,"hotWaterGrams":250,"iceGrams":null,"yieldGrams":null,"waterTempC":94,"grinder":"C40","grindSetting":"24","grinderModel":"comandante-c40","grindLevel":"medium","grindMicrons":720,"brewer":"V60","filterType":null,"roastLevel":null,"restDays":null,"notes":"","steps":[{"kind":"bloom","addedWaterGrams":50,"seconds":45,"note":""}],"sourceId":null,"version":1,"state":"\#(state)","authorName":"سارة","isMine":\#(mine),"likeCount":\#(likes.map(String.init) ?? "null")}"#
        return try JSONDecoder().decode(RemoteRecipe.self, from: Data(json.utf8))
    }

    func testOrderIsMineThenCommunityThenBase() throws {
        let options = BrewPlanner.options(
            methodCode: "V60", lotSlug: "nardos",
            mine: [try recipe("other-lot", lot: "rio", mine: true), try recipe("this-lot", mine: true),
                   try recipe("espresso", method: "ESPRESSO", mine: true), try recipe("gone", mine: true, state: "deleted")],
            community: [try recipe("few", mine: false, likes: 1), try recipe("many", mine: false, likes: 9),
                        try recipe("draft", mine: false, state: "draft"), try recipe("elsewhere", lot: "rio", mine: false)]
        )
        XCTAssertEqual(options.map(\.id).prefix(4), ["recipe:this-lot", "recipe:other-lot", "recipe:many", "recipe:few"])
        XCTAssertEqual(options.dropFirst(4).map(\.source), BrewPreset.presets(for: "V60").map { _ in .base })
        XCTAssertEqual(options[2].sourceAr, "من سارة · 9 إعجاب")
        XCTAssertEqual(options.last?.sourceAr, "وصفة بداية من BunnList")
    }

    func testGrindTextAndApproximateClicks() throws {
        let plan = BrewPlan(recipe: try recipe("r", mine: true))
        XCTAssertEqual(plan.grindText, "24 على Comandante C40")
        XCTAssertEqual(plan.approximateClicks(on: Grinder.find("1zpresso-k-ultra")), 36)
        XCTAssertNil(plan.approximateClicks(on: Grinder.find("timemore-c3")))
        XCTAssertNil(BrewPlan(preset: BrewPreset.all[0]).approximateClicks(on: Grinder.find("comandante-c40")))
    }

    func testRecentCoffeesComeFirst() {
        let ordered = BrewPlanner.ordered(["a", "b", "c", "d"], slug: { $0 }, recent: ["c", "a"])
        XCTAssertEqual(ordered, ["c", "a", "b", "d"])
        XCTAssertEqual(BrewPlanner.remember("b", in: ["a", "b", "c"]), ["b", "a", "c"])
    }

    func testColdBrewIsAChecklist() {
        XCTAssertFalse(BrewPlan(preset: BrewPreset.presets(for: "COLD_BREW")[0]).usesTimer)
        XCTAssertTrue(BrewPlan(preset: BrewPreset.presets(for: "ESPRESSO")[0]).isEspresso)
    }
}
