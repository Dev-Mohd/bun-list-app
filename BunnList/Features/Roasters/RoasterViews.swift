import BunnListCore
import SwiftUI

/// «المحامص»: every roaster with coffees in the catalog, searchable, the ones you
/// follow first.
@MainActor
struct RoastersIndexView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var list: RemoteRoasterList?
    @State private var failed = false
    @State private var query = ""

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var shown: [RemoteRoasterCard] {
        guard let list else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        let matching = q.isEmpty ? list.roasters : list.roasters.filter {
            $0.nameAr.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q)
        }
        let followed = Set(list.following)
        return matching.filter { followed.contains($0.slug) } + matching.filter { !followed.contains($0.slug) }
    }

    var body: some View {
        ScrollView {
            if list == nil {
                if failed {
                    ContentUnavailableView {
                        Label("تعذّر التحميل", systemImage: "wifi.exclamationmark")
                    } actions: { Button("إعادة المحاولة") { Task { await load() } } }
                    .padding(.top, 60)
                } else {
                    ProgressView().padding(.top, 80)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(shown) { roaster in
                        NavigationLink { RoasterPageView(slug: roaster.slug, nameAr: roaster.nameAr) } label: {
                            RoasterRow(roaster: roaster, isFollowing: list?.following.contains(roaster.slug) == true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle("المحامص")
        .searchable(text: $query, prompt: "ابحث عن محمصة")
        .task { if list == nil { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do { list = try await client.fetchRoasters(accessToken: auth.currentAccessToken()) }
        catch { failed = list == nil }
    }
}

/// A roaster's initials on a warm disc, standing in for a logo.
struct RoasterBadge: View {
    let nameAr: String
    var size: CGFloat = 52

    private var initials: String {
        let words = nameAr.replacingOccurrences(of: "محمصة", with: "").split(separator: " ")
        return String(words.first?.prefix(1) ?? "☕")
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Brand.background)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Brand.brown, Brand.olive], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct RoasterRow: View {
    let roaster: RemoteRoasterCard
    let isFollowing: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoasterBadge(nameAr: roaster.nameAr)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(roaster.nameAr).font(.headline).foregroundStyle(Brand.ink).lineLimit(1)
                    if isFollowing {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Brand.olive)
                    }
                }
                HStack(spacing: 10) {
                    Label("\(roaster.lots.formatted()) قهوة", systemImage: "bag.fill")
                    if roaster.reviews > 0 {
                        Label(roaster.averageRating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                            .foregroundStyle(Brand.gold)
                    }
                    if let city = roaster.cityAr { Text(city) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            // Its best-known bags, overlapping.
            HStack(spacing: -18) {
                ForEach(Array(roaster.images.prefix(3).enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: URL(string: url)) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                        .frame(width: 40, height: 52)
                        .padding(3)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// One roaster: who they are, how people rate them, what they lean to, and all
/// their coffees. Following it brings its new coffees to the home.
@MainActor
struct RoasterPageView: View {
    let slug: String
    var nameAr: String = ""

    @EnvironmentObject private var auth: AuthModel
    @State private var page: RemoteRoasterPage?
    @State private var failed = false
    @State private var isTogglingFollow = false
    @State private var showSignIn = false
    @State private var showAll = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if let page {
                content(page)
            } else if failed {
                ContentUnavailableView {
                    Label("تعذّر التحميل", systemImage: "wifi.exclamationmark")
                } actions: { Button("إعادة المحاولة") { Task { await load() } } }
                .padding(.top, 60)
            } else {
                ProgressView().padding(.top, 120)
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle(page?.roaster.nameAr ?? nameAr)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSignIn) { SignInView() }
        .task { if page == nil { await load() } }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ page: RemoteRoasterPage) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            header(page)
            if !page.familyShares.isEmpty { tasteCard(page) }
            if !page.origins.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("من وين قهاويها").font(.headline)
                    RoasterChips(items: page.origins.map { "\($0.key) · \($0.count.formatted())" })
                }
                .padding(.horizontal)
            }
            if !page.topRated.isEmpty { lotRow("الأعلى تقييمًا", page.topRated) }
            if page.lots.count > 4, !page.newest.isEmpty { lotRow("وصلت حديثًا", page.newest) }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("كل قهاويها").font(.headline)
                    Text(page.lots.count.formatted()).font(.subheadline).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(showAll ? page.lots : Array(page.lots.prefix(8))) { lot in
                        NavigationLink { LiveLotDetailView(slug: lot.slug) } label: { LotGridCard(lot: lot) }
                            .buttonStyle(.plain)
                    }
                }
                if page.lots.count > 8 && !showAll {
                    Button { withAnimation { showAll = true } } label: {
                        Text("اعرض الكل (\(page.lots.count.formatted()))").font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private func header(_ page: RemoteRoasterPage) -> some View {
        let r = page.roaster
        return VStack(spacing: 14) {
            ZStack {
                // A fan of its bags behind the badge.
                HStack(spacing: -30) {
                    ForEach(Array(r.images.enumerated()), id: \.offset) { i, url in
                        AsyncImage(url: URL(string: url)) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                            .frame(width: 92, height: 120)
                            .rotationEffect(.degrees(Double(i - 1) * 9))
                            .offset(y: i == 1 ? -8 : 4)
                            .zIndex(i == 1 ? 1 : 0)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(height: 140)
                RoasterBadge(nameAr: r.nameAr, size: 58)
                    .overlay(Circle().stroke(Brand.background, lineWidth: 4))
                    .offset(y: 70)
            }
            .padding(.bottom, 24)
            VStack(spacing: 4) {
                Text(r.nameAr).font(.title2.bold())
                if r.name.lowercased() != r.nameAr.lowercased() {
                    Text(r.name).font(.subheadline).foregroundStyle(.secondary)
                }
                if let city = r.cityAr { Label(city, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 10) {
                stat(r.lots.formatted(), "قهوة")
                stat(r.reviews > 0 ? r.averageRating.formatted(.number.precision(.fractionLength(1))) : "—", "التقييم")
                stat(r.followers.formatted(), "متابع")
            }
            followButton(page)
        }
        .padding(.horizontal)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(Brand.brown)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func followButton(_ page: RemoteRoasterPage) -> some View {
        Button { Task { await toggleFollow() } } label: {
            HStack {
                if isTogglingFollow { ProgressView().tint(page.isFollowing ? Brand.olive : .white) }
                Image(systemName: page.isFollowing ? "checkmark" : "plus")
                Text(page.isFollowing ? "تتابعها" : "تابع المحمصة")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(page.isFollowing ? Brand.olive : .white)
            .background(page.isFollowing ? Brand.olive.opacity(0.12) : Brand.olive, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isTogglingFollow)
        .accessibilityHint("تجيك قهاويها الجديدة في الصفحة الرئيسية")
    }

    private func tasteCard(_ page: RemoteRoasterPage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("وش تميل له قهاويها").font(.headline)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(page.familyShares, id: \.family) { share in
                        share.family.color.frame(width: max(4, geo.size.width * CGFloat(share.percent) / 100 - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 16)
            RoasterChips(items: page.familyShares.map { "\($0.family.shortNameAr) \($0.percent.formatted())٪" },
                      colors: page.familyShares.map(\.family.color))
            if !page.processes.isEmpty {
                Text("المعالجة: " + page.processes.prefix(3).map { ReferenceCodes.process($0.key)?.nameAr ?? $0.key }.joined(separator: "، "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }

    private func lotRow(_ title: String, _ lots: [RemoteLot]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(lots) { lot in
                        NavigationLink { LiveLotDetailView(slug: lot.slug) } label: { LotGridCard(lot: lot).frame(width: 170) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func load() async {
        failed = false
        do { page = try await client.fetchRoaster(slug: slug, accessToken: auth.currentAccessToken()) }
        catch { failed = page == nil }
    }

    private func toggleFollow() async {
        guard auth.isSignedIn else { showSignIn = true; return }
        guard let current = page else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let want = !current.isFollowing
        if let state = try? await auth.withToken({ try await client.setRoasterFollow(slug: slug, follow: want, accessToken: $0) }) {
            Haptics.tap()
            page?.isFollowing = state.following
            // Re-read for the follower count.
            if let fresh = try? await client.fetchRoaster(slug: slug, accessToken: auth.currentAccessToken()) { page = fresh }
        }
    }
}

/// Wrapping text chips, optionally tinted.
struct RoasterChips: View {
    let items: [String]
    var colors: [Color] = []

    var body: some View {
        RoasterWrapLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Text(item).font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(i < colors.count ? Color.white : Brand.ink)
                    .background(i < colors.count ? colors[i] : Color(.secondarySystemGroupedBackground), in: Capsule())
            }
        }
    }
}

/// A simple flow layout: rows that wrap.
struct RoasterWrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width { y += row + spacing; x = 0; row = 0 }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Two doors on the home: the roasters, and the map of where coffee comes from.
struct ExploreTiles: View {
    var openRoasters: () -> Void
    var openMap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            tile("المحامص", "كل محمصة وقهاويها", "storefront.fill", Brand.brown, openRoasters)
                .accessibilityIdentifier("open-roasters")
            tile("خريطة المناطق", "من وين تجي قهوتك", "map.fill", Brand.olive, openMap)
                .accessibilityIdentifier("open-origins-map")
        }
        .padding(.horizontal)
    }

    private func tile(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title2).foregroundStyle(Brand.background)
                    .frame(width: 44, height: 44)
                    .background(color, in: RoundedRectangle(cornerRadius: 12))
                Text(title).font(.headline).foregroundStyle(Brand.ink)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}
