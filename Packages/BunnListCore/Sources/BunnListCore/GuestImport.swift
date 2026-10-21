import Foundation

/// Merge rules for «ضم مجموعتي المحلية لهذا الحساب» (executed against the server in C04).
/// Union for owned/favorite/want-to-try, OR for tried, earliest dates win, the account's note wins and
/// a different guest note is preserved separately. Sample-catalog lots are never uploaded, and no
/// points or streak days are granted retroactively for imported records.
public enum GuestImportRules {
    public static func merge(guest: CollectionEntry, into account: CollectionEntry) -> CollectionEntry {
        var merged = account
        merged.isOwned = account.isOwned || guest.isOwned
        merged.isFavorite = account.isFavorite || guest.isFavorite
        merged.wantsToTry = account.wantsToTry || guest.wantsToTry
        merged.triedAt = [account.triedAt, guest.triedAt].compactMap { $0 }.min()
        merged.firstCollectedAt = [account.firstCollectedAt, guest.firstCollectedAt].compactMap { $0 }.min()
        if merged.note == nil {
            merged.note = guest.note
        } else if let note = guest.note, note != merged.note {
            merged.preservedNotes.append(note)
        }
        merged.preservedNotes += guest.preservedNotes
        if !merged.aliasClientIDs.contains(guest.clientID) { merged.aliasClientIDs.append(guest.clientID) }
        return merged
    }

    /// The guest entries that may be offered for import: active and not from the demo catalog.
    public static func importable(_ guestEntries: [CollectionEntry]) -> [CollectionEntry] {
        guestEntries.filter { $0.isActive && !$0.lotID.isSample }
    }
}

/// Local progress of one import. Only confirmed records are deleted locally; an interrupted batch
/// resumes with the unconfirmed ones under the same batch ID.
public struct GuestImportBatch: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case inProgress, completed, declined }

    public let batchID: ClientID
    public let guestID: OwnerID
    public private(set) var pending: [ClientID]
    public private(set) var confirmed: [ClientID]
    public private(set) var state: State

    public init(batchID: ClientID = ClientID(), guestID: OwnerID, entries: [CollectionEntry]) {
        self.batchID = batchID
        self.guestID = guestID
        pending = GuestImportRules.importable(entries).map(\.clientID).sorted()
        confirmed = []
        state = .inProgress
    }

    /// Records server confirmations; repeating a confirmation changes nothing.
    public mutating func confirm(_ ids: [ClientID]) {
        guard state == .inProgress else { return }
        for id in ids where pending.contains(id) {
            pending.removeAll { $0 == id }
            confirmed.append(id)
        }
        if pending.isEmpty { state = .completed }
    }

    public mutating func decline() {
        guard state == .inProgress, confirmed.isEmpty else { return }
        state = .declined
    }
}

/// Who the device shows. After a completed import the guest starts over empty; after a declined one
/// the original guest returns on sign-out. Account data cached on the device is cleared on sign-out.
public struct LocalSession: Codable, Equatable, Sendable {
    public private(set) var activeOwner: OwnerID
    /// A declined guest set aside while an account is signed in.
    public private(set) var parkedGuest: OwnerID?

    public init(guest: OwnerID = .newGuest()) { activeOwner = guest }

    public var isGuest: Bool { activeOwner.isGuest }

    public mutating func signIn(account: OwnerID, keepGuestSeparately: Bool) {
        parkedGuest = (keepGuestSeparately && activeOwner.isGuest) ? activeOwner : parkedGuest
        activeOwner = account
    }

    /// Clears cached account records and returns to the parked guest, or to a fresh empty guest.
    public mutating func signOut(clearing book: inout CollectionBook, newGuest: OwnerID = .newGuest()) {
        guard !activeOwner.isGuest else { return }
        book.removeAll(owner: activeOwner)
        activeOwner = parkedGuest ?? newGuest
        parkedGuest = nil
    }

    /// Finishes a completed batch: removes the confirmed local copies and the old guest's history.
    public mutating func finishImport(_ batch: GuestImportBatch, book: inout CollectionBook) {
        guard batch.state == .completed else { return }
        book.removeEntries(Set(batch.confirmed))
        book.removeAll(owner: batch.guestID)
        if parkedGuest == batch.guestID { parkedGuest = nil }
    }
}
