import XCTest
@testable import BunnListCore

final class ForYouTests: XCTestCase {
    func testDecodesForYou() throws {
        let lot = #"{"id":"l1","slug":"geisha","name":"Ethiopia Geisha","nameAr":"جيشا إثيوبيا","roasterNameAr":"شفل","originNameAr":"إثيوبيا","originCode":"ET","process":"WASHED","processLabel":null,"flavorNotes":["ياسمين"],"roastLevel":null,"averageRating":4.5,"reviewCount":3,"imageUrl":null}"#
        let json = """
        {"dailyPick":{"lot":\(lot),"score":92,"reason":"تحب الزهور"},
         "resume":[{"lot":\(lot),"since":"2026-10-29T10:00:00.000Z"}],
         "roasterNews":[{"roasterNameAr":"شفل","lots":[{"slug":"a","nameAr":"أ","imageUrl":null,"publishedAt":"2026-10-30T10:00:00.000Z"},{"slug":"b","nameAr":"ب","imageUrl":null,"publishedAt":"2026-10-10T10:00:00.000Z"}]}],
         "friendsDrinking":[{"lot":\(lot),"names":["سارة","نورة","فهد"],"people":6}]}
        """
        let home = try JSONDecoder().decode(RemoteForYou.self, from: Data(json.utf8))
        XCTAssertEqual(home.dailyPick?.score, 92)
        XCTAssertEqual(home.resume.count, 1)
        XCTAssertFalse(home.isEmpty)
        XCTAssertEqual(home.friendsDrinking.first?.line, "سارة ونورة و٤ غيرهم جرّبوها هالأسبوع".replacingOccurrences(of: "٤", with: "4"))
        let news = try XCTUnwrap(home.roasterNews.first)
        XCTAssertEqual(news.unseen(since: nil), 2)
        XCTAssertEqual(news.unseen(since: ISODate.parse("2026-10-20T00:00:00Z")), 1)
        XCTAssertEqual(news.unseen(since: ISODate.parse("2026-11-01T00:00:00Z")), 0)
    }

    func testFriendsLineForOnePerson() throws {
        let lot = RemoteLot.self // keeps the import used
        _ = lot
        let json = #"{"lot":{"id":"l","slug":"s","name":"n","nameAr":"ن","roasterNameAr":"ر","originNameAr":null,"originCode":null,"process":"OTHER","processLabel":null,"flavorNotes":[],"roastLevel":null,"averageRating":0,"reviewCount":0,"imageUrl":null},"names":["سارة"],"people":1}"#
        let item = try JSONDecoder().decode(RemoteForYou.FriendsDrinking.self, from: Data(json.utf8))
        XCTAssertEqual(item.line, "سارة جرّبها هالأسبوع")
    }

    func testAgo() {
        let now = ISODate.parse("2026-11-01T12:00:00Z")!
        XCTAssertEqual(ISODate.ago(now, now: now), "اليوم")
        XCTAssertEqual(ISODate.ago(now.addingTimeInterval(-86_400 * 3), now: now), "من 3 أيام")
        XCTAssertEqual(ISODate.ago(now.addingTimeInterval(-86_400 * 15), now: now), "من أسبوعين")
    }

    private func item(_ id: String, origin: String?, roaster: String, notes: [String], saved: String?) throws -> RemoteCollectionItem {
        var fields: [String: Any] = ["lotId": id, "slug": id, "nameAr": id, "roasterNameAr": roaster, "owned": true, "favorite": false,
                                     "wantsToTry": false, "tried": false, "flavorNotes": notes]
        if let origin { fields["originCode"] = origin }
        if let saved { fields["savedAt"] = saved }
        return try JSONDecoder().decode(RemoteCollectionItem.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    func testCollectionInsights() throws {
        let items = [
            try item("a", origin: "ET", roaster: "شفل", notes: ["توت", "ياسمين"], saved: "2026-11-01T08:00:00Z"),
            try item("b", origin: "et", roaster: "شفل", notes: ["فراولة"], saved: "2026-10-03T08:00:00Z"),
            try item("c", origin: "YE", roaster: "أولالا", notes: ["شوكولاتة", "توت"], saved: "2026-11-02T08:00:00Z"),
            try item("d", origin: "XB", roaster: "سويل", notes: ["قوام"], saved: nil),
        ]
        let now = ISODate.parse("2026-11-05T12:00:00Z")!
        let insights = CollectionInsights(items: items, now: now)
        XCTAssertEqual(insights.coffees, 4)
        XCTAssertEqual(insights.countryCodes, ["ET", "YE"])
        XCTAssertEqual(insights.roasters, 3)
        XCTAssertEqual(insights.shares.first?.family, .berry)
        XCTAssertEqual(insights.shares.map(\.percent).reduce(0, +), 100)
        // This month: a and c; Yemen is new, Ethiopia was there in October.
        XCTAssertEqual(insights.recap, CollectionInsights.Recap(coffees: 2, newCountries: 1, topNote: "توت"))
    }

    func testNoRecapWithoutDates() throws {
        let insights = CollectionInsights(items: [try item("x", origin: nil, roaster: "", notes: [], saved: nil)])
        XCTAssertNil(insights.recap)
        XCTAssertEqual(insights.shares, [])
        XCTAssertEqual(insights.countryCodes, [])
    }
}
