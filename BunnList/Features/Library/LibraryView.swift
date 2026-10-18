import SwiftUI

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case tried = "جربتها", favorites = "المفضلة", wish = "ودي أجرب"
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filter: LibraryFilter = .tried
    private var coffees: [CoffeeLot] {
        store.state.coffees.filter { coffee in
            switch filter {
            case .tried: return store.state.hasTried(coffee.id)
            case .favorites: return store.state.libraryEntry(for: coffee.id).isFavorite
            case .wish: return store.state.libraryEntry(for: coffee.id).wantsToTry
            }
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                DemoNotice()
                Picker("قسم المكتبة", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
                }.pickerStyle(.menu)
                Text(filter.rawValue).font(.title2.bold())
                ForEach(coffees) { coffee in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink { CoffeeDetailView(coffeeID: coffee.id) } label: { CoffeeCard(coffee: coffee) }.buttonStyle(.plain)
                        if filter == .tried {
                            ForEach(store.state.experiences.filter { $0.coffeeID == coffee.id && $0.ownerID == store.state.localUserID }) { experience in
                                NavigationLink { ExperienceDetailView(experienceID: experience.id) } label: {
                                    Label("تجربتي: \(experience.method.title) · \(experience.experiencedAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "cup.and.saucer")
                                }.font(.subheadline).padding(.horizontal, 8)
                            }
                        }
                    }
                }
                if coffees.isEmpty {
                    ContentUnavailableView("مكتبتك تنتظر قهوتك", systemImage: "books.vertical", description: Text("أضف محصولًا من صفحته إلى المفضلة أو ودي أجرب. تظهر جربتها تلقائيًا بعد نشر تجربة."))
                }
            }.padding()
        }.background(Brand.background).navigationTitle("مكتبتي")
    }
}
