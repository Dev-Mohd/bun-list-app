import BunnListCore
import SwiftUI

/// Discover - the home screen: a greeting, quick actions (new recipe, scan, my
/// collection, grind converter), a daily "هل تعلم؟" fact, the newest community
/// discoveries with their discoverers, then every published coffee. The search bar
/// opens the full search screen (SearchView). The demo catalog shows only in UI tests.
struct DiscoverView: View {
    @Binding var tab: AppTab

    private enum Phase: Equatable {
        case loading
        case loaded([RemoteLot])
        case failed
    }

    @EnvironmentObject private var profile: ProfileStore
    @State private var phase: Phase = .loading
    @State private var discoveries: [RemoteLot] = []
    @State private var topRated: [RemoteLot] = []
    @State private var leaderKind = LeaderboardKind.discoverers
    @State private var leaders: [RemoteLeaderboard.Entry]?
    @State private var showSearch = false
    @State private var showSample = false
    @State private var showRecipes = false
    @State private var showConverter = false

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
            .sheet(isPresented: $showRecipes) { RecipesHubView() }
            .sheet(isPresented: $showConverter) { GrindConverterView() }
            .task { if case .loading = phase { await load() } }
            .refreshable { await load() }
        }
    }

    // MARK: Home

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Greeting.text(hour: Calendar.current.component(.hour, from: Date()), name: profile.me?.displayName)) ☕")
                        .font(.title2.bold())
                    Text("وش نشرب اليوم؟").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal)

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
                .buttonStyle(.plain)
                .padding(.horizontal)
                .accessibilityIdentifier("open-search")

                quickActions

                factCard

                if !discoveries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("الاكتشافات الجديدة", systemImage: "sparkles")
                            .font(.title3.bold())
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(discoveries) { lot in
                                    NavigationLink(value: lot.slug) { DiscoveryCard(lot: lot) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("discovery-\(lot.slug)")
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                leadersSection

                if !topRated.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("الأعلى تقييمًا", systemImage: "trophy.fill")
                            .font(.title3.bold())
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(topRated.enumerated()), id: \.offset) { index, lot in
                                    NavigationLink(value: lot.slug) {
                                        LotGridCard(lot: lot)
                                            .frame(width: 150)
                                            .overlay(alignment: .topLeading) {
                                                Text("#\(index + 1)")
                                                    .font(.caption.bold().monospacedDigit())
                                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                                    .background(Brand.gold, in: Capsule())
                                                    .foregroundStyle(.black)
                                                    .padding(6)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("top-\(lot.slug)")
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                allCoffees
            }
            .padding(.vertical)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickAction(icon: "book.closed.fill", title: "إنشاء وصفة") { showRecipes = true }
            QuickAction(icon: "camera.viewfinder", title: "مسح") { tab = .scan }
            QuickAction(icon: "square.stack.3d.up.fill", title: "مجموعتي") { tab = .collection }
            QuickAction(icon: "dial.medium.fill", title: "محوّل الطحن") { showConverter = true }
        }
        .padding(.horizontal)
    }

    /// Top three of one ranking, with a switch between rankings and a link to the full list.
    private var leadersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("قائمة المتصدرين", systemImage: "trophy").font(.title3.bold())
                Spacer()
                Button { tab = .community } label: {
                    Label("عرض الكل", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Brand.gold.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LeaderboardKind.allCases, id: \.self) { kind in
                        Button { leaderKind = kind } label: {
                            Text(kind.titleAr)
                                .font(.subheadline.weight(leaderKind == kind ? .semibold : .regular))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(leaderKind == kind ? Brand.background : Brand.ink)
                                .background(leaderKind == kind ? Brand.ink : Color(.secondarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            if let leaders {
                if leaders.isEmpty {
                    Text("ما أحد في هالقائمة بعد. كن الأول!")
                        .font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(leaders.prefix(3).enumerated()), id: \.offset) { _, entry in
                            if let username = entry.username, !entry.isMe {
                                NavigationLink { PublicProfileView(username: username) } label: { LeaderCard(entry: entry, kind: leaderKind) }
                                    .buttonStyle(.plain)
                            } else {
                                LeaderCard(entry: entry, kind: leaderKind)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 150)
            }
        }
        .task(id: leaderKind) {
            leaders = nil
            leaders = (try? await client.fetchLeaderboard(allTime: true, kind: leaderKind, limit: 3, accessToken: nil))?.entries ?? []
        }
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
        async let feed = try? client.fetchLots()
        async let fresh = try? client.fetchDiscoveries()
        async let best = try? client.fetchTopRated()
        let (lots, newest, top) = await (feed, fresh, best)
        phase = lots.map(Phase.loaded) ?? .failed
        discoveries = newest ?? []
        topRated = top ?? []
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

/// One of the top three on the home leaderboard.
private struct LeaderCard: View {
    let entry: RemoteLeaderboard.Entry
    let kind: LeaderboardKind

    private var medal: String {
        switch entry.rank { case 1: return "🥇"; case 2: return "🥈"; default: return "🥉" }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(medal).font(.title2)
            AvatarView(url: entry.avatarUrl, name: entry.name, size: 64)
            Text(entry.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(entry.points.formatted()) \(kind.unitAr)")
                .font(.caption.monospacedDigit()).foregroundStyle(entry.rank == 1 ? Brand.gold : .secondary)
        }
        .padding(.vertical, 14).padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(entry.rank == 1 ? Brand.gold.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(entry.rank == 1 ? Brand.gold.opacity(0.5) : .clear))
        .accessibilityElement(children: .combine)
    }
}

/// A new discovery: the bag (or its drawn card), name, roaster and who found it.
private struct DiscoveryCard: View {
    let lot: RemoteLot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color(white: 0.97)
                if let url = lot.imageUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit().padding(8) } placeholder: { ProgressView() }
                } else {
                    CoffeeArtCard(roaster: lot.roasterNameAr, name: lot.nameAr, origin: lot.originNameAr, originCode: lot.originCode)
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(lot.nameAr).font(.subheadline.bold()).lineLimit(1)
            Text(lot.roasterNameAr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let by = lot.discoveredBy {
                Label("اكتشفها \(by)", systemImage: "star.circle.fill")
                    .font(.caption2).foregroundStyle(Brand.gold).lineLimit(1)
            } else if let origin = lot.originNameAr {
                Label(origin, systemImage: "globe").font(.caption2).foregroundStyle(Brand.olive).lineLimit(1)
            }
        }
        .frame(width: 150)
        .accessibilityElement(children: .combine)
    }
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
