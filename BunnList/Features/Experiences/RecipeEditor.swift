import BunnListCore
import SwiftUI

/// Create or edit a recipe. Drafts always save; publishing is gated on validation. Numeric fields use
/// the locale bridge so Arabic and Western digits (and a comma decimal on comma-locale devices) parse
/// to the same value. The cumulative water total is shown live.
struct RecipeEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let lotID: LotID?
    var existing: ClientID?

    @State private var clientID = ClientID()
    @State private var title = ""
    @State private var methodCode = "V60"
    @State private var temperature: BrewTemperature = .hot
    @State private var dose = ""
    @State private var hotWater = ""
    @State private var ice = ""
    @State private var yield = ""
    @State private var waterTemp = ""
    @State private var grinder = ""
    @State private var grindSetting = ""
    @State private var notes = ""
    @State private var steps: [StepDraft] = [StepDraft(kind: .bloom), StepDraft(kind: .pour)]
    @State private var publishProblems: [RecipeProblem] = []
    @State private var loaded = false

    private var isEspresso: Bool { methodCode == "ESPRESSO" }

    var body: some View {
        NavigationStack {
            Form {
                Section("الوصفة") {
                    TextField("العنوان", text: $title).accessibilityIdentifier("recipe-title")
                    Picker("الطريقة", selection: $methodCode) {
                        ForEach(ReferenceCodes.brewMethods, id: \.code) { Text($0.nameAr).tag($0.code) }
                    }
                    Picker("الحرارة", selection: $temperature) {
                        Text("ساخن").tag(BrewTemperature.hot)
                        Text("مثلج").tag(BrewTemperature.iced)
                    }.pickerStyle(.segmented)
                }

                Section("المقادير") {
                    numberField("البن (غرام)", text: $dose)
                    if isEspresso {
                        numberField("الناتج (غرام)", text: $yield)
                    } else {
                        numberField("الماء الساخن (غرام)", text: $hotWater)
                        if temperature == .iced { numberField("الثلج (غرام)", text: $ice) }
                    }
                    numberField("حرارة الماء (°م)", text: $waterTemp)
                    TextField("المطحنة", text: $grinder)
                    TextField("درجة الطحن", text: $grindSetting)
                }

                if !isEspresso {
                    stepsSection
                }

                Section("ملاحظات") {
                    TextEditor(text: $notes).frame(minHeight: 70)
                }

                if !publishProblems.isEmpty {
                    Section {
                        ForEach(publishProblems, id: \.self) { problem in
                            Label(message(for: problem), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    } header: { Text("لا يمكن النشر بعد") }
                }
            }
            .navigationTitle(existing == nil ? "وصفة جديدة" : "تعديل وصفة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { saveDraftAndDismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("نشر") { publish() }.accessibilityIdentifier("recipe-publish")
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepsSection: some View {
        Section {
            ForEach($steps) { $step in
                VStack(alignment: .leading, spacing: 6) {
                    Picker("النوع", selection: $step.kind) {
                        Text("تفتح").tag(RecipeStepKind.bloom)
                        Text("صب").tag(RecipeStepKind.pour)
                        Text("انتظار").tag(RecipeStepKind.wait)
                        Text("تدوير").tag(RecipeStepKind.swirl)
                        Text("تقديم").tag(RecipeStepKind.serve)
                    }.pickerStyle(.menu)
                    if step.kind.addsWater {
                        numberField("ماء مضاف (غرام)", text: $step.water)
                    }
                    TextField("ملاحظة الخطوة", text: $step.note)
                }
            }
            .onDelete { steps.remove(atOffsets: $0) }
            Button("أضف خطوة") { steps.append(StepDraft(kind: .pour)) }
            let cumulative = buildRecipe().cumulativeWaterGrams().last?.string
            if let cumulative { Text("إجمالي ماء الصب: \(cumulative) غرام").font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("الخطوات")
        } footer: {
            Text("ماء الصب يُجمع من خطوات التفتح والصب، ولازم يطابق الماء الساخن. الانتظار والتدوير لا يضيفان ماءً.")
        }
    }

    // MARK: Build / actions

    private func parsed(_ text: String, _ policy: NumericFieldPolicy) -> NormalizedDecimal? {
        (try? NumericLocaleBridge.parse(text, policy: policy)) ?? nil
    }

    private func buildRecipe() -> Recipe {
        let doseP = NumericFieldPolicy.decimal(maxIntegerDigits: 3, maxFractionDigits: 1, minimum: 0)
        let waterP = NumericFieldPolicy.decimal(maxIntegerDigits: 4, maxFractionDigits: 1, minimum: 0)
        let tempP = NumericFieldPolicy.decimal(maxIntegerDigits: 3, maxFractionDigits: 1, minimum: 0)
        let recipeSteps = isEspresso ? [] : steps.map { draft -> RecipeStep in
            RecipeStep(kind: draft.kind, addedWaterGrams: draft.kind.addsWater ? parsed(draft.water, waterP) : nil,
                       seconds: nil, note: draft.note)
        }
        return Recipe(clientID: clientID, owner: model.owner, title: title, methodCode: methodCode,
                      temperature: temperature, lotID: lotID, doseGrams: parsed(dose, doseP),
                      hotWaterGrams: isEspresso ? nil : parsed(hotWater, waterP),
                      iceGrams: (!isEspresso && temperature == .iced) ? parsed(ice, waterP) : nil,
                      yieldGrams: isEspresso ? parsed(yield, doseP) : nil,
                      waterTempC: parsed(waterTemp, tempP), grinder: grinder, grindSetting: grindSetting,
                      notes: notes, steps: recipeSteps, now: Date())
    }

    private func saveDraftAndDismiss() {
        _ = model.saveRecipeDraft(buildRecipe())
        dismiss()
    }

    private func publish() {
        let id = model.saveRecipeDraft(buildRecipe())
        guard let id else { return }
        let problems = model.publishRecipe(id)
        publishProblems = problems
        if problems.isEmpty { dismiss() }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let existing, let recipe = model.recipe(existing) else { return }
        clientID = recipe.clientID
        title = recipe.title
        methodCode = recipe.methodCode
        temperature = recipe.temperature
        dose = recipe.doseGrams?.string ?? ""
        hotWater = recipe.hotWaterGrams?.string ?? ""
        ice = recipe.iceGrams?.string ?? ""
        yield = recipe.yieldGrams?.string ?? ""
        waterTemp = recipe.waterTempC?.string ?? ""
        grinder = recipe.grinder
        grindSetting = recipe.grindSetting
        notes = recipe.notes
        if !recipe.steps.isEmpty {
            steps = recipe.steps.map { StepDraft(kind: $0.kind, water: $0.addedWaterGrams?.string ?? "", note: $0.note) }
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
        }
    }

    private func message(for problem: RecipeProblem) -> String {
        switch problem {
        case .missingTitle: return "أضف عنوانًا."
        case .missingMethod: return "اختر طريقة تحضير."
        case .missingHotWater: return "أدخل كمية الماء الساخن."
        case .pourSumDoesNotMatchHotWater: return "مجموع الصبات لا يطابق الماء الساخن."
        case .negativeOrZeroWater: return "كمية ماء خطوة غير صالحة."
        case .missingEspressoDose: return "أدخل جرعة البن."
        case .missingEspressoYield: return "أدخل وزن الناتج."
        case .waterOnNonPourStep: return "خطوة انتظار/تدوير لا تأخذ ماءً."
        }
    }
}

private struct StepDraft: Identifiable {
    let id = UUID()
    var kind: RecipeStepKind
    var water = ""
    var note = ""
}
