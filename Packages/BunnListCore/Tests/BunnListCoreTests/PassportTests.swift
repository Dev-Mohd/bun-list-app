import XCTest
@testable import BunnListCore

final class PassportTests: XCTestCase {
    func testDecodesPassport() throws {
        let json = #"""
        {"coffees":3,"countries":2,"regions":2,"processes":2,
         "stamps":[{"code":"ET","nameAr":"إثيوبيا","region":"africa","count":2,"firstAt":"2026-10-11T10:00:00.000Z"},
                   {"code":"CO","nameAr":"كولومبيا","region":"americas","count":1,"firstAt":"2026-10-12T10:00:00.000Z"}],
         "badges":[{"id":"first-stamp","titleAr":"أول ختم","detailAr":"","icon":"seal.fill","current":1,"goal":1,"earned":true},
                   {"id":"explorer","titleAr":"مستكشف","detailAr":"","icon":"map.fill","current":2,"goal":5,"earned":false}]}
        """#
        let p = try JSONDecoder().decode(RemotePassport.self, from: Data(json.utf8))
        XCTAssertEqual(p.stamps.first?.id, "ET")
        XCTAssertNotNil(p.stamps.first?.firstDate)
        XCTAssertEqual(p.earnedCount, 1)
        XCTAssertEqual(p.badges[1].progress, 0.4, accuracy: 0.001)
        XCTAssertEqual(RemotePassport.regionNameAr("arabia"), "الجزيرة العربية")
    }
}
