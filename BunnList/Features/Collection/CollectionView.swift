import BunnListCore
import SwiftUI

enum CollectionFilter: String, CaseIterable, Identifiable {
    case all = "الكل"
    case owned = "لديّ"
    case tried = "جربته"
    case favorite = "مفضل"
    case wantsToTry = "ودي أجرب"

    var id: Self { self }

    func includes(_ entry: CollectionEntry) -> Bool {
        switch self {
        case .all: return entry.isActive
        case .owned: return entry.isOwned
        case .tried: return entry.isTried
        case .favorite: return entry.isFavorite
        case .wantsToTry: return entry.wantsToTry
        }
    }
}

struct CollectionView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthModel
    @State private var filter: CollectionFilter = .all
    @State private var query = ""
    @State private var serverItems: [RemoteCollectionItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if let catalog = model.catalog {
                    content(catalog)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("مجموعتي")
            .searchable(text: $query, prompt: "ابحث في مجموعتك")
            .navigationDestination(for: ProductID.self) { ProductDetailView(productID: $0) }
            .navigationDestination(for: String.self) { LiveLotDetailView(slug: $0) }
            .refreshable { await loadServerCollection() }
            .task { await loadServerCollection() }
            .onChange(of: auth.isSignedIn) { _, _ in Task { await loadServerCollection() } }
        }
    }

    private func content(_ catalog: Catalog) -> some View {
        let entries = visibleEntries(catalog)
        return List {
            if auth.isSignedIn {
                Section("محفوظة في حسابك") {
                    if serverItems.isEmpty {
                        Text("لم تحفظ محاصيل من «محاصيل مباشرة» بعد. علّم قهوة بـ «لديّ» أو «مفضّل».")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(serverItems) { item in
                            NavigationLink(value: item.slug) { ServerCollectionRow(item: item) }
                        }
                    }
                }
            }
            Section {
                ViewThatFits(in: .horizontal) {
                    filterPicker.pickerStyle(.segmented)
                    filterPicker.pickerStyle(.menu)
                }
            } header: {
                Text("على هذا الجهاز (تجريبي)")
            } footer: {
                Text("محفوظة على هذا الجهاز كزائر. حذف التطبيق يحذفها.")
            }
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "لا شيء هنا بعد" : "لا نتائج", systemImage: "square.stack.3d.up")
                } description: {
                    Text(query.isEmpty ? "أضف محاصيل من «اكتشف» أو «مسح»." : "جرّب كلمة أخرى.")
                }
            } else {
                Section("حسب تاريخ الإضافة") {
                    ForEach(entries) { entry in
                        if let lot = catalog.lot(entry.lotID) {
                            NavigationLink(value: lot.productID) { CollectionRow(entry: entry, lot: lot, catalog: catalog) }
                        }
                    }
                }
            }
        }
    }

    private var filterPicker: some View {
        Picker("عرض", selection: $filter) {
            ForEach(CollectionFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        .accessibilityIdentifier("collection-filter")
    }

    private func visibleEntries(_ catalog: Catalog) -> [CollectionEntry] {
        let tokens = TextNormalizer.tokens(query)
        return model.book.activeEntries(owner: model.owner)
            .filter(filter.includes)
            .filter { entry in
                guard !tokens.isEmpty, let lot = catalog.lot(entry.lotID), let product = catalog.product(lot.productID) else {
                    return tokens.isEmpty
                }
                let text = TextNormalizer.normalize([product.nameAr, product.nameEn ?? "", LotText.season(lot),
                                                     LotText.roaster(product, in: catalog)].joined(separator: " "))
                return tokens.allSatisfy { text.contains($0) }
            }
            .sorted { ($0.firstCollectedAt ?? $0.createdAt) > ($1.firstCollectedAt ?? $1.createdAt) }
    }

    private func loadServerCollection() async {
        guard auth.isSignedIn, let token = auth.currentAccessToken() else { serverItems = []; return }
        let client = CatalogAPIClient(transport: URLSessionTransport())
        do {
            serverItems = try await client.fetchCollection(accessToken: token)
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken() {
                serverItems = (try? await client.fetchCollection(accessToken: fresh)) ?? serverItems
            }
        } catch {
            // keep what we have; not fatal
        }
    }
}

private struct ServerCollectionRow: View {
    let item: RemoteCollectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.nameAr).font(.headline).foregroundStyle(Brand.ink)
            Text(item.roasterNameAr).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if item.owned { Label("لديّ", systemImage: "checkmark.circle") }
                if item.tried { Label("جربته", systemImage: "cup.and.saucer") }
                if item.favorite { Label("مفضل", systemImage: "heart") }
                if item.wantsToTry { Label("ودي أجرب", systemImage: "bookmark") }
            }
            .font(.caption).foregroundStyle(Brand.olive)
        }
        .padding(.vertical, 4)
    }
}

private struct CollectionRow: View {
    let entry: CollectionEntry
    let lot: CoffeeLot
    let catalog: Catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(catalog.product(lot.productID)?.nameAr ?? "محصول").font(.headline).foregroundStyle(Brand.ink)
            Text("\(LotText.season(lot)) · \(catalog.product(lot.productID).map { LotText.roaster($0, in: catalog) } ?? "")")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if entry.isOwned { Label("لديّ", systemImage: "checkmark.circle") }
                if entry.isTried { Label("جربته", systemImage: "cup.and.saucer") }
                if entry.isFavorite { Label("مفضل", systemImage: "heart") }
                if entry.wantsToTry { Label("ودي أجرب", systemImage: "bookmark") }
            }
            .font(.caption).foregroundStyle(Brand.olive)
            Text("أضيف \((entry.firstCollectedAt ?? entry.createdAt).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
