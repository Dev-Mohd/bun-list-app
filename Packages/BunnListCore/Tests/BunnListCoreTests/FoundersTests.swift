import XCTest
@testable import BunnListCore

final class FoundersTests: XCTestCase {
    func testLabelPadsToTwoDigits() {
        XCTAssertEqual(FounderBadge(number: 7).label, "#07")
        XCTAssertEqual(FounderBadge(number: 42).label, "#42")
        XCTAssertEqual(FounderBadge(number: 100).label, "#100")
    }

    func testHandlesFromWhatPeopleType() {
        XCTAssertEqual(SocialNetwork.tiktok.handle(from: "@noura.brews"), "noura.brews")
        XCTAssertEqual(SocialNetwork.tiktok.handle(from: "https://www.tiktok.com/@noura.brews?lang=ar"), "noura.brews")
        XCTAssertEqual(SocialNetwork.instagram.handle(from: "instagram.com/noura_brews/"), "noura_brews")
        XCTAssertEqual(SocialNetwork.youtube.handle(from: "https://youtube.com/@NouraBrews"), "NouraBrews")
        XCTAssertEqual(SocialNetwork.x.handle(from: "https://twitter.com/noura"), "noura")
        XCTAssertNil(SocialNetwork.instagram.handle(from: "نورة"))
        XCTAssertNil(SocialNetwork.tiktok.handle(from: "has space"))
        XCTAssertNil(SocialNetwork.x.handle(from: String(repeating: "a", count: 16)))
    }

    func testLinkedKeepsNetworkOrderAndSkipsEmpty() {
        let s = Socials(tiktok: "a", instagram: "", youtube: nil, x: "b")
        XCTAssertEqual(s.linked.map(\.network), [.tiktok, .x])
        XCTAssertEqual(SocialNetwork.tiktok.url(for: "a")?.absoluteString, "https://www.tiktok.com/@a")
        XCTAssertTrue(Socials().isEmpty)
    }

    func testDecodesFounderFieldsAndOldServers() throws {
        let json = #"{"username":"noura","displayName":"نورة","bio":null,"avatarUrl":null,"points":10,"followers":1,"following":2,"isFollowing":false,"isMe":false,"discoveries":[],"recipes":[{"id":"r1","title":"صباحية","methodCode":"V60","lotNameAr":null,"brewedCount":320}],"founder":{"number":7},"socials":{"tiktok":"noura.brews"}}"#
        let p = try JSONDecoder().decode(RemotePublicProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p.founder?.label, "#07")
        XCTAssertEqual(p.socials?.tiktok, "noura.brews")
        XCTAssertEqual(p.recipes.first?.brewedCount, 320)
        let old = #"{"username":"a","displayName":null,"bio":null,"avatarUrl":null,"points":0,"followers":null,"following":null,"isFollowing":false,"isMe":false,"discoveries":[],"recipes":[]}"#
        let o = try JSONDecoder().decode(RemotePublicProfile.self, from: Data(old.utf8))
        XCTAssertNil(o.founder)
        XCTAssertNil(o.socials)
    }

    func testStatsProgress() {
        let s = FounderStats(limit: 100, taken: 27, remaining: 73)
        XCTAssertEqual(s.progress, 0.27, accuracy: 0.0001)
        XCTAssertFalse(s.isFull)
        XCTAssertTrue(FounderStats(limit: 100, taken: 100, remaining: 0).isFull)
    }

    func testAdminActionPayload() {
        XCTAssertEqual(AdminUserAction.setFounder(true).payload["action"] as? String, "setFounder")
        XCTAssertEqual(AdminUserAction.setFounder(false).payload["founder"] as? Bool, false)
    }
}
