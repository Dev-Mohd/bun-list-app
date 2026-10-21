import XCTest
@testable import BunnListCore

final class ScanTests: XCTestCase {
    var catalog: Catalog!

    override func setUpWithError() throws { catalog = try Catalog.bundledSample() }

    /// Spec tests 11 and 20: missing hardware is distinct from a denied permission.
    func testEntryStates() {
        XCTAssertEqual(ScanEntryState.resolve(hardware: .unavailable, authorization: .notDetermined), .noCamera)
        XCTAssertEqual(ScanEntryState.resolve(hardware: .unavailable, authorization: .denied), .noCamera)
        XCTAssertFalse(ScanEntryState.noCamera.offersSettingsLink, "no Settings link for hardware that is not there")
        XCTAssertFalse(ScanEntryState.noCamera.canCapture)
        XCTAssertEqual(ScanEntryState.resolve(hardware: .available, authorization: .denied), .permissionDenied)
        XCTAssertTrue(ScanEntryState.permissionDenied.offersSettingsLink)
        XCTAssertEqual(ScanEntryState.resolve(hardware: .available, authorization: .notDetermined), .needsPermission)
        XCTAssertEqual(ScanEntryState.resolve(hardware: .available, authorization: .authorized), .ready)
    }

    func testSampleExtractionIsLabeledAndMatchesWithoutChoosingASeason() async throws {
        var flow = ScanFlow()
        let token = flow.beginExtraction()
        let extractor = SampleBagExtractor(catalog: catalog, productID: ProductID("sample:product/guji"))
        let result = try await extractor.extract(imageData: Data([0xFF]))
        XCTAssertTrue(result.isSample)
        XCTAssertTrue(flow.receiveExtraction(.success(result), token: token))
        guard case let .review(fields, _, isSample) = flow.phase else { return XCTFail("\(flow.phase)") }
        XCTAssertTrue(isSample)
        try flow.submitReview(fields, catalog: catalog)
        guard case let .results(_, candidates) = flow.phase else { return XCTFail("\(flow.phase)") }
        XCTAssertEqual(candidates.first?.product.id.rawValue, "sample:product/guji", "the full name match ranks first")
        XCTAssertEqual(candidates[0].lots.count, 3, "all seasons plus UNKNOWN are offered; none is preselected")
    }

    func testLateResponseAfterCancelIsIgnored() {
        var flow = ScanFlow()
        let token = flow.beginExtraction()
        flow.cancel()
        let late = ExtractionResult(fields: ExtractedBagFields(productName: "س", roasterName: "ص"), quality: .readable, isSample: true)
        XCTAssertFalse(flow.receiveExtraction(.success(late), token: token))
        XCTAssertEqual(flow.phase, .idle)

        let stale = flow.beginExtraction()
        let current = flow.beginExtraction()
        XCTAssertFalse(flow.receiveExtraction(.success(late), token: stale), "an older request cannot overwrite a newer one")
        XCTAssertTrue(flow.receiveExtraction(.failure(URLError(.timedOut)), token: current))
        XCTAssertEqual(flow.phase, .failed(fields: nil))
    }

    func testWeakReadKeepsUnknownFieldsEmpty() async throws {
        let extractor = SampleBagExtractor(fields: ExtractedBagFields(productName: "غوجي"))
        let result = try await extractor.extract(imageData: Data())
        XCTAssertEqual(result.quality, .weak)
        XCTAssertEqual(result.fields.roasterName, "")
    }

    func testMatchingNeedsNameAndRoasterAndHandlesMultipleAndNone() throws {
        XCTAssertThrowsError(try CatalogMatcher.match(ExtractedBagFields(productName: "غوجي"), in: catalog)) {
            XCTAssertEqual($0 as? MatchError, .missingNameOrRoaster)
        }
        let multiple = try CatalogMatcher.match(ExtractedBagFields(productName: "التجريبي", roasterName: "محمصة تجريبية أ"), in: catalog)
        guard case let .candidates(found) = multiple else { return XCTFail("\(multiple)") }
        XCTAssertEqual(Set(found.map(\.product.id.rawValue)), ["sample:product/guji", "sample:product/huila"],
                       "several candidates are returned for the user to confirm")
        XCTAssertEqual(try CatalogMatcher.match(ExtractedBagFields(productName: "غوجي", roasterName: "محمصة غير موجودة"), in: catalog),
                       .notFound, "a matching name under a different roaster is not merged")
        var flow = ScanFlow()
        flow.beginManualEntry()
        let unknown = ExtractedBagFields(productName: "قهوة جديدة", roasterName: "محمصة تجريبية ب")
        try flow.submitReview(unknown, catalog: catalog)
        XCTAssertEqual(flow.phase, .notFound(fields: unknown))
        flow.editAgain(unknown)
        guard case .review = flow.phase else { return XCTFail() }
    }
}

final class SnapshotTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testSaveFailureLeavesStateUnchangedAndRetrySucceedsOnce() throws {
        let catalog = try Catalog.bundledSample()
        let store = InMemorySnapshotStore()
        let controller = try LocalSnapshotController(store: store)
        let owner = controller.snapshot.session.activeOwner
        let lot = LotID("sample:lot/nyeri-unknown")
        let op = ClientID()
        store.failNextSave = true
        XCTAssertThrowsError(try controller.mutate { try $0.book.collect(lot, owner: owner, catalog: catalog, operationID: op, now: t0) })
        XCTAssertTrue(controller.snapshot.book.entries.isEmpty)
        XCTAssertEqual(store.saved?.book.entries.isEmpty, true)
        try controller.mutate { _ = try $0.book.collect(lot, owner: owner, catalog: catalog, operationID: op, now: t0) }
        XCTAssertEqual(controller.snapshot.book.entries.count, 1)
    }

    func testRoundTripThroughJSONAndReload() throws {
        let catalog = try Catalog.bundledSample()
        let store = InMemorySnapshotStore()
        let controller = try LocalSnapshotController(store: store)
        let owner = controller.snapshot.session.activeOwner
        try controller.mutate {
            _ = try $0.book.collect(LotID("sample:lot/guji-unknown"), owner: owner, catalog: catalog, operationID: ClientID(), now: t0)
            _ = try $0.book.collect(LotID("sample:lot/guji-2025"), owner: owner, catalog: catalog, decision: .sameBag,
                                    operationID: ClientID(), now: t0)
            try $0.book.setWantsToTry(true, lot: LotID("sample:lot/huila-unknown"), owner: owner, catalog: catalog, now: t0)
        }
        let data = try JSONEncoder().encode(controller.snapshot)
        let decoded = try JSONDecoder().decode(LocalSnapshot.self, from: data)
        XCTAssertEqual(decoded, controller.snapshot)

        let reopened = try LocalSnapshotController(store: InMemorySnapshotStore(decoded))
        XCTAssertEqual(reopened.snapshot.session.activeOwner, owner, "the guest identity survives a restart")
        XCTAssertEqual(reopened.snapshot.book.activeEntries(owner: owner).count, 2)
    }

    func testFutureSchemaIsNotOverwritten() throws {
        var future = LocalSnapshot()
        future.schemaVersion = 99
        let store = InMemorySnapshotStore(future)
        XCTAssertThrowsError(try LocalSnapshotController(store: store))
        XCTAssertEqual(store.saved?.schemaVersion, 99)
    }
}

final class StorageSplitTests: XCTestCase {
    func testSplitAndRestoreRoundTrip() throws {
        let catalog = try Catalog.bundledSample()
        var book = CollectionBook()
        let owner = OwnerID.newGuest()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try book.collect(LotID("sample:lot/guji-unknown"), owner: owner, catalog: catalog, operationID: ClientID(), now: t0)
        _ = try book.collect(LotID("sample:lot/huila-unknown"), owner: owner, catalog: catalog, operationID: ClientID(),
                             now: t0.addingTimeInterval(60))
        let (header, entries) = book.splitForStorage()
        XCTAssertTrue(header.entries.isEmpty)
        var restored = header
        restored.restoreEntries(entries.reversed())
        XCTAssertEqual(restored, book)
    }
}
