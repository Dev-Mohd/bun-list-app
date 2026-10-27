import XCTest

/// Scanning now opens from the home screen's camera button (the tab became «حضّر»):
/// signed out, a sign-in prompt for scanning and the ways in that don't need the
/// bag. Uses `-uiTesting` (in-memory store).
final class ScanTabUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSignedOutScanFromHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-cameraState", "noCamera"]
        app.launch()
        app.buttons["open-scan"].tap()
        XCTAssertTrue(app.buttons["scan-sign-in"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scan-search-name"].exists)
        XCTAssertTrue(app.buttons["scan-suggest"].exists)
    }

    func testBrewTabAsksToSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        app.tabBars.buttons["حضّر"].tap()
        XCTAssertTrue(app.staticTexts["حضّر قهوتك خطوة بخطوة"].waitForExistence(timeout: 5))
    }
}
