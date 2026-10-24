import BunnListCore
import SwiftUI

/// One recipe, read-only: summary card, coffee, parameters, grind, steps with
/// running water, and notes. The owner can edit, publish / unpublish or delete it;
/// anyone signed in can copy it into their own recipes.
@MainActor
struct RecipeDetailView: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var recipe: RemoteRecipe
    @State private var editorDraft: DraftRef?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    let onChange: (RecipeChange) -> Void

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    init(recipe: RemoteRecipe, onChange: @escaping (RecipeChange) -> Void) {
        _recipe = State(initialValue: recipe)
        self.onChange = onChange
    }

    private var draft: RecipeDraft { RecipeDraft(editing: recipe) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecipeSummaryCard(draft: draft)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                }

                section("القهوة") {
                    if let lot = recipe.lot {
                        Label("\(lot.nameAr) — \(lot.roasterNameAr)", systemImage: "leaf.fill").foregroundStyle(Brand.olive)
                    } else {
                        Text("وصفة عامة تصلح لأي قهوة.").foregroundStyle(.secondary)
                    }
                }

                section("المعاملات") {
                    row("البن", recipe.doseGrams.map { "\(RecipeText.number($0)) غ" })
                    if draft.isEspresso {
                        row("الناتج", recipe.yieldGrams.map { "\(RecipeText.number($0)) غ" })
                    } else {
                        row("الماء الساخن", recipe.hotWaterGrams.map { "\(RecipeText.number($0)) غ" })
                        if recipe.temperature == .iced { row("الثلج", recipe.iceGrams.map { "\(RecipeText.number($0)) غ" }) }
                    }
                    row("الحرارة", recipe.waterTempC.map { "\(RecipeText.number($0))°م" })
                    row("المطحنة", recipe.grinder.isEmpty ? nil : recipe.grinder)
                    row("درجة الطحن", recipe.grindSetting.isEmpty ? nil : recipe.grindSetting)
                }

                if !recipe.steps.isEmpty {
                    section("الخطوات") {
                        let cumulative = draft.cumulativeWater
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text((index + 1).formatted())
                                    .font(.subheadline.bold()).foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(RecipeText.stepKind(step.kind)).font(.headline)
                                    if !step.note.isEmpty { Text(step.note).font(.callout).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    if step.kind.addsWater {
                                        Text("\(RecipeText.number(cumulative[index]))غ").font(.subheadline.monospaced())
                                    }
                                    if let seconds = step.seconds {
                                        Text(RecipeText.duration(seconds)).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !recipe.notes.isEmpty {
                    section("ملاحظات") { Text(recipe.notes) }
                }

                Text(recipe.isMine ? "حالة الوصفة: \(RecipeText.state(recipe.state))" : "بواسطة \(recipe.authorName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle(recipe.title.isEmpty ? "وصفة" : recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { actionsMenu }
        }
        .sheet(item: $editorDraft) { ref in
            ServerRecipeEditor(draft: ref.draft) { saved in
                recipe = saved
                onChange(.saved(saved))
            }
            .environmentObject(auth)
        }
        .confirmationDialog("حذف الوصفة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف نهائيًا", role: .destructive) { Task { await change(to: .deleted) } }
        } message: {
            Text("لا يمكن التراجع عن الحذف.")
        }
    }

    @ViewBuilder
    private var actionsMenu: some View {
        if recipe.isMine {
            Menu {
                Button { editorDraft = DraftRef(draft: RecipeDraft(editing: recipe)) } label: { Label("تعديل", systemImage: "pencil") }
                switch recipe.state {
                case .draft, .unpublished:
                    Button { Task { await change(to: .published) } } label: { Label("نشر", systemImage: "paperplane") }
                case .published:
                    Button { Task { await change(to: .unpublished) } } label: { Label("إلغاء النشر", systemImage: "eye.slash") }
                case .deleted:
                    EmptyView()
                }
                Button { onChange(.copy(recipe)) } label: { Label("نسخة جديدة", systemImage: "doc.on.doc") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("حذف", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("خيارات الوصفة")
        } else if auth.isSignedIn {
            Button { onChange(.copy(recipe)) } label: { Label("انسخ لوصفاتي", systemImage: "doc.on.doc") }
        }
    }

    private func change(to state: RemoteExperience.State) async {
        errorMessage = nil
        do {
            let updated = try await auth.withToken {
                try await client.changeRecipeState(id: recipe.id, to: state, accessToken: $0)
            }
            Haptics.tap()
            if updated.state == .deleted {
                onChange(.deleted(updated.id))
                dismiss()
            } else {
                recipe = updated
                onChange(.saved(updated))
            }
        } catch APIError.unprocessable {
            errorMessage = draft.problems().first.map(RecipeText.problem) ?? "الوصفة غير مكتملة للنشر."
        } catch {
            errorMessage = "تعذّر تحديث الوصفة. حاول مجددًا."
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
                .font(.subheadline)
        }
    }
}
