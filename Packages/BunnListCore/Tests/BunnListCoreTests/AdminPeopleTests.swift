import XCTest
@testable import BunnListCore

final class AdminPeopleTests: XCTestCase {
    func testActionPayloads() {
        let suspend = AdminUserAction.suspend(reason: "إزعاج", days: nil).payload
        XCTAssertEqual(suspend["action"] as? String, "suspend")
        XCTAssertTrue(suspend["days"] is NSNull)
        XCTAssertEqual(AdminUserAction.suspend(reason: "x", days: 7).payload["days"] as? Int, 7)
        XCTAssertEqual(AdminUserAction.setAdmin(true).payload["admin"] as? Bool, true)
    }

    func testDecodesUser() throws {
        let json = #"""
        {"accountId":"a","username":"sara","displayName":null,"avatarUrl":null,"joinedAt":"2026-11-01T00:00:00.000Z",
         "isAdmin":false,"suspended":true,"email":"s@x.com","bio":null,"points":40,"lastActiveDay":"2026-11-02",
         "counts":{"reviews":3,"recipes":1,"brews":2,"discoveries":0,"followers":5,"following":4,"reports":1},
         "suspension":{"reason":"إزعاج","until":null,"createdAt":"2026-11-02T00:00:00.000Z"},
         "recentReviews":[{"lotNameAr":"ناردوس","rating":2,"body":null,"status":"HIDDEN","createdAt":"2026-11-02T00:00:00.000Z"}]}
        """#
        let user = try JSONDecoder().decode(RemoteAdminUser.self, from: Data(json.utf8))
        XCTAssertEqual(user.counts.followers, 5)
        XCTAssertNil(user.suspension?.until)
        let row = try JSONDecoder().decode(RemoteAdminUserRow.self, from: Data(#"{"accountId":"a","username":"sara","displayName":null,"avatarUrl":null,"joinedAt":"x","isAdmin":false,"suspended":false}"#.utf8))
        XCTAssertEqual(row.shownName, "@sara")
    }

    func testOlderServerSettingsKeepAnnouncementsOn() throws {
        let s = try JSONDecoder().decode(RemoteNotificationSettings.self, from: Data(#"{"weeklySummary":false}"#.utf8))
        XCTAssertTrue(s.announcements)
        XCTAssertFalse(s.weeklySummary)
    }
}
