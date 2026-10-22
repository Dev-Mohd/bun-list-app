import Foundation

/// A brew experience: one attempt at preparing a lot. Multiple per lot are allowed. Its own `stars`
/// rate that attempt and never feed the lot's rating average (that comes only from `RatingVote`).
public struct BrewExperience: Codable, Hashable, Identifiable, Sendable {
    public let clientID: ClientID
    public let ownerID: OwnerID
    public let lotID: LotID
    public var methodCode: String
    public var stars: Int
    public var brewedAt: Date
    public var note: String
    public var photoRef: String?
    public var lifecycle: ContentState
    public let createdAt: Date
    public var updatedAt: Date

    public var id: ClientID { clientID }
}

public enum ExperienceError: Error, Equatable, Sendable {
    case invalidStars(Int)
    case unknownMethod(String)
    case notFound
    case notOwner
}

/// Owner-scoped store of brew experiences. Lifecycle transitions reuse `ContentState` (draft →
/// published → unpublished, deleted final), and only the owner may change or delete their own.
public struct ExperienceBook: Codable, Equatable, Sendable {
    public private(set) var experiences: [BrewExperience] = []

    public init() {}

    @discardableResult
    public mutating func add(owner: OwnerID, lot: LotID, methodCode: String, stars: Int, brewedAt: Date,
                             note: String = "", photoRef: String? = nil, clientID: ClientID = ClientID(),
                             now: Date, publish: Bool = false) throws -> ClientID {
        guard (1...5).contains(stars) else { throw ExperienceError.invalidStars(stars) }
        guard ReferenceCodes.brewMethod(methodCode) != nil else { throw ExperienceError.unknownMethod(methodCode) }
        var lifecycle = ContentState(kind: .experience)
        if publish { try lifecycle.transition(to: .published, expectedRevision: lifecycle.revision, requestKey: ClientID()) }
        experiences.append(BrewExperience(clientID: clientID, ownerID: owner, lotID: lot, methodCode: methodCode,
                                          stars: stars, brewedAt: brewedAt, note: note, photoRef: photoRef,
                                          lifecycle: lifecycle, createdAt: now, updatedAt: now))
        return clientID
    }

    public func experience(_ id: ClientID, owner: OwnerID) -> BrewExperience? {
        experiences.first { $0.clientID == id && $0.ownerID == owner }
    }

    public func all(owner: OwnerID) -> [BrewExperience] {
        experiences.filter { $0.ownerID == owner && $0.lifecycle.lifecycle != .deleted }
            .sorted { ($0.brewedAt, $0.clientID) > ($1.brewedAt, $1.clientID) }
    }

    /// Publicly visible experiences for a lot (any owner), newest brew first.
    public func published(owner: OwnerID? = nil, lot: LotID) -> [BrewExperience] {
        experiences.filter { $0.lotID == lot && $0.lifecycle.isPubliclyVisible && (owner == nil || $0.ownerID == owner) }
            .sorted { ($0.brewedAt, $0.clientID) > ($1.brewedAt, $1.clientID) }
    }

    public mutating func setLifecycle(_ id: ClientID, owner: OwnerID, to target: ContentLifecycle,
                                      requestKey: ClientID = ClientID(), now: Date) throws {
        try mutate(id, owner: owner, now: now) {
            try $0.lifecycle.transition(to: target, expectedRevision: $0.lifecycle.revision, requestKey: requestKey)
        }
    }

    public mutating func setNote(_ id: ClientID, owner: OwnerID, note: String, now: Date) throws {
        try mutate(id, owner: owner, now: now) { $0.note = note }
    }

    public mutating func setStars(_ id: ClientID, owner: OwnerID, stars: Int, now: Date) throws {
        guard (1...5).contains(stars) else { throw ExperienceError.invalidStars(stars) }
        try mutate(id, owner: owner, now: now) { $0.stars = stars }
    }

    private mutating func mutate(_ id: ClientID, owner: OwnerID, now: Date, _ change: (inout BrewExperience) throws -> Void) throws {
        guard let index = experiences.firstIndex(where: { $0.clientID == id }) else { throw ExperienceError.notFound }
        guard experiences[index].ownerID == owner else { throw ExperienceError.notOwner }
        try change(&experiences[index])
        experiences[index].updatedAt = now
    }
}
