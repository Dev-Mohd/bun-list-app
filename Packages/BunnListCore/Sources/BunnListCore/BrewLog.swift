import Foundation

/// How a brew tasted, as «كيف طلعت؟» asks it: one word, or nothing.
public enum BrewTaste: String, Codable, CaseIterable, Sendable {
    case balanced, sour, bitter, weak, strong

    public var nameAr: String {
        switch self {
        case .balanced: return "متوازنة"
        case .sour: return "حامضة"
        case .bitter: return "مرّة"
        case .weak: return "خفيفة"
        case .strong: return "ثقيلة"
        }
    }

    public var hintAr: String {
        switch self {
        case .balanced: return "حلوة ومتوازنة"
        case .sour: return "حموضة حادة، ناقصة"
        case .bitter: return "مرارة، تنشّف الفم"
        case .weak: return "مائية، طعمها ضعيف"
        case .strong: return "قوية زيادة، ثقيلة"
        }
    }
}

/// What «حضّر» records with an experience: the recipe followed, the grind actually
/// used, the numbers, the time and the taste. All optional.
public struct BrewLogEntry: Codable, Equatable, Sendable {
    public var recipeId: String?
    public var recipeTitle: String?
    public var recipeSource: String?
    public var grinderId: String?
    public var grindSetting: String?
    public var doseGrams: Double?
    public var waterGrams: Double?
    public var brewSeconds: Int?
    public var taste: BrewTaste?

    public init(recipeId: String? = nil, recipeTitle: String? = nil, recipeSource: String? = nil,
                grinderId: String? = nil, grindSetting: String? = nil, doseGrams: Double? = nil,
                waterGrams: Double? = nil, brewSeconds: Int? = nil, taste: BrewTaste? = nil) {
        self.recipeId = recipeId; self.recipeTitle = recipeTitle; self.recipeSource = recipeSource
        self.grinderId = grinderId; self.grindSetting = grindSetting; self.doseGrams = doseGrams
        self.waterGrams = waterGrams; self.brewSeconds = brewSeconds; self.taste = taste
    }

    /// From a plan as brewed. Water is the cup yield for espresso.
    public init(plan: BrewPlan, grinderId: String?, grindSetting: String?, seconds: Int, taste: BrewTaste?) {
        let setting = grindSetting?.trimmingCharacters(in: .whitespaces)
        self.init(recipeId: plan.id, recipeTitle: plan.title, recipeSource: plan.sourceCode,
                  grinderId: grinderId, grindSetting: setting?.isEmpty == false ? setting : nil,
                  doseGrams: plan.doseGrams, waterGrams: plan.isEspresso ? plan.yieldGrams : plan.hotWaterGrams,
                  brewSeconds: seconds > 0 ? seconds : nil, taste: taste)
    }

    /// Body fields for the experience POST (nil fields left out).
    var payload: [String: Any] {
        var out: [String: Any] = [:]
        if let recipeId { out["recipeId"] = recipeId }
        if let recipeTitle { out["recipeTitle"] = recipeTitle }
        if let recipeSource { out["recipeSource"] = recipeSource }
        if let grinderId { out["grinderId"] = grinderId }
        if let grindSetting { out["grindSetting"] = grindSetting }
        if let doseGrams { out["doseGrams"] = doseGrams }
        if let waterGrams { out["waterGrams"] = waterGrams }
        if let brewSeconds { out["brewSeconds"] = brewSeconds }
        if let taste { out["taste"] = taste.rawValue }
        return out
    }
}

extension BrewPlan {
    /// The server's name for where the recipe came from.
    public var sourceCode: String {
        switch source {
        case .mine: return "mine"
        case .community: return "community"
        case .base: return "base"
        }
    }
}

/// One change to try next time, from how the last brew tasted. Always a single
/// variable, so its effect can be tasted; a suggestion, never a promise.
public struct TasteFix: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case keep
        /// Negative = finer. `setting` is the suggested new number when the grinder counts.
        case grind(direction: Int, setting: String?)
        case dose(grams: Double?)
        case water(grams: Double?)
    }

    public let change: Change
    public let titleAr: String
    public let detailAr: String

    /// `setting` is the grind used last time on `grinder` (the guide grinder).
    public static func suggest(taste: BrewTaste, methodCode: String, setting: String?, grinder: RemoteGrinder?,
                               doseGrams: Double?, waterGrams: Double?) -> TasteFix {
        let espresso = methodCode == "ESPRESSO"
        switch taste {
        case .balanced:
            return TasteFix(change: .keep, titleAr: "ثبّتها",
                            detailAr: "كرّر نفس الطحنة والأرقام. إذا تبي تجرّب، غيّر شي واحد بس.")
        case .sour, .bitter:
            let finer = taste == .sour
            let next = nextSetting(from: setting, finer: finer, grinder: grinder, espresso: espresso)
            let word = finer ? "أنعم" : "أخشن"
            let why = finer
                ? "الحموضة الحادة غالبًا معناها استخلاص ناقص، والطحنة الأنعم تطلّع أكثر."
                : "المرارة غالبًا معناها استخلاص زايد، والطحنة الأخشن تخفّفه."
            let title = next.map { "طحنة \(word): جرّب \($0)" } ?? "طحنة \(word) شوي"
            return TasteFix(change: .grind(direction: finer ? -1 : 1, setting: next), titleAr: title,
                            detailAr: why + " ثبّت الباقي.")
        case .weak:
            let dose = doseGrams.map { $0 + (espresso ? 0.5 : 1) }
            let title = dose.map { "زِد البن إلى \(grams($0))غ" } ?? "زِد البن غرام واحد"
            return TasteFix(change: .dose(grams: dose), titleAr: title,
                            detailAr: "نفس الماء ونفس الطحنة، بس بن أكثر شوي عشان يقوى الطعم.")
        case .strong:
            let water = waterGrams.map { $0 + (espresso ? 4 : 20) }
            let title: String
            if let water { title = espresso ? "طوّل الناتج إلى \(grams(water))غ" : "زِد الماء إلى \(grams(water))غ" }
            else { title = espresso ? "طوّل الناتج شوي" : "زِد الماء شوي" }
            return TasteFix(change: .water(grams: water), titleAr: title,
                            detailAr: "نفس البن ونفس الطحنة، بس ماء أكثر شوي عشان تخف.")
        }
    }

    static func grams(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    /// The next number on a counting grinder, lower being finer as on nearly every
    /// grinder's scale. Nil when the setting isn't a number or the grinder is stepless.
    static func nextSetting(from setting: String?, finer: Bool, grinder: RemoteGrinder?, espresso: Bool) -> String? {
        guard let setting, let value = Double(setting.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")) else { return nil }
        let adjustment = grinder?.adjustment
        if adjustment == "stepless" || adjustment == "timer" { return nil }
        let step: Double = adjustment == "clicks" && !espresso ? 2 : 1
        var next = value + (finer ? -step : step)
        if let min = grinder?.rangeMin { next = Swift.max(next, min) }
        if let max = grinder?.rangeMax { next = Swift.min(next, max) }
        guard next != value, next >= 0 else { return nil }
        return next == next.rounded() ? String(Int(next)) : String(format: "%.1f", next)
    }
}

/// «آخر مرة»: your latest logged brew of this coffee with this method, and what to
/// try this time.
public struct BrewMemory: Equatable, Sendable {
    public let stars: Int
    public let brewedAt: Date?
    public let log: BrewLogEntry
    public let fix: TasteFix?

    public static func latest(_ experiences: [RemoteExperience], methodCode: String,
                              grinder: RemoteGrinder?) -> BrewMemory? {
        let logged = experiences
            .filter { $0.methodCode == methodCode && $0.log != nil && $0.state != .deleted }
            .sorted { ($0.brewedDate ?? .distantPast) > ($1.brewedDate ?? .distantPast) }
        guard let last = logged.first, let log = last.log else { return nil }
        // A setting only carries over on the same grinder.
        let sameGrinder = log.grinderId != nil && log.grinderId == grinder?.id
        let fix = log.taste.map {
            TasteFix.suggest(taste: $0, methodCode: methodCode, setting: sameGrinder ? log.grindSetting : nil,
                             grinder: sameGrinder ? grinder : nil, doseGrams: log.doseGrams, waterGrams: log.waterGrams)
        }
        return BrewMemory(stars: last.stars, brewedAt: last.brewedDate, log: log, fix: fix)
    }

    /// The grind to start from: the fix's number, else last time's (same grinder only).
    public func startingSetting(grinderId: String?) -> String? {
        guard log.grinderId != nil, log.grinderId == grinderId else { return nil }
        if case let .grind(_, setting?)? = fix?.change { return setting }
        return log.grindSetting
    }
}
