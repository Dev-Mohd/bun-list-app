import SwiftUI

struct ExperienceEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExperienceDraft
    @State private var error: String?
    @State private var isSaving = false
    @State private var draftSaved = true
    let onPublished: (UUID) -> Void

    init(initial: ExperienceDraft, onPublished: @escaping (UUID) -> Void) {
        _draft = State(initialValue: initial)
        self.onPublished = onPublished
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DemoNotice()
                    Text("الناشر: \(store.state.profile(store.state.localUserID)?.displayName ?? "حسابي التجريبي")")
                        .font(.subheadline)
                    Text("التجربة المكتملة عامة في تصميم المنتج، لكنها في هذه النسخة تبقى على جهازك ولا تُرسل إلى الإنترنت. المسودة خاصة.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("أساسيات التجربة · مطلوبة") {
                    Picker("المحصول", selection: $draft.coffeeID) {
                        Text("اختر المحصول").tag(String?.none)
                        ForEach(store.state.coffees) { coffee in Text(coffee.name).tag(Optional(coffee.id)) }
                    }
                    Picker("طريقة التحضير", selection: $draft.method) {
                        Text("اختر الطريقة").tag(BrewMethod?.none)
                        ForEach(BrewMethod.allCases) { method in Text(method.title).tag(Optional(method)) }
                    }
                    .accessibilityIdentifier("brew-method")
                    StarPicker(value: $draft.stars, label: "تقييم نتيجة تجربتك")
                    Text("هذا التقييم يخص نتيجة تحضيرك، ولا يغيّر تقييم المحصول.").font(.caption).foregroundStyle(.secondary)
                    DatePicker("تاريخ التجربة", selection: $draft.experiencedAt, displayedComponents: .date)
                }
                Section("الوصفة · اختيارية") {
                    if let method = draft.method {
                        quantity("كمية البن (غ)", text: $draft.coffeeGrams)
                        if method == .filter { quantity("كمية الماء (غ)", text: $draft.waterGrams) }
                        else { quantity("ناتج الإسبريسو (غ)", text: $draft.yieldGrams) }
                        quantity("مدة التحضير (ثانية)", text: $draft.seconds)
                        TextField("ملاحظات الطحنة", text: $draft.grind, axis: .vertical)
                    } else { Text("اختر الطريقة لعرض حقول الوصفة المناسبة.").foregroundStyle(.secondary) }
                    Text("اترك القيم غير المعروفة فارغة. كل كمية مدخلة يجب أن تكون موجبة.").font(.caption).foregroundStyle(.secondary)
                }
                Section("ملاحظتك · اختيارية") {
                    TextField("كيف كانت تجربتك؟", text: $draft.note, axis: .vertical).lineLimit(3...8)
                        .accessibilityIdentifier("experience-note")
                    Text("إرفاق الصور غير متاح في هذه النسخة.").font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            .accessibilityAddTraits(.updatesFrequently)
                        Button("إعادة محاولة حفظ المسودة") { saveDraft() }
                    }
                }
                Section {
                    Button(action: publish) {
                        HStack {
                            if isSaving { ProgressView() }
                            Text(draft.editingID == nil ? "نشر التجربة للعامة — على هذا الجهاز فقط" : "حفظ تعديل التجربة — على هذا الجهاز فقط")
                                .fontWeight(.semibold)
                        }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.disabled(isSaving).accessibilityIdentifier("publish-experience")
                    Label(draftSaved ? "المسودة محفوظة على الجهاز" : "لم تُحفظ آخر التغييرات؛ أعد المحاولة قبل الإغلاق",
                          systemImage: draftSaved ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(draft.editingID == nil ? "إضافة تجربة" : "تعديل تجربتك")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("حفظ وإغلاق") {
                        if saveDraft() { dismiss() }
                    }.disabled(isSaving)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled()
            .onChange(of: draft) { _, _ in saveDraft() }
        }
    }

    private func quantity(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline)
            TextField("اختياري", text: text).keyboardType(.decimalPad).accessibilityLabel(title)
        }
    }

    @discardableResult
    private func saveDraft() -> Bool {
        do {
            try store.mutate { try $0.saveDraft(draft) }
            draftSaved = true
            return true
        } catch {
            draftSaved = false
            self.error = "تعذّر حفظ المسودة: \(error.localizedDescription)"
            return false
        }
    }

    private func publish() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // Keep even invalid input recoverable after a validation or write failure.
            try store.mutate { try $0.saveDraft(draft) }
            var savedID: UUID?
            try store.mutate { savedID = try $0.publish(draft) }
            if let savedID {
                onPublished(savedID)
                dismiss()
            }
        } catch { self.error = error.localizedDescription }
    }
}
