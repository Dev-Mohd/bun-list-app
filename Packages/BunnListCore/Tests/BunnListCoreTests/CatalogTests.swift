import XCTest
@testable import BunnListCore

final class CatalogTests: XCTestCase {
    func testBundledSampleCatalogShape() throws {
        let catalog = try Catalog.bundledSample()
        XCTAssertEqual(catalog.label, "دليل تجريبي")
        XCTAssertEqual(catalog.products.count, 4)
        XCTAssertEqual(catalog.lots.count, 6)
        XCTAssertTrue(catalog.isSample)
        XCTAssertTrue(catalog.lots.allSatisfy(\.id.isSample))

        let guji = ProductID("sample:product/guji")
        let gujiLots = catalog.lots(of: guji)
        XCTAssertEqual(gujiLots.map(\.id.rawValue), ["sample:lot/guji-2025", "sample:lot/guji-2024", "sample:lot/guji-unknown"],
                       "two known seasons, newest first, then the shared UNKNOWN lot")
        for product in catalog.products {
            XCTAssertNotNil(catalog.unknownLot(of: product.id), "every product has exactly one UNKNOWN lot")
        }
        let blend = try XCTUnwrap(catalog.product(ProductID("sample:product/house-blend")))
        XCTAssertEqual(blend.origin.type, .multiCountry)
    }

    func testFixtureFileHasNoRatingsOrCommunityNumbers() throws {
        let url = try Catalog.bundledSampleURL()
        let text = try String(contentsOf: url, encoding: .utf8).lowercased()
        for forbidden in ["rating", "stars", "review", "average", "votes", "voter", "users", "followers"] {
            XCTAssertFalse(text.contains(forbidden), "fixtures must not claim community data: \(forbidden)")
        }
    }


    func testValidationRejectsMissingOrDuplicateUnknownLots() throws {
        let roaster = Roaster(id: RoasterID("r"), nameAr: "م", nameEn: nil, cityAr: nil)
        let product = makeProduct("p", approval: .approved)
        let known = CoffeeLot(id: LotID("l1"), productID: product.id, season: .known(label: "2025", harvestYear: 2025),
                              roastBatchCode: nil, approval: .approved)
        XCTAssertThrowsError(try Catalog(label: "x", roasters: [roaster], products: [product], lots: [known])) {
            XCTAssertEqual($0 as? CatalogError, .missingUnknownLot(product.id))
        }
        let unknownA = CoffeeLot(id: LotID("u1"), productID: product.id, season: .unknown, roastBatchCode: nil, approval: .approved)
        let unknownB = CoffeeLot(id: LotID("u2"), productID: product.id, season: .unknown, roastBatchCode: nil, approval: .approved)
        XCTAssertThrowsError(try Catalog(label: "x", roasters: [roaster], products: [product], lots: [unknownA, unknownB])) {
            XCTAssertEqual($0 as? CatalogError, .duplicateUnknownLot(product.id))
        }
    }

    func testUnknownLotFollowsProductApprovalButKnownSeasonsAreReviewedSeparately() throws {
        let roaster = Roaster(id: RoasterID("r"), nameAr: "م", nameEn: nil, cityAr: nil)
        let approved = makeProduct("p", approval: .approved)
        let pendingUnknown = CoffeeLot(id: LotID("u"), productID: approved.id, season: .unknown, roastBatchCode: nil, approval: .pending)
        XCTAssertThrowsError(try Catalog(label: "x", roasters: [roaster], products: [approved], lots: [pendingUnknown])) {
            XCTAssertEqual($0 as? CatalogError, .unknownLotApprovalMismatch(LotID("u")))
        }
        let approvedUnknown = CoffeeLot(id: LotID("u"), productID: approved.id, season: .unknown, roastBatchCode: nil, approval: .approved)
        let newSeason = CoffeeLot(id: LotID("s"), productID: approved.id, season: .known(label: nil, harvestYear: 2026),
                                  roastBatchCode: nil, approval: .pending)
        let catalog = try Catalog(label: "x", roasters: [roaster], products: [approved], lots: [approvedUnknown, newSeason])
        XCTAssertEqual(catalog.lot(LotID("s"))?.approval, .pending, "a new season stays pending even under an approved product")
    }

    func testValidationRejectsMixingSampleAndRealIDsAndUnknownCodes() {
        let roaster = Roaster(id: RoasterID("sample:r"), nameAr: "م", nameEn: nil, cityAr: nil)
        let product = CoffeeProduct(id: ProductID("p"), roasterID: roaster.id, nameAr: "ق", nameEn: nil,
                                    origin: Origin(type: .singleCountry, countryCodes: ["ET"]), processCode: nil,
                                    flavorCodes: [], recommendedBrewMethods: [], approval: .approved)
        let lot = CoffeeLot(id: LotID("u"), productID: product.id, season: .unknown, roastBatchCode: nil, approval: .approved)
        XCTAssertThrowsError(try Catalog(label: "x", roasters: [roaster], products: [product], lots: [lot])) {
            XCTAssertEqual($0 as? CatalogError, .mixedSampleAndRealIDs)
        }
        let realRoaster = Roaster(id: RoasterID("r"), nameAr: "م", nameEn: nil, cityAr: nil)
        let badOrigin = CoffeeProduct(id: ProductID("p"), roasterID: realRoaster.id, nameAr: "ق", nameEn: nil,
                                      origin: Origin(type: .singleCountry, countryCodes: ["ET", "CO"]), processCode: nil,
                                      flavorCodes: [], recommendedBrewMethods: [], approval: .approved)
        XCTAssertThrowsError(try Catalog(label: "x", roasters: [realRoaster], products: [badOrigin], lots: [lot])) {
            XCTAssertEqual($0 as? CatalogError, .inconsistentOrigin(ProductID("p")))
        }
    }

    func testSearchByNameRoasterOriginFlavorWithArabicNormalization() throws {
        let catalog = try Catalog.bundledSample()
        XCTAssertEqual(CatalogSearch.products(in: catalog, query: "غوجي").map(\.id.rawValue), ["sample:product/guji"])
        XCTAssertEqual(CatalogSearch.products(in: catalog, query: "اثيوبيا").map(\.id.rawValue),
                       ["sample:product/house-blend", "sample:product/guji"].sorted { a, b in
                           catalog.product(ProductID(a))!.nameAr < catalog.product(ProductID(b))!.nameAr },
                       "hamza-less spelling matches إثيوبيا, including the multi-origin blend")
        XCTAssertEqual(Set(CatalogSearch.products(in: catalog, query: "محمصة تجريبية ب").map(\.id.rawValue)),
                       ["sample:product/nyeri", "sample:product/house-blend"])
        XCTAssertEqual(CatalogSearch.products(in: catalog, query: "Huila").map(\.id.rawValue), ["sample:product/huila"])
        XCTAssertTrue(CatalogSearch.products(in: catalog, query: "لا يوجد شيء كهذا").isEmpty)
        XCTAssertEqual(CatalogSearch.products(in: catalog, query: "").count, 4)
    }

    func testFilters() throws {
        let catalog = try Catalog.bundledSample()
        XCTAssertEqual(CatalogSearch.products(in: catalog, query: "", filters: CatalogFilters(countryCode: "KE")).map(\.id.rawValue),
                       ["sample:product/nyeri"])
        XCTAssertEqual(Set(CatalogSearch.products(in: catalog, query: "", filters: CatalogFilters(flavorCode: "BERRY")).map(\.id.rawValue)),
                       ["sample:product/nyeri", "sample:product/huila"])
        XCTAssertEqual(CatalogSearch.products(in: catalog, query: "", filters: CatalogFilters(processCode: "NATURAL",
                                                                                        brewMethodCode: "ESPRESSO")).map(\.id.rawValue),
                       ["sample:product/huila"])
    }

    func testNormalizer() {
        XCTAssertEqual(TextNormalizer.normalize("أَحْمَد"), TextNormalizer.normalize("احمد"))
        XCTAssertEqual(TextNormalizer.normalize("قهوة مختصّة"), TextNormalizer.normalize("قهوه مختصه"))
        XCTAssertEqual(TextNormalizer.normalize("Café  ٢٠٢٥"), "cafe 2025")
    }

    private func makeProduct(_ id: String, approval: ApprovalStatus) -> CoffeeProduct {
        CoffeeProduct(id: ProductID(id), roasterID: RoasterID("r"), nameAr: "ق", nameEn: nil,
                      origin: Origin(type: .unknown, countryCodes: []), processCode: nil, flavorCodes: [],
                      recommendedBrewMethods: [], approval: approval)
    }
}
