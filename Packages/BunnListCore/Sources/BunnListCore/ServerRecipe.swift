import Foundation

// Recipes synced with /api/v1/recipes. `RecipeDraft` is what the editor edits: it
// derives the ratio, cumulative water and total time for display, keeps pours in
// step with the hot water, and validates with the same rules as `Recipe.validate()`
// (which the server enforces again on publish).

public struct RemoteRecipeStep: Codable, Equatable, Hashable, Sendable {
    public var kind: RecipeStepKind
    public var addedWaterGrams: Double?
    public var seconds: Int?
    public var note: String

    public init(kind: RecipeStepKind, addedWaterGrams: Double? = nil, seconds: Int? = nil, note: String = "") {
        self.kind = kind; self.addedWaterGrams = addedWaterGrams; self.seconds = seconds; self.note = note
    }
}

public struct RemoteRecipeLot: Codable, Equatable, Hashable, Sendable {
    public let slug: String
    public let nameAr: String
    public let roasterNameAr: String

    public init(slug: String, nameAr: String, roasterNameAr: String) {
        self.slug = slug; self.nameAr = nameAr; self.roasterNameAr = roasterNameAr
    }
}

public struct RemoteRecipe: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let clientId: String
    public let title: String
    public let methodCode: String
    public let temperature: BrewTemperature
    public let lot: RemoteRecipeLot?
    public let doseGrams: Double?
    public let hotWaterGrams: Double?
    public let iceGrams: Double?
    public let yieldGrams: Double?
    public let waterTempC: Double?
    public let grinder: String
    public let grindSetting: String
    public let notes: String
    public let steps: [RemoteRecipeStep]
    public let sourceId: String?
    public let version: Int
    public let state: RemoteExperience.State
    public let authorName: String
    public let isMine: Bool
}

public struct RecipeDraft: Equatable, Sendable {
    public var clientID: String
    public var title: String
    public var methodCode: String
    public var temperature: BrewTemperature
    public var lot: RemoteRecipeLot?
    public var doseGrams: Double?
    public var hotWaterGrams: Double?
    public var iceGrams: Double?
    public var yieldGrams: Double?
    public var waterTempC: Double?
    public var grinder: String
    public var grindSetting: String
    public var notes: String
    public var steps: [RemoteRecipeStep]
    /// Set when this draft copies someone's published recipe.
    public var sourceID: String?
    /// The server state when editing an existing recipe; nil for a new one.
    public var existingState: RemoteExperience.State?

    public static let defaultRatio = 16.7
    public static let ratioRange: ClosedRange<Double> = 10...20

    /// A new pour-over: 15 g, 96 °C, 1:16.7 → 250 g, bloom + two pours.
    public init(clientID: String = UUID().uuidString, lot: RemoteRecipeLot? = nil) {
        self.clientID = clientID
        title = ""
        methodCode = "V60"
        temperature = .hot
        self.lot = lot
        doseGrams = 15
        hotWaterGrams = 250
        iceGrams = nil
        yieldGrams = nil
        waterTempC = 96
        grinder = ""
        grindSetting = ""
        notes = ""
        steps = Self.pourOverSteps(total: 250)
    }

    public init(editing recipe: RemoteRecipe) {
        clientID = recipe.clientId
        title = recipe.title
        methodCode = recipe.methodCode
        temperature = recipe.temperature
        lot = recipe.lot
        doseGrams = recipe.doseGrams
        hotWaterGrams = recipe.hotWaterGrams
        iceGrams = recipe.iceGrams
        yieldGrams = recipe.yieldGrams
        waterTempC = recipe.waterTempC
        grinder = recipe.grinder
        grindSetting = recipe.grindSetting
        notes = recipe.notes
        steps = recipe.steps
        sourceID = recipe.sourceId
        existingState = recipe.state
    }

    /// A fresh draft of someone's recipe: parameters carry over; notes and identity do not.
    public init(copying recipe: RemoteRecipe) {
        self.init(editing: recipe)
        clientID = UUID().uuidString
        notes = ""
        sourceID = recipe.id
        existingState = nil
    }

    public static func pourOverSteps(total: Double) -> [RemoteRecipeStep] {
        let bloom = (total / 5).rounded()
        let first = ((total - bloom) / 2).rounded()
        return [
            RemoteRecipeStep(kind: .bloom, addedWaterGrams: bloom, seconds: 45, note: "صب برفق لترطيب البن ثم اتركه يتنفس."),
            RemoteRecipeStep(kind: .pour, addedWaterGrams: first, seconds: 40, note: "صب بثبات حتى الوزن المستهدف."),
            RemoteRecipeStep(kind: .pour, addedWaterGrams: total - bloom - first, seconds: 40,
                             note: "صب حتى الوزن النهائي ثم اترك الماء ينزل."),
        ]
    }

    public var isEspresso: Bool { methodCode == "ESPRESSO" }

    /// Water per gram of coffee (espresso: yield per gram).
    public var ratio: Double? {
        guard let dose = doseGrams, dose > 0 else { return nil }
        let water = isEspresso ? yieldGrams : hotWaterGrams.map { $0 + (iceGrams ?? 0) }
        guard let water, water > 0 else { return nil }
        return water / dose
    }

    /// Final beverage weight shown on the card.
    public var outputGrams: Double? {
        isEspresso ? yieldGrams : hotWaterGrams.map { $0 + (temperature == .iced ? iceGrams ?? 0 : 0) }
    }

    public var totalSeconds: Int { steps.compactMap(\.seconds).reduce(0, +) }

    /// Running water total after each step.
    public var cumulativeWater: [Double] {
        var running = 0.0
        return steps.map { step in
            if step.kind.addsWater, let added = step.addedWaterGrams { running += added }
            return running
        }
    }

    /// Sets the ratio from the dose (pour-over: hot water, espresso: yield) and rescales pours.
    public mutating func applyRatio(_ ratio: Double) {
        guard let dose = doseGrams, dose > 0 else { return }
        let total = (dose * ratio).rounded()
        if isEspresso {
            yieldGrams = total
        } else {
            setHotWater(total - (temperature == .iced ? iceGrams ?? 0 : 0))
        }
    }

    /// Changes the hot water and scales the water steps so they still add up to it.
    /// The last pour absorbs rounding.
    public mutating func setHotWater(_ newTotal: Double) {
        let newTotal = max(newTotal, 0)
        let indices = steps.indices.filter { steps[$0].kind.addsWater && steps[$0].addedWaterGrams != nil }
        let oldTotal = indices.compactMap { steps[$0].addedWaterGrams }.reduce(0, +)
        hotWaterGrams = newTotal
        guard let last = indices.last, oldTotal > 0 else { return }
        var assigned = 0.0
        for index in indices where index != last {
            let scaled = ((steps[index].addedWaterGrams ?? 0) * newTotal / oldTotal).rounded()
            steps[index].addedWaterGrams = scaled
            assigned += scaled
        }
        steps[last].addedWaterGrams = newTotal - assigned
    }

    public func problems() -> [RecipeProblem] {
        var problems: [RecipeProblem] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append(.missingTitle) }
        if ReferenceCodes.brewMethod(methodCode) == nil { problems.append(.missingMethod) }
        if steps.contains(where: { !$0.kind.addsWater && $0.addedWaterGrams != nil }) { problems.append(.waterOnNonPourStep) }
        let pours = steps.filter(\.kind.addsWater).compactMap(\.addedWaterGrams)
        if pours.contains(where: { $0 <= 0 }) { problems.append(.negativeOrZeroWater) }
        if isEspresso {
            if (doseGrams ?? 0) <= 0 { problems.append(.missingEspressoDose) }
            if (yieldGrams ?? 0) <= 0 { problems.append(.missingEspressoYield) }
        } else {
            guard let hot = hotWaterGrams, hot > 0 else {
                problems.append(.missingHotWater)
                return problems
            }
            if abs(pours.reduce(0, +) - hot) > 1 { problems.append(.pourSumDoesNotMatchHotWater) }
        }
        return problems
    }

    /// JSON body for POST /api/v1/recipes.
    func payload(publish: Bool) -> [String: Any] {
        func num(_ v: Double?) -> Any { v.map { $0 as Any } ?? NSNull() }
        var body: [String: Any] = [
            "clientId": clientID,
            "lotSlug": lot.map { $0.slug as Any } ?? NSNull(),
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "methodCode": methodCode,
            "temperature": temperature.rawValue,
            "doseGrams": num(doseGrams),
            "hotWaterGrams": num(isEspresso ? nil : hotWaterGrams),
            "iceGrams": num(temperature == .iced ? iceGrams : nil),
            "yieldGrams": num(isEspresso ? yieldGrams : nil),
            "waterTempC": num(waterTempC),
            "grinder": grinder,
            "grindSetting": grindSetting,
            "notes": notes,
            "steps": steps.map { step -> [String: Any] in
                ["kind": step.kind.rawValue,
                 "addedWaterGrams": step.kind.addsWater ? num(step.addedWaterGrams) : NSNull(),
                 "seconds": step.seconds.map { $0 as Any } ?? NSNull(),
                 "note": step.note]
            },
            "publish": publish,
        ]
        if let sourceID { body["sourceId"] = sourceID }
        return body
    }
}

extension CatalogAPIClient {
    public func fetchMyRecipes(accessToken: String) async throws -> [RemoteRecipe] {
        let response = try await transport.send(HTTPRequest(method: .get, path: "/api/v1/recipes", bearer: accessToken))
        return try Self.decodeRecipes(response)
    }

    /// Published recipes from everyone; `lotSlug` narrows to one coffee. The token is optional.
    public func exploreRecipes(lotSlug: String? = nil, accessToken: String? = nil) async throws -> [RemoteRecipe] {
        var path = "/api/v1/recipes/explore"
        if let lotSlug, let encoded = lotSlug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?lot=\(encoded)"
        }
        let response = try await transport.send(HTTPRequest(method: .get, path: path, bearer: accessToken))
        return try Self.decodeRecipes(response)
    }

    /// Create or edit by clientID. A publish that fails validation is `APIError.unprocessable`.
    public func saveRecipe(_ draft: RecipeDraft, publish: Bool, accessToken: String) async throws -> RemoteRecipe {
        let data = (try? JSONSerialization.data(withJSONObject: draft.payload(publish: publish))) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .post, path: "/api/v1/recipes", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteRecipe.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    public func changeRecipeState(id: String, to state: RemoteExperience.State, accessToken: String) async throws -> RemoteRecipe {
        let data = (try? JSONSerialization.data(withJSONObject: ["state": state.rawValue])) ?? Data()
        let response = try await transport.send(
            HTTPRequest(method: .patch, path: "/api/v1/recipes/\(id)", body: data, bearer: accessToken)
        )
        try Self.checkContract(response)
        do { return try JSONDecoder().decode(RemoteRecipe.self, from: response.body) }
        catch { throw AuthClientError.malformedResponse }
    }

    private static func decodeRecipes(_ response: HTTPResponse) throws -> [RemoteRecipe] {
        try checkContract(response)
        struct Wrapper: Decodable { let recipes: [RemoteRecipe] }
        do { return try JSONDecoder().decode(Wrapper.self, from: response.body).recipes }
        catch { throw AuthClientError.malformedResponse }
    }
}
