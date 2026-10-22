import Foundation

/// A published vote as seen by the ranking. Eligibility flags come from the catalog and moderation.
public struct RankingVote: Equatable, Sendable {
    public let lotID: LotID
    public let stars: Int
    public let lotIsApproved: Bool
    public let lotSeasonIsKnown: Bool
    public let isPublishedAndVisible: Bool

    public init(lotID: LotID, stars: Int, lotIsApproved: Bool, lotSeasonIsKnown: Bool, isPublishedAndVisible: Bool) {
        self.lotID = lotID
        self.stars = stars
        self.lotIsApproved = lotIsApproved
        self.lotSeasonIsKnown = lotSeasonIsKnown
        self.isPublishedAndVisible = isPublishedAndVisible
    }

    var isEligible: Bool { lotIsApproved && lotSeasonIsKnown && isPublishedAndVisible }
}

public struct RankedLot: Equatable, Sendable {
    public let lotID: LotID
    /// Raw average and count are what the UI shows; `score` only orders the list.
    public let rawAverage: Double
    public let voterCount: Int
    public let score: Double
}

/// ranking-v1: S = (v×R + m×C) / (v + m), m = 20. C is the vote-weighted mean of every eligible vote
/// (approved, known season, published, visible) even on lots below the display threshold; UNKNOWN,
/// pending and hidden votes never enter C or the list.
public enum RankingV1 {
    public static let version = "ranking-v1"
    public static let priorWeight = 20.0
    public static let minimumVoters = 5
    public static let fallbackMean = 3.0

    public static func globalMean(_ votes: [RankingVote]) -> Double {
        let eligible = votes.filter(\.isEligible)
        guard !eligible.isEmpty else { return fallbackMean }
        return Double(eligible.map(\.stars).reduce(0, +)) / Double(eligible.count)
    }

    public static func rank(_ votes: [RankingVote]) -> [RankedLot] {
        let mean = globalMean(votes)
        let byLot = Dictionary(grouping: votes.filter(\.isEligible), by: \.lotID)
        return byLot.compactMap { lotID, lotVotes -> RankedLot? in
            guard lotVotes.count >= minimumVoters else { return nil }
            let v = Double(lotVotes.count)
            let r = Double(lotVotes.map(\.stars).reduce(0, +)) / v
            return RankedLot(lotID: lotID, rawAverage: r, voterCount: lotVotes.count,
                             score: score(average: r, voters: v, globalMean: mean))
        }
        .sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.voterCount != b.voterCount { return a.voterCount > b.voterCount }
            return a.lotID < b.lotID
        }
    }

    public static func score(average: Double, voters: Double, globalMean: Double) -> Double {
        (voters * average + priorWeight * globalMean) / (voters + priorWeight)
    }
}
