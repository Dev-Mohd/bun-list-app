import XCTest
@testable import BunnListCore

final class RecipeWizardTests: XCTestCase {
    func testStartingAToolLoadsItsBaristaRecipeAndKeepsTheName() {
        var draft = RecipeDraft()
        draft.title = "صباحي"
        draft.start(methodCode: "CHEMEX", temperature: .hot)
        XCTAssertEqual(draft.methodCode, "CHEMEX")
        XCTAssertEqual(draft.title, "صباحي")
        XCTAssertFalse(draft.steps.isEmpty)

        draft.start(methodCode: "V60", temperature: .iced)
        XCTAssertEqual(draft.temperature, .iced)
        XCTAssertNotNil(draft.iceGrams)
    }

    func testIcedWithoutItsOwnRecipeTurnsPartOfTheWaterIntoIce() throws {
        var draft = RecipeDraft()
        draft.start(methodCode: "CHEMEX", temperature: .hot)
        let ratio = try XCTUnwrap(draft.ratio)
        draft.setTemperature(.iced)
        XCTAssertNotNil(draft.iceGrams)
        XCTAssertEqual(try XCTUnwrap(draft.ratio), ratio, accuracy: 0.15)
        draft.setTemperature(.hot)
        XCTAssertNil(draft.iceGrams)
    }

    func testChangingTheDoseKeepsTheStrengthAndScalesThePours() throws {
        var draft = RecipeDraft() // 15 g → 250 g
        draft.setDose(20)
        XCTAssertEqual(draft.doseGrams, 20)
        XCTAssertEqual(try XCTUnwrap(draft.ratio), 250.0 / 15, accuracy: 0.05)
        XCTAssertEqual(draft.cumulativeWater.last, draft.hotWaterGrams)
        XCTAssertEqual(draft.hotWaterGrams, 333)

        var shot = RecipeDraft()
        shot.start(methodCode: "ESPRESSO", temperature: .hot)
        let ratio = try XCTUnwrap(shot.ratio)
        shot.setDose(20)
        XCTAssertEqual(try XCTUnwrap(shot.ratio), ratio, accuracy: 0.05)
    }

    func testSuggestedTitleNamesTheToolTheIceAndTheCoffee() {
        var draft = RecipeDraft(lot: RemoteRecipeLot(slug: "x", nameAr: "هامبيلا", roasterNameAr: "آش"))
        XCTAssertEqual(draft.suggestedTitle, "V60 · هامبيلا")
        draft.start(methodCode: "AEROPRESS", temperature: .iced)
        XCTAssertEqual(draft.suggestedTitle, "إيروبرس مثلج · هامبيلا")
    }

    func testABrewBecomesARecipe() throws {
        let preset = try XCTUnwrap(BrewPreset.all.first { $0.id == "v60-46" })
        let draft = RecipeDraft(plan: BrewPlan(preset: preset), lot: nil, grinderId: nil, grindSetting: "")
        XCTAssertEqual(draft.methodCode, "V60")
        XCTAssertEqual(draft.steps, preset.steps)
        XCTAssertEqual(draft.title, "V60")
        XCTAssertNil(draft.existingState)
        XCTAssertTrue(draft.notes.contains("الطحن"))
    }
}
