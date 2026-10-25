import XCTest
@testable import BunnListCore

final class HomeContentTests: XCTestCase {
    func testGreeting() {
        XCTAssertEqual(Greeting.text(hour: 8, name: "محمد العتيبي"), "صباح الخير، محمد")
        XCTAssertEqual(Greeting.text(hour: 20, name: nil), "مساء الخير")
        XCTAssertEqual(Greeting.text(hour: 2, name: ""), "مساء الخير")
    }

    func testFactRotatesDaily() {
        XCTAssertEqual(CoffeeFacts.fact(forDay: 0), CoffeeFacts.all[0])
        XCTAssertEqual(CoffeeFacts.fact(forDay: CoffeeFacts.all.count + 1), CoffeeFacts.all[1])
        XCTAssertFalse(CoffeeFacts.fact(forDay: -3).isEmpty)
    }

    func testGrindEquivalents() throws {
        let c40 = try XCTUnwrap(Grinder.find("comandante-c40"))
        let eq = c40.equivalents(ofClicks: 24) // 720 µm
        XCTAssertEqual(eq.first { $0.grinder.id == "1zpresso-k-ultra" }?.clicks, 36)
        XCTAssertNil(eq.first { $0.grinder.id == "ek43" })
        XCTAssertFalse(eq.contains { $0.grinder.id == c40.id })
        XCTAssertTrue(Grinder.convertible.allSatisfy { $0.micronsPerClick != nil })
    }

    func testDiscoveriesDecodeWithAndWithoutDiscoverer() async throws {
        final class T: HTTPTransport, @unchecked Sendable {
            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                HTTPResponse(status: 200, body: Data(#"{"lots":[{"id":"a","slug":"a","name":"A","nameAr":"أ","roasterNameAr":"م","originNameAr":null,"originCode":null,"process":"WASHED","processLabel":null,"flavorNotes":[],"roastLevel":null,"averageRating":0,"reviewCount":0,"imageUrl":null,"discoveredBy":"@mohd"},{"id":"b","slug":"b","name":"B","nameAr":"ب","roasterNameAr":"م","originNameAr":null,"originCode":null,"process":"WASHED","processLabel":null,"flavorNotes":[],"roastLevel":null,"averageRating":0,"reviewCount":0,"imageUrl":null}]}"#.utf8))
            }
        }
        let lots = try await CatalogAPIClient(transport: T()).fetchDiscoveries()
        XCTAssertEqual(lots[0].discoveredBy, "@mohd")
        XCTAssertNil(lots[1].discoveredBy)
    }
}
