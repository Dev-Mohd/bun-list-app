import XCTest
@testable import BunnListCore

final class HomeFeedTests: XCTestCase {
    private let json = #"""
    {"trending":{"lots":[{"id":"l1","slug":"nardos","name":"Nardos","nameAr":"نردوس","roasterNameAr":"بلاك نايت",
      "originNameAr":"إثيوبيا","originCode":"ET","process":"NATURAL","processLabel":null,"flavorNotes":["ياسمين"],
      "roastLevel":null,"averageRating":4.5,"reviewCount":5,"imageUrl":null,"rank":1,"move":3,"pinned":false,
      "reason":"trend","brews":12,"reviews":2,"adds":9,"recipes":0},
     {"id":"l2","slug":"altura","name":"Altura","nameAr":"ألتورا","roasterNameAr":"بلاك نايت","originNameAr":null,
      "originCode":null,"process":"WASHED","processLabel":null,"flavorNotes":[],"roastLevel":null,"averageRating":0,
      "reviewCount":0,"imageUrl":null,"rank":2,"move":null,"pinned":false,"reason":"added","brews":0,"reviews":0,"adds":4,"recipes":0}],
     "roasters":[{"slug":"bk","nameAr":"بلاك نايت","score":21.5,"coffees":2,"imageUrl":null}],
     "recipes":[{"id":"r1","title":"مقلوبة","methodCode":"AEROPRESS","authorName":"فهد","lotNameAr":null,"likes":24,"brews":1}]},
     "pulse":[{"kind":"brew","at":"2026-11-06T10:00:00.000Z","name":"سارة","username":"sara","avatarUrl":null,
      "lotSlug":"nardos","lotNameAr":"نردوس","recipeId":null,"recipeTitle":null,"methodCode":"V60","stars":5,"note":"زهرية"}],
     "lastBrew":null}
    """#

    func testDecodesTheHome() throws {
        let home = try JSONDecoder().decode(RemoteHome.self, from: Data(json.utf8))
        XCTAssertEqual(home.trending.lots.count, 2)
        let first = home.trending.lots[0]
        XCTAssertEqual(first.lot.slug, "nardos")
        XCTAssertEqual(first.moveAr, "↑ 3")
        XCTAssertEqual(first.reasonsAr, ["12 تجربة", "تقييمين", "+9 أضافوها"])
        XCTAssertTrue(home.trending.lots[1].isTopUp)
        XCTAssertNil(home.trending.lots[1].moveAr)
        XCTAssertEqual(home.trending.lots[1].reasonsAr, ["+4 أضافوها هالشهر"])
        XCTAssertEqual(home.trending.recipes.first?.likes, 24)
        XCTAssertEqual(home.pulse.first?.actionAr, "حضّر نردوس بـفي ٦٠")
        XCTAssertNil(home.lastBrew)
    }

    func testNewEntriesSayNew() {
        let lot = RemoteLot(id: "x", slug: "x", name: "x", nameAr: "x", roasterNameAr: "", originNameAr: nil, originCode: nil,
                            process: "OTHER", processLabel: nil, flavorNotes: [], roastLevel: nil, averageRating: 0,
                            reviewCount: 0, imageUrl: nil)
        XCTAssertEqual(RemoteTrendingLot(lot: lot, rank: 1, move: nil).moveAr, "جديد")
        XCTAssertNil(RemoteTrendingLot(lot: lot, rank: 1, move: 0).moveAr)
        XCTAssertEqual(RemoteTrendingLot(lot: lot, rank: 1, move: -2).moveAr, "↓ 2")
    }

    func testQuickBrowseFilters() {
        XCTAssertEqual(QuickBrowse.decaf.filters?.queryItems(offset: 0, limit: 10).first { $0.name == "tags" }?.value, "decaf")
        XCTAssertEqual(QuickBrowse.iced.filters?.methods, ["COLD_BREW"])
        XCTAssertNil(QuickBrowse.arabic.filters)
        XCTAssertEqual(QuickBrowse.fruity.filters?.flavors.count, 4)
    }
}
