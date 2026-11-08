import Foundation

// The recipe editor's rules (same as Android), as mutations of a draft:
// - A pour's amount is what it ADDS; «حتى» (the scale reading) is computed from the adds; bloom counts once.
// - Pours and bloom have a start time («يبدأ»); wait/stir/swirl/press have a duration («المدة»). Every step stores
//   its duration, so moving a step carries its duration and every start is recomputed from the order.
// - The expected end is the last step's start plus its duration.
// - Ice and dilution water are serve steps with an `addition`; they are never brew water.
// - The recipe's water temperature may be unset («غير محددة»); a pour can override it.

/// «＋ إضافة خطوة»: the kinds of step it adds.
public enum ExtraStep: String, CaseIterable, Sendable {
    case wait, swirl, stir, press, ice, dilute, serve

    public var titleAr: String {
        switch self {
        case .wait: return "انتظار"
        case .swirl: return "تدوير القمع"
        case .stir: return "تقليب بالملعقة"
        case .press: return "ضغط"
        case .ice: return "إضافة ثلج"
        case .dilute: return "إضافة ماء للتخفيف"
        case .serve: return "تقديم"
        }
    }

    public var hintAr: String {
        switch self {
        case .wait: return "المدة بالثواني"
        case .swirl: return "يستوي سرير البن"
        case .stir: return "شمال جنوب شرق غرب"
        case .press: return "إيروبرس وفرنش برس"
        case .ice: return "بالغرام"
        case .dilute: return "الكمية والحرارة"
        case .serve: return "آخر خطوة"
        }
    }
}

public enum AdditionTemp {
    public static let all: [(code: String, nameAr: String)] = [("room", "حرارة الغرفة"), ("hot", "حار"), ("cold", "بارد")]
    public static func nameAr(_ code: String?) -> String { all.first { $0.code == (code ?? "room") }?.nameAr ?? "حرارة الغرفة" }
}

extension RemoteRecipeStep {
    /// The step's title in the editor and review: تشريب, صبّة, انتظار, ثلج, تخفيف…
    public var titleAr: String {
        if addition == "ice" { return "ثلج" }
        if addition == "dilute" { return "تخفيف" }
        switch kind {
        case .bloom: return "تشريب"
        case .pour: return "صبّة"
        case .wait: return "انتظار"
        case .swirl: return "تدوير"
        case .stir: return "تقليب"
        case .press: return "ضغط"
        case .serve: return "تقديم"
        }
    }
}

extension RecipeDraft {
    public var waterIndices: [Int] { steps.indices.filter { steps[$0].kind.addsWater } }
    public var hasBloom: Bool { steps.first?.kind == .bloom }
    public var pourCount: Int { steps.filter { $0.kind == .pour }.count }
    public var pouredGrams: Double { steps.filter(\.kind.addsWater).compactMap(\.addedWaterGrams).reduce(0, +) }

    /// The scale reading when step `index` begins.
    public func scaleBefore(_ index: Int) -> Double {
        cumulativeWater[index] - (steps[index].kind.addsWater ? steps[index].addedWaterGrams ?? 0 : 0)
    }

    /// Hot water minus what the pours add: positive = water still missing, negative = over.
    public var waterShortfall: Double { (hotWaterGrams ?? 0) - pouredGrams }
    public var waterMismatch: Bool { !isEspresso && hotWaterGrams != nil && !waterIndices.isEmpty && abs(waterShortfall) > 1 }
    public func stepTemp(_ index: Int) -> Double? {
        guard steps.indices.contains(index), steps[index].kind.addsWater else { return nil }
        return steps[index].tempC ?? waterTempC
    }
    public var iceAddedGrams: Double { steps.filter { $0.addition == "ice" }.compactMap(\.addedWaterGrams).reduce(0, +) }
    public var dilutionGrams: Double { steps.filter { $0.addition == "dilute" }.compactMap(\.addedWaterGrams).reduce(0, +) }

    /// «جهّز الماء على 92°م», or nil when the temperature is unset.
    public var prepLineAr: String? { waterTempC.map { "جهّز الماء على \(Self.g($0))°م" } }
    /// Pours with their own temperature: «صبّة 2 على 88°».
    public var customTempsAr: String? {
        var pour = 0
        let custom: [String] = steps.compactMap { s in
            if s.kind == .pour { pour += 1 }
            guard s.kind.addsWater, let t = s.tempC, t != waterTempC else { return nil }
            return "\(s.kind == .bloom ? "التشريب" : "صبّة \(pour)") على \(Self.g(t))°"
        }
        return custom.isEmpty ? nil : custom.joined(separator: "، ")
    }

    static func g(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }

    /// The simple editor: `count` pours after an optional bloom (3× the dose), the water split evenly, 30 s apart.
    /// Steps after the last pour (waits, additions) are kept; without any, a drawdown wait of 60 s ends the brew.
    public mutating func simplePours(_ count: Int, bloom: Bool) {
        guard !isEspresso else { return }
        let n = min(max(count, 1), 5)
        let total = hotWaterGrams ?? 250
        let bloomGrams = bloom ? min(((doseGrams ?? 15) * 3).rounded(), (total / 2).rounded(.down)) : 0
        let rest = total - bloomGrams
        let each = (rest / Double(n)).rounded(.down)
        let oldBloom = steps.first { $0.kind == .bloom }
        let oldPours = steps.filter { $0.kind == .pour }
        var list: [RemoteRecipeStep] = []
        if bloom {
            list.append(RemoteRecipeStep(kind: .bloom, addedWaterGrams: bloomGrams, seconds: 45,
                                         note: oldBloom?.note ?? "صب برفق لترطيب البن واتركه يتنفس.", tempC: oldBloom?.tempC))
        }
        for i in 0..<n {
            let old = oldPours.indices.contains(i) ? oldPours[i] : nil
            list.append(RemoteRecipeStep(kind: .pour, addedWaterGrams: i == n - 1 ? rest - each * Double(n - 1) : each, seconds: 30,
                                         note: old?.note ?? "", pourStyle: old?.pourStyle, pourSpeed: old?.pourSpeed, tempC: old?.tempC))
        }
        let tail = waterIndices.last.map { Array(steps[($0 + 1)...]) } ?? []
        steps = list + (tail.isEmpty ? [RemoteRecipeStep(kind: .wait, seconds: 60, note: "اترك الماء ينزل.")] : tail)
    }

    /// Sets how much water step `index` adds; the next pour absorbs the difference (or the total grows if it's the last).
    public mutating func setAdded(_ index: Int, grams: Double) {
        guard steps.indices.contains(index), steps[index].kind.addsWater else { return }
        setPourTo(index, grams: scaleBefore(index) + max(grams, 0))
    }

    /// Moves a step; it keeps its duration, so every start after the change is recomputed from the new order.
    public mutating func moveStep(from: Int, to: Int) {
        guard steps.indices.contains(from), steps.indices.contains(to), from != to else { return }
        let step = steps.remove(at: from)
        steps.insert(step, at: to)
    }

    public mutating func removeStep(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)
    }

    /// «＋ صبّة»: after the last pour, 30 s later. It takes the water still missing, else half of the last pour.
    public mutating func addPour() {
        guard let last = waterIndices.last else {
            steps.insert(RemoteRecipeStep(kind: .pour, addedWaterGrams: hotWaterGrams ?? 0, seconds: 30), at: 0); return
        }
        let missing = waterShortfall
        var grams = missing
        if missing <= 0.5 {
            let half = ((steps[last].addedWaterGrams ?? 0) / 2).rounded(.down)
            steps[last].addedWaterGrams = (steps[last].addedWaterGrams ?? 0) - half
            grams = half
        }
        steps.insert(RemoteRecipeStep(kind: .pour, addedWaterGrams: grams, seconds: 30), at: last + 1)
    }

    public mutating func addStep(_ kind: ExtraStep) {
        switch kind {
        case .wait: steps.append(RemoteRecipeStep(kind: .wait, seconds: 30))
        case .swirl: steps.append(RemoteRecipeStep(kind: .swirl, seconds: 10))
        case .stir: steps.append(RemoteRecipeStep(kind: .stir, seconds: 10))
        case .press: steps.append(RemoteRecipeStep(kind: .press, seconds: 30))
        case .ice: steps.append(RemoteRecipeStep(kind: .serve, addedWaterGrams: 100, seconds: 10, addition: "ice"))
        case .dilute: steps.append(RemoteRecipeStep(kind: .serve, addedWaterGrams: 20, seconds: 10, addition: "dilute", additionTemp: "room"))
        case .serve: steps.append(RemoteRecipeStep(kind: .serve, seconds: 10))
        }
    }

    /// «أضف 10غ لآخر صبّة»: the last pour takes the missing (or extra) water so the steps match the target.
    public mutating func giveShortfallToLastPour() {
        guard let last = waterIndices.last else { return }
        steps[last].addedWaterGrams = max((steps[last].addedWaterGrams ?? 0) + waterShortfall, 0)
    }

    /// «اعتمد إجمالي 240غ»: the target becomes what the steps pour.
    public mutating func adoptPouredTotal() { hotWaterGrams = pouredGrams }
}
