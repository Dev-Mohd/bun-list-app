import XCTest
@testable import BunnListCore

final class AppConfigTests: XCTestCase {
    func testVerdict() {
        let p = RemoteAppConfig.Platform(minBuild: 31, latestBuild: 33, storeUrl: "x")
        XCTAssertEqual(RemoteAppConfig.verdict(build: 30, platform: p), .required)
        XCTAssertEqual(RemoteAppConfig.verdict(build: 31, platform: p), .suggested)
        XCTAssertEqual(RemoteAppConfig.verdict(build: 33, platform: p), .ok)
        XCTAssertEqual(RemoteAppConfig.verdict(build: 1, platform: .init(minBuild: 0, latestBuild: 0, storeUrl: "x")), .ok)
    }
}
