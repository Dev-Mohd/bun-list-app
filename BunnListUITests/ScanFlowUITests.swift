import XCTest

/// Simulator gate for C01: no camera, denied permission, manual entry → match → collect → collection.
/// Uses `-uiTesting` (in-memory store) so it never touches real local data.
final class ScanFlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(cameraState: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-cameraState", cameraState]
        app.launch()
        return app
    }

    func testNoCameraOffersPhotoAndManualEntryWithoutSettingsLink() {
        let app = launch(cameraState: "noCamera")
        app.tabBars.buttons["مسح"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["scan-no-camera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scan-manual"].exists)
        XCTAssertFalse(app.links["افتح الإعدادات"].exists)
        XCTAssertFalse(app.buttons["scan-capture"].exists)
    }

    func testDeniedPermissionIsDistinctFromNoCamera() {
        let app = launch(cameraState: "denied")
        app.tabBars.buttons["مسح"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["scan-permission-denied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["scan-no-camera"].exists)
    }

    func testManualEntryMatchesAndCollectsUnknownSeason() {
        let app = launch(cameraState: "noCamera")
        app.tabBars.buttons["مسح"].tap()
        app.buttons["scan-manual"].tap()

        let product = app.textFields["field-product"]
        XCTAssertTrue(product.waitForExistence(timeout: 5))
        product.tap()
        product.typeText("Sample Guji")
        let roaster = app.textFields["field-roaster"]
        roaster.tap()
        roaster.typeText("Sample Roaster A")
        app.buttons["scan-search"].tap()

        let unknownLot = app.buttons["scan-lot-sample:lot/guji-unknown"]
        XCTAssertTrue(unknownLot.waitForExistence(timeout: 5))
        unknownLot.tap()
        XCTAssertTrue(app.descendants(matching: .any)["scan-result"].waitForExistence(timeout: 5))

        app.tabBars.buttons["مجموعتي"].tap()
        XCTAssertTrue(app.staticTexts["غوجي التجريبي"].waitForExistence(timeout: 5))
    }
}
