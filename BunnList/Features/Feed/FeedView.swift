import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var composer: Composer
    @Binding var publishedID: UUID?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                BrandHeading()
                DemoNotice()
                if let id = publishedID {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("حُفظت تجربتك على هذا الجهاز", systemImage: "checkmark.circle.fill").font(.headline)
                        NavigationLink("عرض التجربة المحفوظة") { ExperienceDetailView(experienceID: id) }
                        Button("إخفاء التنبيه") { publishedID = nil }.font(.caption)
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.olive.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
                if store.state.draft != nil {
                    Button { composer.open(store: store) } label: {
                        Label("متابعة مسودتك المحفوظة", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.bordered)
                }
                Text("تجارب المجتمع التجريبي").font(.title2.bold()).foregroundStyle(Brand.ink)
                Text("أسماء ومحاصيل توضيحية؛ لا اتصال بمجتمع حقيقي في هذه النسخة.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.state.experiences.sorted { $0.createdAt > $1.createdAt }) { experience in
                    NavigationLink { ExperienceDetailView(experienceID: experience.id) } label: {
                        ExperienceCard(experience: experience)
                    }.buttonStyle(.plain)
                }
                if store.state.experiences.isEmpty {
                    ContentUnavailableView("لا توجد تجارب", systemImage: "cup.and.saucer", description: Text("أضف تجربتك الأولى من الشريط السفلي."))
                }
            }.padding()
        }.background(Brand.background).navigationTitle("الرئيسية").navigationBarTitleDisplayMode(.inline)
    }
}
