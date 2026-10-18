import SwiftUI

struct ExperienceDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var composer: Composer
    @Environment(\.dismiss) private var dismiss
    let experienceID: UUID
    @State private var confirmsDelete = false
    var body: some View {
        Group {
            if let experience = store.state.experiences.first(where: { $0.id == experienceID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DemoNotice()
                        ExperienceCard(experience: experience)
                        NavigationLink {
                            ProfileView(profileID: experience.ownerID)
                        } label: {
                            Label("ملف \(store.state.profile(experience.ownerID)?.displayName ?? "الناشر")", systemImage: "person.crop.circle")
                        }
                        NavigationLink { CoffeeDetailView(coffeeID: experience.coffeeID) } label: {
                            Label("صفحة المحصول وتقييمه المستقل", systemImage: "leaf")
                        }
                        if !experience.note.isEmpty {
                            Text("ملاحظة التجربة").font(.headline)
                            Text(experience.note).textSelection(.enabled)
                        }
                        Divider()
                        Text("وصفة \(experience.method.title)").font(.title3.bold())
                        recipeRows(experience)
                        if let originalID = experience.originalExperienceID {
                            if store.state.experiences.contains(where: { $0.id == originalID }) {
                                NavigationLink("مستوحاة من هذه التجربة") { ExperienceDetailView(experienceID: originalID) }
                            } else { Text("نُسخت الوصفة من تجربة لم تعد متاحة.").font(.caption).foregroundStyle(.secondary) }
                        }
                        Button {
                            composer.open(.copyingRecipe(experience), store: store)
                        } label: {
                            Label("تكرار الوصفة في مسودة جديدة", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Text("تُنسخ الوصفة والمحصول والطريقة فقط. أضف تقييمك وملاحظتك قبل نشر تجربة جديدة.")
                            .font(.caption).foregroundStyle(.secondary)
                        if experience.ownerID == store.state.localUserID {
                            Divider()
                            Button("تعديل تجربتي") { composer.open(.editing(experience), store: store) }.buttonStyle(.bordered)
                            Button("حذف تجربتي", role: .destructive) { confirmsDelete = true }.buttonStyle(.bordered)
                        }
                    }.padding()
                }.background(Brand.background)
                    .confirmationDialog("حذف هذه التجربة؟", isPresented: $confirmsDelete, titleVisibility: .visible) {
                        Button("حذف التجربة", role: .destructive) {
                            do {
                                try store.mutate { try $0.deleteExperience(experienceID) }
                                dismiss()
                            } catch { store.error = error.localizedDescription }
                        }
                        Button("إلغاء", role: .cancel) {}
                    } message: { Text("لن يُحذف تقييمك المستقل للمحصول. لا يمكن التراجع عن حذف التجربة.") }
            } else { ContentUnavailableView("التجربة غير متاحة", systemImage: "cup.and.saucer") }
        }.navigationTitle("تفاصيل التجربة").navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func recipeRows(_ experience: BrewExperience) -> some View {
        let recipe = experience.recipe
        VStack(alignment: .leading, spacing: 10) {
            if let grams = recipe.coffeeGrams { Text("كمية البن: \(grams.formatted()) غ") }
            if experience.method == .filter, let grams = recipe.waterGrams { Text("كمية الماء: \(grams.formatted()) غ") }
            if experience.method == .espresso, let grams = recipe.yieldGrams { Text("ناتج الإسبريسو: \(grams.formatted()) غ") }
            if let seconds = recipe.seconds { Text("مدة التحضير: \(seconds.formatted()) ثانية") }
            if let grind = recipe.grind { Text("الطحنة: \(grind)") }
            if recipe.coffeeGrams == nil && recipe.waterGrams == nil && recipe.yieldGrams == nil && recipe.seconds == nil && recipe.grind == nil {
                Text("لم يضف الناشر معلمات للوصفة.").foregroundStyle(.secondary)
            }
        }.font(.body)
    }
}
