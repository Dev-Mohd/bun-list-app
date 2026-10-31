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

    func testApprovalCarriesTheRoastersEnglishName() throws {
        let json = pendingJSON.replacingOccurrences(of: #""roasterName":"محمصة دبليو","#, with: #""roasterName":"محمصة دبليو","roasterNameEn":"W Roastery","hasOriginalPhoto":true,"#)
        let c = try card(json)
        XCTAssertEqual(c.hasOriginalPhoto, true)
        XCTAssertEqual(QueueEdit(c).approvalPayload()["roasterName"] as? String, "W Roastery")
        XCTAssertEqual(QueueEdit(try card(pendingJSON)).approvalPayload()["roasterName"] as? String, "")
    }

    func testPhotoEditAndBulkEditBodies() throws {
        var edit = PhotoEdit()
        let c = try card(pendingJSON)
        XCTAssertNil(edit.body("preview", c)["crop"])
        edit.crop = PhotoCrop(top: 0.1, bottom: 0.2, leading: 0.05, trailing: 0.6)
        edit.sensitivity = 62.4
        let body = edit.body("apply", c)
        XCTAssertEqual(body["action"] as? String, "apply")
        XCTAssertEqual(body["kind"] as? String, "submission")
        XCTAssertEqual(body["sensitivity"] as? Double, 62)
        let crop = try XCTUnwrap(body["crop"] as? [String: Double])
        XCTAssertEqual(crop["x"]!, 0.05, accuracy: 1e-9)
        XCTAssertEqual(crop["w"]!, 0.5, accuracy: 1e-9) // trailing capped at 0.45
        XCTAssertEqual(crop["h"]!, 0.7, accuracy: 1e-9)

        var bulk = BulkEdit()
        XCTAssertTrue(bulk.isEmpty)
        bulk.originCode = "ET"; bulk.roastLevel = .light
        let set = bulk.payload()
        XCTAssertEqual(set["originNameAr"] as? String, ReferenceCodes.country("ET")?.nameAr)
        XCTAssertEqual(set["roastLevel"] as? String, "light")
        XCTAssertNil(set["process"])
    }

    func testDuplicatePairsDecodeWithAStableId() throws {
        let json = #"{"roaster":"محمصة ضحى","score":0.8,"keepId":"b","a":{"id":"z","slug":"doha-brazil-diamond","nameAr":"Brazil Diamond","name":"Brazil Diamond","imageUrl":null,"originName":"البرازيل","process":"OTHER","flavorNotes":[],"used":0},"b":{"id":"b","slug":"doha-diamond","nameAr":"دايموند البرازيل","name":"Diamond Brazil","imageUrl":"https://x/d.jpg","originName":"البرازيل","process":"NATURAL","flavorNotes":["كراميل"],"used":2}}"#
        let p = try JSONDecoder().decode(RemoteDuplicatePair.self, from: Data(json.utf8))
        XCTAssertEqual(p.id, "b|z")
        XCTAssertEqual(p.other(than: p.keepId).slug, "doha-brazil-diamond")
    }

    func testABlendKeepsItsMixedOriginAndProcess() throws {
        let json = lotJSON.replacingOccurrences(of: #""process":"OTHER""#, with: #""process":"MIXED""#)
            .replacingOccurrences(of: #""missing":["origin","process"]"#, with: #""missing":[]"#)
        var edit = QueueEdit(try card(json))
        XCTAssertEqual(edit.originCode, "XB")
        XCTAssertEqual(edit.process, "MIXED")
        XCTAssertEqual(edit.stillMissing, [])
        XCTAssertTrue(edit.lotChanges().isEmpty)
        XCTAssertEqual(ReferenceCodes.process("MIXED")?.nameAr, "مزيج")
        edit.setOrigin(code: "XB")
        XCTAssertEqual(edit.approvalPayload()["originNameAr"] as? String, "مزيج")
    }

    func testRoasterGroupsDecode() throws {
        let g = try JSONDecoder().decode(RemoteRoasterGroup.self, from: Data(#"{"roaster":"أودن","count":26,"noOrigin":4,"noProcess":9,"noNotes":2,"noPhoto":0,"imageUrl":null}"#.utf8))
        XCTAssertEqual(g.gaps, 9)
    }
}
