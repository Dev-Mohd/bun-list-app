import BunnListCore
import SwiftUI

/// «اكتشف» - browsing the coffee guide: a short greeting, search (with filters and
/// the bag scanner), the newest coffee told through its taste, browse by flavor
/// with results in place, where coffees come from, new arrivals, and the way into
/// the whole catalog. Trending, the pulse and the leaders live in «المجتمع»;
/// recipes, the grind converter and «كمّل» in «حضّر». Every section loads, fails
/// and retries on its own, with real data only. The demo catalog shows only in UI tests.
struct DiscoverView: View {
    @Binding var tab: AppTab

    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @State private var newest: SectionLoad<[RemoteLot]> = .loading
    @State private var facets: SectionLoad<RemoteFacets> = .loading
    @State private var featuredMethods: [String] = []
    @State private var owned: Set<String> = []
    @State private var catalogTotal: Int?
    @State private var flavor: FlavorFamily?
    @State private var flavorLots: SectionLoad<[RemoteLot]> = .loading
    @State private var showSearch = false
    @State private var searchPreset: SearchPreset?
    @State private var showSample = false
    @State private var showScan = false
    @State private var openSlug: String?
    @AppStorage("lastBrewMethod") private var brewMethod = "V60"
    @AppStorage("brewFocus") private var brewFocus = ""

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private static let newestCount = 7

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        DiscoverHeader(name: profile.me?.displayName, avatarUrl: profile.me?.avatarUrl,
                                       isSignedIn: auth.isSignedIn) { tab = .account }
                        DiscoverSearchBar(openSearch: { showSearch = true },
                                          openFilters: { searchPreset = SearchPreset(filters: BrowseFilters(), openFilters: true) },
                                          openScan: { showScan = true })
                    }
                    featured
                    TasteSection(families: familyFacets, selected: $flavor, results: flavorLots,
                                 retryFamilies: { Task { await loadFacets() } },
                                 retryResults: { Task { await loadFlavor() } },
                                 showAll: { family in
                                     var filters = BrowseFilters()
                                     filters.flavors = [family]
                                     searchPreset = SearchPreset(filters: filters)
                                 })
                    OriginsRow(origins: originFacets, retry: { Task { await loadFacets() } }) { origin in
                        var filters = BrowseFilters()
                        filters.origins = [origin.value]
                        searchPreset = SearchPreset(filters: filters)
                    }
                    NewArrivalsSection(lots: arrivals, retry: { Task { await loadNewest() } }) {
                        var filters = BrowseFilters()
                        filters.sort = .newest
                        searchPreset = SearchPreset(filters: filters)
                    }
                    CatalogEntryCard(total: catalogTotal) { showSearch = true }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Brand.background.ignoresSafeArea())
            .brandScreen()
            .navigationTitle("اكتشف")
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                // The on-device demo catalog is for UI tests only.
                if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                    Button { showSample = true } label: { Label("الدليل التجريبي", systemImage: "flask") }
                        .accessibilityIdentifier("open-sample-catalog")
                        .padding()
                }
            }
            .navigationDestination(for: String.self) { LiveLotDetailView(slug: $0) }
            .navigationDestination(for: ProductID.self) { ProductDetailView(productID: $0) }
            .navigationDestination(isPresented: $showSample) { SampleCatalogView() }
            .navigationDestination(item: $openSlug) { LiveLotDetailView(slug: $0) }
            .navigationDestination(isPresented: $showSearch) { SearchView(tab: $tab) }
            .navigationDestination(item: $searchPreset) { SearchView(tab: $tab, initial: $0.filters, openFilters: $0.openFilters) }
            .sheet(isPresented: $showScan) { AIBagScanView().environmentObject(auth) }
            .task { await loadAll() }
            .task(id: auth.isSignedIn) { await loadOwned() }
            .task(id: flavor) { await loadFlavor() }
            .refreshable { await loadAll(); await loadOwned() }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var featured: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionHeader(title: "أحدث إضافة")
            switch newest {
            case .loading:
                SkeletonBlock(height: 210, corner: 24).padding(.horizontal)
            case .failed:
                SectionFailure(message: "ما قدرنا نجيب المحاصيل.") { Task { await loadNewest() } }
            case let .loaded(lots):
                if let lot = DiscoverText.split(newest: lots).featured {
                    FeaturedLotCard(lot: lot, methods: featuredMethods, inCollection: owned.contains(lot.slug),
                                    open: { openSlug = lot.slug },
                                    brew: {
                                        brewFocus = lot.slug
                                        if let first = featuredMethods.first(where: { BrewPlanner.methods.contains($0) }) { brewMethod = first }
                                        tab = .brew
                                    })
                } else {
                    Text("ما فيه محاصيل منشورة للحين.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
        }
    }

    private var arrivals: SectionLoad<[RemoteLot]> {
        switch newest {
        case .loading: return .loading
        case .failed: return .failed
        case let .loaded(lots): return .loaded(Array(DiscoverText.split(newest: lots).rest.prefix(6)))
        }
    }

    private var familyFacets: SectionLoad<[RemoteFacets.Facet]> {
        switch facets {
        case .loading: return .loading
        case .failed: return .failed
        case let .loaded(f): return .loaded(f.flavors)
        }
    }

    private var originFacets: SectionLoad<[RemoteFacets.Facet]> {
        switch facets {
        case .loading: return .loading
        case .failed: return .failed
        case let .loaded(f): return .loaded(f.origins)
        }
    }

    // MARK: Data

    private func loadAll() async {
        async let a: Void = loadNewest()
        async let b: Void = loadFacets()
        _ = await (a, b)
    }

    private func loadNewest() async {
        if newest.value == nil { newest = .loading }
        var filters = BrowseFilters()
        filters.sort = .newest
        do {
            let page = try await client.browse(filters, limit: Self.newestCount, accessToken: nil)
            newest = .loaded(page.lots)
            catalogTotal = page.total
            if let first = page.lots.first {
                featuredMethods = (try? await client.fetchLotDetail(slug: first.slug))?.recommendedBrewMethods ?? []
            }
        } catch {
            if newest.value == nil { newest = .failed }
        }
    }

    private func loadFacets() async {
        if facets.value == nil { facets = .loading }
        do { facets = .loaded(try await client.fetchFacets()) }
        catch { if facets.value == nil { facets = .failed } }
    }

    private func loadFlavor() async {
        guard let family = flavor else { return }
        flavorLots = .loading
        var filters = BrowseFilters()
        filters.flavors = [family]
        do {
            let page = try await client.browse(filters, limit: 10, accessToken: nil)
            guard flavor == family else { return }
            flavorLots = .loaded(page.lots)
        } catch {
            if flavor == family { flavorLots = .failed }
        }
    }

    /// Which coffees you own, for «حضّرها» on the newest one.
    private func loadOwned() async {
        guard auth.isSignedIn else { owned = []; return }
        let items = (try? await auth.withToken { try await client.fetchCollection(accessToken: $0) }) ?? []
        owned = Set(items.map(\.slug))
    }
}
