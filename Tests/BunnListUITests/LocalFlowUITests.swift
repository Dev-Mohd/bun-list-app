import XCTest

/// Requires Xcode + an iOS simulator. These tests do not reset or erase application data.
final class LocalFlowUITests: XCTestCase {
    @MainActor
    func testDiscoverPublishAndRestoreAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        app.tabBars.buttons["اكتشف"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("قوجي")
        let coffee = app.buttons["coffee-card-ethiopia"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        coffee.tap()
        app.buttons["compose-from-coffee"].tap()
        if app.buttons["استبدال المسودة وبدء التجربة المطلوبة"].waitForExistence(timeout: 1) {
            // This test should be run on a dedicated test simulator.
            app.buttons["استبدال المسودة وبدء التجربة المطلوبة"].tap()
        }
        let method = app.buttons["brew-method"]
        XCTAssertTrue(method.waitForExistence(timeout: 5))
        method.tap()
        app.buttons["ترشيح"].tap()

        let publish = app.buttons["publish-experience"]
        reveal(publish, in: app)
        publish.tap()
        XCTAssertTrue(app.staticTexts["قيّم نتيجة تجربتك من نجمة إلى خمس نجوم قبل النشر."].waitForExistence(timeout: 3))

        let star = app.buttons["rating-star-4"]
        reveal(star, in: app, up: false)
        star.tap()
        let note = app.descendants(matching: .any).matching(identifier: "experience-note").firstMatch
        reveal(note, in: app)
        note.tap()
        let text = "UI-test-\(UUID().uuidString.prefix(8))"
        note.typeText(text)
        app.swipeUp() // Dismiss the keyboard through the form's scroll-dismiss behavior.
        reveal(publish, in: app)
        publish.tap()
        XCTAssertTrue(app.staticTexts["حُفظت تجربتك على هذا الجهاز"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        app.tabBars.buttons["حسابي"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element)")
    }
}
