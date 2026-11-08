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
        /// The roaster's own recipe for this coffee, from its product page.
        case roaster(name: String)
        /// A champion's published recipe that ships with the app.
        case champion(author: String, titleAr: String)
    }

    public let id: String
    public let title: String
    public let methodCode: String
    public let temperature: BrewTemperature
    public private(set) var doseGrams: Double?
    public private(set) var hotWaterGrams: Double?
    public private(set) var iceGrams: Double?
    public private(set) var yieldGrams: Double?
    public let waterTempC: Double?
    /// The grind as written by the recipe ("٢٤ كليك على Comandante", "متوسط ناعم").
    public let grindText: String
    /// Microns, when the recipe recorded them; enables the approximate conversion.
    public let grindMicrons: Int?
    public private(set) var steps: [RemoteRecipeStep]
    public let source: Source
    /// Who to credit and where it's published, for a champion's recipe.
    public let credit: BrewPreset.Credit?

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
        credit = nil
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
        credit = preset.credit
        source = preset.credit.map { .champion(author: $0.author, titleAr: $0.titleAr) } ?? .base
    }

    /// The roaster's recipe for this coffee. Nil for an xBloom link (its numbers live on xBloom's page).
    /// Its written steps become timed steps sharing the total time evenly, since the page gives no per-step times.
    public init?(roasterRecipe r: RemoteRoasterRecipe, roasterName: String, index: Int) {
        if r.isMachineLink { return nil }
        guard let dose = r.doseG else { return nil }
        let code = BrewPlanner.methods.contains(r.method) ? r.method : "V60"
        id = "roaster:\(index)"
        title = "وصفة " + roasterName
        methodCode = code
        temperature = r.isIced ? .iced : .hot
        doseGrams = dose
        let water: Double? = code == "ESPRESSO" ? nil : r.waterMl.map(Double.init)
        hotWaterGrams = water
        iceGrams = nil
        yieldGrams = code == "ESPRESSO" ? r.waterMl.map(Double.init) : nil
        waterTempC = r.tempC.map(Double.init)
        grindText = r.grind ?? ""
        grindMicrons = nil
        let texts = r.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let total = r.timeSec ?? 0
        if texts.isEmpty {
            steps = [RemoteRecipeStep(kind: .pour, addedWaterGrams: water, seconds: total > 0 ? total : nil,
                                      note: "حضّرها على أرقام المحمصة.")]
        } else {
            let each = total > 0 ? max(total / texts.count, 1) : nil
            steps = texts.enumerated().map { i, text in
                RemoteRecipeStep(kind: i == 0 ? .bloom : .pour, seconds: each, note: text)
            }
        }
        source = .roaster(name: roasterName)
        credit = nil
    }

    // MARK: Cups

    /// What one cup means for this method: a فنجان of Arabic coffee is about 100 g of water, a mug about 250 g.
    public var cupGrams: Double { methodCode == "ARABIC" ? 100 : 250 }
    public var cupNameAr: String { methodCode == "ARABIC" ? "فنجان" : "كوب" }
    /// Espresso is pulled per shot; the cups stepper doesn't apply.
    public var scalesByCups: Bool { !isEspresso }
    /// How many cups the recipe makes as written (at least one).
    public var baseCups: Int {
        let water = (hotWaterGrams ?? 0) + (iceGrams ?? 0)
        return max(1, Int((water / cupGrams).rounded()))
    }
    public var maxCups: Int { methodCode == "ARABIC" ? 20 : 6 }

    /// The recipe for `cups`: coffee, water, ice and every pour scale together, so the strength stays.
    /// Times stay as written. Dose rounds to 0.5 g, water to 1 g.
    public func scaled(toCups cups: Int) -> BrewPlan {
        guard scalesByCups, cups != baseCups, cups > 0 else { return self }
        let k = Double(cups) / Double(baseCups)
        func half(_ v: Double?) -> Double? { v.map { ($0 * k * 2).rounded() / 2 } }
        func whole(_ v: Double?) -> Double? { v.map { ($0 * k).rounded() } }
        var copy = self
        copy.doseGrams = half(doseGrams)
        copy.hotWaterGrams = whole(hotWaterGrams)
        copy.iceGrams = whole(iceGrams)
        copy.yieldGrams = whole(yieldGrams)
        copy.steps = steps.map { step in
            var s = step
            s.addedWaterGrams = whole(step.addedWaterGrams)
            return s
        }
        return copy
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
        case let .roaster(name): return "من \(name) · وصفة المحمصة لهالقهوة"
        case let .champion(author, titleAr): return "\(author) · \(titleAr)"
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
    public static let methods = ["V60", "CHEMEX", "AEROPRESS", "FRENCH_PRESS", "ESPRESSO", "COLD_BREW", "ARABIC"]

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

    /// The recipe tabs of «حضّر»: for this coffee (the roaster's, then the community's, most liked first),
    /// BunnList's (starting recipes, then champions), yours, and the community's for this method.
    public struct Groups: Equatable, Sendable {
        public var forCoffee: [BrewPlan]
        public var bunnlist: [BrewPlan]
        public var mine: [BrewPlan]
        public var community: [BrewPlan]

        public enum Tab: String, CaseIterable, Sendable {
            case forCoffee, bunnlist, mine, community
            public var titleAr: String {
                switch self {
                case .forCoffee: return "★ لهالقهوة"
                case .bunnlist: return "BunnList"
                case .mine: return "وصفاتي"
                case .community: return "المجتمع"
                }
            }
        }

        public func plans(_ tab: Tab) -> [BrewPlan] {
            switch tab {
            case .forCoffee: return forCoffee
            case .bunnlist: return bunnlist
            case .mine: return mine
            case .community: return community
            }
        }
        /// Tabs with something in them, in order.
        public var tabs: [Tab] { Tab.allCases.filter { !plans($0).isEmpty } }
        public var all: [BrewPlan] { Tab.allCases.flatMap { plans($0) } }
        public func tab(of planID: String?) -> Tab? { tabs.first { plans($0).contains { $0.id == planID } } }
        /// Where to open: this coffee's recipes when there are any, else BunnList's.
        public var defaultTab: Tab { forCoffee.isEmpty ? .bunnlist : .forCoffee }
    }

    public static func groups(methodCode: String, lotSlug: String?, roasterName: String,
                              roasterRecipes: [RemoteRoasterRecipe], mine: [RemoteRecipe],
                              lotCommunity: [RemoteRecipe], methodCommunity: [RemoteRecipe]) -> Groups {
        let roaster = roasterRecipes.enumerated()
            .compactMap { BrewPlan(roasterRecipe: $1, roasterName: roasterName, index: $0) }
            .filter { $0.methodCode == methodCode }
        let lotOthers = lotCommunity
            .filter { !$0.isMine && $0.methodCode == methodCode && $0.state == .published && $0.lot?.slug == lotSlug }
            .sorted { ($0.likeCount ?? 0) > ($1.likeCount ?? 0) }
            .map(BrewPlan.init(recipe:))
        let own = mine
            .filter { $0.isMine && $0.methodCode == methodCode && $0.state != .deleted }
            .sorted { ($0.lot?.slug == lotSlug ? 0 : 1) < ($1.lot?.slug == lotSlug ? 0 : 1) }
            .map(BrewPlan.init(recipe:))
        let lotIDs = Set(lotOthers.map(\.id))
        let others = methodCommunity
            .filter { !$0.isMine && $0.methodCode == methodCode && $0.state == .published }
            .map(BrewPlan.init(recipe:))
            .filter { !lotIDs.contains($0.id) }
            .sorted { likes($0) > likes($1) }
            .prefix(10)
        let presets = BrewPreset.presets(for: methodCode).map(BrewPlan.init(preset:))
        let bunnlist = presets.filter { $0.credit == nil } + presets.filter { $0.credit.map { !$0.advanced } ?? false }
            + presets.filter { $0.credit?.advanced == true }
        return Groups(forCoffee: roaster + lotOthers, bunnlist: bunnlist, mine: own, community: Array(others))
    }

    private static func likes(_ plan: BrewPlan) -> Int {
        if case let .community(_, n) = plan.source { return n }
        return 0
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
