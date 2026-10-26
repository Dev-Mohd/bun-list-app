import XCTest
@testable import BunnListCore

final class AdminConsoleTests: XCTestCase {
    private func lot() throws -> RemoteAdminLot {
        let json = #"""
        {"id":"L1","slug":"bk-nardos","nameAr":"ناردوس","name":"Nardos","roasterNameAr":"بلاك نايت","originCode":"ET",
         "originNameAr":"إثيوبيا","imageUrl":null,"published":true,"reviewCount":2,"process":"ANAEROBIC","processLabel":null,
         "roastLevel":null,"flavorNotes":["خوخ"],"region":"Gedeb","variety":null,"altitudeMeters":2180,"descriptionAr":null,"tags":["luxury"]}
        """#
        return try JSONDecoder().decode(RemoteAdminLot.self, from: Data(json.utf8))
    }

    func testUnchangedFormSendsNothing() throws {
        XCTAssertTrue(AdminLotForm(try lot()).changes(from: try lot()).isEmpty)
    }

    func testFormSendsOnlyChanges() throws {
        let original = try lot()
        var form = AdminLotForm(original)
        form.flavorNotes = ["خوخ", " أناناس ", ""]
        form.region = "  "
        form.altitude = ""
        form.published = false
        form.originCode = "YE"; form.originNameAr = "اليمن"
        form.tags = []
        let body = form.changes(from: original)
        XCTAssertEqual(body["flavorNotes"] as? [String], ["خوخ", "أناناس"])
        XCTAssertTrue(body["region"] is NSNull)
        XCTAssertTrue(body["altitudeMeters"] is NSNull)
        XCTAssertEqual(body["published"] as? Bool, false)
        XCTAssertEqual(body["originCode"] as? String, "YE")
        XCTAssertEqual(body["tags"] as? [String], [])
        XCTAssertNil(body["nameAr"])
    }

    func testDecodesOverviewAndReport() throws {
        let o = try JSONDecoder().decode(RemoteAdminOverview.self, from: Data(#"""
        {"users":10,"newUsers7d":2,"activeToday":3,"reviews7d":4,"recipes7d":1,"brews7d":5,"scans7d":6,"lots":117,
         "pendingSubmissions":12,"openReports":1,"series":[{"day":"2026-11-02","active":3,"newUsers":1}]}
        """#.utf8))
        XCTAssertEqual(o.series.first?.id, "2026-11-02")
        XCTAssertEqual(ReportReason.nameAr("offensive"), "مسيء أو غير لائق")
    }
}
