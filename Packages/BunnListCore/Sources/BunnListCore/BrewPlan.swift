import Foundation

/// What «حضّر» brews from: one recipe, whatever it came from (your saved recipe,
/// one from the community for this coffee, or a BunnList starting recipe), with
/// where it came from always said.
public struct BrewPlan: Equatable, Identifiable, Sendable {
    public enum Source: Equatable, Sendable {
        case mine
        /// Someone else's published recipe; `likes` is what the app can show for now.
        case community(author: String, likes: Int)
        /// A starting recipe that ships with the app.
        case base
    }

    public let id: String
    public let title: String
    public let methodCode: String
    public let temperature: BrewTemperature
    public let doseGrams: Double?
    public let hotWaterGrams: Double?
    public let iceGrams: Double?
    public let yieldGrams: Double?
    public let waterTempC: Double?
    /// The grind as written by the recipe ("٢٤ كليك على Comandante", "متوسط ناعم").
    public let grindText: String
    /// Microns, when the recipe recorded them; enables the approximate conversion.
    public let grindMicrons: Int?
    public let steps: [RemoteRecipeStep]
    public let source: Source

    public init(recipe: RemoteRecipe) {
        id = "recipe:" + recipe.id
        title = recipe.title.isEmpty ? "وصفة" : recipe.title
        methodCode = recipe.methodCode
        temperature = recipe.temperature
        doseGrams = recipe.doseGrams
        hotWaterGrams = recipe.hotWaterGrams
        iceGrams = recipe.iceGrams
        yieldGrams = recipe.yieldGrams
        waterTempC = recipe.waterTempC
        let grinderName = Grinder.find(recipe.grinderModel)?.name ?? recipe.grinder
        let written = [recipe.grindSetting, grinderName]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if written.count == 2 { grindText = "\(written[0]) على \(written[1])" }
        else { grindText = written.first ?? recipe.grindLevel?.nameAr ?? "" }
        grindMicrons = recipe.grindMicrons
        steps = recipe.steps
        source = recipe.isMine ? .mine : .community(author: recipe.authorName, likes: recipe.likeCount ?? 0)
    }

    public init(preset: BrewPreset) {
        id = "preset:" + preset.id
        title = preset.nameAr
        methodCode = preset.methodCode
        temperature = preset.temperature
        doseGrams = preset.doseGrams
        hotWaterGrams = preset.hotWaterGrams
        iceGrams = preset.iceGrams
        yieldGrams = preset.yieldGrams
        waterTempC = preset.waterTempC
        grindText = preset.grindAr
        grindMicrons = nil
        steps = preset.steps
        source = .base
    }

    public var isEspresso: Bool { methodCode == "ESPRESSO" }
    /// Hours-long methods get a checklist, not a countdown.
    public var usesTimer: Bool { methodCode != "COLD_BREW" }
    public var totalSeconds: Int { steps.reduce(0) { $0 + ($1.seconds ?? 0) } }

    public var sourceAr: String {
        switch source {
        case .mine: return "وصفتك"
        case let .community(author, likes):
            return likes > 0 ? "من \(author) · \(likes) إعجاب" : "من \(author)"
        case .base: return "وصفة بداية من BunnList"
        }
    }

    /// Your grinder's clicks for this grind, when both sides have published microns
    /// per click. Approximate by nature: a starting point, never a promise.
    public func approximateClicks(on grinder: Grinder?) -> Int? {
        guard let grinder, let grindMicrons else { return nil }
        return grinder.clicks(forMicrons: grindMicrons)
    }
}

public enum BrewPlanner {
    /// Methods «حضّر» offers, in the order shown.
    public static let methods = ["V60", "CHEMEX", "AEROPRESS", "FRENCH_PRESS", "ESPRESSO", "COLD_BREW"]

    /// Recipes for a coffee and method, in the agreed order: yours (this coffee
    /// first), then the community's for this coffee (most liked first), then the
    /// app's starting recipes. At most three of each of the first two.
    public static func options(methodCode: String, lotSlug: String?,
                               mine: [RemoteRecipe], community: [RemoteRecipe]) -> [BrewPlan] {
        let own = mine
            .filter { $0.isMine && $0.methodCode == methodCode && $0.state != .deleted }
            .sorted { ($0.lot?.slug == lotSlug ? 0 : 1) < ($1.lot?.slug == lotSlug ? 0 : 1) }
            .prefix(3)
        let others = community
            .filter { !$0.isMine && $0.methodCode == methodCode && $0.state == .published && $0.lot?.slug == lotSlug }
            .sorted { ($0.likeCount ?? 0) > ($1.likeCount ?? 0) }
            .prefix(3)
        return own.map(BrewPlan.init(recipe:)) + others.map(BrewPlan.init(recipe:))
            + BrewPreset.presets(for: methodCode).map(BrewPlan.init(preset:))
    }

    /// The coffees to offer, most recently brewed first (by slug), then the rest in
    /// their given order.
    public static func ordered<T>(_ items: [T], slug: (T) -> String, recent: [String]) -> [T] {
        let rank = Dictionary(recent.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted { a, b in
            let ra = rank[slug(a.element)] ?? Int.max, rb = rank[slug(b.element)] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Adds a slug to the front of the recent list, without duplicates, capped.
    public static func remember(_ slug: String, in recent: [String], limit: Int = 20) -> [String] {
        Array(([slug] + recent.filter { $0 != slug }).prefix(limit))
    }
}
