import XCTest
@testable import BunnListCore

final class SiteClicksTests: XCTestCase {
    func testDecodesAndSorts() throws {
        let json = #"{"days":30,"total":10,"byPlatform":{"ios":8,"android":2},"bySource":{"hero":7,"bar":3},"byDay":[{"day":"2026-11-09","count":5},{"day":"2026-11-10","count":5}]}"#
        let c = try JSONDecoder().decode(RemoteSiteClicks.self, from: Data(json.utf8))
        XCTAssertEqual(c.total, 10)
        XCTAssertEqual(RemoteSiteClicks.sorted(c.bySource).map(\.key), ["hero", "bar"])
        XCTAssertEqual(RemoteSiteClicks.sorted(["b": 1, "a": 1]).map(\.key), ["a", "b"])
        XCTAssertEqual(c.byDay.last?.day, "2026-11-10")
    }

    func testNames() {
        XCTAssertEqual(RemoteSiteClicks.platformAr("apk"), "Android (تحميل الملف)")
        XCTAssertEqual(RemoteSiteClicks.sourceAr("bar"), "الشريط الثابت تحت")
        XCTAssertEqual(RemoteSiteClicks.sourceAr("tiktok"), "tiktok")
    }
}
