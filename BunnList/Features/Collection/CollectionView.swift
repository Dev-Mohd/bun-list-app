import BunnListCore
import SwiftUI

/// "مجموعتي": the coffees saved to the account, as bag cards, narrowed by
/// لديّ / جرّبته / مفضّل / ودّي أجرّب and by name. Needs an account.
struct CollectionView: View {
    private enum Shelf: String, CaseIterable, Identifiable {
        case all = "الكل", owned = "لديّ", tried = "جرّبته", favorite = "مفضّل", wantsToTry = "ودّي أجرّب"
        var id: Self { self }

        func includes(_ item: RemoteCollectionItem) -> Bool {
            switch self {
            case .all: return true
            case .owned: return item.owned
            case .tried: return item.tried
            case .favorite: return item.favorite
            case .wantsToTry: return item.wantsToTry
            }
        }
    }

    @Binding var tab: AppTab
    @EnvironmentObject private var auth: AuthModel
    @State private var shelf = Shelf.all
    @State private var query = ""
    @State private var items: [RemoteCollectionItem]?
    @State private var failed = false
    @State private var showSignIn = false
    @State private var showScan = false
    @State private var catalogCountries: Int?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var visible: [RemoteCollectionItem] {
        let tokens = TextNormalizer.tokens(query)
        return (items ?? []).filter(shelf.includes).filter { item in
            let text = TextNormalizer.normalize("\(item.nameAr) \(item.roasterNameAr) \(item.originNameAr ?? "")")
            return tokens.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    ContentUnavailableView {
                        Label("مجموعتك تنحفظ في حسابك", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("سجّل الدخول وابدأ تجمع القهوات اللي جرّبتها والقهوات اللي ودّك تجرّبها.")
                    } actions: {
                        Button("سجّل الدخول") { showSignIn = true }.buttonStyle(.borderedProminent).tint(Brand.ink).foregroundStyle(Brand.background)
                    }
                } else if items != nil {
                    content
                } else if failed {
                    ContentUnavailableView {
                        Label("تعذّر تحميل مجموعتك", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("إعادة المحاولة") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.background.ignoresSafeArea())
            .navigationTitle("مجموعتي")
            .searchable(text: $query, prompt: "ابحث في مجموعتك")
            .refreshable { await load() }
            .task(id: auth.isSignedIn) { await load() }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .sheet(isPresented: $showScan) { AIBagScanView().environmentObject(auth) }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                if shelf == .all, query.isEmpty, let items, !items.isEmpty {
                    CollectionOverview(items: items, catalogCountries: catalogCountries)
                        .padding(.bottom, 6)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Shelf.allCases) { option in
                            let count = (items ?? []).filter(option.includes).count
                            Button { shelf = option } label: {
                                Text("\(option.rawValue) \(count.formatted())")
                                    .font(.subheadline.weight(shelf == option ? .semibold : .regular))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(shelf == option ? Brand.background : Brand.ink)
                                    .background(shelf == option ? Brand.ink : Color(.secondarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("collection-shelf-\(option.rawValue)")
                        }
                    }
                    .padding(.horizontal)
                }

                if visible.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "ما فيه شي هنا للحين" : "ما لقينا شي", systemImage: "cup.and.saucer")
                    } description: {
                        Text(query.isEmpty ? "امسح كيس أو دوّر قهوة وعلّمها بـ «لديّ» أو «مفضّل»." : "جرّب كلمة ثانية.")
                    } actions: {
                        if query.isEmpty {
                            Button("امسح كيس") { showScan = true }.buttonStyle(.borderedProminent).tint(Brand.ink).foregroundStyle(Brand.background)
                        }
                    }
                    .padding(.top, 30)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(visible) { item in
                            NavigationLink { LiveLotDetailView(slug: item.slug) } label: { CollectionCard(item: item) }
                                .buttonStyle(CardPressStyle())
                                .cardScrollIn()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func load() async {
        guard auth.isSignedIn else { items = nil; return }
        failed = false
        do {
            items = try await auth.withToken { try await client.fetchCollection(accessToken: $0) }
            if catalogCountries == nil { catalogCountries = try? await client.fetchFacets().origins.count }
        } catch {
            if items == nil { failed = true }
        }
    }
}

private struct CollectionCard: View {
    let item: RemoteCollectionItem

    /// The shelves it's on, in words, so a card says more than an icon.
    private struct Shelf: Hashable { let icon: String; let label: String }

    private var shelves: [Shelf] {
        var out: [Shelf] = []
        if item.owned { out.append(Shelf(icon: "checkmark.circle.fill", label: "لديّ")) }
        if item.tried { out.append(Shelf(icon: "cup.and.saucer.fill", label: "جرّبته")) }
        if item.favorite { out.append(Shelf(icon: "heart.fill", label: "مفضّل")) }
        if item.wantsToTry { out.append(Shelf(icon: "bookmark.fill", label: "ودّي أجرّب")) }
        return out
    }

    private var origin: String? {
        let text = [ReferenceCodes.flag(item.originCode), item.originNameAr].compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LotPhotoWell(imageUrl: item.imageUrl, notes: [], roaster: item.roasterNameAr, name: item.nameAr,
                         origin: item.originNameAr, originCode: item.originCode)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 4)
            Text(item.nameAr).font(.headline).foregroundStyle(Brand.ink).lineLimit(1)
            Text(item.roasterNameAr).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            if let origin {
                Text(origin).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            FlowLayout(spacing: 4) {
                ForEach(shelves, id: \.self) { shelf in
                    Label(shelf.label, systemImage: shelf.icon)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Brand.olive.opacity(0.12), in: Capsule())
                        .foregroundStyle(Brand.olive)
                }
            }
            .padding(.top, 2)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .lotQuickActions(slug: item.slug, name: item.nameAr, roaster: item.roasterNameAr, imageUrl: item.imageUrl,
                         notes: [], origin: item.originNameAr, originCode: item.originCode,
                         known: RemoteCollectionFlags(owned: item.owned, favorite: item.favorite,
                                                      wantsToTry: item.wantsToTry, tried: item.tried))
    }
}

// MARK: - Above the bags: numbers, passport, taste spread, shelf, wish list, recap

/// «مجموعتي» at a glance, worked out from the collection itself.
struct CollectionOverview: View {
    let items: [RemoteCollectionItem]
    /// Countries with coffees in the guide, for the passport ring; nil until loaded.
    let catalogCountries: Int?
    @State private var shown = false
    @State private var showRecap = false

    private var computedInsights: CollectionInsights { CollectionInsights(items: items) }

    var body: some View {
        let insights = computedInsights
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                CountTile(value: insights.coffees, label: "قهوة", play: shown)
                CountTile(value: insights.countryCodes.count, label: "دول", play: shown)
                CountTile(value: insights.roasters, label: "محامص", play: shown)
                CountTile(value: items.filter(\.favorite).count, label: "مفضّلة", play: shown)
            }
            .padding(.horizontal)

            NavigationLink { PassportView() } label: { passport(insights) }
                .buttonStyle(CardPressStyle())
                .padding(.horizontal)

            if !insights.shares.isEmpty { tasteSpread(insights.shares).padding(.horizontal) }

            let owned = items.filter(\.owned)
            if !owned.isEmpty {
                shelfTitle("على رفّي الحين", count: owned.count)
                WoodenShelf(items: Array(owned.prefix(12)), play: shown)
            }

            let wish = items.filter(\.wantsToTry)
            if !wish.isEmpty {
                shelfTitle("ودّي أجرّب", count: wish.count)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(wish.prefix(12)) { item in
                            NavigationLink { LiveLotDetailView(slug: item.slug) } label: { wishCard(item) }
                                .buttonStyle(CardPressStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if let recap = insights.recap {
                Button { showRecap = true } label: { recapBanner(recap) }
                    .buttonStyle(CardPressStyle())
                    .padding(.horizontal)
            }
        }
        .onAppear { shown = true }
        .sheet(isPresented: $showRecap) {
            if let recap = insights.recap {
                RecapShareSheet(recap: recap, countryCodes: insights.countryCodes, shares: insights.shares)
            }
        }
    }

    private func passport(_ insights: CollectionInsights) -> some View {
        let total = max(catalogCountries ?? 0, insights.countryCodes.count)
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Brand.gold.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: shown && total > 0 ? CGFloat(insights.countryCodes.count) / CGFloat(total) : 0)
                    .stroke(Brand.gold, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.4).delay(0.4), value: shown)
                VStack(spacing: -2) {
                    Text("\(insights.countryCodes.count)").font(.headline.bold())
                    if total > 0 { Text("من \(total)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .frame(width: 66, height: 66)
            .environment(\.layoutDirection, .leftToRight)
            VStack(alignment: .leading, spacing: 4) {
                Text("جواز قهوتك").font(.subheadline.bold()).foregroundStyle(Brand.ink)
                HStack(spacing: 2) {
                    ForEach(Array(insights.countryCodes.prefix(9).enumerated()), id: \.offset) { index, code in
                        Text(ReferenceCodes.flag(code) ?? "").font(.title3)
                            .scaleEffect(shown ? 1 : 0.1)
                            .opacity(shown ? 1 : 0)
                            .animation(.spring(response: 0.45, dampingFraction: 0.5).delay(0.6 + Double(index) * 0.08), value: shown)
                    }
                }
                if total > insights.countryCodes.count {
                    Text("ختمك الجاي؟ في الدليل \(total - insights.countryCodes.count) دولة ما جرّبتها")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func tasteSpread(_ shares: [CollectionInsights.Share]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("بصمة ذوقك").font(.subheadline.bold()).foregroundStyle(Brand.ink)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        Rectangle().fill(share.family.color)
                            .frame(width: shown ? geo.size.width * CGFloat(share.percent) / 100 : 0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.5 + Double(index) * 0.12), value: shown)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            FlowLayout(spacing: 8) {
                ForEach(Array(shares.enumerated()), id: \.offset) { _, share in
                    HStack(spacing: 4) {
                        Circle().fill(share.family.color).frame(width: 8, height: 8)
                        Text("\(share.family.nameAr) \(share.percent)٪")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func shelfTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(Brand.brown)
            Spacer()
            Text("\(count)").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func wishCard(_ item: RemoteCollectionItem) -> some View {
        HStack(spacing: 8) {
            LotPhotoWell(imageUrl: item.imageUrl, notes: item.flavorNotes ?? [], roaster: item.roasterNameAr, name: item.nameAr,
                         origin: item.originNameAr, originCode: item.originCode, padding: 2)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.nameAr).font(.footnote.bold()).foregroundStyle(Brand.ink).lineLimit(1)
                Text(item.roasterNameAr).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 170, alignment: .leading)
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func recapBanner(_ recap: CollectionInsights.Recap) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack.fill").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("ملخص \(Self.monthName()) جاهز").font(.subheadline.bold())
                Text(Self.recapLine(recap) + " · شاركه ستوري").font(.caption).opacity(0.75)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.backward")
        }
        .foregroundStyle(Brand.background)
        .padding(14)
        .background(Brand.ink, in: RoundedRectangle(cornerRadius: 18))
    }

    static func monthName(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "LLLL"
        return f.string(from: date)
    }

    static func recapLine(_ recap: CollectionInsights.Recap) -> String {
        var parts = [recap.coffees == 1 ? "قهوة وحدة" : recap.coffees == 2 ? "قهوتين" : "\(recap.coffees) قهوات"]
        if recap.newCountries > 0 {
            parts.append(recap.newCountries == 1 ? "دولة جديدة" : recap.newCountries == 2 ? "دولتين جديدة" : "\(recap.newCountries) دول جديدة")
        }
        return parts.joined(separator: "، ")
    }
}

/// A number that counts up.
private struct CountTile: View {
    let value: Int
    let label: String
    let play: Bool
    @State private var shown = 0

    var body: some View {
        VStack(spacing: 2) {
            Text("\(shown)").font(.title2.bold().monospacedDigit()).contentTransition(.numericText(value: Double(shown)))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .onAppear { withAnimation(.easeOut(duration: 1.1).delay(0.3)) { shown = value } }
        .onChange(of: value) { shown = value }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// The bags they have now, standing on a wooden shelf; they drop in one by one.
private struct WoodenShelf: View {
    let items: [RemoteCollectionItem]
    let play: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink { LiveLotDetailView(slug: item.slug) } label: {
                        LotPhotoWell(imageUrl: item.imageUrl, notes: item.flavorNotes ?? [], roaster: item.roasterNameAr,
                                     name: item.nameAr, origin: item.originNameAr, originCode: item.originCode, padding: 3)
                            .frame(width: 70, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 3)
                    }
                    .buttonStyle(CardPressStyle())
                    .offset(y: play ? 0 : -70)
                    .opacity(play ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.4 + Double(min(index, 8)) * 0.1), value: play)
                    .accessibilityLabel(item.nameAr)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(red: 0.69, green: 0.51, blue: 0.35), Color(red: 0.49, green: 0.33, blue: 0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 12)
                    .shadow(color: Brand.brown.opacity(0.3), radius: 6, y: 5)
            }
        }
    }
}

/// The month's recap as a story-sized card to share.
@MainActor
struct RecapShareSheet: View {
    let recap: CollectionInsights.Recap
    let countryCodes: [String]
    let shares: [CollectionInsights.Share]
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                card.frame(width: 270, height: 480).clipShape(RoundedRectangle(cornerRadius: 26)).shadow(radius: 12)
                if let image {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("ملخصي في BunnList", image: Image(uiImage: image))) {
                        Label("شارك", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.ink)
                    .padding(.horizontal, 40)
                }
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Brand.background.ignoresSafeArea())
            .navigationTitle("ملخص الشهر")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .task {
                let renderer = ImageRenderer(content: card.frame(width: 1080 / 3, height: 1920 / 3))
                renderer.scale = 3
                image = renderer.uiImage
            }
        }
    }

    private var card: some View {
        ZStack {
            LinearGradient(colors: shares.prefix(2).map { $0.family.color } + [Brand.ink], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                Text("ملخص \(CollectionOverview.monthName())").font(.title3.bold())
                Text("\(recap.coffees)").font(.system(size: 76, weight: .heavy))
                Text(recap.coffees == 1 ? "قهوة جديدة في مجموعتي" : "قهوات جديدة في مجموعتي").font(.headline)
                if recap.newCountries > 0 {
                    Text("+\(recap.newCountries) دول جديدة في جوازي").font(.subheadline)
                }
                Text(countryCodes.prefix(8).compactMap { ReferenceCodes.flag($0) }.joined(separator: " ")).font(.title2)
                if let note = recap.topNote {
                    Text("أكثر نكهة: \(note)").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                Spacer()
                Text("BunnList").font(.headline.weight(.heavy)).opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 34)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
