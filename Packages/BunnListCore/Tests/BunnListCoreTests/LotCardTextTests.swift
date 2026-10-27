import XCTest
@testable import BunnListCore

final class LotCardTextTests: XCTestCase {
    func testDominantFamilySkipsUnknownNotes() {
        XCTAssertEqual(FlavorFamily.dominant(["غامض", "خوخ", "شوكولاتة"]), .stoneFruit)
        XCTAssertEqual(FlavorFamily.dominant([]), .other)
    }

    func testFlag() {
        XCTAssertEqual(ReferenceCodes.flag("et"), "🇪🇹")
        XCTAssertNil(ReferenceCodes.flag("XB"))
        XCTAssertNil(ReferenceCodes.flag(nil))
    }

    func testCardLine() {
        let lot = RemoteLot(id: "1", slug: "s", name: "n", nameAr: "ناردوس", roasterNameAr: "بلاك نايت",
                            originNameAr: "إثيوبيا", originCode: "ET", process: "ANAEROBIC", processLabel: nil,
                            flavorNotes: ["خوخ", "أناناس", "زهري"], roastLevel: nil, averageRating: 0, reviewCount: 0, imageUrl: nil)
        XCTAssertEqual(lot.cardLine, "🇪🇹 " + (lot.processNameAr ?? "") + " · خوخ، أناناس")
        let bare = RemoteLot(id: "2", slug: "b", name: "n", nameAr: "م", roasterNameAr: "ر", originNameAr: nil, originCode: "XB",
                             process: "OTHER", processLabel: nil, flavorNotes: [], roastLevel: nil, averageRating: 0, reviewCount: 0, imageUrl: nil)
        XCTAssertEqual(bare.cardLine, "")
    }

    func testSpectrumIsDistinctAndCapped() {
        XCTAssertEqual(FlavorFamily.spectrum(["توت", "فراولة", "خوخ", "غامض", "شوكولاتة", "عسل", "ياسمين"]),
                       [.berry, .stoneFruit, .chocolate, .honey])
        XCTAssertEqual(FlavorFamily.spectrum([]), [])
    }

    func testDecodesMatchScores() throws {
        let m = try JSONDecoder().decode(RemoteMatchScores.self, from: Data(#"{"scores":{"bk-nardos":87},"needed":0}"#.utf8))
        XCTAssertEqual(m.scores["bk-nardos"], 87)
    }
}
