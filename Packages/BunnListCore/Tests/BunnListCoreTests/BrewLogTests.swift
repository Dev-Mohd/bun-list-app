import XCTest
@testable import BunnListCore

final class BrewLogTests: XCTestCase {
    private func grinder(_ adjustment: String?, min: Double? = 0, max: Double? = 40) -> RemoteGrinder {
        RemoteGrinder(id: "g1", brand: "B", model: "M", variant: nil, category: "hand", adjustment: adjustment,
                      rangeMin: min, rangeMax: max, clicksPerRotation: nil, micronsPerStep: nil, zeroGuideAr: nil,
                      notesAr: nil, sources: [], imageUrl: nil, imageCredit: nil, published: true)
    }

    private func experience(method: String = "V60", stars: Int = 3, at: String, log: BrewLogEntry?) -> RemoteExperience {
        RemoteExperience(id: at, clientId: at, methodCode: method, stars: stars, brewedAt: at, note: "",
                         state: .draft, revision: 0, log: log)
    }

    func testSourGoesFinerByTwoClicksOnAPourOver() {
        let fix = TasteFix.suggest(taste: .sour, methodCode: "V60", setting: "24", grinder: grinder("clicks"),
                                   doseGrams: 15, waterGrams: 250)
        XCTAssertEqual(fix.change, .grind(direction: -1, setting: "22"))
        XCTAssertEqual(fix.titleAr, "طحنة أنعم: جرّب 22")
    }

    func testBitterGoesCoarserByOneOnEspressoAndStaysInRange() {
        let fix = TasteFix.suggest(taste: .bitter, methodCode: "ESPRESSO", setting: "40", grinder: grinder("clicks"),
                                   doseGrams: 18, waterGrams: 36)
        XCTAssertEqual(fix.change, .grind(direction: 1, setting: nil)) // already at the top
        let mid = TasteFix.suggest(taste: .bitter, methodCode: "ESPRESSO", setting: "12", grinder: grinder("clicks"),
                                   doseGrams: 18, waterGrams: 36)
        XCTAssertEqual(mid.change, .grind(direction: 1, setting: "13"))
    }

    func testSteplessAndTextSettingsGetWordsOnly() {
        XCTAssertEqual(TasteFix.suggest(taste: .sour, methodCode: "V60", setting: "5", grinder: grinder("stepless"),
                                        doseGrams: nil, waterGrams: nil).change, .grind(direction: -1, setting: nil))
        XCTAssertEqual(TasteFix.suggest(taste: .sour, methodCode: "V60", setting: "متوسط", grinder: grinder("clicks"),
                                        doseGrams: nil, waterGrams: nil).titleAr, "طحنة أنعم شوي")
        XCTAssertEqual(TasteFix.nextSetting(from: "3,5", finer: false, grinder: grinder("stepped"), espresso: false), "4.5")
    }

    func testWeakAndStrongChangeOneNumber() {
        XCTAssertEqual(TasteFix.suggest(taste: .weak, methodCode: "V60", setting: nil, grinder: nil,
                                        doseGrams: 15, waterGrams: 250).change, .dose(grams: 16))
        XCTAssertEqual(TasteFix.suggest(taste: .strong, methodCode: "V60", setting: nil, grinder: nil,
                                        doseGrams: 15, waterGrams: 250).change, .water(grams: 270))
        XCTAssertEqual(TasteFix.suggest(taste: .strong, methodCode: "ESPRESSO", setting: nil, grinder: nil,
                                        doseGrams: 18, waterGrams: 36).titleAr, "طوّل الناتج إلى 40غ")
    }

    func testMemoryTakesLatestLoggedBrewOfThisMethod() {
        let g = grinder("clicks")
        let list = [
            experience(at: "2026-10-20T08:00:00Z", log: BrewLogEntry(grinderId: "g1", grindSetting: "20", taste: .bitter)),
            experience(at: "2026-10-25T08:00:00Z", log: BrewLogEntry(grinderId: "g1", grindSetting: "24", taste: .sour)),
            experience(method: "CHEMEX", at: "2026-10-26T08:00:00Z", log: BrewLogEntry(taste: .weak)),
            experience(at: "2026-10-27T08:00:00Z", log: nil),
        ]
        let memory = BrewMemory.latest(list, methodCode: "V60", grinder: g)
        XCTAssertEqual(memory?.log.grindSetting, "24")
        XCTAssertEqual(memory?.startingSetting(grinderId: "g1"), "22")
        XCTAssertNil(memory?.startingSetting(grinderId: "other"))
    }

    func testAnotherGrindersSettingDoesNotCarryOver() {
        let list = [experience(at: "2026-10-25T08:00:00Z", log: BrewLogEntry(grinderId: "old", grindSetting: "24", taste: .sour))]
        let memory = BrewMemory.latest(list, methodCode: "V60", grinder: grinder("clicks"))
        XCTAssertEqual(memory?.fix?.change, .grind(direction: -1, setting: nil))
    }

    func testDecodesServerLogAndNullLog() throws {
        let json = """
        {"id":"e","clientId":"c","methodCode":"V60","stars":4,"brewedAt":"2026-10-25T08:00:00.000Z","note":"",
         "state":"draft","revision":0,"log":{"recipeId":null,"recipeTitle":"t","recipeSource":"base","grinderId":null,
         "grindSetting":"18","doseGrams":15,"waterGrams":250,"brewSeconds":190,"taste":"sour"}}
        """
        let e = try JSONDecoder().decode(RemoteExperience.self, from: Data(json.utf8))
        XCTAssertEqual(e.log?.taste, .sour)
        XCTAssertEqual(e.log?.brewSeconds, 190)
        let bareJSON = #"{"id":"e","clientId":"c","methodCode":"V60","stars":4,"brewedAt":"x","note":"","state":"draft","revision":0,"log":null}"#
        let bare = try JSONDecoder().decode(RemoteExperience.self, from: Data(bareJSON.utf8))
        XCTAssertNil(bare.log)
    }

    func testPayloadLeavesOutNils() {
        let p = BrewLogEntry(grindSetting: "18", taste: .weak).payload
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p["taste"] as? String, "weak")
    }
}
