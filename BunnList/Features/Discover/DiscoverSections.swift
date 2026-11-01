import BunnListCore
import SwiftUI

// The pieces of «اكتشف»: header, search, the newest coffee, browse by taste (with
// results in place), where coffees come from, new arrivals and the way into the
// whole catalog. Each section loads, fails and retries on its own.

/// A section's data: loading, loaded, or failed (with a retry, never sample data).
enum SectionLoad<Value: Equatable>: Equatable {
    case loading
    case loaded(Value)
    case failed

    var value: Value? { if case let .loaded(v) = self { return v } else { return nil } }
}

// MARK: Shared section chrome

struct DiscoverSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold()).foregroundStyle(Brand.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.bold())
                    .tint(Brand.olive)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal)
    }
}

/// "ما قدرنا نجيب …" with a retry button.
struct SectionFailure: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.secondary)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("إعادة المحاولة", action: retry)
                .font(.subheadline.bold()).tint(Brand.olive)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }
}

/// A quiet placeholder block while a section loads.
struct SkeletonBlock: View {
    var height: CGFloat
    var corner: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Brand.ink.opacity(0.06))
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

// MARK: Header and search

struct DiscoverHeader: View {
    let name: String?
    let avatarUrl: String?
    let isSignedIn: Bool
    var streak: Int? = nil
    var openAccount: () -> Void

    var body: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Greeting.text(hour: hour, name: isSignedIn ? name : nil))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text("قهوتك الجاية، هنا.")
                    .font(.title.bold()).foregroundStyle(Brand.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            if let streak, streak > 0 { StreakBadge(days: streak) }
            Button(action: openAccount) {
                AvatarView(url: avatarUrl, name: name, size: 44)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(isSignedIn ? "حسابي" : "تسجيل الدخول")
        }
        .padding(.horizontal)
    }
}

struct DiscoverSearchBar: View {
    var openSearch: () -> Void
    var openFilters: () -> Void
    var openScan: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openSearch) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("ابحث عن قهوة أو محمصة").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.body)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: Brand.ink.opacity(0.05), radius: 8, y: 3)
            }
            .accessibilityIdentifier("open-search")

            iconButton("line.3.horizontal.decrease", label: "الفلاتر", filled: false, action: openFilters)
                .accessibilityIdentifier("open-filters")
            iconButton("camera.viewfinder", label: "امسح كيس", filled: true, action: openScan)
                .accessibilityIdentifier("open-scan")
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func iconButton(_ symbol: String, label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(filled ? Brand.background : Brand.ink)
                .frame(width: 48, height: 48)
                .background(filled ? Brand.olive : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: Brand.ink.opacity(0.05), radius: 8, y: 3)
        }
        .accessibilityLabel(label)
    }
}

// MARK: The newest coffee

struct FeaturedLotCard: View {
    let lot: RemoteLot
    /// Brew methods the coffee is recommended for (from its detail), when known.
    let methods: [String]
    let inCollection: Bool
    var open: () -> Void
    var brew: () -> Void
    @State private var showProcess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                LotPhotoWell(imageUrl: lot.imageUrl, notes: lot.flavorNotes, roaster: lot.roasterNameAr, name: lot.nameAr,
                             origin: lot.originNameAr, originCode: lot.originCode, padding: 6)
                    .frame(width: 108, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("وصلت للدليل حديثًا").font(.caption.bold()).foregroundStyle(Brand.gold)
                    Text(lot.nameAr).font(.title2.bold()).lineLimit(2).minimumScaleFactor(0.85)
                    Text([lot.roasterNameAr, DiscoverText.originLine(lot)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).opacity(0.85)
                    if !lot.flavorNotes.isEmpty {
                        NotePills(notes: Array(lot.flavorNotes.prefix(4)))
                    }
                    if !methods.isEmpty {
                        Label("تنفع: \(methods.prefix(3).map(RecipeText.method).joined(separator: " · "))", systemImage: "cup.and.saucer")
                            .font(.caption).opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button(action: open) {
                    Label("اكتشف المحصول", systemImage: "chevron.left")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Brand.background, in: Capsule())
                        .foregroundStyle(Brand.olive)
                }
                .accessibilityIdentifier("featured-open")
                if inCollection {
                    Button(action: brew) {
                        Label("حضّرها", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Brand.background.opacity(0.15), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
                if DiscoverText.processGuide(lot.process) != nil {
                    Button { showProcess = true } label: {
                        Image(systemName: "info.circle").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("وش يعني \(lot.processNameAr ?? "المعالجة")؟")
                    .popover(isPresented: $showProcess) {
                        ProcessExplainer(lot: lot).presentationCompactAdaptation(.popover)
                    }
                }
            }
            .padding(.top, 12)
        }
        .padding(14)
        .foregroundStyle(Brand.background)
        .background {
            RoundedRectangle(cornerRadius: 24).fill(Brand.olive)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 24)))
        }
        .shadow(color: Brand.olive.opacity(0.22), radius: 14, y: 8)
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

private struct ProcessExplainer: View {
    let lot: RemoteLot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("معالجة \(lot.processNameAr ?? "")").font(.headline)
            Text(DiscoverText.processGuide(lot.process) ?? "").font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: 300, alignment: .leading)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon.font(.caption.bold()) }
    }
}

/// Flavor notes as small pills, colored by their family.
struct NotePills: View {
    let notes: [String]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(notes, id: \.self) { note in
                HStack(spacing: 4) {
                    Circle().fill(FlavorFamily.of(note).color).frame(width: 7, height: 7)
                    Text(note)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(0.14), in: Capsule())
            }
        }
    }
}

/// Wraps its children onto new lines (for pills).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // SwiftUI mirrors custom layouts for right-to-left, so this reads correctly in Arabic.
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width { y += row + spacing; x = 0; row = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: Browse by taste

struct TasteSection: View {
    let families: SectionLoad<[RemoteFacets.Facet]>
    @Binding var selected: FlavorFamily?
    let results: SectionLoad<[RemoteLot]>
    var retryFamilies: () -> Void
    var retryResults: () -> Void
    var showAll: (FlavorFamily) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionHeader(title: "اكتشف حسب ذوقك", subtitle: "اختر نكهة وتطلع لك محاصيلها هنا")
            switch families {
            case .loading:
                HStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 40, corner: 20).frame(width: 96) } }
                    .padding(.horizontal)
            case .failed:
                SectionFailure(message: "ما قدرنا نجيب النكهات.", retry: retryFamilies)
            case let .loaded(list):
                chips(list)
                if let family = selected { resultsRow(family) }
            }
        }
    }

    private func chips(_ list: [RemoteFacets.Facet]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(list) { facet in
                    if let family = FlavorFamily(rawValue: facet.value), family != .other {
                        let on = selected == family
                        Button {
                            withAnimation(.snappy) { selected = on ? nil : family }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(family.color).frame(width: 11, height: 11)
                                Text(family.shortNameAr)
                                if on { Image(systemName: "xmark").font(.caption2.bold()) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(on ? Brand.olive : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(on ? Brand.background : Brand.ink)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: on)
                        .accessibilityLabel("\(family.shortNameAr)، \(facet.count) محصول")
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityHint(on ? "اضغط لإلغاء الفلتر" : "يعرض محاصيل هالنكهة")
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func resultsRow(_ family: FlavorFamily) -> some View {
        switch results {
        case .loading:
            HStack(spacing: 12) { ForEach(0..<2, id: \.self) { _ in SkeletonBlock(height: 210).frame(width: 160) } }
                .padding(.horizontal)
        case .failed:
            SectionFailure(message: "ما قدرنا نجيب المحاصيل.", retry: retryResults)
        case let .loaded(lots):
            if lots.isEmpty {
                Text("ما فيه محاصيل بهالنكهة للحين.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(lots) { lot in
                            NavigationLink(value: lot.slug) {
                                DiscoverLotCard(lot: lot, showRoaster: true).frame(width: 164)
                            }
                            .buttonStyle(CardPressStyle())
                        }
                        Button { showAll(family) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.left.circle.fill").font(.largeTitle)
                                Text("كل محاصيل \(family.shortNameAr)").font(.subheadline.bold()).multilineTextAlignment(.center)
                            }
                            .foregroundStyle(Brand.olive)
                            .frame(width: 120, height: 210)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                .transition(.opacity)
            }
        }
    }
}

extension FlavorFamily {
    /// Short chip names.
    var shortNameAr: String {
        switch self {
        case .berry: return "توت"
        case .citrus: return "حمضيات"
        case .stoneFruit: return "خوخ ومشمش"
        case .tropical: return "استوائي"
        case .driedFruit: return "فواكه مجففة"
        case .floral: return "زهري"
        case .chocolate: return "شوكولاتة"
        case .caramel: return "كراميل"
        case .nutty: return "مكسرات"
        case .spice: return "توابل"
        case .tea: return "شاي"
        case .honey: return "عسل"
        case .other: return "أخرى"
        }
    }
}

// MARK: Where it comes from

struct OriginsRow: View {
    let origins: SectionLoad<[RemoteFacets.Facet]>
    var retry: () -> Void
    var open: (RemoteFacets.Facet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionHeader(title: "من وين؟", subtitle: "المنشأ يقول كثير عن الكوب")
            switch origins {
            case .loading:
                HStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 84, corner: 18).frame(width: 100) } }
                    .padding(.horizontal)
            case .failed:
                SectionFailure(message: "ما قدرنا نجيب المناشئ.", retry: retry)
            case let .loaded(list):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(list.filter { ReferenceCodes.flag($0.value) != nil }) { origin in
                            Button { open(origin) } label: {
                                VStack(spacing: 4) {
                                    Text(ReferenceCodes.flag(origin.value) ?? "").font(.largeTitle)
                                    Text(origin.labelAr).font(.subheadline.bold()).foregroundStyle(Brand.ink).lineLimit(1)
                                    Text("\(origin.count) محصول").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10).padding(.horizontal, 14)
                                .frame(minWidth: 96, minHeight: 44)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(CardPressStyle())
                            .accessibilityLabel("\(origin.labelAr)، \(origin.count) محصول")
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: New arrivals

struct NewArrivalsSection: View {
    let lots: SectionLoad<[RemoteLot]>
    var retry: () -> Void
    var showAll: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shown = lots.value ?? []
        let roaster = DiscoverText.sharedRoaster(shown)
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionHeader(title: "وصلت حديثًا", subtitle: roaster.map { "كلها من \($0)" },
                                  actionTitle: "عرض الكل", action: showAll)
            switch lots {
            case .loading:
                grid { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 230) } }
            case .failed:
                SectionFailure(message: "ما قدرنا نجيب الجديد.", retry: retry)
            case let .loaded(list):
                if list.isEmpty {
                    Text("ما فيه محاصيل جديدة للحين.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                } else {
                    grid {
                        ForEach(list) { lot in
                            NavigationLink(value: lot.slug) { DiscoverLotCard(lot: lot, showRoaster: roaster == nil) }
                                .buttonStyle(CardPressStyle())
                                .accessibilityIdentifier("new-\(lot.slug)")
                        }
                    }
                }
            }
        }
    }

    /// Two columns, one when the text is large.
    private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let columns = typeSize >= .xxLarge ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columns), spacing: 12) {
            content()
        }
        .padding(.horizontal)
    }
}

/// A coffee in «اكتشف»: the bag on its flavor wash, the name, origin and process,
/// three flavor dots, and the real rating (or an invitation to rate).
struct DiscoverLotCard: View {
    let lot: RemoteLot
    var showRoaster = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let wide = typeSize >= .xxLarge
        let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            LotPhotoWell(imageUrl: lot.imageUrl, notes: lot.flavorNotes, roaster: lot.roasterNameAr, name: lot.nameAr,
                         origin: lot.originNameAr, originCode: lot.originCode, padding: 8)
                .frame(width: wide ? 96 : nil, height: wide ? 112 : 140)
                .frame(maxWidth: wide ? 96 : .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(lot.nameAr).font(.headline).foregroundStyle(Brand.ink).lineLimit(2)
                if showRoaster, !lot.roasterNameAr.isEmpty {
                    Text(lot.roasterNameAr).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(DiscoverText.originLine(lot)).font(.footnote).foregroundStyle(.secondary).lineLimit(wide ? 2 : 1)
                HStack(spacing: 4) {
                    ForEach(FlavorFamily.spectrum(lot.flavorNotes).prefix(3), id: \.self) { family in
                        Circle().fill(family.color).frame(width: 9, height: 9)
                    }
                }
                .padding(.top, 2)
                .accessibilityHidden(true)
                Text(DiscoverText.rating(lot))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(lot.reviewCount > 0 ? Brand.gold : Brand.olive)
                    .padding(.top, 2)
            }
            .padding(.horizontal, wide ? 0 : 4)
            .padding(.top, wide ? 0 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Brand.ink.opacity(0.05), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: The whole catalog

struct CatalogEntryCard: View {
    let total: Int?
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill").font(.title2).foregroundStyle(Brand.olive)
                    .frame(width: 44, height: 44)
                    .background(Brand.olive.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("تصفّح كل الدليل").font(.headline).foregroundStyle(Brand.ink)
                    Text(total.map { "\($0) محصول · بحث وفلاتر وفرز" } ?? "بحث وفلاتر وفرز")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.left").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(CardPressStyle())
        .padding(.horizontal)
        .accessibilityIdentifier("open-catalog")
    }
}

// MARK: - For you (signed in): today's coffee, carry on, roasters' news, friends

/// Today's coffee for this person: the bag floats, the match ring fills, and why it fits.
struct DailyPickCard: View {
    let pick: RemoteForYou.DailyPick
    var open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var bob = false

    private var colors: [Color] {
        let families = FlavorFamily.spectrum(pick.lot.flavorNotes, limit: 2)
        let base = families.map(\.color)
        return base.count >= 2 ? base : (base + [Brand.brown, Brand.gold]).prefix(2).map { $0 }
    }

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: colors, startPoint: .topTrailing, endPoint: .bottomLeading)
                LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("قهوة اليوم لك").font(.caption.weight(.bold)).opacity(0.85)
                        Text(pick.lot.nameAr).font(.title2.bold()).lineLimit(2).minimumScaleFactor(0.8)
                        Text([pick.lot.roasterNameAr, ReferenceCodes.flag(pick.lot.originCode), pick.lot.originNameAr]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).opacity(0.9).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(pick.reason)
                            .font(.caption)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                            .lineLimit(3)
                        if let score = pick.score { MatchRing(score: score, play: shown).padding(.top, 4) }
                    }
                    .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    LotPhotoWell(imageUrl: pick.lot.imageUrl, notes: pick.lot.flavorNotes, roaster: pick.lot.roasterNameAr,
                                 name: pick.lot.nameAr, origin: pick.lot.originNameAr, originCode: pick.lot.originCode, padding: 6)
                        .frame(width: 128, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 8)
                        .offset(y: bob ? -6 : 2)
                        .rotationEffect(.degrees(bob ? -1.5 : 0.5))
                }
                .padding(16)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .scaleEffect(shown ? 1 : 0.96)
            .opacity(shown ? 1 : 0)
        }
        .buttonStyle(CardPressStyle())
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { shown = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true).delay(0.8)) { bob = true }
        }
        .accessibilityLabel("قهوة اليوم لك: \(pick.lot.nameAr)، \(pick.reason)")
    }
}

/// "92٪ تناسبك" as a ring that fills.
struct MatchRing: View {
    let score: Int
    let play: Bool
    var size: CGFloat = 60
    var tint: Color = .white

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: play ? CGFloat(score) / 100 : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.4).delay(0.5), value: play)
            VStack(spacing: -1) {
                Text("\(score)٪").font(.system(size: size * 0.27, weight: .bold))
                Text("تناسبك").font(.system(size: size * 0.15))
            }
            .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// A bag they own but haven't rated: rate it or brew it.
struct ResumeCard: View {
    let item: RemoteForYou.Resume
    var open: () -> Void
    var brew: () -> Void
    @State private var lit = 0

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    LotPhotoWell(imageUrl: item.lot.imageUrl, notes: item.lot.flavorNotes, roaster: item.lot.roasterNameAr,
                                 name: item.lot.nameAr, origin: item.lot.originNameAr, originCode: item.lot.originCode, padding: 3)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.lot.nameAr).font(.subheadline.bold()).foregroundStyle(Brand.ink).lineLimit(1)
                        Text("عندك \(ISODate.parse(item.since).map { ISODate.ago($0) } ?? "") · كيف كانت؟")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: "star.fill").font(.caption)
                                    .foregroundStyle(i < lit ? Brand.gold : Brand.brown.opacity(0.2))
                                    .scaleEffect(i < lit ? 1.12 : 1)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.lot.nameAr): قيّمها")
            Button(action: brew) {
                Label("حضّرها", systemImage: "cup.and.saucer.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Brand.olive, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .task {
            // The stars light up one by one: an invitation to rate.
            for i in 1...4 {
                try? await Task.sleep(for: .milliseconds(450 + i * 140))
                withAnimation(.spring(response: 0.3)) { lit = i }
            }
        }
    }
}

/// Roasters they collect, as rings that turn while they hold coffees not seen yet.
struct RoasterNewsRow: View {
    let news: [RemoteForYou.RoasterNews]
    var open: (String) -> Void
    @AppStorage("roasterNewsSeen") private var seenJSON = "{}"
    @State private var showing: RemoteForYou.RoasterNews?

    private var seen: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(seenJSON.utf8))) ?? [:]
    }

    private func markSeen(_ roaster: String) {
        var all = seen
        all[roaster] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { seenJSON = text }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionHeader(title: "جديد من محامصك", subtitle: "آخر ٣٠ يوم من المحامص اللي في مجموعتك")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(news) { roaster in
                        let unseen = roaster.unseen(since: ISODate.parse(seen[roaster.roasterNameAr]))
                        Button {
                            Haptics.tap()
                            markSeen(roaster.roasterNameAr)
                            showing = roaster
                        } label: {
                            VStack(spacing: 5) {
                                StoryRing(imageUrl: roaster.lots.first?.imageUrl, fresh: unseen > 0)
                                Text(roaster.roasterNameAr).font(.caption).foregroundStyle(Brand.ink).lineLimit(1)
                                Text(unseen > 0 ? (unseen == 1 ? "جديد" : "\(unseen) جديد") : " ")
                                    .font(.caption2.bold()).foregroundStyle(Color(red: 0.76, green: 0.27, blue: 0.35))
                            }
                            .frame(width: 70)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(roaster.roasterNameAr)، \(unseen) جديد")
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(item: $showing) { roaster in
            NavigationStack {
                List(roaster.lots) { lot in
                    Button {
                        showing = nil
                        open(lot.slug)
                    } label: {
                        HStack(spacing: 12) {
                            LotPhotoWell(imageUrl: lot.imageUrl, notes: [], roaster: roaster.roasterNameAr, name: lot.nameAr,
                                         origin: nil, originCode: nil, padding: 2)
                                .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lot.nameAr).foregroundStyle(Brand.ink)
                                Text("نزلت \(ISODate.parse(lot.publishedAt).map { ISODate.ago($0) } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("جديد \(roaster.roasterNameAr)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { showing = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// A story-style ring: turning colors while it holds something new.
struct StoryRing: View {
    let imageUrl: String?
    let fresh: Bool
    var size: CGFloat = 62
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(fresh
                      ? AnyShapeStyle(AngularGradient(colors: [Brand.gold, Color(red: 0.76, green: 0.27, blue: 0.35), Brand.olive, Brand.gold], center: .center))
                      : AnyShapeStyle(Brand.brown.opacity(0.18)))
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle().fill(Brand.background).padding(3)
            LotPhotoWell(imageUrl: imageUrl, notes: [], roaster: "", name: "", origin: nil, originCode: nil, padding: 4)
                .clipShape(Circle())
                .padding(5)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard fresh, !reduceMotion else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// What the people they follow brewed most this week.
struct FriendsDrinkingCard: View {
    let item: RemoteForYou.FriendsDrinking
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(Array(item.names.prefix(3).enumerated()), id: \.offset) { index, name in
                        Text(String(name.prefix(1)))
                            .font(.caption.bold())
                            .frame(width: 32, height: 32)
                            .background([Brand.brown.opacity(0.22), Brand.olive.opacity(0.25), Brand.gold.opacity(0.28)][index % 3], in: Circle())
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            .foregroundStyle(Brand.brown)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.lot.nameAr).font(.subheadline.bold()).foregroundStyle(Brand.ink).lineLimit(1)
                    Text(item.line).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(CardPressStyle())
        .padding(.horizontal)
    }
}

/// The streak flame next to the greeting.
struct StreakBadge: View {
    let days: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flick = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .scaleEffect(flick ? 1.18 : 1)
                .rotationEffect(.degrees(flick ? -8 : 0))
            Text(days == 1 ? "يوم" : days == 2 ? "يومين" : "\(days) أيام")
        }
        .font(.footnote.bold())
        .foregroundStyle(Color(red: 0.71, green: 0.38, blue: 0.10))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(red: 0.98, green: 0.91, blue: 0.82), in: Capsule())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { flick = true }
        }
        .accessibilityLabel("سلسلة \(days) أيام متتالية")
    }
}
