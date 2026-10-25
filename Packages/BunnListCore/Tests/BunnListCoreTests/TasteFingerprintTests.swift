import XCTest
@testable import BunnListCore

final class TasteFingerprintTests: XCTestCase {
    func testFamilies() {
        XCTAssertEqual(FlavorFamily.of("خوخ"), .stoneFruit)
        XCTAssertEqual(FlavorFamily.of("فراولة"), .berry)
        XCTAssertEqual(FlavorFamily.of("شمام"), .tea)
        XCTAssertEqual(FlavorFamily.of("Dark Chocolate"), .chocolate)
        XCTAssertEqual(FlavorFamily.of("ياسمين"), .floral)
        XCTAssertEqual(FlavorFamily.of("غامض"), .other)
    }

    func testPercentagesAddUpTo100() {
        XCTAssertEqual(LotCommunityStats.percentages([1, 1, 1]), [34, 33, 33])
        XCTAssertEqual(LotCommunityStats.percentages([3, 1]), [75, 25])
        XCTAssertEqual(LotCommunityStats.percentages([2]), [100])
        XCTAssertEqual(LotCommunityStats.percentages([]), [])
        XCTAssertEqual(LotCommunityStats.percentages([0, 0]), [0, 0])
    }

    func testLotDetailDecodesCommunity() throws {
        let json = #"{"id":"1","slug":"s","name":"n","nameAr":"خوخ","roasterNameAr":"ر","originNameAr":null,"originCode":null,"process":"HONEY","processLabel":null,"flavorNotes":[],"roastLevel":null,"averageRating":5,"reviewCount":2,"imageUrl":null,"descriptionAr":null,"regionAr":null,"variety":null,"recommendedBrewMethods":[],"brewStats":[],"discoveredBy":"Shumukh","discoveredByUsername":"shumukh","discoverer":{"name":"Shumukh","username":"shumukh","avatarUrl":null,"note":"رائعة"},"community":{"collectors":7,"brewers":2,"methods":[{"method":"V60","count":2}]}}"#
        let lot = try JSONDecoder().decode(RemoteLotDetail.self, from: Data(json.utf8))
        XCTAssertEqual(lot.discoverer?.note, "رائعة")
        XCTAssertEqual(lot.community?.collectors, 7)
    }
}
