import Foundation

// The recipe editor walks through three steps: pick the tool (a barista recipe is
// loaded for it), tune it (dose, strength, grind, pours), then name and share it.
// Simple and pro use the same steps; pro shows more fields inside each.

public enum RecipeWizardStep: Int, CaseIterable, Sendable {
    case tool, tune, finish

    public var titleAr: String {
        switch self {
        case .tool: return "وش بتحضّر؟"
        case .tune: return "اضبطها على ذوقك"
        case .finish: return "جاهزة"
        }
    }

    public var subtitleAr: String {
        switch self {
        case .tool: return "اختر الأداة، ونجهّز لك وصفة باريستا تعدّل عليها."
        case .tune: return "غيّر البن، والماء والصبات تتعدل معه."
        case .finish: return "سمّها إذا تبي، أو خلّ الاسم المقترح."
        }
    }
}

extension BrewPreset {
    /// The starting recipe for a tool: the one served at that temperature, else its first.
    public static func starter(methodCode: String, temperature: BrewTemperature) -> BrewPreset? {
        let list = presets(for: methodCode)
        return list.first { $0.temperature == temperature } ?? list.first
    }
}

extension RecipeDraft {
    /// Starts over from the tool's barista recipe; the name, coffee and notes stay.
    public mutating func start(methodCode: String, temperature: BrewTemperature) {
        if let preset = BrewPreset.starter(methodCode: methodCode, temperature: temperature) {
            apply(preset)
        } else {
            self.methodCode = methodCode
        }
        if temperature != self.temperature { setTemperature(temperature) }
    }

    /// Hot or iced. Iced pour-over without a recipe of its own melts 40% of the water as ice.
    public mutating func setTemperature(_ newValue: BrewTemperature) {
        let ratio = self.ratio
        temperature = newValue
        if isEspresso { temperature = .hot; return }
        if newValue == .iced, iceGrams == nil { iceGrams = ((hotWaterGrams ?? 250) * 0.4).rounded() }
        if newValue == .hot { iceGrams = nil }
        if let ratio { applyRatio(ratio) }
    }

    /// Changes the dose and keeps the strength: water (or the shot), ice and every
    /// pour scale with it.
    public mutating func setDose(_ grams: Double) {
        let grams = (grams * 10).rounded() / 10
        guard grams > 0 else { return }
        let ratio = self.ratio
        if let old = doseGrams, old > 0, let ice = iceGrams { iceGrams = (ice * grams / old).rounded() }
        doseGrams = grams
        if let ratio { applyRatio(ratio) }
    }

    /// A name for an untitled recipe: the tool, iced if so, and the coffee's name.
    public var suggestedTitle: String {
        var parts = [methodCode == "V60" ? "V60" : ReferenceCodes.brewMethod(methodCode)?.nameAr ?? "وصفة"]
        if temperature == .iced { parts[0] += " مثلج" }
        if let lot { parts.append(lot.nameAr) }
        return parts.joined(separator: " · ")
    }

    /// A recipe from a brew just made (a barista or community recipe), to keep as one's own.
    public init(plan: BrewPlan, lot: RemoteRecipeLot?, grinderId: String?, grindSetting: String) {
        self.init(lot: lot)
        methodCode = plan.methodCode
        temperature = plan.temperature
        doseGrams = plan.doseGrams
        hotWaterGrams = plan.hotWaterGrams
        iceGrams = plan.iceGrams
        yieldGrams = plan.yieldGrams
        waterTempC = plan.waterTempC
        steps = plan.steps
        grindMicrons = plan.grindMicrons
        let setting = grindSetting.trimmingCharacters(in: .whitespaces)
        if let known = Grinder.find(grinderId) {
            grinderModel = known.id
            grinder = known.name
        }
        self.grindSetting = setting
        if setting.isEmpty, !plan.grindText.isEmpty { notes = "الطحن: \(plan.grindText)" }
        title = suggestedTitle
    }
}
