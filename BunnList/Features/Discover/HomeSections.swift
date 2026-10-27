import BunnListCore
import SwiftUI

// The home's sections: «كمّل من وين وقفت», trending (coffees, roasters,
// recipes), quick browse and the community pulse. DiscoverView arranges them.

/// What a search opened from the home starts with.
struct SearchPreset: Identifiable, Hashable {
    let id = UUID()
    let filters: BrowseFilters
    static func == (a: SearchPreset, b: SearchPreset) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: Header

struct HomeHeader: View {
    let name: String?
    let avatarUrl: String?
    let points: RemotePoints?
    var openAccount: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Greeting.text(hour: Calendar.current.component(.hour, from: Date()), name: name)) ☕")
                    .font(.title2.bold())
                if let points {
                    HStack(spacing: 6) {
                        if points.streak > 0 {
                            chip("\(points.streak) \(points.streak == 1 ? "يوم" : "أيام")", icon: "flame.fill", tint: .orange)
                        }
                        chip("\(points.total.formatted()) نقطة", icon: "star.fill", tint: Brand.gold)
                    }
                } else {
                    Text("وش نشرب اليوم؟").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: openAccount) { AvatarView(url: avatarUrl, name: name, size: 42) }
                .buttonStyle(.plain)
                .accessibilityLabel("حسابي")
        }
    }

    private func chip(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .labelStyle(ChipLabelStyle(tint: tint))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    private struct ChipLabelStyle: LabelStyle {
        let tint: Color
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 4) { configuration.icon.foregroundStyle(tint); configuration.title }
        }
    }
}

// MARK: «كمّل من وين وقفت»

struct ContinueCard: View {
    let lot: RemoteLot?
    let memory: BrewMemory?
    let methodCode: String?
    var brew: () -> Void

    var body: some View {
        Button(action: brew) {
            HStack(spacing: 12) {
                if let lot {
                    LotPhotoWell(imageUrl: lot.imageUrl, notes: lot.flavorNotes, roaster: lot.roasterNameAr, name: lot.nameAr,
                                 origin: lot.originNameAr, originCode: lot.originCode, padding: 3)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Image(systemName: "cup.and.saucer.fill").font(.title)
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(lot == nil ? "ابدأ من هنا" : "كمّل من وين وقفت").font(.caption.weight(.semibold)).opacity(0.75)
                    Text(lot.map { "حضّر \($0.nameAr) مرة ثانية" } ?? "حضّر أول كوب مع BunnList")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    if let line = detail {
                        Text(line).font(.caption).foregroundStyle(Color(red: 0.94, green: 0.86, blue: 0.68)).lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                Label("حضّر", systemImage: "play.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Brand.gold, in: Capsule())
                    .foregroundStyle(Brand.ink)
            }
            .padding(14)
            .foregroundStyle(Brand.background)
            .background {
                ZStack {
                    LinearGradient(colors: [Brand.olive.opacity(0.95), Brand.olive, Brand.olive.opacity(0.8)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                    Circle().fill(Brand.gold.opacity(0.3)).frame(width: 180).blur(radius: 30).offset(x: -140, y: -50)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
        }
        .buttonStyle(CardPressStyle())
        .accessibilityIdentifier("home-continue")
    }

    private var detail: String? {
        if let fix = memory?.fix { return "✦ هالمرة: \(fix.titleAr)" }
        if let memory, let methodCode {
            return "آخر مرة: \(String(repeating: "★", count: memory.stars)) · \(RecipeText.method(methodCode))"
        }
        return lot == nil ? "اختر قهوتك والطريقة، والتطبيق يمشي معك خطوة بخطوة" : nil
    }
}

// MARK: Trending

enum TrendTab: String, CaseIterable {
    case coffee, roasters, recipes
    var titleAr: String {
        switch self {
        case .coffee: return "قهوة"
        case .roasters: return "محامص"
        case .recipes: return "وصفات"
        }
    }
}

struct TrendingSection: View {
    let trending: RemoteHome.Trending?
    let failed: Bool
    @Binding var tab: TrendTab
    var openRoaster: (RemoteTrendingRoaster) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("ترند هالأسبوع")
                } icon: {
                    Image(systemName: "flame.fill").foregroundStyle(.orange).symbolEffect(.pulse, options: .repeating)
                }
                .font(.title3.bold())
                Spacer()
            }
            .padding(.horizontal)

            HStack(spacing: 6) {
                ForEach(TrendTab.allCases, id: \.self) { t in
                    Button { withAnimation(.snappy) { tab = t } } label: {
                        Text(t.titleAr).font(.subheadline.bold())
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(tab == t ? Brand.ink : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(tab == t ? Brand.background : .secondary)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: tab == t)
                }
            }
            .padding(.horizontal)

            Group {
                if let trending {
                    switch tab {
                    case .coffee: coffees(trending.lots)
                    case .roasters: roasters(trending.roasters)
                    case .recipes: recipes(trending.recipes)
                    }
                } else if failed {
                    Text("ما قدرنا نجيب الترند. اسحب للتحديث.").font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 200)
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func coffees(_ lots: [RemoteTrendingLot]) -> some View {
        if lots.isEmpty {
            empty("الترند يبدأ لما الناس تحضّر وتقيّم. كن أول واحد هالأسبوع!")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(lots) { item in
                            NavigationLink(value: item.lot.slug) { TrendingCard(item: item) }
                                .buttonStyle(CardPressStyle())
                                .carouselCard()
                                .accessibilityIdentifier("trend-\(item.lot.slug)")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .scrollTargetBehavior(.viewAligned)
                if lots.contains(where: \.isTopUp) {
                    Text("القائمة تكمل من الأكثر إضافة هالشهر لين يكثر النشاط.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func roasters(_ list: [RemoteTrendingRoaster]) -> some View {
        if list.isEmpty {
            empty("ما فيه محامص في الترند هالأسبوع للحين.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, roaster in
                    Button { openRoaster(roaster) } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.title2.bold().monospacedDigit()).foregroundStyle(Brand.gold).frame(width: 30)
                            LotPhotoWell(imageUrl: roaster.imageUrl, notes: [], roaster: roaster.nameAr, name: roaster.nameAr,
                                         origin: nil, originCode: nil, padding: 3)
                                .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(roaster.nameAr).font(.headline).foregroundStyle(Brand.ink)
                                Text("\(roaster.coffees) \(roaster.coffees == 1 ? "قهوة" : "قهوات") عليها نشاط هالأسبوع")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < list.count - 1 { Divider().padding(.leading, 12) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func recipes(_ list: [RemoteTrendingRecipe]) -> some View {
        if list.isEmpty {
            empty("انشر وصفتك، وإذا عجبت الناس تطلع هنا.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, recipe in
                        NavigationLink { TrendingRecipeLoader(id: recipe.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(index + 1)").font(.system(size: 34, weight: .bold)).foregroundStyle(Brand.gold.opacity(0.8))
                                    Spacer()
                                    Text(RecipeText.method(recipe.methodCode)).font(.caption.bold())
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Brand.olive.opacity(0.12), in: Capsule()).foregroundStyle(Brand.olive)
                                }
                                Text(recipe.title).font(.headline).foregroundStyle(Brand.ink).lineLimit(2)
                                Text("\(recipe.authorName)\(recipe.lotNameAr.map { " · \($0)" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                                HStack(spacing: 10) {
                                    Label("\(recipe.likes)", systemImage: "heart.fill").foregroundStyle(.pink)
                                    if recipe.brews > 0 { Label("\(recipe.brews) حضّروها", systemImage: "cup.and.saucer.fill").foregroundStyle(Brand.olive) }
                                }
                                .font(.caption.bold())
                            }
                            .padding(14)
                            .frame(width: 210, height: 170, alignment: .topLeading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                        }
                        .buttonStyle(CardPressStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Label(text, systemImage: "sparkles")
            .font(.callout).foregroundStyle(.secondary)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal)
    }
}

/// One big trending card: the place, the bag, how it moved and why it's here.
private struct TrendingCard: View {
    let item: RemoteTrendingLot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                LotPhotoWell(imageUrl: item.lot.imageUrl, notes: item.lot.flavorNotes, roaster: item.lot.roasterNameAr,
                             name: item.lot.nameAr, origin: item.lot.originNameAr, originCode: item.lot.originCode, padding: 14)
                    .frame(height: 190)
                HStack(alignment: .top) {
                    Text("\(item.rank)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    Spacer()
                    if item.pinned {
                        badge("مثبّتة", icon: "pin.fill", color: Brand.ink)
                    } else if let move = item.moveAr {
                        badge(move, icon: nil, color: item.move == nil ? Brand.gold : (item.move ?? 0) > 0 ? Brand.olive : Brand.brown)
                    }
                }
                .padding(12)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.lot.nameAr).font(.title3.bold()).foregroundStyle(Brand.ink).lineLimit(1)
                Text([item.lot.roasterNameAr, item.lot.originNameAr, item.lot.processNameAr].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(item.reasonsAr, id: \.self) { reason in
                        Text(reason).font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Brand.ink)
                    }
                }
                .padding(.top, 4)
                FlavorStrip(families: FlavorFamily.spectrum(item.lot.flavorNotes)).padding(.top, 6)
            }
            .padding(14)
        }
        .frame(width: 270)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: Brand.brown.opacity(0.12), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("المركز \(item.rank): \(item.lot.nameAr)، \(item.reasonsAr.joined(separator: "، "))")
    }

    private func badge(_ text: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption.bold())
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(color, in: Capsule())
        .foregroundStyle(color == Brand.gold ? Brand.ink : .white)
    }
}

/// Opens a trending recipe by id (the home only carries a summary).
private struct TrendingRecipeLoader: View {
    let id: String
    @EnvironmentObject private var auth: AuthModel
    @State private var recipe: RemoteRecipe?
    @State private var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Group {
            if let recipe {
                RecipeDetailView(recipe: recipe) { _ in }
            } else if failed {
                ContentUnavailableView("الوصفة ما عادت متاحة", systemImage: "book.closed")
            } else {
                ProgressView()
            }
        }
        .task {
            let all = (try? await auth.withOptionalToken { try await client.exploreRecipes(accessToken: $0) }) ?? []
            recipe = all.first { $0.id == id }
            failed = recipe == nil
        }
    }
}

// MARK: For you

/// Coffees with a high taste match, from the ones the home already loaded.
struct ForYouSection: View {
    let lots: [RemoteLot]
    @EnvironmentObject private var auth: AuthModel
    @ObservedObject private var match = MatchScores.shared

    private var picks: [RemoteLot] {
        lots.filter { (match.scores[$0.slug] ?? 0) >= 70 }
            .sorted { (match.scores[$0.slug] ?? 0) > (match.scores[$1.slug] ?? 0) }
            .prefix(8).map { $0 }
    }

    var body: some View {
        Group {
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("يناسب ذوقك", systemImage: "heart.text.square.fill").font(.title3.bold())
                        Text("على حسب تقييماتك وتجاربك").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(picks) { lot in
                                NavigationLink(value: lot.slug) { BunnCoffeeCard(lot: lot).frame(width: 160) }
                                    .buttonStyle(CardPressStyle())
                                    .carouselCard()
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal)
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }
        }
        .task(id: lots.map(\.slug).prefix(60).joined(separator: ",")) {
            for lot in lots.prefix(60) { match.want(lot.slug, auth: auth) }
        }
    }
}

// MARK: Quick browse

struct QuickBrowseGrid: View {
    var open: (QuickBrowse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("تصفّح سريع").font(.title3.bold()).padding(.horizontal)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(QuickBrowse.allCases, id: \.self) { item in
                    Button { open(item) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: icon(item)).font(.title2).foregroundStyle(color(item))
                                .symbolRenderingMode(.hierarchical)
                            Text(item.titleAr).font(.subheadline.bold()).foregroundStyle(Brand.ink)
                        }
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityIdentifier("quick-\(item.rawValue)")
                }
            }
            .padding(.horizontal)
        }
    }

    private func icon(_ item: QuickBrowse) -> String {
        switch item {
        case .fruity: return "leaf.fill"
        case .chocolate: return "square.grid.3x3.fill"
        case .floral: return "camera.macro"
        case .iced: return "snowflake"
        case .arabic: return "flame.fill"
        case .decaf: return "moon.zzz.fill"
        }
    }

    private func color(_ item: QuickBrowse) -> Color {
        switch item {
        case .fruity: return FlavorFamily.berry.color
        case .chocolate: return FlavorFamily.chocolate.color
        case .floral: return FlavorFamily.floral.color
        case .iced: return .cyan
        case .arabic: return Brand.gold
        case .decaf: return .indigo
        }
    }
}

// MARK: Community pulse

struct PulseSection: View {
    let items: [RemotePulseItem]
    var openCommunity: () -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("نبض المجتمع", systemImage: "waveform.path.ecg").font(.title3.bold())
                    Spacer()
                    Button("المجتمع", action: openCommunity).font(.subheadline.bold()).tint(Brand.olive)
                }
                .padding(.horizontal)
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                        row(item)
                        if index < min(items.count, 5) - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: RemotePulseItem) -> some View {
        let content = HStack(spacing: 10) {
            AvatarView(url: item.avatarUrl, name: item.name, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                (Text(item.name).bold() + Text(" ") + Text(item.actionAr))
                    .font(.subheadline).foregroundStyle(Brand.ink).lineLimit(2)
                Text([item.date.map { $0.formatted(.relative(presentation: .named)) }, item.note.map { "«\($0)»" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing(item)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())

        if let slug = item.lotSlug, item.kind != .recipe {
            NavigationLink(value: slug) { content }.buttonStyle(.plain)
        } else if let username = item.username {
            NavigationLink { PublicProfileView(username: username) } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private func trailing(_ item: RemotePulseItem) -> some View {
        switch item.kind {
        case .brew:
            if let stars = item.stars {
                Text(String(repeating: "★", count: stars)).font(.caption).foregroundStyle(Brand.gold)
            }
        case .recipe:
            Image(systemName: "book.closed.fill").foregroundStyle(Brand.olive)
        case .discovery:
            Label("اكتشاف", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(Brand.gold)
        }
    }
}

// MARK: Leaders, in one line

struct LeadersStrip: View {
    let leaders: [RemoteLeaderboard.Entry]
    let myRank: Int?
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                HStack(spacing: -10) {
                    ForEach(Array(leaders.prefix(3).enumerated()), id: \.offset) { index, entry in
                        AvatarView(url: entry.avatarUrl, name: entry.name, size: 32)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            .zIndex(Double(3 - index))
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                VStack(alignment: .leading, spacing: 1) {
                    Text("المتصدرين هالأسبوع").font(.subheadline.bold()).foregroundStyle(Brand.ink)
                    if let first = leaders.first {
                        Text("الأول: \(first.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let myRank {
                    Text("أنت #\(myRank)").font(.subheadline.bold()).foregroundStyle(Brand.olive)
                }
                Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(CardPressStyle())
        .padding(.horizontal)
    }
}
