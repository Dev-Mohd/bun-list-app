import BunnListCore
import SwiftUI

/// "بحث": the whole catalog with text search, the shelf (الكل / عندي / باقي علي),
/// quick flavor-family chips and the filter sheet. Results load in pages.
@MainActor
struct SearchView: View {
    @Binding var tab: AppTab

    @EnvironmentObject private var auth: AuthModel
    @State private var filters: BrowseFilters
    @State private var lots: [RemoteLot] = []
    @State private var total = 0
    @State private var phase = Phase.loading
    @State private var facets: RemoteFacets?
    @State private var showFilters = false
    @State private var showSignIn = false
    @State private var showScan = false
    @FocusState private var searchFocused: Bool

    private enum Phase: Equatable { case loading, loaded, failed, loadingMore }
    private static let pageSize = 40
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    /// `initial` opens the search already filtered (quick browse, a roaster).
    init(tab: Binding<AppTab>, initial: BrowseFilters = BrowseFilters()) {
        _tab = tab
        _filters = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                searchBar
                shelfPicker
                flavorChips
                results
            }
            .padding(.vertical)
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle("بحث")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .task(id: filters) {
            // A short pause so typing doesn't send a request per letter.
            try? await Task.sleep(for: .milliseconds(filters.text.isEmpty ? 0 : 350))
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
        .task { facets = try? await client.fetchFacets() }
        .sheet(isPresented: $showFilters) {
            BrowseFilterSheet(filters: $filters, facets: facets, isSignedIn: auth.isSignedIn)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .sheet(isPresented: $showScan) { AIBagScanView().environmentObject(auth) }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if !signedIn { filters.shelf = .all; filters.favoritesOnly = false }
        }
    }

    // MARK: Header

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("ابحث عن قهوة، محمصة، أصل…", text: $filters.text)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("search-field")
                if !filters.text.isEmpty {
                    Button { filters.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("مسح النص")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            Button { showFilters = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.headline)
                    .frame(width: 46, height: 46)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        if filters.activeCount > 0 {
                            Text(filters.activeCount.formatted())
                                .font(.caption2.bold()).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Brand.olive, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("فلترة")
            .accessibilityIdentifier("search-filters")

            Button { showScan = true } label: {
                Image(systemName: "camera.fill")
                    .font(.headline)
                    .frame(width: 46, height: 46)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ابحث بتصوير الكيس")
        }
        .foregroundStyle(Brand.ink)
        .padding(.horizontal)
    }

    private var shelfPicker: some View {
        Picker("القسم", selection: Binding(
            get: { filters.shelf },
            set: { value in
                if value != .all && !auth.isSignedIn { showSignIn = true } else { filters.shelf = value }
            }
        )) {
            Text("الكل").tag(BrowseFilters.Shelf.all)
            Text("عندي").tag(BrowseFilters.Shelf.owned)
            Text("باقي علي").tag(BrowseFilters.Shelf.missing)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var flavorChips: some View {
        let families = facets?.flavors.compactMap { FlavorFamily(rawValue: $0.value) } ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Filters the sheet doesn't show (set from the home), removable here.
                ForEach(filters.tags.sorted(), id: \.self) { tag in
                    Button { filters.tags.remove(tag) } label: {
                        Label(tag == "decaf" ? "بدون كافيين" : tag == "luxury" ? "فاخرة" : "منقوعة", systemImage: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Brand.olive.opacity(0.16), in: Capsule())
                            .overlay(Capsule().stroke(Brand.olive))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(families, id: \.self) { family in
                    let on = filters.flavors.contains(family)
                    Button {
                        if on { filters.flavors.remove(family) } else { filters.flavors.insert(family) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(family.color).frame(width: 14, height: 14)
                            Text(family.nameAr).font(.subheadline.weight(on ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(on ? Brand.olive.opacity(0.16) : Color(.secondarySystemGroupedBackground), in: Capsule())
                        .overlay(Capsule().stroke(on ? Brand.olive : Color.secondary.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        switch phase {
        case .loading:
            ProgressView().padding(.top, 40)
        case .failed:
            ContentUnavailableView {
                Label("تعذّر البحث", systemImage: "wifi.exclamationmark")
            } description: {
                Text("تحقّق من اتصالك ثم أعد المحاولة.")
            } actions: {
                Button("إعادة المحاولة") { Task { await load(reset: true) } }.buttonStyle(.borderedProminent)
            }
        case .loaded, .loadingMore:
            if lots.isEmpty {
                ContentUnavailableView("ما لقينا قهوة", systemImage: "cup.and.saucer",
                                       description: Text("جرّب كلمة ثانية أو خفّف الفلاتر."))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(total.formatted()) قهوة").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(lots) { lot in
                            NavigationLink { LiveLotDetailView(slug: lot.slug) } label: { LotGridCard(lot: lot) }
                                .buttonStyle(CardPressStyle())
                                .cardScrollIn()
                                .accessibilityIdentifier("search-lot-\(lot.slug)")
                                .onAppear { if lot.id == lots.last?.id { Task { await load(reset: false) } } }
                        }
                    }
                    .padding(.horizontal)
                    if phase == .loadingMore { HStack { Spacer(); ProgressView(); Spacer() } }
                }
            }
        }
    }

    private func load(reset: Bool) async {
        if !reset && (phase != .loaded || lots.count >= total) { return }
        if filters.needsAccount && !auth.isSignedIn { filters.shelf = .all; filters.favoritesOnly = false; return }
        phase = reset ? .loading : .loadingMore
        let offset = reset ? 0 : lots.count
        let current = filters
        do {
            let page = try await auth.withOptionalToken { try await client.browse(current, offset: offset, limit: Self.pageSize, accessToken: $0) }
            guard current == filters else { return }
            lots = reset ? page.lots : lots + page.lots
            total = page.total
            phase = .loaded
        } catch {
            if reset { phase = .failed } else { phase = .loaded }
        }
    }
}

extension FlavorFamily {
    var color: Color { Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }
}

/// A coffee in the search grid and ranked rows: BunnList's coffee card.
struct LotGridCard: View {
    let lot: RemoteLot
    var rank: Int?

    var body: some View { BunnCoffeeCard(lot: lot, rank: rank) }
}
