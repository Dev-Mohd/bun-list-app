import BunnListCore
import SwiftUI

/// One slice of the signed-in user's collection (owned, favorites, tried or the
/// wishlist) as bag cards; tapping one opens the coffee.
@MainActor
struct FilteredCollectionView: View {
    let filter: CollectionSlice

    @EnvironmentObject private var auth: AuthModel
    @State private var items: [RemoteCollectionItem]?
    @State private var failed = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if let items {
                let shown = items.filter(filter.includes)
                if shown.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "cup.and.saucer", description: Text(emptyHint))
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(shown) { item in
                            NavigationLink(value: item.slug) { CollectionCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            } else if failed {
                ContentUnavailableView("تعذّر التحميل", systemImage: "wifi.exclamationmark").padding(.top, 60)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var emptyTitle: String {
        switch filter {
        case .owned: return "مجموعتك فاضية"
        case .favorite: return "ما عندك مفضّلة بعد"
        case .wantsToTry: return "قائمة الأمنيات فاضية"
        case .tried: return "ما جرّبت شي بعد"
        }
    }

    private var emptyHint: String {
        "افتح أي قهوة من «اكتشف» وعلّمها، أو امسح كيس من تبويب «مسح»."
    }

    private func load() async {
        failed = false
        do {
            items = try await auth.withToken { try await client.fetchCollection(accessToken: $0) }
        } catch {
            failed = true
        }
    }
}

/// A collection entry as a card: the bag on cream, then name, roaster and origin.
private struct CollectionCard: View {
    let item: RemoteCollectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LotPhotoWell(imageUrl: item.imageUrl, notes: [], roaster: item.roasterNameAr, name: item.nameAr,
                         origin: item.originNameAr, originCode: item.originCode)
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(item.nameAr).font(.subheadline.bold()).lineLimit(1)
            Text(item.roasterNameAr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let origin = item.originNameAr {
                Label(origin, systemImage: "globe").font(.caption2).foregroundStyle(Brand.olive).lineLimit(1)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
