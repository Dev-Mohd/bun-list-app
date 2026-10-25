import XCTest
@testable import BunnListCore

final class BrowseTests: XCTestCase {
    func testQueryItems() {
        var f = BrowseFilters()
        f.text = " خوخ "
        f.origins = ["ET", "CO"]
        f.flavors = [.stoneFruit]
        f.shelf = .missing
        f.favoritesOnly = true
        let items = Dictionary(uniqueKeysWithValues: f.queryItems(offset: 40, limit: 40).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["q"], "خوخ")
        XCTAssertEqual(items["origins"], "CO,ET")
        XCTAssertEqual(items["flavors"], "stoneFruit")
        XCTAssertEqual(items["shelf"], "missing")
        XCTAssertEqual(items["favorites"], "1")
        XCTAssertEqual(items["offset"], "40")
        XCTAssertEqual(f.activeCount, 4)
        XCTAssertTrue(f.needsAccount)
        XCTAssertNil(Dictionary(uniqueKeysWithValues: BrowseFilters().queryItems(offset: 0, limit: 1).map { ($0.name, $0.value) })["q"] ?? nil)
    }

    func testFamilyCodesMatchServer() {
        // lib/mobile/flavorFamilies.ts uses the same codes.
        XCTAssertEqual(FlavorFamily.allCases.map(\.rawValue).filter { $0 != "other" },
                       ["berry", "citrus", "stoneFruit", "tropical", "driedFruit", "floral", "chocolate", "caramel", "nutty", "spice", "tea", "honey"])
    }
}
