import BunnListCore
import SwiftUI

// Sections fed by /api/v1/home: trending (coffees, roasters, recipes) and the
// community pulse for «المجتمع», «كمّل من وين وقفت» for «حضّر»; and the search
// preset other screens open search with.

/// What a search opened from the home starts with.
struct SearchPreset: Identifiable, Hashable {
    let id = UUID()
    let filters: BrowseFilters
    /// Opens the filter sheet straight away (the filters button).
    var openFilters = false
    static func == (a: SearchPreset, b: SearchPreset) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
                    LoadingRows()
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
                LoadingRows()
            }
        }
        .task {
            let all = (try? await auth.withOptionalToken { try await client.exploreRecipes(accessToken: $0) }) ?? []
            recipe = all.first { $0.id == id }
            failed = recipe == nil
        }
    }
}

// MARK: Community pulse

struct PulseSection: View {
    let items: [RemotePulseItem]
    var title = "نبض المجتمع"
    var icon = "waveform.path.ecg"
    var limit = 5

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon).font(.title3.bold())
                    .padding(.horizontal)
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(limit).enumerated()), id: \.element.id) { index, item in
                        row(item)
                        if index < min(items.count, limit) - 1 { Divider().padding(.leading, 58) }
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
                .founderRing(item.founderNumber != nil, size: 36)
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

// MARK: - Posts: the pulse as cards with the bag, the numbers and «ودّي أجرّبها»

/// The pulse as posts, newest first.
struct PulsePostList: View {
    let items: [RemotePulseItem]
    var limit = 20

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(items.prefix(limit).enumerated()), id: \.element.id) { index, item in
                PulsePostCard(item: item)
                    .modifier(RiseIn(order: index))
            }
        }
        .padding(.horizontal)
    }
}

private struct RiseIn: ViewModifier {
    let order: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .offset(y: shown ? 0 : 20)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(Double(min(order, 6)) * 0.07)) { shown = true }
            }
    }
}

/// One person's brew, recipe or discovery, with the coffee's bag and a way to save it.
struct PulsePostCard: View {
    let item: RemotePulseItem
    @EnvironmentObject private var auth: AuthModel
    @State private var wanted = false
    @State private var beat = false
    @State private var showComments = false
    @State private var comments: Int?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var numbers: [String] {
        var out: [String] = []
        if let method = item.methodCode.flatMap({ ReferenceCodes.brewMethod($0)?.nameAr }) { out.append(method) }
        if let dose = item.doseGrams { out.append("\(RemoteRoasterRecipe.grams(dose)) جم") }
        if let dose = item.doseGrams, let water = item.waterGrams, dose > 0 {
            out.append("1:\(RemoteRoasterRecipe.grams((water / dose * 10).rounded() / 10))")
        }
        if let seconds = item.brewSeconds { out.append(RemoteRoasterRecipe.clock(seconds)) }
        return out
    }

    private var headline: String {
        switch item.kind {
        case .brew: return "حضّرت"
        case .recipe: return "نشرت وصفة"
        case .discovery: return "اكتشفت محصول جديد 🏅"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let slug = item.lotSlug, item.lotNameAr != nil {
                NavigationLink(value: slug) { coffee }.buttonStyle(.plain)
            }
            if let title = item.recipeTitle, item.kind == .recipe {
                Label("«\(title)»", systemImage: "book.closed.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.olive)
            }
            if let note = item.note, !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let ref = item.commentTarget {
                    Button { showComments = true } label: {
                        Label("\(comments ?? item.commentCount ?? 0)", systemImage: "bubble.left")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("التعليقات")
                    .sheet(isPresented: $showComments) {
                        CommentsSheet(target: ref.0, id: ref.1, title: "التعليقات") { comments = $0 }
                            .environmentObject(auth)
                    }
                }
                Spacer()
                if auth.isSignedIn, let slug = item.lotSlug {
                    Button { Task { await wantToTry(slug) } } label: {
                        Label(wanted ? "انضافت لـ«ودّي أجرّب»" : "ودّي أجرّبها", systemImage: wanted ? "bookmark.fill" : "bookmark")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(wanted ? Brand.olive : Brand.ink, in: RoundedRectangle(cornerRadius: 11))
                            .foregroundStyle(Brand.background)
                            .scaleEffect(beat ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(wanted)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var header: some View {
        let row = HStack(spacing: 10) {
            AvatarView(url: item.avatarUrl, name: item.name, size: 38)
                .founderRing(item.founderNumber != nil, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).font(.subheadline.bold()).foregroundStyle(Brand.ink)
                    if let number = item.founderNumber { FounderChip(number: number, compact: true, name: item.name) }
                }
                Text([item.username.flatMap { item.name.contains($0) ? nil : "@\($0)" }, headline,
                      item.date.map { $0.formatted(.relative(presentation: .named)) }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let stars = item.stars {
                Label("\(stars)", systemImage: "star.fill").font(.subheadline.bold()).foregroundStyle(Brand.gold)
            }
        }
        if let username = item.username {
            NavigationLink { PublicProfileView(username: username) } label: { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private var coffee: some View {
        HStack(spacing: 11) {
            LotPhotoWell(imageUrl: item.imageUrl, notes: [], roaster: item.roasterNameAr ?? "", name: item.lotNameAr ?? "",
                         origin: nil, originCode: item.originCode, padding: 4)
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.lotNameAr ?? "").font(.subheadline.bold()).foregroundStyle(Brand.ink).lineLimit(2)
                Text([item.roasterNameAr, ReferenceCodes.flag(item.originCode)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if !numbers.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(numbers, id: \.self) { n in
                            Text(n).font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(.systemBackground), in: Capsule())
                                .foregroundStyle(Brand.brown)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Brand.brown.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func wantToTry(_ slug: String) async {
        Haptics.tap()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { beat = true }
        defer { withAnimation(.spring(response: 0.3)) { beat = false } }
        do {
            let current = try await auth.withToken { try await client.fetchCollectionFlags(slug: slug, accessToken: $0) }
            _ = try await auth.withToken {
                try await client.updateCollectionFlags(slug: slug, accessToken: $0, owned: current.owned, favorite: current.favorite,
                                                       wantsToTry: true, tried: current.tried)
            }
            withAnimation(.spring(response: 0.35)) { wanted = true }
        } catch {
            // Left as is; they can try again.
        }
    }
}

/// «توأم ذوقك»: people whose coffees overlap yours most, with the share as a ring.
struct TasteTwinsRow: View {
    let people: [RemotePersonCard]
    @State private var shown = false

    var body: some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("توأم ذوقك", systemImage: "person.2.wave.2.fill").font(.title3.bold())
                    Spacer()
                    NavigationLink("الكل") { FindPeopleView() }.font(.subheadline.bold()).tint(Brand.olive)
                }
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(people.prefix(10)) { person in
                            NavigationLink { PublicProfileView(username: person.username) } label: { twin(person) }
                                .buttonStyle(CardPressStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .onAppear { shown = true }
        }
    }

    private func twin(_ person: RemotePersonCard) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Brand.brown.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: shown ? CGFloat(person.sharedPercent ?? 0) / 100 : 0)
                    .stroke(Brand.olive, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.3).delay(0.4), value: shown)
                AvatarView(url: person.avatarUrl, name: person.displayName ?? person.username, size: 48)
                    .founderRing(person.founderNumber != nil, size: 48)
            }
            .frame(width: 60, height: 60)
            .environment(\.layoutDirection, .leftToRight)
            Text(person.displayName ?? person.username).font(.caption.weight(.semibold)).foregroundStyle(Brand.ink).lineLimit(1)
            if let percent = person.sharedPercent, percent > 0 {
                Text("\(percent)٪").font(.caption.bold()).foregroundStyle(Brand.olive)
            } else if let reason = person.reasonAr {
                Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .frame(width: 96)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Weekly challenge

/// «تحدي الأسبوع»: what to do, time left, my progress filling up, how many joined.
struct WeeklyChallengeCard: View {
    let state: RemoteChallengeState
    var showCoffees: (BrowseFilters) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var bob = false
    @State private var celebrate = false

    var body: some View {
        if let c = state.challenge {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("تحدي الأسبوع · \(c.timeLeftAr())").font(.caption.weight(.bold)).opacity(0.85)
                        Text(c.titleAr).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                        if let sub = c.subtitleAr, !sub.isEmpty { Text(sub).font(.footnote).opacity(0.9) }
                    }
                    Spacer(minLength: 8)
                    if let emoji = c.emoji, !emoji.isEmpty {
                        Text(emoji).font(.system(size: 44))
                            .offset(y: bob ? -5 : 2)
                            .rotationEffect(.degrees(bob ? -6 : 3))
                    }
                }
                if let me = state.me {
                    VStack(alignment: .leading, spacing: 5) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.22))
                                Capsule().fill(Color(red: 0.91, green: 0.76, blue: 0.48))
                                    .frame(width: shown ? geo.size.width * CGFloat(me.progress) / CGFloat(max(c.target, 1)) : 0)
                                    .animation(.spring(response: 1, dampingFraction: 0.8).delay(0.4), value: shown)
                            }
                        }
                        .frame(height: 9)
                        .environment(\.layoutDirection, .rightToLeft)
                        Text(me.completed ? "خلّصت التحدي 🎉 +\(c.points) نقطة" : "\(me.progress) من \(c.target) · \(c.actionAr) \(c.target == 1 ? "قهوة وحدة" : "\(c.target) قهاوي مختلفة")")
                            .font(.caption.weight(.semibold))
                    }
                }
                HStack {
                    Text(state.participants == 0 ? "كن أول واحد يشارك" : "\(state.participants) شخص شاركوا · \(state.finished) خلّصوه")
                    Spacer()
                    Text("+\(c.points) نقطة وشارة")
                }
                .font(.caption).opacity(0.9)
                if !c.filters.isEmpty {
                    Button { showCoffees(c.browseFilters) } label: {
                        Label("القهاوي اللي تحسب", systemImage: "cup.and.saucer.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(LinearGradient(colors: [Brand.olive, Color(red: 0.18, green: 0.23, blue: 0.15)], startPoint: .topTrailing, endPoint: .bottomLeading),
                        in: RoundedRectangle(cornerRadius: 24))
            .overlay(alignment: .topLeading) {
                if celebrate {
                    Text("🎉").font(.system(size: 60)).transition(.scale.combined(with: .opacity)).padding(8)
                }
            }
            .scaleEffect(celebrate ? 1.03 : 1)
            .padding(.horizontal)
            .onAppear {
                shown = true
                if !reduceMotion { withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { bob = true } }
                if state.me?.justCompleted == true {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.6)) { celebrate = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { withAnimation { celebrate = false } }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Comments

/// A post's comments, with a box to add one; long-press to delete or report.
@MainActor
struct CommentsSheet: View {
    let target: CommentTarget
    let id: String
    let title: String
    var onCount: (Int) -> Void = { _ in }

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [RemoteComment]?
    @State private var failed = false
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @State private var reporting: ReportRef?
    @State private var blocking: RemoteComment?
    @FocusState private var focused: Bool
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if let comments {
                        if comments.isEmpty {
                            ContentUnavailableView("ما فيه تعليقات للحين", systemImage: "bubble.left.and.bubble.right",
                                                   description: Text("كن أول من يعلّق."))
                        } else {
                            ScrollViewReader { proxy in
                                List {
                                    ForEach(comments) { comment in row(comment).id(comment.id) }
                                }
                                .listStyle(.plain)
                                .onChange(of: comments.count) { if let last = comments.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                            }
                        }
                    } else if failed {
                        ContentUnavailableView {
                            Label("ما قدرنا نجيب التعليقات", systemImage: "wifi.exclamationmark")
                        } actions: {
                            Button("إعادة المحاولة") { Task { await load() } }
                        }
                    } else {
                        ProgressView().frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
                composer
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .task { await load() }
            .sheet(item: $reporting) { ReportSheet(ref: $0) }
            .confirmationDialog("تحظر @\(blocking?.username ?? "")؟", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible) {
                Button("حظر", role: .destructive) { if let c = blocking { Task { await block(c) } } }
            } message: {
                Text("ما بتشوفون نشاط وتعليقات بعض. تقدر تلغي الحظر من الإعدادات.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func block(_ c: RemoteComment) async {
        guard let username = c.username else { return }
        do {
            _ = try await auth.withToken { try await client.setBlocked(true, username: username, accessToken: $0) }
            Haptics.tap()
            withAnimation { comments?.removeAll { $0.username == username } }
            onCount(comments?.count ?? 0)
        } catch {
            self.error = "ما قدرنا نحظره، جرّب مرة ثانية."
        }
        blocking = nil
    }

    private func row(_ c: RemoteComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if c.official { OfficialAvatar(size: 34) } else { AvatarView(url: c.avatarUrl, name: c.name, size: 34) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if c.official { OfficialName() } else { Text(c.name).font(.subheadline.bold()) }
                    if let date = ISODate.parse(c.createdAt) {
                        Text(date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(c.body).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .contextMenu {
            if c.canDelete {
                Button(role: .destructive) { Task { await remove(c) } } label: { Label("حذف", systemImage: "trash") }
            }
            if auth.isSignedIn && !c.isMine {
                Button { reporting = ReportRef(target: .comment, targetID: c.id) } label: { Label("بلّغ", systemImage: "flag") }
            }
            if auth.isSignedIn && !c.isMine && !c.official, let username = c.username {
                Button(role: .destructive) { blocking = c } label: { Label("حظر @\(username)", systemImage: "hand.raised.fill") }
            }
        }
        .swipeActions {
            if c.canDelete {
                Button(role: .destructive) { Task { await remove(c) } } label: { Label("حذف", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder private var composer: some View {
        if auth.isSignedIn {
            VStack(spacing: 4) {
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack(spacing: 8) {
                    TextField("اكتب تعليق…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    Button { Task { await send() } } label: {
                        Image(systemName: sending ? "ellipsis" : "arrow.up.circle.fill").font(.system(size: 30))
                    }
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .tint(Brand.olive)
                }
                Text("\(draft.count)/500").font(.caption2).foregroundStyle(draft.count > 500 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
        } else {
            Text("سجّل دخولك عشان تعلّق").font(.footnote).foregroundStyle(.secondary).padding()
        }
    }

    private func load() async {
        failed = false
        do {
            let result = try await client.fetchComments(target, id: id, accessToken: auth.currentAccessToken())
            comments = result.comments
            onCount(result.count)
        } catch {
            if comments == nil { failed = true }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            let comment = try await auth.withToken { try await client.postComment(target, id: id, body: text, accessToken: $0) }
            Haptics.tap()
            withAnimation(.spring(response: 0.35)) { comments = (comments ?? []) + [comment] }
            draft = ""
            onCount(comments?.count ?? 0)
        } catch APIError.rateLimited {
            error = "على هونك 🙂 جرّب بعد دقيقة."
        } catch APIError.forbidden {
            error = "حسابك موقوف عن النشر حاليًا."
        } catch {
            self.error = "ما انرسل التعليق، جرّب مرة ثانية."
        }
    }

    private func remove(_ c: RemoteComment) async {
        do {
            try await auth.withToken { try await client.deleteComment(id: c.id, accessToken: $0) }
            withAnimation { comments?.removeAll { $0.id == c.id } }
            onCount(comments?.count ?? 0)
        } catch {
            self.error = "ما انحذف التعليق."
        }
    }
}
