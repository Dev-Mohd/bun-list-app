import XCTest
@testable import BunnListCore

final class UpdatesTests: XCTestCase {
    func testDecodesUpdatesAndOfficialComments() throws {
        let u = try JSONDecoder().decode(RemoteUpdate.self, from: Data("""
        {"id":"u1","title":"قهوة جديدة","body":"وصلت إثيوبيا","author":"BunnList","createdAt":"2026-11-03T10:00:00.000Z","commentCount":2}
        """.utf8))
        XCTAssertEqual(u.author, "BunnList")
        XCTAssertEqual(u.commentCount, 2)

        let comments = try JSONDecoder().decode(RemoteComments.self, from: Data("""
        {"comments":[
          {"id":"a","body":"متى؟","createdAt":"2026-11-03T10:00:00.000Z","name":"سارة","username":"sara","avatarUrl":null,"isMine":false,"canDelete":false,"isOfficial":false},
          {"id":"b","body":"بكرة","createdAt":"2026-11-03T10:05:00.000Z","name":"BunnList","username":null,"avatarUrl":null,"isMine":false,"canDelete":false,"isOfficial":true},
          {"id":"c","body":"قديم","createdAt":"2026-11-03T10:05:00.000Z","name":"فهد","username":null,"avatarUrl":null,"isMine":false,"canDelete":false}
        ],"count":3}
        """.utf8))
        XCTAssertEqual(comments.comments.map(\.official), [false, true, false])
        XCTAssertEqual(CommentTarget.update.rawValue, "update")
    }

    func testFeedbackKindsAndReplies() throws {
        let inbox = try JSONDecoder().decode(RemoteFeedbackInbox.self, from: Data("""
        {"open":1,"items":[
          {"id":"f1","kind":"problem","body":"الصفحة تعلق","createdAt":"2026-11-03T10:00:00.000Z","reply":null,"repliedAt":null,"name":"سارة","username":"sara","avatarUrl":null,"isRead":false},
          {"id":"f2","kind":"weird","body":"x","createdAt":"2026-11-03T10:00:00.000Z","reply":"تم","repliedAt":"2026-11-03T11:00:00.000Z"}
        ]}
        """.utf8))
        XCTAssertEqual(inbox.items[0].feedbackKind, .problem)
        XCTAssertFalse(inbox.items[0].isAnswered)
        XCTAssertEqual(inbox.items[1].feedbackKind, .suggestion) // unknown kinds fall back
        XCTAssertTrue(inbox.items[1].isAnswered)
        XCTAssertEqual(FeedbackKind.allCases.map(\.nameAr), ["اقتراح", "تجربة", "مشكلة"])
    }

    func testUpdateDraftEncodesAndValidates() throws {
        var draft = UpdateDraft(title: "ميزة جديدة", body: "صار فيه مستشار القهوة", notify: true)
        XCTAssertTrue(draft.isReady)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        XCTAssertEqual(object["notify"] as? Bool, true)
        draft.body = " "
        XCTAssertFalse(draft.isReady)
    }
}
