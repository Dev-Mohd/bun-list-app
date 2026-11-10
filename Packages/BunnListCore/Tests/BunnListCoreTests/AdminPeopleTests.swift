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

    func testActivityLabels() {
        XCTAssertEqual(AdminActivity.label("2026-11-10", today: "2026-11-10"), "نشط اليوم")
        XCTAssertEqual(AdminActivity.label("2026-11-09", today: "2026-11-10"), "أمس")
        XCTAssertEqual(AdminActivity.label("2026-11-05", today: "2026-11-10"), "قبل 5 أيام")
        XCTAssertEqual(AdminActivity.label("2026-10-01", today: "2026-11-10"), "قبل 40 يوم")
        XCTAssertEqual(AdminActivity.label(nil, today: "2026-11-10"), "ما فتح التطبيق")
        XCTAssertEqual(AdminActivity.riyadhToday(Date(timeIntervalSince1970: 1_794_348_000)).count, 10)
    }

    func testRotationDecodesAndSendsOnlyKnownIDs() throws {
        var r = try JSONDecoder().decode(RemoteRotation.self, from: Data(#"""
        {"enabled":true,"everyDays":2,"audience":"all","lastRunAt":null,"nextRunAt":"2026-11-12T15:00:00.000Z","nextItemId":"a",
         "items":[{"id":"a","title":"أولى","body":"نص","enabled":true,"sentCount":3,"lastSentAt":null}]}
        """#.utf8))
        r.items.append(.init(id: "local-1", title: "جديدة", body: "نص جديد"))
        let items = r.payload(knownIDs: ["a"])["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?[0]["id"] as? String, "a")
        XCTAssertNil(items?[1]["id"])
        XCTAssertEqual(r.payload(knownIDs: [])["everyDays"] as? Int, 2)
        XCTAssertFalse(BroadcastTemplates.all.isEmpty)
        XCTAssertTrue(BroadcastTemplates.all.allSatisfy { $0.title.count <= 60 && $0.body.count <= 200 })
    }
}
