import BunnListCore
import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthModel
    @State private var query = ""
    @State private var filters = CatalogFilters()
    @State private var showLiveCatalog = false

    var body: some View {
        NavigationStack {
            Group {
                if let catalog = model.catalog {
                    content(catalog)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("اكتشف")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "الاسم أو المحمصة أو المنشأ أو النكهة")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLiveCatalog = true } label: {
                        Label("محاصيل مباشرة", systemImage: "cloud")
                    }
                    .accessibilityIdentifier("open-live-catalog")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let catalog = model.catalog { FilterMenu(filters: $filters, catalog: catalog) }
                }
            }
            .navigationDestination(for: ProductID.self) { ProductDetailView(productID: $0) }
            .sheet(isPresented: $showLiveCatalog) { LiveCatalogView().environmentObject(auth) }
        }
    }

    private func content(_ catalog: Catalog) -> some View {
        let results = CatalogSearch.products(in: catalog, query: query, filters: filters)
        let browsing = query.trimmingCharacters(in: .whitespaces).isEmpty && filters.isEmpty
        return List {
            Section {
                BrandHeading()
                SampleBadge(text: "\(catalog.label): أسماء ومحامص توضيحية، بلا تقييمات أو أعداد مستخدمين")
            }
            if !filters.isEmpty {
                Section {
                    Button("مسح المرشحات") { filters = CatalogFilters() }
                        .accessibilityIdentifier("clear-filters")
                }
            }
            Section(browsing ? "الدليل" : "النتائج") {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(results) { product in
                        NavigationLink(value: product.id) { ProductRow(product: product, catalog: catalog) }
                            .accessibilityIdentifier("product-\(product.id.rawValue)")
                    }
                }
            }
        }
    }
}

private struct FilterMenu: View {
    @Binding var filters: CatalogFilters
    let catalog: Catalog

    var body: some View {
        Menu {
            Picker("المحمصة", selection: $filters.roasterID) {
                Text("كل المحامص").tag(RoasterID?.none)
                ForEach(catalog.roasters) { Text($0.nameAr).tag(Optional($0.id)) }
            }
            codePicker("المنشأ", all: "كل المناشئ", selection: $filters.countryCode,
                       entries: used(\.origin.countryCodes).compactMap(ReferenceCodes.country))
            codePicker("المعالجة", all: "كل المعالجات", selection: $filters.processCode,
                       entries: used { [$0.processCode].compactMap { $0 } }.compactMap(ReferenceCodes.process))
            codePicker("النكهة", all: "كل النكهات", selection: $filters.flavorCode,
                       entries: used(\.flavorCodes).compactMap(ReferenceCodes.flavor))
            codePicker("طريقة التحضير المقترحة", all: "كل الطرق", selection: $filters.brewMethodCode,
                       entries: used(\.recommendedBrewMethods).compactMap(ReferenceCodes.brewMethod))
        } label: {
            Label("ترشيح", systemImage: filters.isEmpty ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("filters")
    }

    private func used(_ codes: (CoffeeProduct) -> [String]) -> [String] {
        Array(Set(catalog.products.flatMap(codes))).sorted()
    }

    private func codePicker(_ title: String, all: String, selection: Binding<String?>, entries: [ReferenceEntry]) -> some View {
        Picker(title, selection: selection) {
            Text(all).tag(String?.none)
            ForEach(entries, id: \.code) { Text($0.nameAr).tag(Optional($0.code)) }
        }
    }
}
