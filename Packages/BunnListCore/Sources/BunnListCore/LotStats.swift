import Foundation

/// Lot-level statistics shown on the lot page. Rating stats come only from rating votes; experience
/// stars never enter them, and brew-method participation counts distinct people, not experiences.
public struct LotRatingStats: Equatable, Sendable {
    /// nil when there are no published votes (different from an average of zero).
    public let average: Double?
    public let count: Int
}

public enum LotStats {
    /// Average and voter count for a lot from rating votes only.
    public static func rating(for lot: LotID, votes: [RatingVote]) -> LotRatingStats {
        let forLot = votes.filter { $0.lotID == lot }
        guard !forLot.isEmpty else { return LotRatingStats(average: nil, count: 0) }
        let sum = forLot.reduce(0) { $0 + $1.stars }
        return LotRatingStats(average: Double(sum) / Double(forLot.count), count: forLot.count)
    }

    /// Distinct participating owners per brew method, over published experiences of a lot. These are
    /// per-method participation counts and intentionally do not sum to the total number of people.
    public static func brewMethodParticipants(for lot: LotID, in book: ExperienceBook) -> [String: Int] {
        var byMethod: [String: Set<OwnerID>] = [:]
        for experience in book.published(lot: lot) {
            byMethod[experience.methodCode, default: []].insert(experience.ownerID)
        }
        return byMethod.mapValues(\.count)
    }
}
