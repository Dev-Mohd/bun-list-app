import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                DemoNotice()
                Text("محصولك القادم يبدأ من هنا").font(.title2.bold()).foregroundStyle(Brand.ink)
                Text("ابحث في ثلاثة محاصيل توضيحية بالاسم أو المحمصة.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(store.state.search(query)) { coffee in
                    NavigationLink { CoffeeDetailView(coffeeID: coffee.id) } label: { CoffeeCard(coffee: coffee) }
                        .buttonStyle(.plain).accessibilityIdentifier("coffee-card-\(coffee.id)")
                }
                if store.state.search(query).isEmpty {
                    ContentUnavailableView.search(text: query)
                    Text("إضافة المحاصيل غير متاحة في هذه النسخة المحلية.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding()
        }.background(Brand.background).navigationTitle("اكتشف")
            .searchable(text: $query, prompt: "اسم المحصول أو المحمصة")
    }
}

struct CoffeeDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var composer: Composer
    let coffeeID: String
    @State private var rating = 0
    @State private var ratingMessage: String?
    var body: some View {
        Group {
            if let coffee = store.state.coffee(coffeeID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        DemoNotice()
                        CoffeeCard(coffee: coffee)
                        VStack(alignment: .leading, spacing: 8) {
                            if let origin = coffee.origin { Label(origin, systemImage: "globe") }
                            if let process = coffee.process { Label("المعالجة: \(process)", systemImage: "leaf") }
                        }.font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            var draft = ExperienceDraft()
                            draft.coffeeID = coffeeID
                            composer.open(draft, store: store)
                        } label: {
                            Label("إضافة تجربة لهذا المحصول", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("compose-from-coffee")
                        libraryControls
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("تقييم المحصول").font(.title3.bold())
                            Text("مساهمة واحدة لحسابك، ويمكن تحديثها. نجوم تجارب التحضير لا تغيّر هذا المتوسط.")
                                .font(.caption).foregroundStyle(.secondary)
                            StarPicker(value: $rating, label: "تقييمك للمحصول")
                            Button("حفظ تقييم المحصول على الجهاز") {
                                do {
                                    try store.mutate { try $0.rateCoffee(coffeeID, stars: rating) }
                                    ratingMessage = "حُدّث تقييمك؛ لم يُضف صوت مكرر."
                                } catch { ratingMessage = error.localizedDescription }
                            }.buttonStyle(.bordered).disabled(rating == 0)
                            if let ratingMessage { Text(ratingMessage).font(.caption).accessibilityAddTraits(.updatesFrequently) }
                        }
                        Divider()
                        Text("تجارب هذا المحصول").font(.title2.bold())
                        ForEach(store.state.experiences.filter { $0.coffeeID == coffeeID }.sorted { $0.createdAt > $1.createdAt }) { experience in
                            NavigationLink { ExperienceDetailView(experienceID: experience.id) } label: {
                                ExperienceCard(experience: experience)
                            }.buttonStyle(.plain)
                        }
                        if !store.state.experiences.contains(where: { $0.coffeeID == coffeeID }) {
                            Text("لا توجد تجارب بعد. شارك أول تجربة محلية.").foregroundStyle(.secondary)
                        }
                    }.padding()
                }.background(Brand.background).navigationTitle(coffee.name).navigationBarTitleDisplayMode(.inline)
            } else { ContentUnavailableView("المحصول غير موجود", systemImage: "leaf") }
        }.onAppear {
            rating = store.state.ratings.first { $0.userID == store.state.localUserID && $0.coffeeID == coffeeID }?.stars ?? 0
        }
    }

    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            let entry = store.state.libraryEntry(for: coffeeID)
            Button { store.perform { try $0.toggleLibrary(coffeeID, favorite: true) } } label: {
                Label(entry.isFavorite ? "إزالة من المفضلة" : "أضف إلى المفضلة", systemImage: entry.isFavorite ? "heart.fill" : "heart")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered)
            Button { store.perform { try $0.toggleLibrary(coffeeID, favorite: false) } } label: {
                Label(entry.wantsToTry ? "إزالة من ودي أجرب" : "ودي أجرب", systemImage: entry.wantsToTry ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered)
            if store.state.hasTried(coffeeID) { Label("جربتها — لديك تجربة لهذا المحصول", systemImage: "checkmark.circle").font(.caption) }
        }
    }
}
