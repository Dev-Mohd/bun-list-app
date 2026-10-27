import XCTest
@testable import BunnListCore

final class SharedLinkTests: XCTestCase {
    func testCoffeeLinks() {
        XCTAssertEqual(SharedLink.coffeeSlug(from: URL(string: "https://bunnlist.com/coffees/black-knight-nardos")!), "black-knight-nardos")
        XCTAssertEqual(SharedLink.coffeeSlug(from: URL(string: "https://www.bunnlist.com/coffees/abc-1/")!), "abc-1")
    }

    func testOtherLinksAreIgnored() {
        XCTAssertNil(SharedLink.coffeeSlug(from: URL(string: "https://bunnlist.com/privacy")!))
        XCTAssertNil(SharedLink.coffeeSlug(from: URL(string: "https://evil.com/coffees/x")!))
        XCTAssertNil(SharedLink.coffeeSlug(from: URL(string: "https://bunnlist.com/coffees/a/b")!))
        XCTAssertNil(SharedLink.coffeeSlug(from: URL(string: "com.googleusercontent.apps.x:/oauth")!))
    }
}
