import XCTest
@testable import BunnListCore

final class CoffeePageTests: XCTestCase {
    func testDecodesTheNewDetailFields() throws {
        let json = """
        {"id":"l","slug":"s","name":"Konga","nameAr":"كونجا","roasterNameAr":"أولالا","originNameAr":"إثيوبيا","originCode":"ET","process":"NATURAL","processLabel":null,"flavorNotes":["موز"],"roastLevel":null,"averageRating":4.6,"reviewCount":23,"imageUrl":null,"descriptionAr":null,"regionAr":"يرغاتشيف","variety":null,"recommendedBrewMethods":[],"brewStats":[],
         "altitudeMeters":2100,
         "buy":{"url":"https://olalaroastery.com/p/1","host":"olalaroastery.com","kind":"roaster","storeNameAr":null},
         "roasterRecipes":[{"method":"V60","tool":"عين تايمور V60","doseG":18.5,"waterMl":270,"tempC":93,"timeSec":135,"grind":"متوسطة","ratio":15,"steps":["الترطيب إلى 40 مل","الصب إلى 270 مل"]}]}
        """
        let lot = try JSONDecoder().decode(RemoteLotDetail.self, from: Data(json.utf8))
        XCTAssertEqual(lot.altitudeMeters, 2100)
        XCTAssertEqual(lot.buy?.title, "اشترِ من المحمصة")
        XCTAssertEqual(lot.buy?.subtitle, "olalaroastery.com · الموقع الرسمي")
        XCTAssertEqual(lot.roasterRecipes?.first?.steps.count, 2)
        XCTAssertEqual(lot.factTiles.map(\.kind), [.origin, .altitude, .process])
    }

    func testOlderServersDecodeWithoutTheNewFields() throws {
        let json = """
        {"id":"l","slug":"s","name":"x","nameAr":"س","roasterNameAr":"ر","originNameAr":null,"originCode":null,"process":"OTHER","processLabel":null,"flavorNotes":[],"roastLevel":null,"averageRating":0,"reviewCount":0,"imageUrl":null,"descriptionAr":"وصف","regionAr":null,"variety":null,"recommendedBrewMethods":[],"brewStats":[]}
        """
        let lot = try JSONDecoder().decode(RemoteLotDetail.self, from: Data(json.utf8))
        XCTAssertNil(lot.buy)
        XCTAssertNil(lot.roasterRecipes)
        XCTAssertNil(lot.altitudeMeters)
        XCTAssertEqual(lot.factTiles, [])
    }

    func testAStoreLinkIsNamedAsTheStore() {
        let link = RemoteBuyLink(url: "https://yahimcups.com/x", host: "yahimcups.com", kind: "store", storeNameAr: "يحيم كبس")
        XCTAssertFalse(link.isRoasterStore)
        XCTAssertEqual(link.title, "اشترِها من يحيم كبس")
        XCTAssertEqual(link.subtitle, "متجر يبيعها · yahimcups.com")
    }

    func testMissingFactsLeaveNoEmptyTile() {
        typealias T = CoffeeFactTiles.Tile
        // Only the country: one wide tile.
        XCTAssertEqual(CoffeeFactTiles.tiles(origin: "البرازيل", altitude: nil, process: nil, variety: nil),
                       [T(kind: .origin, wide: true)])
        // Country and process: the process spans the row on its own.
        XCTAssertEqual(CoffeeFactTiles.tiles(origin: "إثيوبيا", altitude: nil, process: "مجففة", variety: " "),
                       [T(kind: .origin, wide: true), T(kind: .process, wide: true)])
        // Three halves: two share a row, the last spans.
        XCTAssertEqual(CoffeeFactTiles.tiles(origin: "كولومبيا", altitude: 1800, process: "مغسولة", variety: "كاتورا"),
                       [T(kind: .origin, wide: true), T(kind: .altitude, wide: false), T(kind: .process, wide: false), T(kind: .variety, wide: true)])
        // No altitude of zero.
        XCTAssertEqual(CoffeeFactTiles.tiles(origin: nil, altitude: 0, process: nil, variety: nil), [])
    }

    func testTasteLeanFollowsTheNotes() throws {
        XCTAssertEqual(try XCTUnwrap(TasteLean.position(["شوكولاتة", "مكسرات"])), 0.033, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(TasteLean.position(["فراولة", "مانجو"])), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(TasteLean.position(["كراميل"])), 0.5, accuracy: 0.001)
        // The first note counts most.
        let fruitFirst = try XCTUnwrap(TasteLean.position(["توت", "شوكولاتة"]))
        let chocolateFirst = try XCTUnwrap(TasteLean.position(["شوكولاتة", "توت"]))
        XCTAssertGreaterThan(fruitFirst, 0.5)
        XCTAssertLessThan(chocolateFirst, 0.5)
        XCTAssertNil(TasteLean.position([]))
        XCTAssertNil(TasteLean.position(["قوام ممتلئ"]))
    }

    func testHotIcedAndMachineRecipes() throws {
        let json = """
        [{"method":"V60","serve":"HOT","link":null,"tool":null,"doseG":19,"waterMl":285,"tempC":91,"timeSec":160,"grind":null,"ratio":15,"steps":[]},
         {"method":"XBLOOM","serve":"ICED","link":"https://share-h5.xbloom.com/?id=x","tool":"xBloom","doseG":null,"waterMl":null,"tempC":null,"timeSec":null,"grind":null,"ratio":null,"steps":[]},
         {"method":"CHEMEX","tool":"كيمكس","doseG":18,"waterMl":270,"tempC":93,"timeSec":130,"grind":null,"ratio":15,"steps":[]}]
        """
        let recipes = try JSONDecoder().decode([RemoteRoasterRecipe].self, from: Data(json.utf8))
        XCTAssertEqual(recipes.map(\.label), ["تقطير V60", "xBloom · بارد", "كيمكس"])
        XCTAssertFalse(recipes[0].isIced)
        XCTAssertTrue(recipes[1].isIced)
        XCTAssertTrue(recipes[1].isMachineLink)
        XCTAssertNil(recipes[1].doseG)
        XCTAssertFalse(recipes[2].isIced) // older servers: no serve, hot
    }

    func testDecodesSimilarCoffees() throws {
        let lot = #"{"id":"l","slug":"s","name":"n","nameAr":"ن","roasterNameAr":"شفل","originNameAr":"إثيوبيا","originCode":"ET","process":"NATURAL","processLabel":null,"flavorNotes":["توت"],"roastLevel":null,"averageRating":0,"reviewCount":0,"imageUrl":null}"#
        let json = "{\"similar\":[{\"lot\":\(lot),\"reason\":\"نفس النكهات: توت\"}],\"sameRoaster\":[\(lot)]}"
        let result = try JSONDecoder().decode(RemoteSimilarLots.self, from: Data(json.utf8))
        XCTAssertEqual(result.similar.first?.reason, "نفس النكهات: توت")
        XCTAssertEqual(result.sameRoaster.count, 1)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(FlavorFamily.of("زهور"), .floral)
    }

    func testRecipeText() {
        XCTAssertEqual(RemoteRoasterRecipe.clock(135), "2:15")
        XCTAssertEqual(RemoteRoasterRecipe.clock(30), "30 ث")
        XCTAssertEqual(RemoteRoasterRecipe.grams(18), "18")
        XCTAssertEqual(RemoteRoasterRecipe.grams(20.5), "20.5")
    }
}
