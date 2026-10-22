import XCTest
@testable import BunnListCore

/// C02 — recipe water accounting, espresso validation, and copy semantics.
final class RecipeTests: XCTestCase {
    let owner = OwnerID.guest(UUID())
    let lot = LotID("sample:lot/guji-2025")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func g(_ s: String) -> NormalizedDecimal { try! NumericInputParser.parse(s, policy: .decimal(maxIntegerDigits: 4, maxFractionDigits: 1))! }

    private func pourRecipe(pours: [String], hotWater: String, method: String = "V60") -> Recipe {
        var steps: [RecipeStep] = [RecipeStep(kind: .bloom, addedWaterGrams: g(pours[0]), seconds: 30, note: "تفتح")]
        for p in pours.dropFirst() { steps.append(RecipeStep(kind: .pour, addedWaterGrams: g(p), seconds: 30, note: "صب")) }
        steps.append(RecipeStep(kind: .swirl, addedWaterGrams: nil, seconds: nil, note: "تدوير"))
        return Recipe(owner: owner, title: "وصفة", methodCode: method, temperature: .hot, lotID: lot,
                      doseGrams: g("15"), hotWaterGrams: g(hotWater), iceGrams: nil, yieldGrams: nil,
                      waterTempC: g("92"), grinder: "كوماندانتي", grindSetting: "20", notes: "ملاحظة",
                      steps: steps, now: t0)
    }

    // MARK: Water accounting — spec test 18

    func testMatchingPoursPublishAndCumulativeIsDerived() throws {
        let recipe = pourRecipe(pours: ["50", "100", "100"], hotWater: "250")
        let result = recipe.validate()
        XCTAssertTrue(result.isPublishable, "50+100+100 = 250 matches the hot-water total")
        XCTAssertTrue(result.problems.isEmpty)
        // Cumulative is derived for display only; wait/swirl steps do not add water.
        XCTAssertEqual(recipe.cumulativeWaterGrams().map(\.string), ["50", "150", "250", "250"])
    }

    func testMismatchedPoursBlockPublishButSaveAsDraftWithWarning() throws {
        let recipe = pourRecipe(pours: ["50", "100", "150"], hotWater: "250") // sums to 300
        let result = recipe.validate()
        XCTAssertFalse(result.isPublishable)
        XCTAssertTrue(result.problems.contains(.pourSumDoesNotMatchHotWater))
        // Draft save keeps the invalid recipe with the warning surfaced.
        var book = RecipeBook()
        let id = book.saveDraft(recipe)
        XCTAssertEqual(book.recipe(id, owner: owner)?.lifecycle.lifecycle, .draft)
        XCTAssertThrowsError(try book.publish(id, owner: owner, now: t0)) {
            XCTAssertEqual($0 as? RecipeError, .notPublishable([.pourSumDoesNotMatchHotWater]))
        }
    }

    func testArabicAndWesternDigitsAreEquivalentForWaterMath() {
        let western = pourRecipe(pours: ["50", "100", "100"], hotWater: "250")
        // Same recipe entered with Arabic-Indic digits through the parser.
        var steps: [RecipeStep] = [RecipeStep(kind: .bloom, addedWaterGrams: g("٥٠"), seconds: 30, note: "")]
        steps.append(RecipeStep(kind: .pour, addedWaterGrams: g("١٠٠"), seconds: 30, note: ""))
        steps.append(RecipeStep(kind: .pour, addedWaterGrams: g("١٠٠"), seconds: 30, note: ""))
        let arabic = Recipe(owner: owner, title: "وصفة", methodCode: "V60", temperature: .hot, lotID: lot,
                            doseGrams: g("١٥"), hotWaterGrams: g("٢٥٠"), iceGrams: nil, yieldGrams: nil,
                            waterTempC: nil, grinder: "", grindSetting: "", notes: "", steps: steps, now: t0)
        XCTAssertTrue(western.validate().isPublishable)
        XCTAssertTrue(arabic.validate().isPublishable)
        // Same water regardless of digit script (the western fixture adds a no-water swirl step,
        // so compare the final cumulative total rather than the per-step arrays).
        XCTAssertEqual(western.cumulativeWaterGrams().last, arabic.cumulativeWaterGrams().last)
        XCTAssertEqual(arabic.cumulativeWaterGrams().last?.string, "250")
    }

    func testIceIsSeparateFromThePourSum() {
        var steps: [RecipeStep] = [RecipeStep(kind: .bloom, addedWaterGrams: g("50"), seconds: 30, note: "")]
        steps.append(RecipeStep(kind: .pour, addedWaterGrams: g("150"), seconds: 30, note: ""))
        let iced = Recipe(owner: owner, title: "مثلج", methodCode: "V60", temperature: .iced, lotID: lot,
                          doseGrams: g("16"), hotWaterGrams: g("200"), iceGrams: g("120"), yieldGrams: nil,
                          waterTempC: nil, grinder: "", grindSetting: "", notes: "", steps: steps, now: t0)
        let result = iced.validate()
        XCTAssertTrue(result.isPublishable, "pours (50+150=200) match hot water; ice is a separate total")
    }

    func testNegativeOrMissingRequiredFieldsBlockPublish() {
        // Missing hot water on a pour-over.
        let noWater = Recipe(owner: owner, title: "", methodCode: "V60", temperature: .hot, lotID: nil,
                             doseGrams: g("15"), hotWaterGrams: nil, iceGrams: nil, yieldGrams: nil,
                             waterTempC: nil, grinder: "", grindSetting: "", notes: "",
                             steps: [RecipeStep(kind: .pour, addedWaterGrams: g("250"), seconds: 30, note: "")], now: t0)
        let result = noWater.validate()
        XCTAssertFalse(result.isPublishable)
        XCTAssertTrue(result.problems.contains(.missingTitle))
        XCTAssertTrue(result.problems.contains(.missingHotWater))
    }

    // MARK: Espresso — its own validation, no filter pours required

    func testEspressoValidatesDoseAndYieldAndIgnoresPours() {
        let shot = Recipe(owner: owner, title: "شوت", methodCode: "ESPRESSO", temperature: .hot, lotID: lot,
                          doseGrams: g("18"), hotWaterGrams: nil, iceGrams: nil, yieldGrams: g("36"),
                          waterTempC: g("93"), grinder: "نيتش", grindSetting: "12", notes: "", steps: [], now: t0)
        XCTAssertTrue(shot.validate().isPublishable, "espresso needs dose + yield, not pour/hot-water matching")

        let noYield = Recipe(owner: owner, title: "شوت", methodCode: "ESPRESSO", temperature: .hot, lotID: lot,
                             doseGrams: g("18"), hotWaterGrams: nil, iceGrams: nil, yieldGrams: nil,
                             waterTempC: nil, grinder: "", grindSetting: "", notes: "", steps: [], now: t0)
        let result = noYield.validate()
        XCTAssertFalse(result.isPublishable)
        XCTAssertTrue(result.problems.contains(.missingEspressoYield))
    }

    // MARK: Copy — spec test 4

    func testCopyIsANewUnratedDraftWithoutNotesAndKeepsSourceReference() throws {
        var book = RecipeBook()
        let original = pourRecipe(pours: ["50", "100", "100"], hotWater: "250")
        let originalID = book.saveDraft(original)
        try book.publish(originalID, owner: owner, now: t0)

        let copyID = try book.copy(originalID, by: owner, now: t0.addingTimeInterval(60))
        let copy = try XCTUnwrap(book.recipe(copyID, owner: owner))
        XCTAssertNotEqual(copy.clientID, original.clientID)
        XCTAssertEqual(copy.lifecycle.lifecycle, .draft, "a copy starts as a private draft")
        XCTAssertEqual(copy.notes, "", "notes are personal and are not copied")
        XCTAssertEqual(copy.steps.map(\.addedWaterGrams), original.steps.map(\.addedWaterGrams), "method and params carry over")
        XCTAssertEqual(copy.methodCode, original.methodCode)
        XCTAssertEqual(copy.source?.clientID, original.clientID, "the copy references its source")
        XCTAssertEqual(copy.source?.version, book.recipe(originalID, owner: owner)?.version)
        XCTAssertEqual(copy.version, 1)
    }

    func testEditingTheOriginalDoesNotChangePreviousCopies() throws {
        var book = RecipeBook()
        let originalID = book.saveDraft(pourRecipe(pours: ["50", "100", "100"], hotWater: "250"))
        try book.publish(originalID, owner: owner, now: t0)
        let copyID = try book.copy(originalID, by: owner, now: t0.addingTimeInterval(60))
        let copyBefore = try XCTUnwrap(book.recipe(copyID, owner: owner))

        // Edit the original: change title and bump its version.
        try book.update(originalID, owner: owner, now: t0.addingTimeInterval(120)) { $0.title = "عنوان جديد" }
        let copyAfter = try XCTUnwrap(book.recipe(copyID, owner: owner))
        XCTAssertEqual(copyAfter, copyBefore, "the existing copy is unaffected by edits to the original")
        XCTAssertEqual(book.recipe(originalID, owner: owner)?.version, 2, "editing the original bumps its version")
    }

    func testNonOwnerCannotPublishOrEditOrCopyIntoAnotherOwner() throws {
        var book = RecipeBook()
        let id = book.saveDraft(pourRecipe(pours: ["50", "100", "100"], hotWater: "250"))
        let bob = OwnerID.guest(UUID())
        XCTAssertThrowsError(try book.publish(id, owner: bob, now: t0)) { XCTAssertEqual($0 as? RecipeError, .notOwner) }
        XCTAssertThrowsError(try book.update(id, owner: bob, now: t0) { $0.title = "x" })
    }
}
