import XCTest
@testable import BunnListCore

/// Stand-in for the C04 endpoint: upsert on (accountID, lotID) with a stable request key.
private final class FakeAccountServer {
    var collections: [OwnerID: [LotID: CollectionEntry]] = [:]
    var localToServer: [ClientID: ClientID] = [:]
    private var processedKeys: Set<String> = []
    var failAfter: Int?

    func importEntries(_ entries: [CollectionEntry], account: OwnerID, batch: ClientID) throws -> [ClientID] {
        var confirmed: [ClientID] = []
        for entry in entries {
            if let limit = failAfter, confirmed.count >= limit { throw URLError(.networkConnectionLost) }
            let key = "\(batch)|\(entry.clientID)"
            if processedKeys.contains(key) { confirmed.append(entry.clientID); continue }
            var bucket = collections[account, default: [:]]
            if let existing = bucket[entry.lotID] {
                bucket[entry.lotID] = GuestImportRules.merge(guest: entry, into: existing)
                localToServer[entry.clientID] = existing.clientID
            } else {
                bucket[entry.lotID] = entry
                localToServer[entry.clientID] = entry.clientID
            }
            collections[account] = bucket
            processedKeys.insert(key)
            confirmed.append(entry.clientID)
        }
        return confirmed
    }
}

final class GuestImportTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let account = OwnerID.account("acct-1")
    let otherAccount = OwnerID.account("acct-2")
    let lots = (1...6).map { LotID("lot-\($0)") }

    private func realCatalog() throws -> Catalog {
        let roaster = Roaster(id: RoasterID("r"), nameAr: "محمصة", nameEn: nil, cityAr: nil)
        var products: [CoffeeProduct] = []
        var catalogLots: [CoffeeLot] = []
        for (index, lot) in lots.enumerated() {
            let product = CoffeeProduct(id: ProductID("p-\(index)"), roasterID: roaster.id, nameAr: "قهوة \(index)", nameEn: nil,
                                        origin: Origin(type: .unknown, countryCodes: []), processCode: nil, flavorCodes: [],
                                        recommendedBrewMethods: [], approval: .approved)
            products.append(product)
            catalogLots.append(CoffeeLot(id: lot, productID: product.id, season: .unknown, roastBatchCode: nil, approval: .approved))
        }
        return try Catalog(label: "اختبار", roasters: [roaster], products: products, lots: catalogLots)
    }

    /// Spec test 13: guest has lots 1–5, account has 3 (two shared) → 6 unique.
    func testFivePlusThreeWithTwoSharedIsSixAndRetryIsSafe() throws {
        let catalog = try realCatalog()
        var session = LocalSession()
        let guest = session.activeOwner
        var book = CollectionBook()
        for lot in lots[0..<5] { _ = try book.collect(lot, owner: guest, catalog: catalog, operationID: ClientID(), now: t0) }
        try book.setNote("ملاحظة الزائر", lot: lots[0], owner: guest, now: t0)

        let server = FakeAccountServer()
        var accountBook = CollectionBook()
        for lot in [lots[0], lots[1], lots[5]] {
            _ = try accountBook.collect(lot, owner: account, catalog: catalog, operationID: ClientID(), now: t0.addingTimeInterval(-3600))
        }
        try accountBook.setNote("ملاحظة الحساب", lot: lots[0], owner: account, now: t0)
        server.collections[account] = Dictionary(uniqueKeysWithValues: accountBook.activeEntries(owner: account).map { ($0.lotID, $0) })

        session.signIn(account: account, keepGuestSeparately: true)
        var batch = GuestImportBatch(guestID: guest, entries: book.activeEntries(owner: guest))
        XCTAssertEqual(batch.pending.count, 5)

        // First attempt is interrupted after two confirmations.
        server.failAfter = 2
        let pendingEntries = { batch.pending.compactMap { id in book.entries.first { $0.clientID == id } } }
        XCTAssertThrowsError(try server.importEntries(pendingEntries(), account: account, batch: batch.batchID))
        batch.confirm(Array(batch.pending.prefix(2)))
        XCTAssertEqual(batch.state, .inProgress)
        XCTAssertEqual(batch.pending.count, 3, "only unconfirmed records remain")

        // Resume the same batch; resending already-confirmed records changes nothing on the server.
        server.failAfter = nil
        batch.confirm(try server.importEntries(book.activeEntries(owner: guest), account: account, batch: batch.batchID))
        XCTAssertEqual(batch.state, .completed)
        XCTAssertEqual(server.collections[account]?.count, 6)
        _ = try server.importEntries(book.activeEntries(owner: guest), account: account, batch: batch.batchID)
        XCTAssertEqual(server.collections[account]?.count, 6, "retrying the batch does not duplicate")
        XCTAssertNil(server.collections[otherAccount], "another account sees nothing")

        let merged = try XCTUnwrap(server.collections[account]?[lots[0]])
        XCTAssertEqual(merged.note, "ملاحظة الحساب", "the account's note wins")
        XCTAssertEqual(merged.preservedNotes, ["ملاحظة الزائر"], "the guest note is kept separately")
        XCTAssertEqual(merged.firstCollectedAt, t0.addingTimeInterval(-3600), "earliest date wins")

        session.finishImport(batch, book: &book)
        XCTAssertTrue(book.entries.filter { $0.ownerID == guest }.isEmpty, "confirmed local copies are removed")

        session.signOut(clearing: &book)
        XCTAssertTrue(session.isGuest)
        XCTAssertNotEqual(session.activeOwner, guest, "a completed import leaves a fresh, empty guest")
        XCTAssertTrue(book.activeEntries(owner: session.activeOwner).isEmpty)
    }

    func testDeclinedImportKeepsTheGuestSeparateAndReturnsItOnSignOut() throws {
        let catalog = try realCatalog()
        var session = LocalSession()
        let guest = session.activeOwner
        var book = CollectionBook()
        _ = try book.collect(lots[0], owner: guest, catalog: catalog, operationID: ClientID(), now: t0)

        session.signIn(account: account, keepGuestSeparately: true)
        var batch = GuestImportBatch(guestID: guest, entries: book.activeEntries(owner: guest))
        batch.decline()
        XCTAssertEqual(batch.state, .declined)
        // Cached account data on the device.
        _ = try book.collect(lots[3], owner: account, catalog: catalog, operationID: ClientID(), now: t0)

        session.signOut(clearing: &book)
        XCTAssertEqual(session.activeOwner, guest)
        XCTAssertEqual(book.activeEntries(owner: guest).map(\.lotID), [lots[0]])
        XCTAssertTrue(book.activeEntries(owner: account).isEmpty, "account data is cleared from the device on sign-out")
    }

    func testSampleCatalogEntriesAreNeverOffered() throws {
        let sample = try Catalog.bundledSample()
        var book = CollectionBook()
        let guest = OwnerID.newGuest()
        _ = try book.collect(LotID("sample:lot/huila-unknown"), owner: guest, catalog: sample, operationID: ClientID(), now: t0)
        let batch = GuestImportBatch(guestID: guest, entries: book.activeEntries(owner: guest))
        XCTAssertTrue(batch.pending.isEmpty)
        XCTAssertEqual(batch.state, .inProgress)
    }
}
