import XCTest
@testable import BunnListCore

final class DiscoverTextTests: XCTestCase {
    private func lot(_ id: String, roaster: String = "بلاك نايت", rating: Double = 0, reviews: Int = 0,
                     origin: String? = "ET", process: String = "ANAEROBIC") -> RemoteLot {
        RemoteLot(id: id, slug: id, name: id, nameAr: id, roasterNameAr: roaster, originNameAr: "إثيوبيا", originCode: origin,
                  process: process, processLabel: nil, flavorNotes: [], roastLevel: nil, averageRating: rating,
                  reviewCount: reviews, imageUrl: nil)
    }

    func testOnePerRoasterKeepsTheNewestOfEach() {
        let lots = [lot("a1", roaster: "أسانتي"), lot("a2", roaster: "أسانتي"), lot("s1", roaster: "شفل"),
                    lot("a3", roaster: "أسانتي"), lot("o1", roaster: "أولالا"), lot("s2", roaster: "شفل")]
        XCTAssertEqual(DiscoverText.onePerRoaster(lots, limit: 6).map(\.id), ["a1", "s1", "o1"])
        XCTAssertEqual(DiscoverText.onePerRoaster(lots, limit: 2).map(\.id), ["a1", "s1"])
    }

    func testNoRatingLineBeforeAnyRating() {
        XCTAssertNil(DiscoverText.ratingLine(lot("a")))
        XCTAssertEqual(DiscoverText.ratingLine(lot("a", rating: 5, reviews: 2)), "★ 5.0 · تقييمين")
    }

    func testNewestLeadsAndIsNotRepeated() {
        let (featured, rest) = DiscoverText.split(newest: [lot("a"), lot("b"), lot("c")])
        XCTAssertEqual(featured?.id, "a")
        XCTAssertEqual(rest.map(\.id), ["b", "c"])
        XCTAssertNil(DiscoverText.split(newest: []).featured)
    }

    func testRoasterShownOnceOnlyWhenShared() {
        XCTAssertEqual(DiscoverText.sharedRoaster([lot("a"), lot("b")]), "بلاك نايت")
        XCTAssertNil(DiscoverText.sharedRoaster([lot("a"), lot("b", roaster: "أخرى")]))
    }

    func testRatingIsRealOrAnInvitation() {
        XCTAssertEqual(DiscoverText.rating(lot("a")), "كن أول من يقيّمها")
        XCTAssertEqual(DiscoverText.rating(lot("a", rating: 4.46, reviews: 12)), "★ 4.5 · 12 تقييم")
        XCTAssertEqual(DiscoverText.rating(lot("a", rating: 5, reviews: 2)), "★ 5.0 · تقييمين")
    }

    func testOriginLineAndProcessGuide() {
        XCTAssertEqual(DiscoverText.originLine(lot("a")), "🇪🇹 إثيوبيا · لاهوائية")
        XCTAssertNotNil(DiscoverText.processGuide("NATURAL"))
        XCTAssertNil(DiscoverText.processGuide("OTHER"))
    }

    func testSubtitleByHour() {
        XCTAssertEqual(DiscoverText.subtitle(hour: 8), "قهوة الصباح؟")
        XCTAssertEqual(DiscoverText.subtitle(hour: 22), "شي خفيف للمسا؟")
    }
}
