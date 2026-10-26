import BunnListCore
import SwiftUI

/// "بحث": the whole catalog with text search, the shelf (الكل / عندي / باقي علي),
/// quick flavor-family chips and the filter sheet. Results load in pages.
@MainActor
struct SearchView: View {
    @Binding var tab: AppTab

    @EnvironmentObject private var auth: AuthModel
    @State private var filters = BrowseFilters()
    @State private var lots: [RemoteLot] = []
    @State private var total = 0
    @State private var phase = Phase.loading
    @State private var facets: RemoteFacets?
    @State private var showFilters = false
    @State private var showSignIn = false
    @FocusState private var searchFocused: Bool

    private enum Phase: Equatable { case loading, loaded, failed, loadingMore }
    private static let pageSize = 40
    private let client = CatalogAPIClient(transport: URLSessionTransport())

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

            Button { tab = .scan } label: {
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
                                .buttonStyle(.plain)
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

/// A coffee in the search grid: the bag on its flavor's wash (or its drawn card),
/// name, roaster, then flag, process and first notes, and the rating.
struct LotGridCard: View {
    let lot: RemoteLot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LotPhotoWell(imageUrl: lot.imageUrl, notes: lot.flavorNotes, roaster: lot.roasterNameAr, name: lot.nameAr,
                         origin: lot.originNameAr, originCode: lot.originCode)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(lot.nameAr).font(.subheadline.bold()).lineLimit(1)
            Text(lot.roasterNameAr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 4) {
                Text(lot.cardLine.isEmpty ? (lot.originNameAr ?? "") : lot.cardLine).lineLimit(1)
                Spacer(minLength: 0)
                if lot.reviewCount > 0 {
                    Label(lot.averageRating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                        .foregroundStyle(Brand.gold)
                }
            }
            .font(.caption2)
            .foregroundStyle(Brand.olive)
        }
        .accessibilityElement(children: .combine)
    }
}
