import Foundation

public enum BrewTemperature: String, Codable, Hashable, Sendable { case hot, iced }

public enum RecipeStepKind: String, Codable, Hashable, Sendable {
    case bloom, pour, wait, swirl, stir, press, serve
    /// Only bloom and pour add water; the others do not.
    public var addsWater: Bool { self == .bloom || self == .pour }
}

public struct RecipeStep: Codable, Hashable, Sendable {
    public var kind: RecipeStepKind
    /// Water added at this step, in grams. Only meaningful for bloom/pour.
    public var addedWaterGrams: NormalizedDecimal?
    public var seconds: Int?
    public var note: String

    public init(kind: RecipeStepKind, addedWaterGrams: NormalizedDecimal?, seconds: Int?, note: String) {
        self.kind = kind
        self.addedWaterGrams = addedWaterGrams
        self.seconds = seconds
        self.note = note
    }
}

/// Reference from a copied recipe back to its source and the source's version at copy time.
public struct RecipeReference: Codable, Hashable, Sendable {
    public let clientID: ClientID
    public let version: Int
}

public enum RecipeProblem: Equatable, Hashable, Sendable {
    case missingTitle
    case missingMethod
    case missingHotWater
    case pourSumDoesNotMatchHotWater
    case negativeOrZeroWater
    case missingEspressoDose
    case missingEspressoYield
    case waterOnNonPourStep
    /// Server recipes only: the publish standard needs a grind so anyone can repeat it.
    case missingGrind
    /// Server recipes only: non-espresso recipes need at least one step.
    case missingSteps
}

public struct RecipeValidation: Equatable, Sendable {
    public let problems: [RecipeProblem]
    public var isPublishable: Bool { problems.isEmpty }
}

/// A brew recipe. `lotID` is optional: a recipe with no lot is a general recipe. Water is stored as
/// per-step additions and the cumulative total is derived for display only.
public struct Recipe: Codable, Hashable, Identifiable, Sendable {
    public let clientID: ClientID
    public let ownerID: OwnerID
    public var title: String
    public var methodCode: String
    public var temperature: BrewTemperature
    public var lotID: LotID?
    public var doseGrams: NormalizedDecimal?
    public var hotWaterGrams: NormalizedDecimal?
    public var iceGrams: NormalizedDecimal?
    public var yieldGrams: NormalizedDecimal?
    public var waterTempC: NormalizedDecimal?
    public var grinder: String
    public var grindSetting: String
    public var notes: String
    public var steps: [RecipeStep]
    public var source: RecipeReference?
    public var version: Int
    public var lifecycle: ContentState
    public let createdAt: Date
    public var updatedAt: Date

    public var id: ClientID { clientID }

    private static let matchToleranceGrams = Decimal(1)

    public init(clientID: ClientID = ClientID(), owner: OwnerID, title: String, methodCode: String,
                temperature: BrewTemperature, lotID: LotID?, doseGrams: NormalizedDecimal?, hotWaterGrams: NormalizedDecimal?,
                iceGrams: NormalizedDecimal?, yieldGrams: NormalizedDecimal?, waterTempC: NormalizedDecimal?,
                grinder: String, grindSetting: String, notes: String, steps: [RecipeStep], source: RecipeReference? = nil,
                version: Int = 1, now: Date) {
        self.clientID = clientID
        self.ownerID = owner
        self.title = title
        self.methodCode = methodCode
        self.temperature = temperature
        self.lotID = lotID
        self.doseGrams = doseGrams
        self.hotWaterGrams = hotWaterGrams
        self.iceGrams = iceGrams
        self.yieldGrams = yieldGrams
        self.waterTempC = waterTempC
        self.grinder = grinder
        self.grindSetting = grindSetting
        self.notes = notes
        self.steps = steps
        self.source = source
        self.version = version
        lifecycle = ContentState(kind: .recipe)
        createdAt = now
        updatedAt = now
    }

    public var isEspresso: Bool { methodCode == "ESPRESSO" }

    /// Running water total after each step, for display. Non-water steps repeat the prior total.
    public func cumulativeWaterGrams() -> [NormalizedDecimal] {
        var running = Decimal(0)
        return steps.map { step in
            if step.kind.addsWater, let added = step.addedWaterGrams?.decimal { running += added }
            return NormalizedDecimal(string: canonical(running))
        }
    }

    public func validate() -> RecipeValidation {
        var problems: [RecipeProblem] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append(.missingTitle) }
        if ReferenceCodes.brewMethod(methodCode) == nil { problems.append(.missingMethod) }

        for step in steps where !step.kind.addsWater && step.addedWaterGrams != nil {
            problems.append(.waterOnNonPourStep)
            break
        }
        let pourValues = steps.filter { $0.kind.addsWater }.compactMap { $0.addedWaterGrams?.decimal }
        if pourValues.contains(where: { $0 <= 0 }) { problems.append(.negativeOrZeroWater) }

        if isEspresso {
            if (doseGrams?.decimal ?? 0) <= 0 { problems.append(.missingEspressoDose) }
            if (yieldGrams?.decimal ?? 0) <= 0 { problems.append(.missingEspressoYield) }
            // Espresso does not require pour/hot-water matching.
        } else {
            guard let hot = hotWaterGrams?.decimal, hot > 0 else {
                problems.append(.missingHotWater)
                return RecipeValidation(problems: problems)
            }
            let poured = pourValues.reduce(0, +)
            if abs(poured - hot) > Self.matchToleranceGrams { problems.append(.pourSumDoesNotMatchHotWater) }
        }
        return RecipeValidation(problems: problems)
    }

    /// A fresh draft copy: method and parameters carry over; notes, source photos and identity do not.
    public func makeCopy(by owner: OwnerID, now: Date) -> Recipe {
        var copy = Recipe(owner: owner, title: title, methodCode: methodCode, temperature: temperature, lotID: lotID,
                          doseGrams: doseGrams, hotWaterGrams: hotWaterGrams, iceGrams: iceGrams, yieldGrams: yieldGrams,
                          waterTempC: waterTempC, grinder: grinder, grindSetting: grindSetting, notes: "",
                          steps: steps.map { RecipeStep(kind: $0.kind, addedWaterGrams: $0.addedWaterGrams,
                                                        seconds: $0.seconds, note: $0.note) },
                          source: RecipeReference(clientID: clientID, version: version), version: 1, now: now)
        copy.notes = ""
        return copy
    }

    private func canonical(_ value: Decimal) -> String {
        var v = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &v, 1, .plain)
        let s = NSDecimalNumber(decimal: rounded).stringValue
        return s.contains(".") ? String(s.reversed().drop(while: { $0 == "0" }).drop(while: { $0 == "." }).reversed()) : s
    }
}

public enum RecipeError: Error, Equatable, Sendable {
    case notFound
    case notOwner
    case notPublishable([RecipeProblem])
}

/// Owner-scoped recipe store. Drafts always save (even invalid); publishing enforces validation.
public struct RecipeBook: Codable, Equatable, Sendable {
    public private(set) var recipes: [Recipe] = []

    public init() {}

    @discardableResult
    public mutating func saveDraft(_ recipe: Recipe) -> ClientID {
        if let index = recipes.firstIndex(where: { $0.clientID == recipe.clientID }) {
            recipes[index] = recipe
        } else {
            recipes.append(recipe)
        }
        return recipe.clientID
    }

    public func recipe(_ id: ClientID, owner: OwnerID) -> Recipe? {
        recipes.first { $0.clientID == id && $0.ownerID == owner }
    }

    public func all(owner: OwnerID) -> [Recipe] {
        recipes.filter { $0.ownerID == owner && $0.lifecycle.lifecycle != .deleted }
            .sorted { ($0.updatedAt, $0.clientID) > ($1.updatedAt, $1.clientID) }
    }

    public mutating func publish(_ id: ClientID, owner: OwnerID, requestKey: ClientID = ClientID(), now: Date) throws {
        try mutate(id, owner: owner, now: now, bumpVersion: false) { recipe in
            let validation = recipe.validate()
            guard validation.isPublishable else { throw RecipeError.notPublishable(validation.problems) }
            try recipe.lifecycle.transition(to: .published, expectedRevision: recipe.lifecycle.revision, requestKey: requestKey)
        }
    }

    public mutating func setLifecycle(_ id: ClientID, owner: OwnerID, to target: ContentLifecycle,
                                      requestKey: ClientID = ClientID(), now: Date) throws {
        try mutate(id, owner: owner, now: now, bumpVersion: false) {
            try $0.lifecycle.transition(to: target, expectedRevision: $0.lifecycle.revision, requestKey: requestKey)
        }
    }

    /// Edits bump the recipe's version; previously made copies keep the version they referenced.
    public mutating func update(_ id: ClientID, owner: OwnerID, now: Date, _ change: (inout Recipe) -> Void) throws {
        try mutate(id, owner: owner, now: now, bumpVersion: true) { change(&$0) }
    }

    @discardableResult
    public mutating func copy(_ id: ClientID, by owner: OwnerID, now: Date) throws -> ClientID {
        guard let original = recipes.first(where: { $0.clientID == id }) else { throw RecipeError.notFound }
        let copy = original.makeCopy(by: owner, now: now)
        recipes.append(copy)
        return copy.clientID
    }

    private mutating func mutate(_ id: ClientID, owner: OwnerID, now: Date, bumpVersion: Bool,
                                 _ change: (inout Recipe) throws -> Void) throws {
        guard let index = recipes.firstIndex(where: { $0.clientID == id }) else { throw RecipeError.notFound }
        guard recipes[index].ownerID == owner else { throw RecipeError.notOwner }
        try change(&recipes[index])
        if bumpVersion { recipes[index].version += 1 }
        recipes[index].updatedAt = now
    }
}
