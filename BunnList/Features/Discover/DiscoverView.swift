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
    @State private var owned: Set<String> = []
    @State private var catalogTotal: Int?
    @State private var flavor: FlavorFamily?
    @State private var flavorLots: SectionLoad<[RemoteLot]> = .loading
    @State private var showSearch = false
    @State private var searchPreset: SearchPreset?
    @State private var showRoasters = false
    @State private var showMap = false
    @State private var showAdvisor = false
    @State private var showSample = false
    @State private var showScan = false
    @State private var openSlug: String?
    @State private var forYou: RemoteForYou?
    @State private var streak: Int?
    @State private var trending: [RemoteTrendingLot] = []
    @AppStorage("lastBrewMethod") private var brewMethod = "V60"
    @AppStorage("brewFocus") private var brewFocus = ""

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    /// Enough of the newest to find several roasters in them.
    private static let newestCount = 60

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        DiscoverHeader(name: profile.me?.displayName, avatarUrl: profile.me?.avatarUrl,
                                       isSignedIn: auth.isSignedIn, streak: auth.isSignedIn ? streak : nil) { tab = .account }
                        DiscoverSearchBar(openSearch: { showSearch = true },
                                          openFilters: { searchPreset = SearchPreset(filters: BrowseFilters(), openFilters: true) },
                                          openScan: { showScan = true })
                    }
                    AdvisorCard { showAdvisor = true }
                    if auth.isSignedIn, let forYou { forYouSections(forYou) }
                    HomeTrendingRow(lots: trending, open: { openSlug = $0 }, showAll: { tab = .community })
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
                    ExploreTiles(openRoasters: { showRoasters = true }, openMap: { showMap = true })
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
            // The bar is hidden, so a frosted strip keeps scrolled content off the clock.
            .overlay(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                    .frame(height: 0)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
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
            .navigationDestination(isPresented: $showRoasters) { RoastersIndexView() }
            .navigationDestination(isPresented: $showMap) {
                OriginsMapView { code in
                    var filters = BrowseFilters()
                    filters.origins = [code]
                    searchPreset = SearchPreset(filters: filters)
                }
            }
            .navigationDestination(item: $searchPreset) { SearchView(tab: $tab, initial: $0.filters, openFilters: $0.openFilters) }
            .sheet(isPresented: $showScan) { AIBagScanView().environmentObject(auth) }
            .fullScreenCover(isPresented: $showAdvisor) { AdvisorFlow().environmentObject(auth).environmentObject(profile).environment(\.layoutDirection, .rightToLeft) }
            .task { await loadAll() }
            .task { await loadTrending() }
            .task(id: auth.isSignedIn) { await loadOwned(); await loadForYou() }
            .task(id: flavor) { await loadFlavor() }
            .refreshable { await loadAll(); await loadOwned(); await loadForYou() }
        }
    }

    // MARK: Sections

    /// The newest coffee of each roaster, so one big import doesn't fill the row.
    private var arrivals: SectionLoad<[RemoteLot]> {
        switch newest {
        case .loading: return .loading
        case .failed: return .failed
        case let .loaded(lots): return .loaded(DiscoverText.onePerRoaster(lots, limit: 6))
        }
    }

    private func loadTrending() async {
        trending = (try? await client.fetchHome(accessToken: auth.currentAccessToken()))?.trending.lots ?? []
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
    /// Today's coffee, carry on, roasters' news and friends; silent when it can't load.
    private func loadForYou() async {
        guard auth.isSignedIn else { forYou = nil; streak = nil; return }
        let home = try? await auth.withToken { try await client.fetchForYou(accessToken: $0) }
        withAnimation(.spring(response: 0.5)) { forYou = home }
        streak = (try? await auth.withToken { try await client.fetchPoints(accessToken: $0) })?.streak
    }

    @ViewBuilder
    private func forYouSections(_ home: RemoteForYou) -> some View {
        if let pick = home.dailyPick {
            DailyPickCard(pick: pick) { openSlug = pick.lot.slug }
        }
        if !home.resume.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DiscoverSectionHeader(title: "كمّل من حيث وقفت")
                ForEach(home.resume) { item in
                    ResumeCard(item: item, open: { openSlug = item.lot.slug }, brew: {
                        brewFocus = item.lot.slug
                        tab = .brew
                    })
                }
            }
        }
        if !home.roasterNews.isEmpty {
            RoasterNewsRow(news: home.roasterNews) { openSlug = $0 }
        }
        if !home.friendsDrinking.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DiscoverSectionHeader(title: "اللي تتابعهم يشربون")
                ForEach(home.friendsDrinking) { item in
                    FriendsDrinkingCard(item: item) { openSlug = item.lot.slug }
                }
            }
        }
    }

    private func loadOwned() async {
        guard auth.isSignedIn else { owned = []; return }
        let items = (try? await auth.withToken { try await client.fetchCollection(accessToken: $0) }) ?? []
        owned = Set(items.map(\.slug))
    }
}
