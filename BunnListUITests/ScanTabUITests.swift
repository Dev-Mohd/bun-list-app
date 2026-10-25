import XCTest

/// The scan tab signed out: a sign-in prompt for scanning, and the ways in that
/// don't need the bag. Uses `-uiTesting` (in-memory store).
final class ScanTabUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSignedOutScanTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-cameraState", "noCamera"]
        app.launch()
        app.tabBars.buttons["مسح"].tap()
        XCTAssertTrue(app.buttons["scan-sign-in"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scan-search-name"].exists)
        XCTAssertTrue(app.buttons["scan-suggest"].exists)
    }
}
