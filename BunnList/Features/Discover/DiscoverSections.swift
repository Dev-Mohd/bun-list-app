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
