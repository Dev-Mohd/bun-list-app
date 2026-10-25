import XCTest
@testable import BunnListCore

final class AppIconTests: XCTestCase {
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s + "T12:00:00+03:00")!
    }

    func testSeasons() {
        XCTAssertEqual(AppIconChoice.season(on: date("2026-09-23")), .nationalDay)
        XCTAssertEqual(AppIconChoice.season(on: date("2027-02-22")), .foundingDay)
        XCTAssertNil(AppIconChoice.season(on: date("2026-10-25")))
        // Ramadan 1448 starts around 8 Feb 2027; Eid al-Fitr around 9 Mar 2027.
        XCTAssertEqual(AppIconChoice.season(on: date("2027-02-15")), .ramadan)
        XCTAssertEqual(AppIconChoice.season(on: date("2027-03-10")), .eidFitr)
        // Eid al-Adha 1447 around 26-27 May 2026.
        XCTAssertEqual(AppIconChoice.season(on: date("2026-05-27")), .eidAdha)
    }

    func testAssetNames() {
        XCTAssertNil(AppIconChoice.classic.assetName)
        XCTAssertEqual(AppIconChoice.ramadan.previewName, "IconPreview-Ramadan")
        XCTAssertEqual(AppIconChoice.classic.previewName, "IconPreview-Classic")
    }
}
