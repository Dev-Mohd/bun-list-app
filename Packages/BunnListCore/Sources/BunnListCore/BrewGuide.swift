import Foundation

// Barista knowledge for recipes: proven starting recipes per method, gentle tips
// while editing, a taste-troubleshooting guide, and the guided-brew timeline.
// Tips never block saving; only `RecipeDraft.problems()` does.

/// A proven starting recipe. Applying it replaces the draft's brew parameters and
/// steps; the title, notes and coffee stay the user's.
public struct BrewPreset: Equatable, Identifiable, Sendable {
    public let id: String
    public let nameAr: String
    public let summaryAr: String
    public let methodCode: String
    public let temperature: BrewTemperature
    public let doseGrams: Double
    public let hotWaterGrams: Double?
    public let iceGrams: Double?
    public let yieldGrams: Double?
    public let waterTempC: Double
    public let grindAr: String
    public let steps: [RemoteRecipeStep]

    public static func presets(for methodCode: String) -> [BrewPreset] { all.filter { $0.methodCode == methodCode } }

    public static let all: [BrewPreset] = [
        BrewPreset(
            id: "v60-classic", nameAr: "V60 الكلاسيكية", summaryAr: "متوازنة وواضحة النكهات · ١:١٦٫٧ · ٢:٥٥",
            methodCode: "V60", temperature: .hot, doseGrams: 15, hotWaterGrams: 250, iceGrams: nil, yieldGrams: nil,
            waterTempC: 94, grindAr: "متوسط إلى ناعم",
            steps: [
                .init(kind: .bloom, addedWaterGrams: 45, seconds: 45,
                      note: "صب ٤٥غ بحركة دائرية حتى يتبلل كل البن، ثم حرّك القمع حركة دائرية خفيفة."),
                .init(kind: .pour, addedWaterGrams: 105, seconds: 30, note: "صب من المنتصف للخارج بثبات حتى ١٥٠غ."),
                .init(kind: .pour, addedWaterGrams: 100, seconds: 30, note: "صب ببطء حتى ٢٥٠غ وحافظ على مستوى الماء."),
                .init(kind: .swirl, seconds: 10, note: "حرّك القمع بلطف ليستوي سرير البن."),
                .init(kind: .wait, seconds: 60, note: "اترك الماء ينزل كاملًا. الهدف ينتهي بين ٢:٣٠ و٣:٠٠."),
            ]),
        BrewPreset(
            id: "v60-46", nameAr: "طريقة ٤:٦", summaryAr: "طريقة تيتسو كاسويا · خمس صبات · ١:١٥ · ٣:٣٠",
            methodCode: "V60", temperature: .hot, doseGrams: 20, hotWaterGrams: 300, iceGrams: nil, yieldGrams: nil,
            waterTempC: 92, grindAr: "خشن",
            steps: [
                .init(kind: .bloom, addedWaterGrams: 50, seconds: 45,
                      note: "أول ٤٠٪ تتحكم بالحلاوة والحموضة: صبة أولى أصغر = حموضة أوضح."),
                .init(kind: .pour, addedWaterGrams: 70, seconds: 45, note: "أكمل حتى ١٢٠غ."),
                .init(kind: .pour, addedWaterGrams: 60, seconds: 45,
                      note: "الـ٦٠٪ الأخيرة تتحكم بالقوة: صبات أكثر = كوب أقوى."),
                .init(kind: .pour, addedWaterGrams: 60, seconds: 45, note: "حتى ٢٤٠غ."),
                .init(kind: .pour, addedWaterGrams: 60, seconds: 30, note: "حتى ٣٠٠غ، ثم اترك الماء ينزل. الهدف ٣:٣٠."),
            ]),
        BrewPreset(
            id: "v60-iced", nameAr: "المثلجة اليابانية", summaryAr: "صب على الثلج · ثلج ٣٧٪ · ١:١٦",
            methodCode: "V60", temperature: .iced, doseGrams: 20, hotWaterGrams: 200, iceGrams: 120, yieldGrams: nil,
            waterTempC: 94, grindAr: "متوسط إلى ناعم (أنعم قليلًا من الساخنة)",
            steps: [
                .init(kind: .bloom, addedWaterGrams: 50, seconds: 45, note: "الثلج في الإبريق تحت القمع. صب ٥٠غ للتفتيح."),
                .init(kind: .pour, addedWaterGrams: 70, seconds: 30, note: "حتى ١٢٠غ."),
                .init(kind: .pour, addedWaterGrams: 80, seconds: 30, note: "حتى ٢٠٠غ."),
                .init(kind: .swirl, seconds: 10, note: "حرّك القمع بلطف."),
                .init(kind: .wait, seconds: 45, note: "اترك الماء ينزل."),
                .init(kind: .serve, seconds: 10, note: "حرّك الإبريق حتى يذوب الثلج وتبرد القهوة، وقدّمها على ثلج جديد."),
            ]),
        BrewPreset(
            id: "chemex-classic", nameAr: "كيمكس للمشاركة", summaryAr: "كوبان صافيان · ١:١٦٫٧ · ٤:٠٠",
            methodCode: "CHEMEX", temperature: .hot, doseGrams: 30, hotWaterGrams: 500, iceGrams: nil, yieldGrams: nil,
            waterTempC: 94, grindAr: "متوسط إلى خشن",
            steps: [
                .init(kind: .bloom, addedWaterGrams: 60, seconds: 45,
                      note: "اغسل الورق جيدًا بالماء الحار قبل البدء. صب ٦٠غ وحرّك بلطف."),
                .init(kind: .pour, addedWaterGrams: 190, seconds: 45, note: "حتى ٢٥٠غ بحركة دائرية."),
                .init(kind: .pour, addedWaterGrams: 250, seconds: 60, note: "حتى ٥٠٠غ، لا تصب على جدار الورق مباشرة."),
                .init(kind: .wait, seconds: 90, note: "اترك الماء ينزل. الهدف بين ٤:٠٠ و٤:٣٠."),
            ]),
        BrewPreset(
            id: "aeropress-classic", nameAr: "إيروبرس اليومية", summaryAr: "نظيفة وحلوة · ١:١٦ · ٢:٤٠",
            methodCode: "AEROPRESS", temperature: .hot, doseGrams: 15, hotWaterGrams: 240, iceGrams: nil, yieldGrams: nil,
            waterTempC: 90, grindAr: "متوسط إلى ناعم",
            steps: [
                .init(kind: .bloom, addedWaterGrams: 40, seconds: 30, note: "صب ٤٠غ وحرّك ثلاث مرات."),
                .init(kind: .pour, addedWaterGrams: 200, seconds: 15, note: "أكمل حتى ٢٤٠غ."),
                .init(kind: .wait, seconds: 75, note: "ركّب المكبس قليلًا ليمنع التنقيط، واتركها تنقع."),
                .init(kind: .swirl, seconds: 10, note: "حرّك الجهاز بلطف قبل الضغط."),
                .init(kind: .serve, seconds: 30, note: "اضغط ببطء وثبات ٣٠ ثانية، وتوقف عند سماع الهسهسة."),
            ]),
        BrewPreset(
            id: "french-clean", nameAr: "فرنش برس النظيفة", summaryAr: "قوام غني بدون رواسب · ١:١٦٫٧ · ١٠:٠٠",
            methodCode: "FRENCH_PRESS", temperature: .hot, doseGrams: 30, hotWaterGrams: 500, iceGrams: nil, yieldGrams: nil,
            waterTempC: 95, grindAr: "متوسط إلى خشن",
            steps: [
                .init(kind: .pour, addedWaterGrams: 500, seconds: 15, note: "صب كل الماء بسرعة وتأكد أن البن تبلل كله."),
                .init(kind: .wait, seconds: 240, note: "اتركها ٤ دقائق بدون تحريك."),
                .init(kind: .swirl, seconds: 30, note: "اكسر الطبقة العلوية بالملعقة، وأزل الرغوة والحبيبات الطافية."),
                .init(kind: .wait, seconds: 300, note: "انتظر ٥ دقائق لتترسب الحبيبات، فيصير الكوب أنظف."),
                .init(kind: .serve, seconds: 15, note: "أنزل المكبس إلى السطح فقط بدون ضغط، واسكب ببطء."),
            ]),
        BrewPreset(
            id: "espresso-classic", nameAr: "إسبريسو ١:٢", summaryAr: "١٨غ ← ٣٦غ في ٢٥–٣٠ ثانية",
            methodCode: "ESPRESSO", temperature: .hot, doseGrams: 18, hotWaterGrams: nil, iceGrams: nil, yieldGrams: 36,
            waterTempC: 93, grindAr: "ناعم",
            steps: [
                .init(kind: .serve, seconds: 28,
                      note: "وزّع البن ودكّه بثبات. الهدف ٣٦غ في ٢٥–٣٠ ثانية: أسرع = نعّم الطحنة، أبطأ = خشّنها."),
            ]),
        BrewPreset(
            id: "cold-brew", nameAr: "كولد برو مركّز", summaryAr: "١:١٠ · نقع ١٢–١٦ ساعة · يُخفف ١:١",
            methodCode: "COLD_BREW", temperature: .iced, doseGrams: 100, hotWaterGrams: 1000, iceGrams: nil, yieldGrams: nil,
            waterTempC: 20, grindAr: "خشن جدًا",
            steps: [
                .init(kind: .pour, addedWaterGrams: 1000, seconds: 60,
                      note: "صب ماء بحرارة الغرفة وحرّك حتى يتبلل كل البن."),
                .init(kind: .wait, note: "غطّها وانقعها ١٢–١٦ ساعة في الثلاجة."),
                .init(kind: .serve, note: "صفّها بفلتر ورقي، وخففها بالماء أو الحليب ١:١ وقدّمها على ثلج."),
            ]),
    ]
}

extension RecipeDraft {
    /// Replaces brew parameters and steps with the preset's; keeps title, notes, coffee and grinder.
    public mutating func apply(_ preset: BrewPreset) {
        methodCode = preset.methodCode
        temperature = preset.temperature
        doseGrams = preset.doseGrams
        hotWaterGrams = preset.hotWaterGrams
        iceGrams = preset.iceGrams
        yieldGrams = preset.yieldGrams
        waterTempC = preset.waterTempC
        grindSetting = preset.grindAr
        steps = preset.steps
    }
}

/// A non-blocking barista tip about a draft.
public enum BrewTip: Equatable, Hashable, Sendable {
    case waterTooCool
    case waterTooHot
    case ratioStrong(typical: ClosedRange<Double>)
    case ratioWeak(typical: ClosedRange<Double>)
    case shortBloom
    case smallBloom
    case fastBrew(typical: ClosedRange<Int>)
    case slowBrew(typical: ClosedRange<Int>)
    case icedShare
    case missingGrind

    public var messageAr: String {
        switch self {
        case .waterTooCool: return "الحرارة منخفضة: للتحميص الفاتح جرّب ٩٢–٩٦°م لاستخلاص أحلى."
        case .waterTooHot: return "الحرارة عالية: قد تبرز المرارة، خصوصًا مع التحميص الغامق."
        case let .ratioStrong(r): return "النسبة أقوى من المعتاد لهذه الطريقة (١:\(Self.n(r.lowerBound))–١:\(Self.n(r.upperBound)))."
        case let .ratioWeak(r): return "النسبة أخف من المعتاد لهذه الطريقة (١:\(Self.n(r.lowerBound))–١:\(Self.n(r.upperBound)))."
        case .shortBloom: return "اترك التفتيح ٣٠–٤٥ ثانية ليخرج ثاني أكسيد الكربون ويتشبع البن بالتساوي."
        case .smallBloom: return "ماء التفتيح يكون عادة ضعفي إلى ثلاثة أضعاف وزن البن."
        case let .fastBrew(r): return "الوقت أقصر من المعتاد (\(Self.t(r.lowerBound))–\(Self.t(r.upperBound))): جرّب طحنة أنعم."
        case let .slowBrew(r): return "الوقت أطول من المعتاد (\(Self.t(r.lowerBound))–\(Self.t(r.upperBound))): جرّب طحنة أخشن."
        case .icedShare: return "في الطريقة اليابانية خلّ الثلج ٣٠–٤٠٪ من الماء الكلي."
        case .missingGrind: return "اكتب درجة الطحن ليقدر غيرك يكرر وصفتك بدقة."
        }
    }

    private static func n(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private static func t(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

public enum BrewAdvisor {
    /// Typical ratio (water or yield per gram of coffee) for each method.
    public static func typicalRatio(_ methodCode: String) -> ClosedRange<Double> {
        switch methodCode {
        case "ESPRESSO": return 1.5...3
        case "COLD_BREW": return 4...12
        case "AEROPRESS": return 12...18
        default: return 14...18
        }
    }

    /// Typical total brew time in seconds, or nil when time is not meaningful (cold brew).
    public static func typicalSeconds(_ methodCode: String) -> ClosedRange<Int>? {
        switch methodCode {
        case "ESPRESSO": return 20...35
        case "V60": return 120...240
        case "CHEMEX": return 210...330
        case "AEROPRESS": return 90...240
        case "FRENCH_PRESS": return 240...720
        default: return nil
        }
    }

    public static func tips(for draft: RecipeDraft) -> [BrewTip] {
        var tips: [BrewTip] = []
        let method = draft.methodCode

        if let temp = draft.waterTempC, method != "COLD_BREW" {
            if temp < 88 { tips.append(.waterTooCool) } else if temp > 98 { tips.append(.waterTooHot) }
        }

        if let ratio = draft.ratio {
            let typical = typicalRatio(method)
            if ratio < typical.lowerBound - 0.05 { tips.append(.ratioStrong(typical: typical)) }
            else if ratio > typical.upperBound + 0.05 { tips.append(.ratioWeak(typical: typical)) }
        }

        if let bloom = draft.steps.first, bloom.kind == .bloom {
            if let seconds = bloom.seconds, seconds < 30 { tips.append(.shortBloom) }
            if let water = bloom.addedWaterGrams, let dose = draft.doseGrams, water < dose * 2 - 0.5 { tips.append(.smallBloom) }
        }

        if let typical = typicalSeconds(method), draft.totalSeconds > 0 {
            if draft.totalSeconds < typical.lowerBound { tips.append(.fastBrew(typical: typical)) }
            else if draft.totalSeconds > typical.upperBound { tips.append(.slowBrew(typical: typical)) }
        }

        if draft.temperature == .iced, method != "COLD_BREW", !draft.isEspresso,
           let ice = draft.iceGrams, let hot = draft.hotWaterGrams, ice + hot > 0 {
            let share = ice / (ice + hot)
            if share < 0.25 || share > 0.5 { tips.append(.icedShare) }
        }

        if draft.grindSetting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tips.append(.missingGrind) }
        return tips
    }

    /// Taste → fix, for dialing in.
    public struct TasteFix: Hashable, Sendable {
        public let taste: String
        public let fix: String
    }

    public static let troubleshooting: [TasteFix] = [
        TasteFix(taste: "حامضة أو لاذعة", fix: "استخلاص ناقص: نعّم الطحنة، أو ارفع الحرارة، أو طوّل وقت التحضير."),
        TasteFix(taste: "مُرّة أو جافة", fix: "استخلاص زائد: خشّن الطحنة، أو اخفض الحرارة درجتين."),
        TasteFix(taste: "خفيفة ومائية", fix: "زِد البن قليلًا (مثلًا ١:١٥ بدل ١:١٧)."),
        TasteFix(taste: "ثقيلة أو طاغية", fix: "خفّف النسبة (مثلًا ١:١٧) أو قلّل البن غرامًا."),
        TasteFix(taste: "حامضة ومُرّة معًا", fix: "استخلاص غير متساوٍ: حرّك القمع بعد التفتيح، وصب بثبات من المنتصف."),
    ]
}

/// Where a guided brew is at a given elapsed time. Untimed steps take no time.
public struct BrewTimeline: Equatable, Sendable {
    public struct Position: Equatable, Sendable {
        public let stepIndex: Int
        public let secondsLeftInStep: Int
        /// Scale reading to pour up to by the end of this step, if it adds water.
        public let pourTo: Double?
        public let isFinished: Bool
    }

    public let steps: [RemoteRecipeStep]
    public let totalSeconds: Int
    private let starts: [Int]
    private let cumulative: [Double]

    public init(steps: [RemoteRecipeStep]) {
        self.steps = steps
        var running = 0
        var starts: [Int] = []
        var water = 0.0
        var cumulative: [Double] = []
        for step in steps {
            starts.append(running)
            running += step.seconds ?? 0
            if step.kind.addsWater, let added = step.addedWaterGrams { water += added }
            cumulative.append(water)
        }
        self.starts = starts
        self.cumulative = cumulative
        totalSeconds = running
    }

    public func position(at elapsed: Int) -> Position {
        guard !steps.isEmpty else { return Position(stepIndex: 0, secondsLeftInStep: 0, pourTo: nil, isFinished: true) }
        if elapsed >= totalSeconds {
            return Position(stepIndex: steps.count - 1, secondsLeftInStep: 0, pourTo: nil, isFinished: true)
        }
        // The last step whose start is at or before `elapsed` and that still has time left.
        var index = 0
        for i in steps.indices where starts[i] <= elapsed && elapsed < starts[i] + (steps[i].seconds ?? 0) {
            index = i
        }
        let left = starts[index] + (steps[index].seconds ?? 0) - elapsed
        let pourTo = steps[index].kind.addsWater ? cumulative[index] : nil
        return Position(stepIndex: index, secondsLeftInStep: left, pourTo: pourTo, isFinished: false)
    }

    /// Seconds from the start at which step `index` begins.
    public func start(of index: Int) -> Int { starts.indices.contains(index) ? starts[index] : totalSeconds }
}
