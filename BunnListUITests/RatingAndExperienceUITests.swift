import XCTest

/// Simulator gate for C02: rate a lot, then add a brew experience and see it listed.
/// Launches with -uiTesting (in-memory store) so it never touches real local data.
final class RatingAndExperienceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-cameraState", "noCamera"]
        app.launch()
        return app
    }

    private func openGuji(_ app: XCUIApplication) {
        app.tabBars.buttons["اكتشف"].tap()
        let guji = app.buttons["product-sample:product/guji"]
        XCTAssertTrue(guji.waitForExistence(timeout: 5))
        guji.tap()
    }

    func testRatingAKnownSeasonShowsAverage() {
        let app = launch()
        openGuji(app)
        // Rate the 2025 season four stars (no prior UNKNOWN record, so no bag question).
        let fourth = app.descendants(matching: .any)["rating-sample:lot/guji-2025"].buttons["star-4"]
        XCTAssertTrue(fourth.waitForExistence(timeout: 5))
        fourth.tap()
        XCTAssertTrue(app.staticTexts["4.0 · 1 مقيّم"].waitForExistence(timeout: 5))
    }

    func testAddingAnExperienceListsItUnderMyExperiences() {
        let app = launch()
        openGuji(app)
        app.descendants(matching: .any)["activity-sample:lot/guji-2025"].firstMatch.tap()
        app.buttons["add-experience"].tap()
        let fourStars = app.buttons["star-4"]
        XCTAssertTrue(fourStars.waitForExistence(timeout: 5))
        fourStars.tap()
        app.textViews["experience-note"].tap()
        app.textViews["experience-note"].typeText("حلاوة واضحة")
        app.buttons["experience-publish"].tap()
        XCTAssertTrue(app.staticTexts["حلاوة واضحة"].waitForExistence(timeout: 5))
    }
}
