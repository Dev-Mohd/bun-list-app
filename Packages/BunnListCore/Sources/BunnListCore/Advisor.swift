import Foundation

// «ساعدني أختار» (POST /api/v1/advisor): the answers, and the three coffees back.

public struct AdvisorAnswers: Equatable, Sendable {
    public enum Mood: String, CaseIterable, Sendable { case wake, calm, guests, new }
    public enum Method: String, CaseIterable, Sendable { case v60 = "V60", espresso = "ESPRESSO", chemex = "CHEMEX", frenchPress = "FRENCH_PRESS" }
    public enum Serve: String, Sendable { case hot = "HOT", iced = "ICED" }

    public var mood: Mood?
    public var method: Method?
    /// Asked only after espresso.
    public var milk: Bool?
    /// Asked only after «مع حليب»: which drink.
    public var milkDrink: MilkDrink?
    public var families: Set<FlavorFamily> = []
    public var serve: Serve?
    /// 0 = the safe pick … 1 = surprise me.
    public var adventure: Double = 0.5
    public var text = ""

    public init() {}

    /// The steps to ask, in order; milk appears only with espresso.
    public var steps: [AdvisorStep] {
        var s: [AdvisorStep] = [.mood, .method]
        if method == .espresso { s.append(.milk) }
        if method == .espresso, milk == true { s.append(.milkDrink) }
        s += [.flavors, .serve, .adventure, .text]
        return s
    }

    public var isComplete: Bool { mood != nil && method != nil && serve != nil && (method != .espresso || milk != nil) }

    var body: [String: Any] {
        var b: [String: Any] = [
            "mood": mood?.rawValue ?? "calm",
            "method": method?.rawValue ?? "V60",
            "families": FlavorFamily.allCases.filter { families.contains($0) && $0 != .other }.map(\.rawValue),
            "serve": serve?.rawValue ?? "HOT",
            "adventure": (adventure * 100).rounded() / 100,
        ]
        if method == .espresso, let milk { b["milk"] = milk }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { b["text"] = String(t.prefix(300)) }
        return b
    }
}

public enum AdvisorStep: String, Equatable, Sendable { case mood, method, milk, milkDrink, flavors, serve, adventure, text }

extension AdvisorAnswers {
    /// The drinks offered after «مع حليب», smallest to largest.
    public static let milkDrinks: [MilkDrink] = [.cortado, .flatWhite, .cappuccino, .latte]

    /// The BunnList recipe for the chosen drink, to show with the results.
    public var milkPreset: BrewPreset? {
        guard method == .espresso, milk == true, let milkDrink else { return nil }
        return BrewPreset.all.first { $0.milkDrink == milkDrink }
    }
}

public struct RemoteAdvisorPick: Codable, Equatable, Sendable, Identifiable {
    public var id: String { lot.id }
    public let lot: RemoteLot
    public let score: Int
    public let reason: String
    public let tag: String?
}

public struct RemoteAdvisorResult: Codable, Equatable, Sendable {
    public struct Understood: Codable, Equatable, Sendable { public let chips: [String] }
    public let understood: Understood?
    public let picks: [RemoteAdvisorPick]
}

extension CatalogAPIClient {
    public func advise(_ answers: AdvisorAnswers, accessToken: String?) async throws -> RemoteAdvisorResult {
        let data = (try? JSONSerialization.data(withJSONObject: answers.body)) ?? Data()
        let response = try await transport.send(HTTPRequest(method: .post, path: "/api/v1/advisor", body: data, bearer: accessToken))
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteAdvisorResult.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }
}
