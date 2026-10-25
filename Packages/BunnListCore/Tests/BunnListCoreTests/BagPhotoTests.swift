import XCTest
@testable import BunnListCore

final class BagPhotoTests: XCTestCase {
    private let good = BagPhotoCheck.Box(minX: 0.2, minY: 0.1, maxX: 0.8, maxY: 0.9)

    func testAGoodShotPasses() {
        XCTAssertEqual(BagPhotoCheck.issues(box: good, photoWidth: 3024, photoHeight: 4032, sharpness: 0.05), [])
    }

    func testFarSmallCutOffAndBlurry() {
        let far = BagPhotoCheck.Box(minX: 0.45, minY: 0.45, maxX: 0.6, maxY: 0.6)
        XCTAssertEqual(BagPhotoCheck.issues(box: far, photoWidth: 1000, photoHeight: 1000, sharpness: nil), [.tooSmall, .tooFar])
        let clipped = BagPhotoCheck.Box(minX: 0.0, minY: 0.1, maxX: 0.7, maxY: 0.9)
        XCTAssertEqual(BagPhotoCheck.issues(box: clipped, photoWidth: 3024, photoHeight: 4032, sharpness: 0.05), [.cutOff])
        XCTAssertEqual(BagPhotoCheck.issues(box: good, photoWidth: 3024, photoHeight: 4032, sharpness: 0.005), [.blurry])
    }

    func testToneByOrigin() {
        XCTAssertEqual(CoffeeArtTone.forOrigin("et"), .africa)
        XCTAssertEqual(CoffeeArtTone.forOrigin("CO"), .latinAmerica)
        XCTAssertEqual(CoffeeArtTone.forOrigin("YE"), .arabia)
        XCTAssertEqual(CoffeeArtTone.forOrigin("ID"), .asia)
        XCTAssertEqual(CoffeeArtTone.forOrigin(nil), .other)
    }
}
