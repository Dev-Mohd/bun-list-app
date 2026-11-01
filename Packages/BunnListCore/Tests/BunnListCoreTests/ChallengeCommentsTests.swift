import XCTest
@testable import BunnListCore

final class ChallengeCommentsTests: XCTestCase {
    private let json = """
    {"challenge":{"id":"c1","titleAr":"جرّب قهوة يمنية","subtitleAr":null,"emoji":"🇾🇪","action":"rate",
      "filters":{"originCode":"YE","process":null,"roasterSlug":null,"flavorFamily":"berry"},
      "target":2,"points":50,"startsAt":"2026-11-01T00:00:00.000Z","endsAt":"2026-11-08T00:00:00.000Z"},
     "participants":12,"finished":3,"me":{"progress":1,"completed":false,"justCompleted":false}}
    """

    func testDecodesTheChallenge() throws {
        let state = try JSONDecoder().decode(RemoteChallengeState.self, from: Data(json.utf8))
        let c = try XCTUnwrap(state.challenge)
        XCTAssertEqual(c.actionAr, "قيّم")
        XCTAssertEqual(state.me?.progress, 1)
        XCTAssertEqual(c.browseFilters.origins, ["YE"])
        XCTAssertEqual(c.browseFilters.flavors, [.berry])
        XCTAssertFalse(c.filters.isEmpty)
        let now = ISODate.parse("2026-11-05T12:00:00Z")!
        XCTAssertEqual(c.timeLeftAr(now: now), "باقي 3 أيام")
        XCTAssertEqual(c.timeLeftAr(now: ISODate.parse("2026-11-07T20:00:00Z")!), "آخر يوم")
        XCTAssertEqual(c.timeLeftAr(now: ISODate.parse("2026-11-09T00:00:00Z")!), "انتهى")
    }

    func testNoChallenge() throws {
        let state = try JSONDecoder().decode(RemoteChallengeState.self, from: Data(#"{"challenge":null,"participants":0,"finished":0,"me":null}"#.utf8))
        XCTAssertNil(state.challenge)
    }

    func testDraftEncodesWhatTheServerExpects() throws {
        let state = try JSONDecoder().decode(RemoteChallengeState.self, from: Data(json.utf8))
        var draft = ChallengeDraft(try XCTUnwrap(state.challenge))
        draft.subtitleAr = ""
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        XCTAssertEqual(object["titleAr"] as? String, "جرّب قهوة يمنية")
        XCTAssertTrue(object["subtitleAr"] is NSNull)
        XCTAssertEqual(object["originCode"] as? String, "YE")
        XCTAssertEqual(object["target"] as? Int, 2)
        XCTAssertEqual(object["startsAt"] as? String, "2026-11-01T00:00:00Z")
        XCTAssertTrue(draft.isValid)
        draft.endsAt = draft.startsAt
        XCTAssertFalse(draft.isValid)
    }

    func testCommentsAndPostTargets() throws {
        let comments = try JSONDecoder().decode(RemoteComments.self, from: Data("""
        {"comments":[{"id":"x","body":"حلوة","createdAt":"2026-11-01T10:00:00.000Z","name":"سارة","username":"sara","avatarUrl":null,"isMine":false,"canDelete":true}],"count":1}
        """.utf8))
        XCTAssertEqual(comments.comments.first?.name, "سارة")
        let brew = try JSONDecoder().decode(RemotePulseItem.self, from: Data("""
        {"kind":"brew","at":"2026-11-01T10:00:00.000Z","name":"سارة","username":"sara","avatarUrl":null,"lotSlug":"s","lotNameAr":"ن","recipeId":null,"recipeTitle":null,"methodCode":"V60","stars":5,"note":null,"brewId":"b1","commentCount":4}
        """.utf8))
        XCTAssertEqual(brew.commentTarget?.0, .brew)
        XCTAssertEqual(brew.commentTarget?.1, "b1")
        XCTAssertEqual(brew.commentCount, 4)
        let discovery = try JSONDecoder().decode(RemotePulseItem.self, from: Data("""
        {"kind":"discovery","at":"2026-11-01T10:00:00.000Z","name":"فهد","username":null,"avatarUrl":null,"lotSlug":"s","lotNameAr":"ن","recipeId":null,"recipeTitle":null,"methodCode":null,"stars":null,"note":null}
        """.utf8))
        XCTAssertNil(discovery.commentTarget)
    }

    func testNotificationSettingsCarryComments() throws {
        let old = try JSONDecoder().decode(RemoteNotificationSettings.self, from: Data(#"{"newFollower":false}"#.utf8))
        XCTAssertTrue(old.comments)
        let off = try JSONDecoder().decode(RemoteNotificationSettings.self, from: Data(#"{"comments":false}"#.utf8))
        XCTAssertFalse(off.comments)
    }
}
