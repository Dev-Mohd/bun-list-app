import BunnListCore
import SwiftUI

/// Discover: published coffee from the server is the primary content. Search runs on
/// the server; loading, empty and error states are explicit and actionable. Demo data
/// is never shown as a fallback — it lives behind a clearly labeled "الدليل التجريبي"
/// entry in the toolbar.
struct DiscoverView: View {
    private enum Phase: Equatable {
        case loading
        case loaded([RemoteLot])
        case failed
    }

    @State private var phase: Phase = .loading
    @State private var query = ""
    @State private var searchResults: [RemoteLot]?
    @State private var isSearching = false
    @State private var showSample = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("اكتشف")
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "ابحث بالاسم أو المحمصة")
                .onSubmit(of: .search) { Task { await search() } }
                .onChange(of: query) { _, newValue in
                    if newValue.trimmingCharacters(in: .whitespaces).isEmpty { searchResults = nil }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSample = true } label: {
                            Label("الدليل التجريبي", systemImage: "flask")
                        }
                        .accessibilityIdentifier("open-sample-catalog")
                    }
                }
                .navigationDestination(for: String.self) { LiveLotDetailView(slug: $0) }
                .navigationDestination(for: ProductID.self) { ProductDetailView(productID: $0) }
                .navigationDestination(isPresented: $showSample) { SampleCatalogView() }
                .task { if case .loading = phase { await load() } }
                .refreshable { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("جارٍ تحميل المحاصيل…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label("تعذّر تحميل المحاصيل", systemImage: "wifi.exclamationmark")
            } description: {
                Text("تحقّق من اتصالك ثم أعد المحاولة.")
            } actions: {
                Button("إعادة المحاولة") { Task { await load() } }.buttonStyle(.borderedProminent)
            }
        case let .loaded(all):
            list(searchResults ?? all, isSearchResult: searchResults != nil)
        }
    }

    private func list(_ lots: [RemoteLot], isSearchResult: Bool) -> some View {
        List {
            if isSearching {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if lots.isEmpty {
                if isSearchResult {
                    ContentUnavailableView.search(text: query)
                } else {
                    ContentUnavailableView {
                        Label("لا محاصيل منشورة بعد", systemImage: "cup.and.saucer")
                    } description: {
                        Text("تظهر هنا القهوة فور نشرها.")
                    }
                }
            } else {
                Section(isSearchResult ? "النتائج" : "المحاصيل") {
                    ForEach(lots) { lot in
                        NavigationLink(value: lot.slug) { LiveLotRow(lot: lot) }
                            .accessibilityIdentifier("live-lot-\(lot.slug)")
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            phase = .loaded(try await client.fetchLots())
        } catch {
            phase = .failed
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await client.searchLots(query: q)) ?? []
    }
}
