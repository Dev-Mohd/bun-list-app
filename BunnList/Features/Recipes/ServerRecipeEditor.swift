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
                    infoCard
                    methodCard
                    coffeeCard
                    parametersCard
                    grindCard
                    stepsCard
                    if canTogglePublish { publishCard }
                }
                .padding()
            }
            .background(Brand.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle(isNew ? "إنشاء وصفة" : "تعديل الوصفة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
            .sheet(item: $editingStep) { ref in
                if draft.steps.indices.contains(ref.index) {
                    StepEditor(step: draft.steps[ref.index], number: ref.index + 1) { updated in
                        guard draft.steps.indices.contains(ref.index) else { return }
                        if let updated { draft.steps[ref.index] = updated } else { draft.steps.remove(at: ref.index) }
                        syncHotWaterToPours()
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
                .tint(.black)
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
            HStack(spacing: 12) {
                field("المطحنة") {
                    TextField("مثال: Comandante", text: $draft.grinder).textFieldStyle(.roundedBorder)
                }
                field("الدرجة") {
                    TextField("مثال: 24", text: $draft.grindSetting).textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var stepsCard: some View {
        let cumulative = draft.cumulativeWater
        let target = draft.hotWaterGrams ?? 0
        return card("الخطوات", trailing: draft.totalSeconds > 0 ? RecipeText.duration(draft.totalSeconds) : nil) {
            if !draft.isEspresso && target > 0 {
                ProgressView(value: min(cumulative.last ?? 0, target), total: target).tint(.black)
                HStack {
                    Text("الماء التراكمي").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(RecipeText.number(cumulative.last ?? 0)) / \(RecipeText.number(target)) غ")
                        .font(.caption.monospaced())
                }
            }
            ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                Button { editingStep = StepRef(index: index) } label: {
                    StepRow(number: index + 1, step: step, cumulative: step.kind.addsWater ? cumulative[index] : nil)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([RecipeStepKind.bloom, .pour, .wait, .swirl, .serve], id: \.self) { kind in
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
                    if isBusy { ProgressView().tint(.white) } else { Image(systemName: "checkmark.circle.fill") }
                    Text(publish && canTogglePublish ? "حفظ ونشر" : "حفظ")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(blockingProblem == nil ? Color.black : Color.secondary.opacity(0.4), in: Capsule())
                .foregroundStyle(.white)
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
    let cumulative: Double?

    var body: some View {
        HStack(spacing: 12) {
            Text(number.formatted())
                .font(.headline).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.black, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(RecipeText.stepKind(step.kind)).font(.headline)
                if !step.note.isEmpty {
                    Text(step.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let cumulative { Text("\(RecipeText.number(cumulative))غ").font(.subheadline.monospaced()) }
                if let seconds = step.seconds { Text(RecipeText.duration(seconds)).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
            Image(systemName: "chevron.left").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25)))
        .contentShape(Rectangle())
    }
}

/// Edit one step. Passing nil to `onDone` deletes it.
private struct StepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: RemoteRecipeStep
    let number: Int
    let onDone: (RemoteRecipeStep?) -> Void

    init(step: RemoteRecipeStep, number: Int, onDone: @escaping (RemoteRecipeStep?) -> Void) {
        _step = State(initialValue: step)
        self.number = number
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("النوع", selection: $step.kind) {
                    ForEach([RecipeStepKind.bloom, .pour, .wait, .swirl, .serve], id: \.self) {
                        Label(RecipeText.stepKind($0), systemImage: RecipeText.stepIcon($0)).tag($0)
                    }
                }
                if step.kind.addsWater {
                    LabeledContent("الماء المضاف (غ)") {
                        TextField("50", value: Binding(
                            get: { step.addedWaterGrams ?? 0 },
                            set: { step.addedWaterGrams = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("المدة (ث)") {
                    TextField("30", value: Binding(
                        get: { step.seconds ?? 0 },
                        set: { step.seconds = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                }
                Section("ملاحظة") {
                    TextField("مثال: صب بشكل دائري من المنتصف", text: $step.note, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Button("حذف الخطوة", role: .destructive) { onDone(nil); dismiss() }
                }
            }
            .navigationTitle("الخطوة \(number.formatted())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        if !step.kind.addsWater { step.addedWaterGrams = nil }
                        onDone(step)
                        dismiss()
                    }
                }
            }
        }
    }
}
