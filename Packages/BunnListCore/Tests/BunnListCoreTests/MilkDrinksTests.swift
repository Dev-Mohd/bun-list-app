import XCTest
@testable import BunnListCore

final class MilkDrinksTests: XCTestCase {
    func testEspressoHasItsMilkDrinksUnderIt() {
        let espresso = BrewPreset.presets(for: "ESPRESSO")
        XCTAssertEqual(espresso.map(\.id), ["espresso-classic", "espresso-cortado", "espresso-flatwhite", "espresso-cappuccino", "espresso-latte"])
        XCTAssertEqual(espresso.compactMap(\.milkDrink), [.cortado, .flatWhite, .cappuccino, .latte])
        for preset in espresso {
            XCTAssertEqual(preset.doseGrams, 18)
            XCTAssertEqual(preset.yieldGrams, 36)
            XCTAssertEqual(preset.steps.first?.seconds, 28)
            XCTAssertEqual(preset.prepAr.count, 5, preset.id)
        }
    }

    func testDrinksGrowFromCortadoToLatte() {
        let drinks = AdvisorAnswers.milkDrinks
        XCTAssertEqual(drinks.map(\.typicalMilkGrams), [40, 120, 110, 220])
        XCTAssertEqual(drinks.map(\.cupMl), [120, 160, 180, 300])
        // A cappuccino takes more air than a flat white.
        XCTAssertGreaterThan(MilkDrink.cappuccino.airSeconds.lowerBound, MilkDrink.flatWhite.airSeconds.upperBound)
        XCTAssertEqual(MilkDrink.flatWhite.steamingAr.count, 6)
        XCTAssertTrue(MilkDrink.flatWhite.steamingAr[0].contains("120غ"))
    }

    func testPlanCarriesTheMilkAndThePrep() {
        let plan = BrewPlan(preset: BrewPreset.all.first { $0.id == "espresso-flatwhite" }!)
        XCTAssertEqual(plan.milkDrink, .flatWhite)
        XCTAssertEqual(plan.milkGrams, 120)
        XCTAssertEqual(plan.prepAr.count, 5)
        XCTAssertTrue(plan.isEspresso)
        XCTAssertNil(BrewPlan(preset: BrewPreset.all.first { $0.id == "v60-classic" }!).milkDrink)
    }

    func testAdvisorAsksForTheDrinkOnlyWithMilk() {
        var a = AdvisorAnswers()
        a.method = .espresso
        XCTAssertFalse(a.steps.contains(.milkDrink))
        a.milk = true
        XCTAssertEqual(a.steps, [.mood, .method, .milk, .milkDrink, .flavors, .serve, .adventure, .text])
        a.milkDrink = .cappuccino
        XCTAssertEqual(a.milkPreset?.id, "espresso-cappuccino")
        a.milk = false
        XCTAssertFalse(a.steps.contains(.milkDrink))
        XCTAssertNil(a.milkPreset)
        a.method = .v60
        XCTAssertNil(a.milkPreset)
    }

    func testColdBrewHasAConcentrateAndAReadyOne() {
        let cold = BrewPreset.presets(for: "COLD_BREW")
        XCTAssertEqual(cold.map(\.id), ["cold-brew", "cold-brew-ready"])
        let concentrate = cold[0]
        XCTAssertEqual(concentrate.steps.filter { $0.kind == .pour }.compactMap(\.addedWaterGrams).reduce(0, +), 1000)
        XCTAssertEqual(concentrate.steps.filter(\.isAddition).map(\.addition), ["dilute", "ice"])
        XCTAssertEqual(cold[1].steps.filter(\.isAddition).map(\.addition), ["ice"])
        XCTAssertEqual(cold[1].steps.filter { $0.kind == .pour }.compactMap(\.addedWaterGrams).reduce(0, +), 960)
    }
}
