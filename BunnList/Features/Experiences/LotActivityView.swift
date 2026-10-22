import BunnListCore
import SwiftUI

/// Per-lot activity: brew-method participation, published experiences, and the owner's own
/// experiences and recipes for this lot, with entry points to add each.
struct LotActivityView: View {
    @EnvironmentObject private var model: AppModel
    let lotID: LotID
    @State private var addingExperience = false
    @State private var editingRecipe: ClientID?
    @State private var creatingRecipe = false

    var body: some View {
        let catalog = model.catalog
        let lot = catalog?.lot(lotID)
        List {
            if let lot, let catalog {
                Section { Text(LotText.title(lot, in: catalog)).font(.headline).foregroundStyle(Brand.ink) }
            }

            let participants = model.brewParticipants(for: lotID)
            if !participants.isEmpty {
                Section("طرق التحضير") {
                    ForEach(participants, id: \.method.code) { row in
                        LabeledContent(row.method.nameAr, value: "\(row.people.formatted()) شخص")
                    }
                    Text("عدد الأشخاص لكل طريقة؛ قد يجرّب الشخص أكثر من طريقة، فالمجموع لا يساوي عدد الناس.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    addingExperience = true
                } label: {
                    Label("أضف تجربة تحضير", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("add-experience")
            }

            experienceList

            Section {
                Button { creatingRecipe = true } label: { Label("وصفة جديدة", systemImage: "list.bullet.rectangle") }
                    .accessibilityIdentifier("add-recipe")
                ForEach(model.myRecipes().filter { $0.lotID == lotID }) { recipe in
                    Button { editingRecipe = recipe.clientID } label: { RecipeRow(recipe: recipe) }
                }
            } header: {
                Text("وصفاتي لهذا المحصول")
            }
        }
        .navigationTitle("التجارب والوصفات")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingExperience) { ExperienceEditor(lotID: lotID) }
        .sheet(isPresented: $creatingRecipe) { RecipeEditor(lotID: lotID) }
        .sheet(item: Binding(get: { editingRecipe.map(IdentifiedClientID.init) },
                             set: { editingRecipe = $0?.id })) { wrapped in
            RecipeEditor(lotID: lotID, existing: wrapped.id)
        }
    }

    @ViewBuilder
    private var experienceList: some View {
        let mine = model.myExperiences(for: lotID)
        let othersCount = max(0, model.experiences(for: lotID).count - mine.count)
        Section {
            if mine.isEmpty {
                Text("لم تضف تجربة بعد.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(mine) { exp in
                    ExperienceRow(experience: exp)
                        .swipeActions {
                            Button("حذف", role: .destructive) { model.setExperienceLifecycle(exp.clientID, to: .deleted) }
                            Button(exp.lifecycle.isPubliclyVisible ? "إخفاء" : "نشر") {
                                model.setExperienceLifecycle(exp.clientID, to: exp.lifecycle.isPubliclyVisible ? .unpublished : .published)
                            }
                        }
                }
            }
        } header: {
            Text("تجاربي")
        } footer: {
            if othersCount > 0 { Text("و\(othersCount.formatted()) تجربة من آخرين.") }
        }
    }
}

private struct IdentifiedClientID: Identifiable { let id: ClientID }

struct ExperienceRow: View {
    let experience: BrewExperience
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ReferenceCodes.brewMethod(experience.methodCode)?.nameAr ?? experience.methodCode)
                    .font(.subheadline).foregroundStyle(Brand.olive)
                Spacer(minLength: 8)
                StarsDisplay(value: experience.stars)
            }
            if !experience.note.isEmpty { Text(experience.note).font(.body).foregroundStyle(Brand.ink).lineLimit(3) }
            HStack(spacing: 8) {
                Text(experience.brewedAt.formatted(date: .abbreviated, time: .omitted))
                if !experience.lifecycle.isPubliclyVisible { Text("· مسحوبة").foregroundStyle(.secondary) }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recipe.title.isEmpty ? "وصفة بلا عنوان" : recipe.title).font(.headline).foregroundStyle(Brand.ink)
            HStack(spacing: 8) {
                Text(ReferenceCodes.brewMethod(recipe.methodCode)?.nameAr ?? recipe.methodCode)
                Text(recipe.temperature == .iced ? "مثلج" : "ساخن")
                Text(recipe.lifecycle.lifecycle == .published ? "منشورة" : "مسودة").foregroundStyle(.secondary)
            }
            .font(.caption).foregroundStyle(Brand.brown)
        }
        .padding(.vertical, 2)
    }
}
