import BunnListCore
import SwiftUI

/// "مجموعتي": the coffees saved to the account, as bag cards, narrowed by
/// لديّ / جرّبته / مفضّل / ودّي أجرّب and by name. Needs an account.
struct CollectionView: View {
    private enum Shelf: String, CaseIterable, Identifiable {
        case all = "الكل", owned = "لديّ", tried = "جرّبته", favorite = "مفضّل", wantsToTry = "ودّي أجرّب"
        var id: Self { self }

        func includes(_ item: RemoteCollectionItem) -> Bool {
            switch self {
            case .all: return true
            case .owned: return item.owned
            case .tried: return item.tried
            case .favorite: return item.favorite
            case .wantsToTry: return item.wantsToTry
            }
        }
    }

    @Binding var tab: AppTab
    @EnvironmentObject private var auth: AuthModel
    @State private var shelf = Shelf.all
    @State private var query = ""
    @State private var items: [RemoteCollectionItem]?
    @State private var failed = false
    @State private var showSignIn = false
    @State private var showScan = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var visible: [RemoteCollectionItem] {
        let tokens = TextNormalizer.tokens(query)
        return (items ?? []).filter(shelf.includes).filter { item in
            let text = TextNormalizer.normalize("\(item.nameAr) \(item.roasterNameAr) \(item.originNameAr ?? "")")
            return tokens.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    ContentUnavailableView {
                        Label("مجموعتك تنحفظ في حسابك", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("سجّل الدخول وابدأ تجمع القهوات اللي جرّبتها والقهوات اللي ودّك تجرّبها.")
                    } actions: {
                        Button("سجّل الدخول") { showSignIn = true }.buttonStyle(.borderedProminent).tint(Brand.ink).foregroundStyle(Brand.background)
                    }
                } else if items != nil {
                    content
                } else if failed {
                    ContentUnavailableView {
                        Label("تعذّر تحميل مجموعتك", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("إعادة المحاولة") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.background.ignoresSafeArea())
            .navigationTitle("مجموعتي")
            .searchable(text: $query, prompt: "ابحث في مجموعتك")
            .refreshable { await load() }
            .task(id: auth.isSignedIn) { await load() }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .sheet(isPresented: $showScan) { AIBagScanView().environmentObject(auth) }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Shelf.allCases) { option in
                            let count = (items ?? []).filter(option.includes).count
                            Button { shelf = option } label: {
                                Text("\(option.rawValue) \(count.formatted())")
                                    .font(.subheadline.weight(shelf == option ? .semibold : .regular))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(shelf == option ? Brand.background : Brand.ink)
                                    .background(shelf == option ? Brand.ink : Color(.secondarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("collection-shelf-\(option.rawValue)")
                        }
                    }
                    .padding(.horizontal)
                }

                if visible.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "ما فيه شي هنا للحين" : "ما لقينا شي", systemImage: "cup.and.saucer")
                    } description: {
                        Text(query.isEmpty ? "امسح كيس أو دوّر قهوة وعلّمها بـ «لديّ» أو «مفضّل»." : "جرّب كلمة ثانية.")
                    } actions: {
                        if query.isEmpty {
                            Button("امسح كيس") { showScan = true }.buttonStyle(.borderedProminent).tint(Brand.ink).foregroundStyle(Brand.background)
                        }
                    }
                    .padding(.top, 30)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(visible) { item in
                            NavigationLink { LiveLotDetailView(slug: item.slug) } label: { CollectionCard(item: item) }
                                .buttonStyle(CardPressStyle())
                                .cardScrollIn()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func load() async {
        guard auth.isSignedIn else { items = nil; return }
        failed = false
        do {
            items = try await auth.withToken { try await client.fetchCollection(accessToken: $0) }
        } catch {
            if items == nil { failed = true }
        }
    }
}

private struct CollectionCard: View {
    let item: RemoteCollectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LotPhotoWell(imageUrl: item.imageUrl, notes: [], roaster: item.roasterNameAr, name: item.nameAr,
                         origin: item.originNameAr, originCode: item.originCode)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(item.nameAr).font(.subheadline.bold()).lineLimit(1)
            Text(item.roasterNameAr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                if item.owned { Image(systemName: "checkmark.circle.fill") }
                if item.tried { Image(systemName: "cup.and.saucer.fill") }
                if item.favorite { Image(systemName: "heart.fill") }
                if item.wantsToTry { Image(systemName: "bookmark.fill") }
            }
            .font(.caption).foregroundStyle(Brand.olive)
        }
        .accessibilityElement(children: .combine)
        .lotQuickActions(slug: item.slug, name: item.nameAr, roaster: item.roasterNameAr, imageUrl: item.imageUrl,
                         notes: [], origin: item.originNameAr, originCode: item.originCode,
                         known: RemoteCollectionFlags(owned: item.owned, favorite: item.favorite,
                                                      wantsToTry: item.wantsToTry, tried: item.tried))
    }
}
