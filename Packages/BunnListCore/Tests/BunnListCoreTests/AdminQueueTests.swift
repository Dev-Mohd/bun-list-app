import XCTest
@testable import BunnListCore

final class AdminQueueTests: XCTestCase {
    private func card(_ json: String) throws -> RemoteQueueCard {
        try JSONDecoder().decode(RemoteQueueCard.self, from: Data(json.utf8))
    }

    private let pendingJSON = #"{"kind":"submission","id":"s1","name":"شيلشلي","nameEn":null,"roasterName":"محمصة دبليو","imageUrl":null,"originName":"اثيوبيا","originCode":null,"process":null,"roastLevel":null,"flavorNotes":[],"descriptionAr":"مجففة","sourceUrl":null,"missing":["process","notes"]}"#
    private let lotJSON = #"{"kind":"lot","id":"l1","name":"مزيج","nameEn":"Blend","roasterName":"سويل","imageUrl":null,"originName":"مزيج","originCode":"XB","process":"OTHER","roastLevel":"فاتح","flavorNotes":["كراميل"],"descriptionAr":null,"sourceUrl":null,"missing":["origin","process"]}"#

    func testAnEditStartsFromWhatTheCardHas() throws {
        let edit = QueueEdit(try card(pendingJSON))
        XCTAssertEqual(edit.originCode, "ET")
        XCTAssertEqual(edit.stillMissing, [.process, .notes])
        let lot = QueueEdit(try card(lotJSON))
        XCTAssertNil(lot.originCode) // a blend counts as missing
        XCTAssertNil(lot.process)    // so does OTHER
        XCTAssertEqual(lot.roastLevel, .light)
    }

    func testSuggestionsFillWhatTheyKnow() throws {
        var edit = QueueEdit(try card(pendingJSON))
        edit.apply(RemoteDetailSuggestion(process: "NATURAL", originCode: nil, originNameAr: nil, flavorNotes: ["توت", "فراولة"], roastLevel: nil))
        XCTAssertEqual(edit.process, "NATURAL")
        XCTAssertEqual(edit.originCode, "ET") // kept
        XCTAssertEqual(edit.stillMissing, [])
        let body = edit.approvalPayload()
        XCTAssertEqual(body["process"] as? String, "NATURAL")
        XCTAssertEqual(body["originCode"] as? String, "ET")
        XCTAssertEqual(body["flavorNotes"] as? [String], ["توت", "فراولة"])
    }

    func testApprovingWithoutAnswersFilesABlendAsOther() throws {
        var edit = QueueEdit(try card(pendingJSON))
        edit.setOrigin(code: nil)
        let body = edit.approvalPayload()
        XCTAssertEqual(body["originCode"] as? String, "XB")
        XCTAssertEqual(body["originNameAr"] as? String, "مزيج")
        XCTAssertEqual(body["process"] as? String, "OTHER")
    }

    func testALotSendsOnlyWhatChanged() throws {
        var edit = QueueEdit(try card(lotJSON))
        XCTAssertTrue(edit.lotChanges().isEmpty)
        edit.setOrigin(code: "CO")
        edit.process = "WASHED"
        let body = edit.lotChanges()
        XCTAssertEqual(body["originCode"] as? String, "CO")
        XCTAssertEqual(body["originNameAr"] as? String, ReferenceCodes.country("CO")?.nameAr)
        XCTAssertEqual(body["process"] as? String, "WASHED")
        XCTAssertNil(body["flavorNotes"])
    }

    func testRoasterGroupsDecode() throws {
        let g = try JSONDecoder().decode(RemoteRoasterGroup.self, from: Data(#"{"roaster":"أودن","count":26,"noOrigin":4,"noProcess":9,"noNotes":2,"noPhoto":0,"imageUrl":null}"#.utf8))
        XCTAssertEqual(g.gaps, 9)
    }
}
