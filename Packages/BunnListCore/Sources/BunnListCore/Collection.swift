import Foundation

/// One user's relationship with one lot. Natural identity is (ownerID, lotID); `clientID` is the
/// device-created `localEntryId`. Removing a lot keeps the row (with its history) so re-collecting
/// it is an upsert, not a new first collection.
public struct CollectionEntry: Codable, Hashable, Identifiable, Sendable {
    public let clientID: ClientID
    public let ownerID: OwnerID
    public internal(set) var lotID: LotID
    /// «لديّ»
    public internal(set) var isOwned: Bool
    /// «مفضل»
    public internal(set) var isFavorite: Bool
    /// «ودي أجرب»
    public internal(set) var wantsToTry: Bool
    /// «جربته» — set by an explicit confirmation, an experience or a rating; never cleared by deleting them.
    public internal(set) var triedAt: Date?
    public internal(set) var firstCollectedAt: Date?
    public internal(set) var note: String?
    /// Notes kept separately when two records merge with different notes.
    public internal(set) var preservedNotes: [String]
    /// Client IDs of records merged into this one (kept so retries and server mapping still resolve).
    public internal(set) var aliasClientIDs: [ClientID]
    public let createdAt: Date
    public internal(set) var updatedAt: Date
    public internal(set) var revision: Int

    public var id: ClientID { clientID }
    public var isTried: Bool { triedAt != nil }
    public var isActive: Bool { isOwned || isFavorite || wantsToTry || isTried }

    init(clientID: ClientID, ownerID: OwnerID, lotID: LotID, now: Date) {
        self.clientID = clientID
        self.ownerID = ownerID
        self.lotID = lotID
        isOwned = false
        isFavorite = false
        wantsToTry = false
        triedAt = nil
        firstCollectedAt = nil
        note = nil
        preservedNotes = []
        aliasClientIDs = []
        createdAt = now
        updatedAt = now
        revision = 0
    }
}

/// A user's single vote on a lot (1–5). Experiences never feed this average.
public struct RatingVote: Codable, Hashable, Sendable {
    public let clientID: ClientID
    public let ownerID: OwnerID
    public internal(set) var lotID: LotID
    public internal(set) var stars: Int
    public internal(set) var updatedAt: Date
}

/// Kept permanently, even after the entry is removed, so re-collecting never counts as a first collection.
public struct FirstCollectionEvent: Codable, Hashable, Sendable {
    public let ownerID: OwnerID
    public let lotID: LotID
    public let at: Date
}

/// Answer to «هل هو نفس الكيس الذي سجلته بدون موسم؟».
public enum BagDecision: String, Codable, Sendable {
    case sameBag
    case distinctBag
}

public struct BagConflict: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        /// Owner already has the UNKNOWN lot and now picks a known season.
        case unknownToKnown
        /// Owner already has a known season and now picks the UNKNOWN lot.
        case knownToUnknown
    }

    public let productID: ProductID
    public let requestedLot: LotID
    public let existingLots: [LotID]
    public let direction: Direction
}

/// Links two lots for one owner after a same-bag transfer so neither lot reopens a first-time reward.
public struct RewardAlias: Codable, Hashable, Sendable {
    public let ownerID: OwnerID
    public let source: LotID
    public let target: LotID
}

public struct LotAssignmentEvent: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case sameBagTransfer(from: LotID, to: LotID)
        case keptKnownSeason(requested: LotID, kept: [LotID])
        case distinctBag(requested: LotID, existing: [LotID])
        case seasonAssignment(from: LotID, to: LotID, movedCollection: Bool, movedRating: Bool)
    }

    public let operationID: ClientID
    public let ownerID: OwnerID
    public let kind: Kind
    /// When both lots had a vote, the older one is dropped and recorded here.
    public let replacedRatingClientID: ClientID?
    public let at: Date
}

public enum CollectOutcome: Codable, Hashable, Sendable {
    case collected(firstTime: Bool)
    case alreadyOwned
    case transferredFromUnknown(LotID)
    case keptKnownSeason([LotID])
}

public enum RatingOutcome: Codable, Hashable, Sendable {
    case rated(lot: LotID, firstTime: Bool)
    case transferredFromUnknown(LotID)
}

public enum CollectionError: Error, Equatable, Sendable {
    case unknownLot(LotID)
    case lotNotCollectable(LotID)
    case needsBagDecision(BagConflict)
    case operationPayloadMismatch(ClientID)
    case staleRevision(expected: Int, actual: Int)
    case invalidStars(Int)
    case notSameProduct
    case sourceIsNotUnknownSeason
    case targetIsNotKnownSeason
    case nothingToMove
    case noEntry
}

public struct CollectionBook: Codable, Equatable, Sendable {
    public private(set) var entries: [CollectionEntry] = []
    public private(set) var ratings: [RatingVote] = []
    public private(set) var firstCollectionEvents: [FirstCollectionEvent] = []
    public private(set) var assignmentEvents: [LotAssignmentEvent] = []
    public private(set) var rewardAliases: [RewardAlias] = []
    private var processedOperations: [ProcessedOperation] = []

    public init() {}

    /// Entries and ratings carry no inherent order (the UI sorts them for display), and storage that
    /// splits entries into rows may restore them in a different order. Compare them by content keyed
    /// on clientID so a round-trip through such a store is equal; append-only logs compare in order.
    public static func == (lhs: CollectionBook, rhs: CollectionBook) -> Bool {
        keyed(lhs.entries) == keyed(rhs.entries)
            && keyed(lhs.ratings) == keyed(rhs.ratings)
            && lhs.firstCollectionEvents == rhs.firstCollectionEvents
            && lhs.assignmentEvents == rhs.assignmentEvents
            && lhs.rewardAliases == rhs.rewardAliases
            && lhs.processedOperations == rhs.processedOperations
    }

    private static func keyed(_ entries: [CollectionEntry]) -> [ClientID: CollectionEntry] {
        Dictionary(entries.map { ($0.clientID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func keyed(_ ratings: [RatingVote]) -> [ClientID: RatingVote] {
        Dictionary(ratings.map { ($0.clientID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    struct ProcessedOperation: Codable, Equatable, Sendable {
        let operationID: ClientID
        let fingerprint: String
        let outcome: StoredOutcome
    }

    enum StoredOutcome: Codable, Equatable, Sendable {
        case collect(CollectOutcome)
        case rate(RatingOutcome)
        case assign
    }

    // MARK: Queries

    public func entry(owner: OwnerID, lot: LotID) -> CollectionEntry? {
        entries.first { $0.ownerID == owner && $0.lotID == lot }
    }

    /// Active entries, most recently changed first.
    public func activeEntries(owner: OwnerID) -> [CollectionEntry] {
        entries.filter { $0.ownerID == owner && $0.isActive }
            .sorted { ($0.updatedAt, $0.clientID) > ($1.updatedAt, $1.clientID) }
    }

    public func rating(owner: OwnerID, lot: LotID) -> RatingVote? {
        ratings.first { $0.ownerID == owner && $0.lotID == lot }
    }

    /// True if this lot, or any lot linked to it by a same-bag transfer, was ever collected by the owner.
    public func hasEverCollected(owner: OwnerID, lot: LotID) -> Bool {
        let group = aliasGroup(owner: owner, lot: lot)
        return firstCollectionEvents.contains { $0.ownerID == owner && group.contains($0.lotID) }
    }

    /// Conflict that requires a same-bag answer before collecting or rating `lot`.
    public func bagConflict(owner: OwnerID, lot lotID: LotID, catalog: Catalog) -> BagConflict? {
        guard let lot = catalog.lot(lotID) else { return nil }
        let siblings = catalog.lots(of: lot.productID).filter { $0.id != lot.id }
        let opposing = siblings.filter { $0.season.isUnknown != lot.season.isUnknown }.map(\.id)
        let held = opposing.filter { id in entry(owner: owner, lot: id)?.isOwned == true || rating(owner: owner, lot: id) != nil }
        guard !held.isEmpty else { return nil }
        return BagConflict(productID: lot.productID, requestedLot: lot.id, existingLots: held.sorted(),
                           direction: lot.season.isUnknown ? .knownToUnknown : .unknownToKnown)
    }

    // MARK: Collect

    /// Adds `lotID` to «لديّ». Retrying the same `operationID` returns the stored outcome; reusing it
    /// for a different request is rejected. When the owner already holds the opposing UNKNOWN/known
    /// lot of the same product, a `decision` is required.
    public mutating func collect(_ lotID: LotID, owner: OwnerID, catalog: Catalog, decision: BagDecision? = nil,
                                 operationID: ClientID, newEntryID: ClientID = ClientID(), now: Date) throws -> CollectOutcome {
        let fingerprint = "collect|\(owner)|\(lotID)|\(decision?.rawValue ?? "-")"
        if case let .collect(outcome)? = try replay(operationID, fingerprint: fingerprint) { return outcome }
        guard let lot = catalog.lot(lotID) else { throw CollectionError.unknownLot(lotID) }
        guard lot.approval != .rejected else { throw CollectionError.lotNotCollectable(lotID) }

        let outcome: CollectOutcome
        if entry(owner: owner, lot: lotID)?.isOwned == true {
            outcome = .alreadyOwned
        } else if let conflict = bagConflict(owner: owner, lot: lotID, catalog: catalog) {
            guard let decision else { throw CollectionError.needsBagDecision(conflict) }
            switch (conflict.direction, decision) {
            case (.unknownToKnown, .sameBag):
                let source = conflict.existingLots[0]
                let replaced = try moveRecords(owner: owner, from: source, to: lotID, moveCollection: true,
                                               moveRating: true, now: now)
                setOwned(owner: owner, lot: lotID, newEntryID: newEntryID, now: now)
                record(.sameBagTransfer(from: source, to: lotID), owner: owner, operationID: operationID,
                       replaced: replaced, now: now)
                outcome = .transferredFromUnknown(source)
            case (.knownToUnknown, .sameBag):
                record(.keptKnownSeason(requested: lotID, kept: conflict.existingLots), owner: owner,
                       operationID: operationID, replaced: nil, now: now)
                outcome = .keptKnownSeason(conflict.existingLots)
            case (_, .distinctBag):
                record(.distinctBag(requested: lotID, existing: conflict.existingLots), owner: owner,
                       operationID: operationID, replaced: nil, now: now)
                outcome = .collected(firstTime: setOwned(owner: owner, lot: lotID, newEntryID: newEntryID, now: now))
            }
        } else {
            outcome = .collected(firstTime: setOwned(owner: owner, lot: lotID, newEntryID: newEntryID, now: now))
        }
        processedOperations.append(.init(operationID: operationID, fingerprint: fingerprint, outcome: .collect(outcome)))
        return outcome
    }

    /// Removes the lot from «لديّ». Other states and the first-collection history stay.
    public mutating func removeFromOwned(_ lotID: LotID, owner: OwnerID, expectedRevision: Int? = nil, now: Date) throws {
        try update(owner: owner, lot: lotID, expectedRevision: expectedRevision, now: now) { $0.isOwned = false }
    }

    public mutating func setFavorite(_ value: Bool, lot: LotID, owner: OwnerID, catalog: Catalog,
                                     expectedRevision: Int? = nil, now: Date) throws {
        try upsertFlag(lot: lot, owner: owner, catalog: catalog, expectedRevision: expectedRevision, now: now) {
            $0.isFavorite = value
        }
    }

    public mutating func setWantsToTry(_ value: Bool, lot: LotID, owner: OwnerID, catalog: Catalog,
                                       expectedRevision: Int? = nil, now: Date) throws {
        try upsertFlag(lot: lot, owner: owner, catalog: catalog, expectedRevision: expectedRevision, now: now) {
            $0.wantsToTry = value
        }
    }

    /// Explicit «جربته» confirmation. Turning it off only clears an explicit mark made in error.
    public mutating func setTried(_ value: Bool, lot: LotID, owner: OwnerID, catalog: Catalog,
                                  expectedRevision: Int? = nil, now: Date) throws {
        try upsertFlag(lot: lot, owner: owner, catalog: catalog, expectedRevision: expectedRevision, now: now) {
            $0.triedAt = value ? ($0.triedAt ?? now) : nil
        }
    }

    public mutating func setNote(_ note: String?, lot: LotID, owner: OwnerID, expectedRevision: Int? = nil, now: Date) throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try update(owner: owner, lot: lot, expectedRevision: expectedRevision, now: now) {
            $0.note = trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    // MARK: Rating (contract used by season transfer; rating UI arrives in C02)

    /// One vote per owner and lot. Rating marks the lot as tried but never as owned.
    public mutating func rate(_ lotID: LotID, stars: Int, owner: OwnerID, catalog: Catalog, decision: BagDecision? = nil,
                              operationID: ClientID, newVoteID: ClientID = ClientID(), now: Date) throws -> RatingOutcome {
        let fingerprint = "rate|\(owner)|\(lotID)|\(stars)|\(decision?.rawValue ?? "-")"
        if case let .rate(outcome)? = try replay(operationID, fingerprint: fingerprint) { return outcome }
        guard (1...5).contains(stars) else { throw CollectionError.invalidStars(stars) }
        guard catalog.lot(lotID) != nil else { throw CollectionError.unknownLot(lotID) }

        var target = lotID
        var outcome: RatingOutcome?
        if rating(owner: owner, lot: lotID) == nil, let conflict = bagConflict(owner: owner, lot: lotID, catalog: catalog) {
            guard let decision else { throw CollectionError.needsBagDecision(conflict) }
            switch (conflict.direction, decision) {
            case (.unknownToKnown, .sameBag):
                let source = conflict.existingLots[0]
                let replaced = try moveRecords(owner: owner, from: source, to: lotID, moveCollection: true,
                                               moveRating: true, now: now)
                record(.sameBagTransfer(from: source, to: lotID), owner: owner, operationID: operationID,
                       replaced: replaced, now: now)
                outcome = .transferredFromUnknown(source)
            case (.knownToUnknown, .sameBag):
                // Same bag: the vote belongs to the known season the owner already has.
                target = conflict.existingLots[0]
                record(.keptKnownSeason(requested: lotID, kept: conflict.existingLots), owner: owner,
                       operationID: operationID, replaced: nil, now: now)
            case (_, .distinctBag):
                record(.distinctBag(requested: lotID, existing: conflict.existingLots), owner: owner,
                       operationID: operationID, replaced: nil, now: now)
            }
        }

        let firstTime: Bool
        if let index = ratings.firstIndex(where: { $0.ownerID == owner && $0.lotID == target }) {
            ratings[index].stars = stars
            ratings[index].updatedAt = now
            firstTime = false
        } else {
            ratings.append(RatingVote(clientID: newVoteID, ownerID: owner, lotID: target, stars: stars, updatedAt: now))
            firstTime = true
        }
        try upsertFlag(lot: target, owner: owner, catalog: catalog, expectedRevision: nil, now: now) {
            $0.triedAt = $0.triedAt ?? now
        }
        let result = outcome ?? .rated(lot: target, firstTime: firstTime)
        processedOperations.append(.init(operationID: operationID, fingerprint: fingerprint, outcome: .rate(result)))
        return result
    }

    // MARK: «تحديد موسم سجلي»

    /// Moves the owner's own records from a product's UNKNOWN lot to one of its known seasons. Other
    /// users' records are untouched. No new first collection, vote or streak day results from it.
    public mutating func assignSeason(owner: OwnerID, from source: LotID, to target: LotID, moveCollection: Bool,
                                      moveRating: Bool, catalog: Catalog, operationID: ClientID, now: Date) throws {
        let fingerprint = "assign|\(owner)|\(source)|\(target)|\(moveCollection)|\(moveRating)"
        if try replay(operationID, fingerprint: fingerprint) != nil { return }
        guard let sourceLot = catalog.lot(source) else { throw CollectionError.unknownLot(source) }
        guard let targetLot = catalog.lot(target) else { throw CollectionError.unknownLot(target) }
        guard sourceLot.productID == targetLot.productID else { throw CollectionError.notSameProduct }
        guard sourceLot.season.isUnknown else { throw CollectionError.sourceIsNotUnknownSeason }
        guard !targetLot.season.isUnknown else { throw CollectionError.targetIsNotKnownSeason }
        let hasCollection = moveCollection && entry(owner: owner, lot: source)?.isActive == true
        let hasRating = moveRating && rating(owner: owner, lot: source) != nil
        guard hasCollection || hasRating else { throw CollectionError.nothingToMove }

        let replaced = try moveRecords(owner: owner, from: source, to: target, moveCollection: hasCollection,
                                       moveRating: hasRating, now: now)
        record(.seasonAssignment(from: source, to: target, movedCollection: hasCollection, movedRating: hasRating),
               owner: owner, operationID: operationID, replaced: replaced, now: now)
        processedOperations.append(.init(operationID: operationID, fingerprint: fingerprint, outcome: .assign))
    }

    // MARK: Guest session

    /// Removes the given records after a confirmed import (C04); history of other owners is untouched.
    public mutating func removeEntries(_ clientIDs: Set<ClientID>) {
        entries.removeAll { clientIDs.contains($0.clientID) }
    }

    /// Drops everything belonging to `owner` (used on sign-out for cached account data).
    public mutating func removeAll(owner: OwnerID) {
        entries.removeAll { $0.ownerID == owner }
        ratings.removeAll { $0.ownerID == owner }
        firstCollectionEvents.removeAll { $0.ownerID == owner }
        assignmentEvents.removeAll { $0.ownerID == owner }
        rewardAliases.removeAll { $0.ownerID == owner }
    }

    // MARK: Internals

    private func replay(_ operationID: ClientID, fingerprint: String) throws -> StoredOutcome? {
        guard let previous = processedOperations.first(where: { $0.operationID == operationID }) else { return nil }
        guard previous.fingerprint == fingerprint else { throw CollectionError.operationPayloadMismatch(operationID) }
        return previous.outcome
    }

    private func aliasGroup(owner: OwnerID, lot: LotID) -> Set<LotID> {
        var group: Set<LotID> = [lot]
        var changed = true
        while changed {
            changed = false
            for alias in rewardAliases where alias.ownerID == owner {
                if group.contains(alias.source) != group.contains(alias.target) {
                    group.formUnion([alias.source, alias.target])
                    changed = true
                }
            }
        }
        return group
    }

    /// Returns whether this was the owner's first collection of the lot (or its alias group).
    @discardableResult
    private mutating func setOwned(owner: OwnerID, lot: LotID, newEntryID: ClientID, now: Date) -> Bool {
        let firstTime = !hasEverCollected(owner: owner, lot: lot)
        if entry(owner: owner, lot: lot) == nil {
            entries.append(CollectionEntry(clientID: newEntryID, ownerID: owner, lotID: lot, now: now))
        }
        let index = entries.firstIndex { $0.ownerID == owner && $0.lotID == lot }!
        entries[index].isOwned = true
        if entries[index].firstCollectedAt == nil { entries[index].firstCollectedAt = now }
        entries[index].updatedAt = now
        entries[index].revision += 1
        if firstTime { firstCollectionEvents.append(FirstCollectionEvent(ownerID: owner, lotID: lot, at: now)) }
        return firstTime
    }

    private mutating func update(owner: OwnerID, lot: LotID, expectedRevision: Int?, now: Date,
                                 _ change: (inout CollectionEntry) -> Void) throws {
        guard let index = entries.firstIndex(where: { $0.ownerID == owner && $0.lotID == lot }) else {
            throw CollectionError.noEntry
        }
        if let expectedRevision, expectedRevision != entries[index].revision {
            throw CollectionError.staleRevision(expected: expectedRevision, actual: entries[index].revision)
        }
        let before = entries[index]
        change(&entries[index])
        if entries[index] != before {
            entries[index].updatedAt = now
            entries[index].revision += 1
        }
    }

    private mutating func upsertFlag(lot: LotID, owner: OwnerID, catalog: Catalog, expectedRevision: Int?, now: Date,
                                     _ change: (inout CollectionEntry) -> Void) throws {
        guard catalog.lot(lot) != nil else { throw CollectionError.unknownLot(lot) }
        if entry(owner: owner, lot: lot) == nil {
            if let expectedRevision, expectedRevision != 0 {
                throw CollectionError.staleRevision(expected: expectedRevision, actual: 0)
            }
            entries.append(CollectionEntry(clientID: ClientID(), ownerID: owner, lotID: lot, now: now))
        }
        try update(owner: owner, lot: lot, expectedRevision: expectedRevision, now: now, change)
    }

    /// Moves or merges records from `source` to `target` for one owner. Returns the vote dropped
    /// when both lots had one (the most recently updated vote is kept).
    private mutating func moveRecords(owner: OwnerID, from source: LotID, to target: LotID, moveCollection: Bool,
                                      moveRating: Bool, now: Date) throws -> ClientID? {
        if moveCollection, let sourceIndex = entries.firstIndex(where: { $0.ownerID == owner && $0.lotID == source }) {
            let moving = entries[sourceIndex]
            if let targetIndex = entries.firstIndex(where: { $0.ownerID == owner && $0.lotID == target }) {
                var merged = entries[targetIndex]
                merged.isOwned = merged.isOwned || moving.isOwned
                merged.isFavorite = merged.isFavorite || moving.isFavorite
                merged.wantsToTry = merged.wantsToTry || moving.wantsToTry
                merged.triedAt = [merged.triedAt, moving.triedAt].compactMap { $0 }.min()
                merged.firstCollectedAt = [merged.firstCollectedAt, moving.firstCollectedAt].compactMap { $0 }.min()
                if merged.note == nil {
                    merged.note = moving.note
                } else if let note = moving.note, note != merged.note {
                    merged.preservedNotes.append(note)
                }
                merged.preservedNotes += moving.preservedNotes
                merged.aliasClientIDs += [moving.clientID] + moving.aliasClientIDs
                merged.updatedAt = now
                merged.revision += 1
                entries[targetIndex] = merged
                entries.remove(at: sourceIndex)
            } else {
                entries[sourceIndex].lotID = target
                entries[sourceIndex].updatedAt = now
                entries[sourceIndex].revision += 1
            }
        }

        var replaced: ClientID?
        if moveRating, let sourceIndex = ratings.firstIndex(where: { $0.ownerID == owner && $0.lotID == source }) {
            if let targetIndex = ratings.firstIndex(where: { $0.ownerID == owner && $0.lotID == target }) {
                if ratings[sourceIndex].updatedAt > ratings[targetIndex].updatedAt {
                    replaced = ratings[targetIndex].clientID
                    ratings[sourceIndex].lotID = target
                    ratings.remove(at: targetIndex)
                } else {
                    replaced = ratings[sourceIndex].clientID
                    ratings.remove(at: sourceIndex)
                }
            } else {
                ratings[sourceIndex].lotID = target
            }
        }

        if !rewardAliases.contains(RewardAlias(ownerID: owner, source: source, target: target)) {
            rewardAliases.append(RewardAlias(ownerID: owner, source: source, target: target))
        }
        return replaced
    }

    private mutating func record(_ kind: LotAssignmentEvent.Kind, owner: OwnerID, operationID: ClientID,
                                 replaced: ClientID?, now: Date) {
        assignmentEvents.append(LotAssignmentEvent(operationID: operationID, ownerID: owner, kind: kind,
                                                   replacedRatingClientID: replaced, at: now))
    }
}

extension CollectionBook {
    /// Persistence seam: stores keep entries as their own rows and the rest of the book as one record.
    public func splitForStorage() -> (book: CollectionBook, entries: [CollectionEntry]) {
        var header = self
        header.entries = []
        return (header, entries)
    }

    /// Rebuilds a book saved with `splitForStorage()`.
    public mutating func restoreEntries(_ stored: [CollectionEntry]) {
        entries = stored.sorted { ($0.createdAt, $0.clientID) < ($1.createdAt, $1.clientID) }
    }
}
