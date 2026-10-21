import BunnListCore
import SwiftData
import XCTest
@testable import BunnList

/// Runs inside the built app (hosted tests), so `Bundle.main` is the real app bundle.
final class BuiltBundleTests: XCTestCase {
    func testCameraUsageDescriptionIsInTheBuiltAppAndLocalized() throws {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        XCTAssertEqual(value?.isEmpty, false)

        let expected = [
            "ar": "نستخدم الكاميرا لتصوير كيس القهوة وقراءة بياناته لإضافته إلى مجموعتك.",
            "en": "We use the camera to photograph coffee bags and read their details for your collection.",
        ]
        for (language, text) in expected {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil,
                                                      forLocalization: language), "missing \(language).lproj/InfoPlist.strings")
            let strings = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            XCTAssertEqual(strings["NSCameraUsageDescription"], text, language)
        }
    }

    func testBundledSampleCatalogLoadsInTheApp() throws {
        let catalog = try Catalog.bundledSample()
        XCTAssertEqual(catalog.lots.count, 6)
        XCTAssertTrue(catalog.isSample)
    }
}

final class SwiftDataStoreTests: XCTestCase {
    func testSnapshotSurvivesANewStoreOnTheSameContainer() throws {
        let catalog = try Catalog.bundledSample()
        let container = try SwiftDataSnapshotStore.makeContainer(inMemory: true)
        let controller = try LocalSnapshotController(store: SwiftDataSnapshotStore(container: container))
        let owner = controller.snapshot.session.activeOwner
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        try controller.mutate {
            _ = try $0.book.collect(LotID("sample:lot/guji-unknown"), owner: owner, catalog: catalog,
                                    operationID: ClientID(), now: at)
            try $0.book.setFavorite(true, lot: LotID("sample:lot/nyeri-unknown"), owner: owner, catalog: catalog, now: at)
        }
        try controller.mutate { try $0.book.removeFromOwned(LotID("sample:lot/guji-unknown"), owner: owner, now: at) }

        let reopened = try XCTUnwrap(SwiftDataSnapshotStore(container: container).load())
        XCTAssertEqual(reopened, controller.snapshot)
        XCTAssertEqual(reopened.book.entries.count, 2, "removed entries keep their row and history")
        XCTAssertEqual(reopened.book.firstCollectionEvents.count, 1)
    }
}

final class SwiftDataRelaunchTests: XCTestCase {
    func testCollectionSurvivesAFreshContainerOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("relaunch.store")
        let catalog = try Catalog.bundledSample()

        var expected: LocalSnapshot?
        do {
            let controller = try LocalSnapshotController(store: SwiftDataSnapshotStore(container: SwiftDataSnapshotStore.makeContainer(url: url)))
            let owner = controller.snapshot.session.activeOwner
            try controller.mutate {
                _ = try $0.book.collect(LotID("sample:lot/huila-unknown"), owner: owner, catalog: catalog,
                                        operationID: ClientID(), now: Date(timeIntervalSince1970: 1_800_000_000))
            }
            expected = controller.snapshot
        }
        let relaunched = try LocalSnapshotController(store: SwiftDataSnapshotStore(container: SwiftDataSnapshotStore.makeContainer(url: url)))
        XCTAssertEqual(relaunched.snapshot, expected)
        XCTAssertEqual(relaunched.snapshot.book.activeEntries(owner: relaunched.snapshot.session.activeOwner).count, 1)
    }
}

final class NumericLocaleBridgeTests: XCTestCase {
    let grams = NumericFieldPolicy.decimal(maxIntegerDigits: 4, maxFractionDigits: 1)

    func testCommaIsPassedOnlyForCommaRegionsAndShortDecimalFields() {
        XCTAssertEqual(NumericLocaleBridge.extraDecimalSeparator(for: Locale(identifier: "de_DE"), policy: grams), ",")
        XCTAssertNil(NumericLocaleBridge.extraDecimalSeparator(for: Locale(identifier: "en_US"), policy: grams))
        XCTAssertNil(NumericLocaleBridge.extraDecimalSeparator(for: Locale(identifier: "de_DE"),
                                                               policy: .integer(maxDigits: 4)))
        XCTAssertNil(NumericLocaleBridge.extraDecimalSeparator(for: Locale(identifier: "de_DE"),
                                                               policy: .decimal(maxIntegerDigits: 6, maxFractionDigits: 1)))
    }

    func testSameVectorsAsCore() throws {
        XCTAssertEqual(try NumericLocaleBridge.parse("12,5", policy: grams, locale: Locale(identifier: "de_DE"))?.string, "12.5")
        XCTAssertThrowsError(try NumericLocaleBridge.parse("12,5", policy: grams, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(try NumericLocaleBridge.parse("١٢٫٥", policy: grams, locale: Locale(identifier: "ar_SA"))?.string, "12.5")
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    func testSameBagQuestionThenTransfer() throws {
        let model = AppModel(makeStore: { InMemorySnapshotStore() })
        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.collect(LotID("sample:lot/guji-unknown"), operationID: ClientID()), .done(.collected(firstTime: true)))
        let op = ClientID()
        guard case .needsDecision = model.collect(LotID("sample:lot/guji-2025"), operationID: op) else {
            return XCTFail("collecting a known season after UNKNOWN must ask first")
        }
        XCTAssertEqual(model.collect(LotID("sample:lot/guji-2025"), decision: .sameBag, operationID: op),
                       .done(.transferredFromUnknown(LotID("sample:lot/guji-unknown"))))
        XCTAssertNil(model.entry(for: LotID("sample:lot/guji-unknown")))
        XCTAssertEqual(model.entry(for: LotID("sample:lot/guji-2025"))?.isOwned, true)
        XCTAssertNil(model.errorMessage)
    }

    func testFailedSaveShowsAMessageAndChangesNothing() throws {
        let store = InMemorySnapshotStore()
        let model = AppModel(makeStore: { store })
        store.failNextSave = true
        XCTAssertEqual(model.collect(LotID("sample:lot/huila-unknown"), operationID: ClientID()), .failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.entry(for: LotID("sample:lot/huila-unknown")))
    }
}
