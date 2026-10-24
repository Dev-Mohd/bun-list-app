import XCTest
@testable import BunnListCore

/// Server recipes: the editor draft's derived values and validation, and the client calls.
final class ServerRecipeTests: XCTestCase {
    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let responder: @Sendable (HTTPRequest) -> HTTPResponse
        private(set) var requests: [HTTPRequest] = []
        init(_ responder: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.responder = responder }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            requests.append(request)
            return responder(request)
        }
    }

    private let recipeJSON = #"{"id":"r1","clientId":"c1","title":"صباحية","methodCode":"V60","temperature":"hot","lot":{"slug":"s","nameAr":"قهوة","roasterNameAr":"محمصة"},"doseGrams":15,"hotWaterGrams":250,"iceGrams":null,"yieldGrams":null,"waterTempC":96,"grinder":"C40","grindSetting":"24","grinderModel":"comandante-c40","grindLevel":"medium","grindMicrons":720,"brewer":"V60 02","filterType":"abaca","roastLevel":"light","restDays":12,"notes":"","steps":[{"kind":"bloom","addedWaterGrams":50,"seconds":45,"note":""},{"kind":"pour","addedWaterGrams":200,"seconds":80,"note":"","pourStyle":"circular","pourSpeed":"slow"}],"sourceId":null,"sourceVersion":null,"version":1,"state":"published","authorName":"محمد","isMine":true,"publishedAt":"2026-10-24T00:00:00.000Z","updatedAt":"2026-10-24T00:00:00.000Z"}"#

    // MARK: Draft

    func testDefaultDraftIsAValidPourOverOnceTitled() {
        var draft = RecipeDraft()
        XCTAssertEqual(draft.problems(), [.missingTitle, .missingGrind])
        draft.title = "صباحية"
        draft.grindLevel = .mediumFine
        XCTAssertEqual(draft.problems(), [])
        XCTAssertEqual(draft.cumulativeWater.last, 250)
        XCTAssertEqual(draft.ratio ?? 0, 16.67, accuracy: 0.01)
        XCTAssertEqual(draft.totalSeconds, 125)
    }

    func testApplyingARatioRescalesPoursToMatchHotWater() {
        var draft = RecipeDraft()
        draft.title = "t"
        draft.grindLevel = .medium
        draft.doseGrams = 20
        draft.applyRatio(15)
        XCTAssertEqual(draft.hotWaterGrams, 300)
        XCTAssertEqual(draft.cumulativeWater.last, 300)
        XCTAssertEqual(draft.problems(), [])
    }

    func testIcedRatioCountsIceAndKeepsPoursOnHotWater() {
        var draft = RecipeDraft()
        draft.title = "t"
        draft.grindLevel = .medium
        draft.temperature = .iced
        draft.iceGrams = 100
        draft.applyRatio(16)  // 15 g × 16 = 240 total, 140 hot
        XCTAssertEqual(draft.hotWaterGrams, 140)
        XCTAssertEqual(draft.outputGrams, 240)
        XCTAssertEqual(draft.problems(), [])
    }

    func testEspressoNeedsDoseAndYieldNotHotWater() {
        var draft = RecipeDraft()
        draft.title = "شوت"
        draft.grindLevel = .extraFine
        draft.methodCode = "ESPRESSO"
        draft.steps = []
        draft.yieldGrams = nil
        XCTAssertEqual(draft.problems(), [.missingEspressoYield])
        draft.doseGrams = 18
        draft.applyRatio(2)
        XCTAssertEqual(draft.yieldGrams, 36)
        XCTAssertEqual(draft.problems(), [])
    }

    func testMismatchedPoursAreFlagged() {
        var draft = RecipeDraft()
        draft.title = "t"
        draft.grindLevel = .medium
        draft.steps[1].addedWaterGrams = 10
        XCTAssertEqual(draft.problems(), [.pourSumDoesNotMatchHotWater])
    }

    func testCopyKeepsParametersButNotIdentityOrNotes() throws {
        let recipe = try JSONDecoder().decode(RemoteRecipe.self, from: Data(recipeJSON.utf8))
        let copy = RecipeDraft(copying: recipe)
        XCTAssertNotEqual(copy.clientID, "c1")
        XCTAssertEqual(copy.sourceID, "r1")
        XCTAssertNil(copy.existingState)
        XCTAssertEqual(copy.steps.count, 2)
        let edit = RecipeDraft(editing: recipe)
        XCTAssertEqual(edit.clientID, "c1")
        XCTAssertEqual(edit.existingState, .published)
    }

    // MARK: Client

    func testSavePostsTheDraft() async throws {
        let transport = FakeTransport { [recipeJSON] _ in HTTPResponse(status: 200, body: Data(recipeJSON.utf8)) }
        var draft = RecipeDraft(lot: RemoteRecipeLot(slug: "s", nameAr: "قهوة", roasterNameAr: "محمصة"))
        draft.title = "صباحية"
        let saved = try await CatalogAPIClient(transport: transport).saveRecipe(draft, publish: true, accessToken: "acc")
        XCTAssertEqual(saved.id, "r1")
        XCTAssertEqual(saved.lot?.slug, "s")
        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.path, "/api/v1/recipes")
        let body = try XCTUnwrap((try? JSONSerialization.jsonObject(with: req.body ?? Data())) as? [String: Any])
        XCTAssertEqual(body["lotSlug"] as? String, "s")
        XCTAssertEqual(body["publish"] as? Bool, true)
        XCTAssertEqual((body["steps"] as? [[String: Any]])?.count, 3)
        XCTAssertTrue(body["yieldGrams"] is NSNull)
    }

    func testExploreEncodesTheLotAndDecodes() async throws {
        let transport = FakeTransport { [recipeJSON] _ in
            HTTPResponse(status: 200, body: Data((#"{"recipes":["# + recipeJSON + "]}").utf8))
        }
        let list = try await CatalogAPIClient(transport: transport).exploreRecipes(lotSlug: "yirga-natural")
        XCTAssertEqual(list.first?.authorName, "محمد")
        XCTAssertEqual(transport.requests.first?.path, "/api/v1/recipes/explore?lot=yirga-natural")
        XCTAssertNil(transport.requests.first?.bearer)
    }

    func testPublishRejectionMapsToUnprocessable() async {
        let transport = FakeTransport { _ in HTTPResponse(status: 422, body: Data(#"{"error":"unprocessable"}"#.utf8)) }
        do {
            _ = try await CatalogAPIClient(transport: transport).changeRecipeState(id: "r1", to: .published, accessToken: "a")
            XCTFail("expected 422")
        } catch let error as APIError {
            XCTAssertEqual(error, .unprocessable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: Recipe standard

    func testDecodesStandardFieldsAndOlderRecipesWithoutThem() throws {
        let recipe = try JSONDecoder().decode(RemoteRecipe.self, from: Data(recipeJSON.utf8))
        XCTAssertEqual(recipe.grindLevel, .medium)
        XCTAssertEqual(recipe.filterType, .abaca)
        XCTAssertEqual(recipe.steps[1].pourStyle, .circular)
        let older = recipeJSON
            .replacingOccurrences(of: #""grinderModel":"comandante-c40","grindLevel":"medium","grindMicrons":720,"brewer":"V60 02","filterType":"abaca","roastLevel":"light","restDays":12,"#, with: "")
        let old = try JSONDecoder().decode(RemoteRecipe.self, from: Data(older.utf8))
        XCTAssertNil(old.grindLevel)
        XCTAssertEqual(RecipeDraft(editing: old).brewer, "")
    }

    func testPublishStandardNeedsGrindAndSteps() {
        var draft = RecipeDraft()
        draft.title = "t"
        draft.grindSetting = "٢٤ كليك"
        XCTAssertEqual(draft.problems(), [])
        draft.steps = []
        XCTAssertTrue(draft.problems().contains(.missingSteps))
    }

    func testCompetitionSheetEditing() {
        var draft = RecipeDraft()
        draft.apply(BrewPreset.all[0]) // 0:00 bloom 45, 0:45 →150, 1:15 →250, 1:45 swirl, 1:55 wait, ends 2:55
        XCTAssertEqual(draft.startTimes, [0, 45, 75, 105, 115])

        draft.setStart(1, to: 40)
        XCTAssertEqual(draft.startTimes, [0, 40, 75, 105, 115])
        XCTAssertEqual(draft.totalSeconds, 175)

        draft.setPourTo(1, grams: 160)
        XCTAssertEqual(draft.cumulativeWater[1], 160)
        XCTAssertEqual(draft.cumulativeWater[2], 250) // later reading kept
        XCTAssertEqual(draft.hotWaterGrams, 250)

        draft.setPourTo(2, grams: 260) // last pour: hot water follows
        XCTAssertEqual(draft.hotWaterGrams, 260)

        draft.setFinish(200)
        XCTAssertEqual(draft.totalSeconds, 200)
    }

    func testGrinderConversion() throws {
        var draft = RecipeDraft()
        draft.setGrind(grinderID: "comandante-c40", clicks: 24)
        XCTAssertEqual(draft.grindMicrons, 720)
        XCTAssertEqual(draft.grindLevel, .medium)
        XCTAssertEqual(draft.grindSetting, "24")
        let kUltra = try XCTUnwrap(Grinder.find("1zpresso-k-ultra"))
        XCTAssertEqual(kUltra.clicks(forMicrons: 720), 36)
        XCTAssertNil(try XCTUnwrap(Grinder.find("ek43")).clicks(forMicrons: 720))
        draft.setGrind(grinderID: "ek43", clicks: 9)
        XCTAssertNil(draft.grindMicrons)
        XCTAssertEqual(GrindLevel.level(forMicrons: 300), .extraFine)
        XCTAssertEqual(GrindLevel.level(forMicrons: 1300), .extraCoarse)
    }
}
