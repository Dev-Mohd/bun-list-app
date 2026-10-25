import BunnListCore
import SwiftUI

/// Create or edit a server recipe. A live summary card on top, then the recipe's
/// info, method, coffee, parameters (dose, temperature, ratio slider), grind and
/// steps with running water. Saves as a draft, or publishes when the toggle is on
/// and the recipe is valid.
@MainActor
struct ServerRecipeEditor: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecipeDraft
    @State private var publish: Bool
    @State private var collection: [RemoteCollectionItem] = []
    @State private var showCoffeePicker = false
    @State private var editingStep: StepRef?
    @State private var isBusy = false
    @State private var errorMessage: String?
    /// Simple shows the essentials; pro opens brewer, filter, roast, grinder and pour details.
    @AppStorage("recipeProMode") private var proMode = false
    /// The viewer's own grinder, used to show converted settings.
    @AppStorage("myGrinderID") private var myGrinderID = ""
    let onSaved: (RemoteRecipe) -> Void

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    init(draft: RecipeDraft, onSaved: @escaping (RemoteRecipe) -> Void) {
        _draft = State(initialValue: draft)
        _publish = State(initialValue: draft.existingState == .published)
        self.onSaved = onSaved
    }

    private var isNew: Bool { draft.existingState == nil }
    /// A published recipe stays published on edit; unpublishing happens from its menu.
    private var canTogglePublish: Bool { draft.existingState != .published && draft.existingState != .unpublished }
    private var problems: [RecipeProblem] { draft.problems() }
    private var blockingProblem: RecipeProblem? {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingTitle }
        return publish ? problems.first : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RecipeSummaryCard(draft: draft)
                    Picker("الوضع", selection: $proMode) {
                        Text("بسيط").tag(false)
                        Text("احترافي").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("recipe-mode")
                    if isNew { presetsCard }
                    infoCard
                    methodCard
                    coffeeCard
                    parametersCard
                    grindCard
                    if proMode { waterCard }
                    stepsCard
                    if draft.isEspresso { milkCard }
                    if proMode { resultCard }
                    tipsCard
                    if canTogglePublish { publishCard }
                }
                .padding()
            }
            .background(Brand.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { saveBar }
            .brandScreen()
            .navigationTitle(isNew ? "إنشاء وصفة" : "تعديل الوصفة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
            .sheet(item: $editingStep) { ref in
                if draft.steps.indices.contains(ref.index) {
                    StepEditor(step: draft.steps[ref.index], number: ref.index + 1,
                               startAt: draft.startTimes[ref.index],
                               pourTo: draft.steps[ref.index].kind.addsWater ? draft.cumulativeWater[ref.index] : nil,
                               canMoveStart: ref.index > 0, proMode: proMode) { result in
                        apply(result, at: ref.index)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showCoffeePicker) { coffeePicker }
            .disabled(isBusy)
            .task { await loadCollection() }
        }
    }

    // MARK: Cards

    private var infoCard: some View {
        card("معلومات الوصفة") {
            field("اسم الوصفة") {
                TextField("مثال: قهوة مقطرة صباحية", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("recipe-title")
            }
            field("ملاحظات") {
                TextField("ملاحظات اختيارية عن الوصفة…", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var methodCard: some View {
        card("طريقة التحضير") {
            field("الطريقة") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ReferenceCodes.brewMethods, id: \.code) { entry in
                            ChoiceChip(title: entry.nameAr, isSelected: draft.methodCode == entry.code) {
                                setMethod(entry.code)
                            }
                        }
                    }
                }
            }
            field("النوع") {
                HStack(spacing: 8) {
                    ChoiceChip(title: "ساخن", icon: "flame.fill", isSelected: draft.temperature == .hot) {
                        setTemperature(.hot)
                    }
                    ChoiceChip(title: "مثلج", icon: "snowflake", isSelected: draft.temperature == .iced) {
                        setTemperature(.iced)
                    }
                }
            }
            if proMode {
                field("الأداة") {
                    TextField("مثال: V60 02", text: $draft.brewer).textFieldStyle(.roundedBorder)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Brewers.suggestions(for: draft.methodCode), id: \.self) { name in
                                ChoiceChip(title: name, isSelected: draft.brewer == name) { draft.brewer = name }
                            }
                        }
                    }
                }
                if !draft.isEspresso {
                    field("الفلتر") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FilterType.allCases, id: \.self) { filter in
                                    ChoiceChip(title: filter.nameAr, isSelected: draft.filterType == filter) {
                                        draft.filterType = draft.filterType == filter ? nil : filter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var coffeeCard: some View {
        card("القهوة") {
            HStack(spacing: 8) {
                ChoiceChip(title: "من مجموعتي", isSelected: draft.lot != nil) { showCoffeePicker = true }
                ChoiceChip(title: "عامة", isSelected: draft.lot == nil) { draft.lot = nil }
            }
            if let lot = draft.lot {
                Label("\(lot.nameAr) — \(lot.roasterNameAr)", systemImage: "leaf.fill")
                    .font(.subheadline).foregroundStyle(Brand.olive)
                Button("تغيير القهوة") { showCoffeePicker = true }.font(.subheadline)
            } else {
                Text("وصفة عامة تصلح لأي قهوة.").font(.caption).foregroundStyle(.secondary)
            }
            if proMode {
                field("درجة التحميص") {
                    HStack(spacing: 8) {
                        ForEach(RoastLevel.allCases, id: \.self) { roast in
                            ChoiceChip(title: roast.nameAr, isSelected: draft.roastLevel == roast) {
                                draft.roastLevel = draft.roastLevel == roast ? nil : roast
                            }
                        }
                    }
                    if let roast = draft.roastLevel, draft.waterTempC != roast.suggestedTempC, draft.methodCode != "COLD_BREW" {
                        Button("استخدم الحرارة المقترحة \(RecipeText.number(roast.suggestedTempC))°م") {
                            draft.waterTempC = roast.suggestedTempC
                        }
                        .font(.caption)
                    }
                }
                field("عمر البن من التحميص") {
                    Stepper(value: Binding(get: { draft.restDays ?? 0 }, set: { draft.restDays = $0 > 0 ? $0 : nil }),
                            in: 0...90) {
                        Text(draft.restDays.map { "\($0.formatted()) يوم" } ?? "غير محدد").monospacedDigit()
                    }
                    Text(draft.isEspresso ? "الأفضل للإسبريسو ١٠–٤٠ يوم." : "الأفضل للفلتر ٧–٣٠ يوم.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var parametersCard: some View {
        card("المعاملات") {
            HStack(spacing: 12) {
                field("البن (غ)") { numberField("15", value: $draft.doseGrams) }
                field("الحرارة (°م)") { numberField("96", value: $draft.waterTempC) }
            }
            if draft.temperature == .iced && !draft.isEspresso {
                field("الثلج (غ)") { numberField("100", value: iceBinding) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(RecipeText.ratio(draft.ratio))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                Text(draft.isEspresso ? "إسبريسو" : RecipeText.method(draft.methodCode))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("← \(RecipeText.number(draft.isEspresso ? draft.yieldGrams : draft.outputGrams))غ")
                    .font(.headline.monospaced())
            }
            Slider(value: ratioBinding, in: ratioRange, step: 0.1)
                .tint(Brand.ink)
                .foregroundStyle(Brand.background)
                .accessibilityLabel("النسبة")
                .accessibilityValue(RecipeText.ratio(draft.ratio))
            HStack {
                Text("قوي").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("خفيف").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var grindCard: some View {
        card("الطحن") {
            field("درجة الطحن") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GrindLevel.allCases, id: \.self) { level in
                            ChoiceChip(title: level.nameAr, isSelected: draft.grindLevel == level) {
                                draft.grindLevel = level
                                draft.grindMicrons = nil
                            }
                        }
                    }
                }
                if let level = draft.grindLevel {
                    Text("تناسب عادة: \(level.usedForAr)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if proMode {
                field("المطحنة") {
                    Picker("المطحنة", selection: grinderBinding) {
                        Text("اختر مطحنتك").tag("")
                        ForEach(Grinder.all) { Text($0.name).tag($0.id) }
                        Text("أخرى").tag("other")
                    }
                    .pickerStyle(.menu)
                    if grinderBinding.wrappedValue == "other" {
                        TextField("اسم المطحنة", text: $draft.grinder).textFieldStyle(.roundedBorder)
                    }
                }
                field("الإعداد (كليك / رقم)") {
                    TextField("مثال: 24", text: Binding(
                        get: { draft.grindSetting },
                        set: { text in
                            draft.grindSetting = text
                            let clicks = Double(text.replacingOccurrences(of: ",", with: "."))
                            if let grinder = Grinder.find(draft.grinderModel), grinder.micronsPerClick != nil, let clicks {
                                draft.setGrind(grinderID: grinder.id, clicks: clicks)
                                draft.grindSetting = text
                            }
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                }
                if let microns = draft.grindMicrons {
                    Label("≈ \(microns.formatted()) ميكرون · \(GrindLevel.level(forMicrons: microns).nameAr)", systemImage: "ruler")
                        .font(.caption).foregroundStyle(Brand.olive)
                    Text("أي أحد يقرأ وصفتك بيشوف الدرجة محوّلة لمطحنته (تقريبيًا).")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var waterCard: some View {
        card("الماء") {
            field("نوع الماء") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WaterType.allCases, id: \.self) { type in
                            ChoiceChip(title: type.nameAr, isSelected: draft.waterType == type) {
                                draft.waterType = draft.waterType == type ? nil : type
                            }
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                field(draft.waterType == .mineralRecipe ? "الوصفة" : "الماركة") {
                    TextField(draft.waterType == .mineralRecipe ? "مثال: Third Wave Water" : "مثال: نوفا",
                              text: $draft.waterBrand)
                        .textFieldStyle(.roundedBorder)
                }
                field("TDS (ppm)") {
                    TextField("110", value: Binding(
                        get: { draft.waterTdsPpm ?? 0 },
                        set: { draft.waterTdsPpm = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                }
            }
            Text("المكتوب على العبوة غالبًا «الأملاح الذائبة الكلية». المثالي للقهوة ٧٥–١٥٠ ppm.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var resultCard: some View {
        let typical = BrewAdvisor.typicalBeverageTds(draft.methodCode)
        return card("النتيجة (اختياري)") {
            field("TDS المشروب (٪)") {
                TextField(draft.isEspresso ? "9.5" : "1.35", value: $draft.beverageTds.orZero, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
            }
            Text("المعتاد \(typical.lowerBound.formatted())–\(typical.upperBound.formatted())٪. لمن عنده مقياس انكسار (Refractometer).")
                .font(.caption2).foregroundStyle(.secondary)
            if let ey = draft.extractionYield {
                HStack {
                    Label("نسبة الاستخلاص", systemImage: "chart.bar.fill")
                    Spacer()
                    Text("\(ey.formatted(.number.precision(.fractionLength(1))))٪")
                        .font(.headline.monospaced())
                        .foregroundStyle((18...22).contains(ey) ? Brand.olive : .orange)
                }
                Text(draft.isEspresso
                     ? "محسوبة من وزن الشوت. المثالي ١٨–٢٢٪."
                     : "تقريبية: المشروب ≈ \(RecipeText.number(draft.beverageGrams))غ بعد احتساب ما يمسكه البن (٢غ لكل غرام). المثالي ١٨–٢٢٪.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var milkCard: some View {
        card("مشروب بالحليب") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChoiceChip(title: "شوت فقط", isSelected: draft.milkDrink == nil) { draft.setMilkDrink(nil) }
                    ForEach(MilkDrink.allCases, id: \.self) { drink in
                        ChoiceChip(title: drink.nameAr, isSelected: draft.milkDrink == drink) { draft.setMilkDrink(drink) }
                    }
                }
            }
            if let drink = draft.milkDrink {
                Text(drink.textureAr).font(.caption).foregroundStyle(Brand.olive)
                field("الحليب") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MilkType.allCases, id: \.self) { type in
                                ChoiceChip(title: type.nameAr, isSelected: draft.milkType == type) {
                                    draft.milkType = draft.milkType == type ? nil : type
                                }
                            }
                        }
                    }
                }
                field("كمية الحليب (غ)") { numberField(RecipeText.number(drink.typicalMilkGrams), value: $draft.milkGrams) }
                Text("بخّر الحليب إلى ٥٥–٦٥°م؛ أسخن من كذا يفقد حلاوته.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Grinder choice: a catalog id, "other" (free-text name), or "" for none.
    private var grinderBinding: Binding<String> {
        Binding(
            get: {
                if let id = draft.grinderModel, Grinder.find(id) != nil { return id }
                return draft.grinder.isEmpty && draft.grinderModel == nil ? "" : "other"
            },
            set: { id in
                switch id {
                case "": draft.grinderModel = nil; draft.grinder = ""; draft.grindMicrons = nil
                case "other": draft.grinderModel = nil; draft.grindMicrons = nil
                default:
                    draft.grinder = Grinder.find(id)?.name ?? ""
                    let clicks = Double(draft.grindSetting.replacingOccurrences(of: ",", with: "."))
                    let text = draft.grindSetting
                    draft.setGrind(grinderID: id, clicks: clicks)
                    draft.grindSetting = text
                    myGrinderID = id
                }
            }
        )
    }

    private var stepsCard: some View {
        let cumulative = draft.cumulativeWater
        let target = draft.hotWaterGrams ?? 0
        return card("الخطوات", trailing: draft.totalSeconds > 0 ? RecipeText.duration(draft.totalSeconds) : nil) {
            if !draft.isEspresso && target > 0 {
                ProgressView(value: min(cumulative.last ?? 0, target), total: target).tint(Brand.ink)
                HStack {
                    Text("الماء التراكمي").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(RecipeText.number(cumulative.last ?? 0)) / \(RecipeText.number(target)) غ")
                        .font(.caption.monospaced())
                }
            }
            let starts = draft.startTimes
            ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                Button { editingStep = StepRef(index: index) } label: {
                    StepRow(number: index + 1, step: step, startAt: starts[index],
                            pourTo: step.kind.addsWater ? cumulative[index] : nil, proMode: proMode)
                }
                .buttonStyle(.plain)
            }
            if !draft.steps.isEmpty {
                HStack {
                    Label("ينتهي النزول عند", systemImage: "flag.checkered").font(.subheadline)
                    Spacer()
                    Stepper(value: Binding(get: { draft.totalSeconds }, set: { draft.setFinish($0) }),
                            in: min(starts.last ?? 0, 3600)...3600, step: 5) {
                        Text(RecipeText.duration(draft.totalSeconds)).font(.subheadline.monospaced())
                    }
                    .fixedSize()
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RecipeText.stepKinds, id: \.self) { kind in
                        ChoiceChip(title: RecipeText.stepKind(kind), icon: RecipeText.stepIcon(kind), isSelected: false) {
                            addStep(kind)
                        }
                    }
                }
            }
            if !draft.isEspresso && problems.contains(.pourSumDoesNotMatchHotWater) {
                Button("اجعل كمية الماء = مجموع الصبات") { syncHotWaterToPours(force: true) }
                    .font(.caption)
            }
        }
    }

    /// Proven starting points for the selected method (new recipes only).
    private var presetsCard: some View {
        let presets = BrewPreset.presets(for: draft.methodCode)
        let shown = presets.isEmpty ? BrewPreset.all : presets
        return card("ابدأ من وصفة باريستا") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shown) { preset in
                        Button {
                            withAnimation { draft.apply(preset) }
                            Haptics.tap()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(preset.nameAr, systemImage: preset.temperature == .iced ? "snowflake" : "flame.fill")
                                    .font(.subheadline.bold())
                                Text(preset.summaryAr).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                Text("الطحن: \(preset.grindAr)").font(.caption2).foregroundStyle(Brand.olive)
                            }
                            .frame(width: 190, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("preset-\(preset.id)")
                    }
                }
            }
            Text("تختار وصفة وتعدّل عليها بذوقك. اسمك وقهوتك يبقون كما هم.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tipsCard: some View {
        let tips = BrewAdvisor.tips(for: draft)
        if !tips.isEmpty {
            card("نصائح الباريستا") {
                ForEach(tips, id: \.self) { tip in
                    Label(tip.messageAr, systemImage: "lightbulb")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private var publishCard: some View {
        card(nil) {
            Toggle(isOn: $publish) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("نشر في الملف الشخصي").font(.headline)
                    Text("شارك هذه الوصفة في «استكشف» ليجرّبها غيرك.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Brand.olive)
            .accessibilityIdentifier("recipe-publish-toggle")
        }
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            } else if let blockingProblem {
                Text(RecipeText.problem(blockingProblem)).font(.caption).foregroundStyle(.secondary)
            }
            Button { Task { await save() } } label: {
                HStack {
                    if isBusy { ProgressView().tint(Brand.background) } else { Image(systemName: "checkmark.circle.fill") }
                    Text(publish && canTogglePublish ? "حفظ ونشر" : "حفظ")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(blockingProblem == nil ? Brand.ink : Color.secondary.opacity(0.4), in: Capsule())
                .foregroundStyle(Brand.background)
            }
            .buttonStyle(.plain)
            .disabled(blockingProblem != nil || isBusy)
            .accessibilityIdentifier("recipe-save")
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }

    private var coffeePicker: some View {
        NavigationStack {
            List {
                if collection.isEmpty {
                    Text("مجموعتك فاضية. أضف قهوة من «اكتشف» أولًا.").foregroundStyle(.secondary)
                }
                ForEach(collection, id: \.lotId) { item in
                    Button {
                        draft.lot = RemoteRecipeLot(slug: item.slug, nameAr: item.nameAr, roasterNameAr: item.roasterNameAr)
                        showCoffeePicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.nameAr)
                                Text(item.roasterNameAr).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draft.lot?.slug == item.slug { Image(systemName: "checkmark").foregroundStyle(Brand.olive) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .brandScreen()
            .navigationTitle("اختر قهوة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { showCoffeePicker = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Layout helpers

    private func card(_ title: String?, trailing: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack {
                    Text(title).font(.title3.bold())
                    Spacer()
                    if let trailing {
                        Label(trailing, systemImage: "clock").font(.subheadline.monospaced())
                    }
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberField(_ placeholder: String, value: Binding<Double?>) -> some View {
        TextField(placeholder, value: Binding(
            get: { value.wrappedValue ?? 0 },
            set: { value.wrappedValue = $0 > 0 ? $0 : nil }
        ), format: .number)
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
        .monospacedDigit()
    }

    // MARK: Behaviour

    private var ratioRange: ClosedRange<Double> { draft.isEspresso ? 1...4 : RecipeDraft.ratioRange }

    private var ratioBinding: Binding<Double> {
        Binding(
            get: { min(max(draft.ratio ?? (draft.isEspresso ? 2 : RecipeDraft.defaultRatio), ratioRange.lowerBound), ratioRange.upperBound) },
            set: { draft.applyRatio(($0 * 10).rounded() / 10) }
        )
    }

    /// Changing the ice keeps the total and moves the difference to the hot water.
    private var iceBinding: Binding<Double?> {
        Binding(
            get: { draft.iceGrams },
            set: { newIce in
                let ratio = draft.ratio
                draft.iceGrams = newIce
                if let ratio { draft.applyRatio(ratio) }
            }
        )
    }

    private func setMethod(_ code: String) {
        guard code != draft.methodCode else { return }
        // A new recipe switches to that method's barista recipe as a starting point.
        if isNew, let preset = BrewPreset.presets(for: code).first {
            draft.apply(preset)
            return
        }
        let wasEspresso = draft.isEspresso
        draft.methodCode = code
        if draft.isEspresso && !wasEspresso {
            draft.steps = []
            draft.temperature = .hot
            draft.doseGrams = draft.doseGrams ?? 18
            draft.applyRatio(2)
        } else if !draft.isEspresso && wasEspresso {
            draft.steps = RecipeDraft.pourOverSteps(total: 250)
            draft.hotWaterGrams = 250
        }
    }


    private func setTemperature(_ temperature: BrewTemperature) {
        let ratio = draft.ratio
        draft.temperature = temperature
        if temperature == .iced, draft.iceGrams == nil, !draft.isEspresso {
            draft.iceGrams = ((draft.hotWaterGrams ?? 250) * 0.4).rounded()
        }
        if let ratio { draft.applyRatio(ratio) }
    }

    private func apply(_ result: StepEditor.Result?, at index: Int) {
        guard draft.steps.indices.contains(index) else { return }
        guard let result else {
            draft.steps.remove(at: index)
            syncHotWaterToPours()
            return
        }
        var step = result.step
        if !step.kind.addsWater { step.addedWaterGrams = nil }
        draft.steps[index] = step
        draft.setStart(index, to: result.startAt)
        if step.kind.addsWater, let pourTo = result.pourTo { draft.setPourTo(index, grams: pourTo) }
        syncHotWaterToPours()
    }

    private func addStep(_ kind: RecipeStepKind) {
        var step = RemoteRecipeStep(kind: kind, seconds: kind == .wait ? 30 : nil)
        if kind.addsWater { step.addedWaterGrams = 50 }
        draft.steps.append(step)
        syncHotWaterToPours()
        editingStep = StepRef(index: draft.steps.count - 1)
    }

    /// After steps change, the hot water follows the pours (unless espresso).
    private func syncHotWaterToPours(force: Bool = false) {
        guard !draft.isEspresso else { return }
        let poured = draft.cumulativeWater.last ?? 0
        if force || poured > 0 { draft.hotWaterGrams = poured }
    }

    private func loadCollection() async {
        guard auth.isSignedIn else { return }
        if let items = try? await auth.withToken({ try await client.fetchCollection(accessToken: $0) }) {
            collection = items
        }
    }

    private func save() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let shouldPublish = publish && canTogglePublish
        do {
            let saved = try await auth.withToken { try await client.saveRecipe(draft, publish: shouldPublish, accessToken: $0) }
            Haptics.tap()
            onSaved(saved)
            dismiss()
        } catch APIError.unauthorized {
            errorMessage = "انتهت الجلسة. سجّل الدخول من جديد ثم أعد المحاولة."
        } catch APIError.unprocessable {
            errorMessage = "الوصفة غير مكتملة للنشر. راجع الماء والخطوات."
        } catch APIError.conflict {
            errorMessage = "هذه الوصفة حُذفت ولا يمكن تعديلها."
        } catch {
            errorMessage = "تعذّر حفظ الوصفة. تحقّق من اتصالك وحاول مجددًا."
        }
    }
}

private struct StepRef: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct StepRow: View {
    let number: Int
    let step: RemoteRecipeStep
    let startAt: Int
    let pourTo: Double?
    let proMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(number.formatted())
                .font(.headline).foregroundStyle(Brand.background)
                .frame(width: 40, height: 40)
                .background(Brand.ink, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(RecipeText.duration(startAt)).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    Text(RecipeText.stepKind(step.kind)).font(.headline)
                }
                if proMode, step.kind.addsWater, let detail = RecipeText.pourDetail(step) {
                    Text(detail).font(.caption).foregroundStyle(Brand.olive)
                }
                if !step.note.isEmpty {
                    Text(step.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let pourTo {
                Text("حتى \(RecipeText.number(pourTo))غ").font(.subheadline.monospaced().bold())
            }
            Image(systemName: "chevron.left").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25)))
        .contentShape(Rectangle())
    }
}

/// Edit one step the way a competition brew sheet reads: when it starts and the
/// scale reading to pour to. Returning nil deletes the step.
private struct StepEditor: View {
    struct Result {
        let step: RemoteRecipeStep
        let startAt: Int
        let pourTo: Double?
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: RemoteRecipeStep
    @State private var startAt: Int
    @State private var pourTo: Double
    let number: Int
    let canMoveStart: Bool
    let proMode: Bool
    let onDone: (Result?) -> Void

    init(step: RemoteRecipeStep, number: Int, startAt: Int, pourTo: Double?, canMoveStart: Bool,
         proMode: Bool, onDone: @escaping (Result?) -> Void) {
        _step = State(initialValue: step)
        _startAt = State(initialValue: startAt)
        _pourTo = State(initialValue: pourTo ?? 0)
        self.number = number
        self.canMoveStart = canMoveStart
        self.proMode = proMode
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("النوع", selection: $step.kind) {
                    ForEach(RecipeText.stepKinds, id: \.self) {
                        Label(RecipeText.stepKind($0), systemImage: RecipeText.stepIcon($0)).tag($0)
                    }
                }
                Section {
                    if canMoveStart {
                        Stepper(value: $startAt, in: 0...3600, step: 5) {
                            LabeledContent("يبدأ عند", value: RecipeText.duration(startAt)).monospacedDigit()
                        }
                    } else {
                        LabeledContent("يبدأ عند", value: RecipeText.duration(0))
                    }
                    if step.kind.addsWater {
                        LabeledContent("صب حتى (غ على الميزان)") {
                            TextField("150", value: $pourTo, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } footer: {
                    Text(step.kind.addsWater ? "اكتب قراءة الميزان في نهاية الصبة، مثل أوراق البطولات." : "خطوة بدون ماء.")
                }
                if proMode && step.kind.addsWater {
                    Section("الصبة") {
                        Picker("الطريقة", selection: $step.pourStyle) {
                            Text("—").tag(PourStyle?.none)
                            ForEach(PourStyle.allCases, id: \.self) { Text($0.nameAr).tag(Optional($0)) }
                        }
                        Picker("السرعة", selection: $step.pourSpeed) {
                            Text("—").tag(PourSpeed?.none)
                            ForEach(PourSpeed.allCases, id: \.self) { Text($0.nameAr).tag(Optional($0)) }
                        }
                    }
                }
                Section("ملاحظة") {
                    TextField("مثال: صب بشكل دائري من المنتصف", text: $step.note, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Button("حذف الخطوة", role: .destructive) { onDone(nil); dismiss() }
                }
            }
            .brandScreen()
            .navigationTitle("الخطوة \(number.formatted())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        if !step.kind.addsWater { step.pourStyle = nil; step.pourSpeed = nil }
                        onDone(Result(step: step, startAt: startAt, pourTo: step.kind.addsWater ? pourTo : nil))
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension Binding where Value == Double? {
    /// Edits an optional number in a TextField: 0 or empty clears it.
    var orZero: Binding<Double> {
        Binding<Double>(get: { wrappedValue ?? 0 }, set: { wrappedValue = $0 > 0 ? $0 : nil })
    }
}
