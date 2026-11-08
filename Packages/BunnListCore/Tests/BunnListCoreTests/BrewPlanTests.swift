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
        XCTAssertEqual(options.dropFirst(4).map(\.id), BrewPreset.presets(for: "V60").map { "preset:" + $0.id })
        XCTAssertEqual(options[2].sourceAr, "من سارة · 9 إعجاب")
        XCTAssertEqual(options.first { $0.id == "preset:v60-classic" }?.sourceAr, "وصفة بداية من BunnList")
        XCTAssertEqual(options.first { $0.id == "preset:v60-46" }?.sourceAr, "Tetsu Kasuya · بطل العالم لتحضير القهوة 2016")
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

    func testCupsScaleEverythingButTime() {
        let arabic = BrewPlan(preset: BrewPreset.presets(for: "ARABIC")[0])
        XCTAssertEqual(arabic.baseCups, 10)
        XCTAssertEqual(arabic.cupNameAr, "فنجان")
        let four = arabic.scaled(toCups: 4)
        XCTAssertEqual(four.doseGrams, 12)
        XCTAssertEqual(four.hotWaterGrams, 400)
        XCTAssertEqual(four.steps.first?.addedWaterGrams, 400)
        XCTAssertEqual(four.totalSeconds, arabic.totalSeconds)
        let v60 = BrewPlan(preset: BrewPreset.presets(for: "V60")[0])
        XCTAssertEqual(v60.baseCups, 1)
        XCTAssertEqual(v60.scaled(toCups: 2).doseGrams, 30)
        XCTAssertEqual(v60.scaled(toCups: 2).hotWaterGrams, 500)
        XCTAssertEqual(v60.scaled(toCups: 1), v60)
        let espresso = BrewPlan(preset: BrewPreset.presets(for: "ESPRESSO")[0])
        XCTAssertFalse(espresso.scalesByCups)
        XCTAssertEqual(espresso.scaled(toCups: 3), espresso)
    }

    func testGroupsPutThisCoffeeFirst() throws {
        let roaster = RemoteRoasterRecipe(method: "V60", tool: "V60", doseG: 15, waterMl: 240, tempC: 92, timeSec: 165,
                                          grind: "متوسط", ratio: 16, steps: ["تشريب ٤٠غ", "صب لين ١٥٠غ", "صب لين ٢٤٠غ"])
        let link = RemoteRoasterRecipe(method: "XBLOOM", link: "https://x", tool: nil, doseG: nil, waterMl: nil,
                                       tempC: nil, timeSec: nil, grind: nil, ratio: nil, steps: [])
        let g = BrewPlanner.groups(methodCode: "V60", lotSlug: "nardos", roasterName: "أسانتي",
                                   roasterRecipes: [link, roaster], mine: [try recipe("m", mine: true)],
                                   lotCommunity: [try recipe("few", mine: false, likes: 1), try recipe("many", mine: false, likes: 9)],
                                   methodCommunity: [try recipe("many", mine: false, likes: 9), try recipe("rio", lot: "rio", mine: false, likes: 4)])
        XCTAssertEqual(g.forCoffee.map(\.id), ["roaster:1", "recipe:many", "recipe:few"])
        XCTAssertEqual(g.forCoffee[0].sourceAr, "من أسانتي · وصفة المحمصة لهالقهوة")
        XCTAssertEqual(g.forCoffee[0].steps.map(\.seconds), [55, 55, 55])
        XCTAssertEqual(g.community.map(\.id), ["recipe:rio"], "this coffee's recipes aren't repeated")
        XCTAssertEqual(g.mine.map(\.id), ["recipe:m"])
        XCTAssertEqual(g.defaultTab, .forCoffee)
        XCTAssertEqual(g.tabs, [.forCoffee, .bunnlist, .mine, .community])
        XCTAssertEqual(g.tab(of: "recipe:m"), .mine)
        // Starting recipes before champions.
        XCTAssertEqual(g.bunnlist.first?.id, "preset:v60-classic")
        XCTAssertTrue(g.bunnlist.contains { $0.id == "preset:v60-hoffmann" })
    }

    func testChampionRecipesMatchTheirPublishedTotals() {
        func plan(_ id: String) -> BrewPlan { BrewPlan(preset: BrewPreset.all.first { $0.id == id }!) }
        let kasuya = plan("v60-46")
        XCTAssertEqual(kasuya.steps.compactMap(\.addedWaterGrams).reduce(0, +), 300)
        XCTAssertEqual(kasuya.totalSeconds, 210)
        let hoffmann = plan("v60-hoffmann")
        XCTAssertEqual(hoffmann.steps.compactMap(\.addedWaterGrams).reduce(0, +), 500)
        XCTAssertEqual(hoffmann.totalSeconds, 210)
        XCTAssertEqual(plan("aeropress-wac-2024").steps.compactMap(\.addedWaterGrams).reduce(0, +), 225)
        XCTAssertEqual(plan("aeropress-wac-2023").credit?.advanced, true)
        for preset in BrewPreset.champions {
            XCTAssertTrue(preset.credit?.sourceURL.hasPrefix("https://") == true, preset.id)
            XCTAssertEqual(preset.steps.compactMap(\.addedWaterGrams).reduce(0, +), preset.hotWaterGrams, preset.id)
        }
    }

    func testColdBrewIsAChecklist() {
        XCTAssertFalse(BrewPlan(preset: BrewPreset.presets(for: "COLD_BREW")[0]).usesTimer)
        XCTAssertTrue(BrewPlan(preset: BrewPreset.presets(for: "ESPRESSO")[0]).isEspresso)
    }
}
