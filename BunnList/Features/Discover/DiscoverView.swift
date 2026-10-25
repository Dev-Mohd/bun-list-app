import BunnListCore
import SwiftUI

/// Discover - the home screen: a greeting, quick actions (new recipe, scan, my
/// collection, grind converter), a daily "هل تعلم؟" fact, the newest community
/// discoveries with their discoverers, then every published coffee. Search runs on
/// the server and replaces the home sections while active. Demo data stays behind
/// the labeled "الدليل التجريبي" entry and is never a fallback.
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
    @State private var query = ""
    @State private var searchResults: [RemoteLot]?
    @State private var isSearching = false
    @State private var showSample = false
    @State private var showRecipes = false
    @State private var showConverter = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            Group {
                if searchResults != nil || isSearching {
                    searchList
                } else {
                    home
                }
            }
            .background(Brand.background.ignoresSafeArea())
            .navigationTitle("اكتشف")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
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

    // MARK: Search

    private var searchList: some View {
        List {
            if isSearching {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if let results = searchResults {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("النتائج") {
                        ForEach(results) { lot in
                            NavigationLink(value: lot.slug) { LiveLotRow(lot: lot) }
                                .accessibilityIdentifier("live-lot-\(lot.slug)")
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        async let feed = try? client.fetchLots()
        async let fresh = try? client.fetchDiscoveries()
        let (lots, newest) = await (feed, fresh)
        phase = lots.map(Phase.loaded) ?? .failed
        discoveries = newest ?? []
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await client.searchLots(query: q)) ?? []
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
