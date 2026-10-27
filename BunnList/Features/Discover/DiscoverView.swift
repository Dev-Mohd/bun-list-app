import BunnListCore
import SwiftUI

/// Discover - the home screen: greeting with streak and points, search, «كمّل من
/// وين وقفت» (your last brew and what to try this time), trending this week
/// (coffees, roasters, recipes), what suits your taste, quick browse, the
/// community pulse, new discoveries, the leaders in one line, the best rated, tools
/// and a daily fact, then every published coffee. The search bar opens the full
/// search screen (SearchView). The demo catalog shows only in UI tests.
struct DiscoverView: View {
    @Binding var tab: AppTab

    private enum Phase: Equatable {
        case loading
        case loaded([RemoteLot])
        case failed
    }

    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @State private var phase: Phase = .loading
    @State private var discoveries: [RemoteLot] = []
    @State private var topRated: [RemoteLot] = []
    @State private var showSearch = false
    @State private var showSample = false
    @State private var showRecipes = false
    @State private var showConverter = false
    @State private var showScan = false
    @State private var feed: RemoteHome?
    @State private var feedFailed = false
    @State private var trendTab = TrendTab.coffee
    @State private var points: RemotePoints?
    @State private var weekLeaders: RemoteLeaderboard?
    @State private var searchPreset: SearchPreset?
    @AppStorage("lastBrewMethod") private var brewMethod = "V60"
    @AppStorage("brewFocus") private var brewFocus = ""
    @AppStorage(MyGrinder.key) private var myGuideGrinderID = ""
    @ObservedObject private var grinders = GrinderCatalog.shared

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            home
            .background(Brand.background.ignoresSafeArea())
            .brandScreen()
            .navigationTitle("اكتشف")
            .toolbar {
                // The on-device demo catalog is for UI tests only.
                if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSample = true } label: {
                            Label("الدليل التجريبي", systemImage: "flask")
                        }
                        .accessibilityIdentifier("open-sample-catalog")
                    }
                }
            }
            .navigationDestination(for: String.self) { LiveLotDetailView(slug: $0) }
            .navigationDestination(for: ProductID.self) { ProductDetailView(productID: $0) }
            .navigationDestination(isPresented: $showSample) { SampleCatalogView() }
            .navigationDestination(isPresented: $showSearch) { SearchView(tab: $tab) }
            .navigationDestination(item: $searchPreset) { SearchView(tab: $tab, initial: $0.filters) }
            .sheet(isPresented: $showRecipes) { RecipesHubView() }
            .sheet(isPresented: $showConverter) { GrindConverterView() }
            .sheet(isPresented: $showScan) { AIBagScanView().environmentObject(auth) }
            .task { if case .loading = phase { await load() } }
            .task(id: auth.isSignedIn) { await loadPersonal() }
            .refreshable { await load(); await loadPersonal() }
        }
    }

    // MARK: Home

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HomeHeader(name: profile.me?.displayName, avatarUrl: profile.me?.avatarUrl, points: points) { tab = .account }
                    searchRow
                    if auth.isSignedIn, feed != nil { continueCard }
                }
                .padding(.horizontal)

                TrendingSection(trending: feed?.trending, failed: feedFailed, tab: $trendTab) { roaster in
                    var filters = BrowseFilters()
                    filters.roasters = [roaster.slug]
                    searchPreset = SearchPreset(filters: filters)
                }

                if auth.isSignedIn, case let .loaded(lots) = phase { ForYouSection(lots: lots) }

                QuickBrowseGrid { item in
                    if let filters = item.filters {
                        searchPreset = SearchPreset(filters: filters)
                    } else {
                        brewMethod = "ARABIC"
                        tab = .brew
                    }
                }

                PulseSection(items: feed?.pulse ?? []) { tab = .community }

                if !discoveries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("الاكتشافات الجديدة", systemImage: "sparkles")
                            .font(.title3.bold())
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(discoveries) { lot in
                                    NavigationLink(value: lot.slug) { DiscoveryCard(lot: lot) }
                                        .buttonStyle(CardPressStyle())
                                        .carouselCard()
                                        .accessibilityIdentifier("discovery-\(lot.slug)")
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }

                if let weekLeaders, !weekLeaders.entries.isEmpty {
                    LeadersStrip(leaders: weekLeaders.entries, myRank: weekLeaders.me?.rank) { tab = .community }
                }

                if !topRated.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("الأعلى تقييمًا", systemImage: "trophy.fill")
                            .font(.title3.bold())
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(topRated.enumerated()), id: \.offset) { index, lot in
                                    NavigationLink(value: lot.slug) {
                                        LotGridCard(lot: lot, rank: index + 1)
                                            .frame(width: 160)
                                    }
                                    .buttonStyle(CardPressStyle())
                                    .carouselCard()
                                    .accessibilityIdentifier("top-\(lot.slug)")
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }

                tools
                factCard
                allCoffees
            }
            .padding(.vertical)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Button { showSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("ابحث عن قهوة، محمصة، أصل…")
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityIdentifier("open-search")
            Button { showScan = true } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(Brand.olive)
                    .frame(width: 46, height: 46)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("امسح كيس")
            .accessibilityIdentifier("open-scan")
        }
        .buttonStyle(.plain)
    }

    private var continueCard: some View {
        let last = feed?.lastBrew
        let memory = last.flatMap {
            BrewMemory.latest([$0.experience], methodCode: $0.experience.methodCode, grinder: grinders.grinder(myGuideGrinderID))
        }
        return ContinueCard(lot: last?.lot, memory: memory, methodCode: last?.experience.methodCode) {
            if let last {
                brewMethod = last.experience.methodCode
                brewFocus = last.lot.slug
            }
            tab = .brew
        }
    }

    /// The tools that used to sit on top: recipes and the grind converter.
    private var tools: some View {
        HStack(spacing: 10) {
            QuickAction(icon: "book.closed.fill", title: "الوصفات") { showRecipes = true }
            QuickAction(icon: "dial.medium.fill", title: "محوّل الطحن") { showConverter = true }
            QuickAction(icon: "square.stack.3d.up.fill", title: "مجموعتي") { tab = .collection }
        }
        .padding(.horizontal)
    }

    private var factCard: some View {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Label("هل تعلم؟", systemImage: "lightbulb.fill")
                .font(.caption.bold()).foregroundStyle(Brand.gold)
            Text(CoffeeFacts.fact(forDay: day)).font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var allCoffees: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("كل المحاصيل").font(.title3.bold()).padding(.horizontal)
            switch phase {
            case .loading:
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 30)
            case .failed:
                ContentUnavailableView {
                    Label("تعذّر تحميل المحاصيل", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("تحقّق من اتصالك ثم أعد المحاولة.")
                } actions: {
                    Button("إعادة المحاولة") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            case let .loaded(lots):
                if lots.isEmpty {
                    ContentUnavailableView("لا محاصيل منشورة بعد", systemImage: "cup.and.saucer",
                                           description: Text("تظهر هنا القهوة فور نشرها."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(lots) { lot in
                            NavigationLink(value: lot.slug) {
                                HStack {
                                    LiveLotRow(lot: lot)
                                    Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("live-lot-\(lot.slug)")
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            if lot.id != lots.last?.id { Divider().padding(.leading) }
                        }
                    }
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal)
                }
            }
        }
    }

    private func load() async {
        async let all = try? client.fetchLots()
        async let fresh = try? client.fetchDiscoveries()
        async let best = try? client.fetchTopRated()
        let (lots, newest, top) = await (all, fresh, best)
        phase = lots.map(Phase.loaded) ?? .failed
        discoveries = newest ?? []
        topRated = top ?? []
    }

    /// The home feed, points and this week's leaders; with the account when signed in.
    private func loadPersonal() async {
        do {
            feed = try await auth.withOptionalToken { try await client.fetchHome(accessToken: $0) }
            feedFailed = false
        } catch {
            feedFailed = feed == nil
        }
        weekLeaders = try? await auth.withOptionalToken {
            try await client.fetchLeaderboard(allTime: false, kind: .points, limit: 3, accessToken: $0)
        }
        if auth.isSignedIn {
            points = try? await auth.withToken { try await client.fetchPoints(accessToken: $0) }
        } else {
            points = nil
        }
        await grinders.load()
    }
}

private struct QuickAction: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(Brand.olive)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// A new discovery: the coffee card, with who found it.
private struct DiscoveryCard: View {
    let lot: RemoteLot

    var body: some View { BunnCoffeeCard(lot: lot).frame(width: 172) }
}

/// Converts a grind setting between hand grinders using their published microns
/// per click. Approximate: a starting point to adjust by taste.
struct GrindConverterView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myGrinderID") private var myGrinderID = ""
    @State private var grinderID = ""
    @State private var clicks: Double = 24

    private var grinder: Grinder? { Grinder.find(grinderID) }
    private var microns: Int? { grinder?.microns(forClicks: clicks) }

    var body: some View {
        NavigationStack {
            Form {
                Section("مطحنتك") {
                    Picker("المطحنة", selection: $grinderID) {
                        ForEach(Grinder.convertible) { Text($0.name).tag($0.id) }
                    }
                    Stepper(value: $clicks, in: 1...120, step: 1) {
                        LabeledContent("الإعداد", value: "\(Int(clicks).formatted()) كليك").monospacedDigit()
                    }
                }
                if let microns {
                    Section {
                        LabeledContent("بالميكرون (تقريبي)", value: "≈ \(microns.formatted())")
                        let level = GrindLevel.level(forMicrons: microns)
                        LabeledContent("الدرجة", value: level.nameAr)
                        Text("تناسب عادة: \(level.usedForAr)").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("نفس الطحنة على مطاحن ثانية") {
                        let equivalents = grinder?.equivalents(ofClicks: clicks) ?? []
                        ForEach(Array(equivalents.enumerated()), id: \.offset) { _, item in
                            LabeledContent(item.grinder.name, value: "≈ \(item.clicks.formatted()) كليك").monospacedDigit()
                        }
                    }
                }
                Section {
                    Text("تحويل تقريبي محسوب من الصفر (التصاق الشفرات) وما ينشره كل مصنّع. ابدأ منه واضبط بالتذوق.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .brandScreen()
            .navigationTitle("محوّل الطحن")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .onAppear {
                if grinderID.isEmpty {
                    grinderID = Grinder.find(myGrinderID)?.micronsPerClick != nil ? myGrinderID : (Grinder.convertible.first?.id ?? "")
                }
            }
            .onChange(of: grinderID) { _, id in myGrinderID = id }
        }
    }
}
