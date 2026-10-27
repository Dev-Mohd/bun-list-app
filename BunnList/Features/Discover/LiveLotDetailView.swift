import BunnListCore
import SwiftUI

/// Full detail for one server lot (GET /api/v1/catalog/lots/[slug]): hero, origin,
/// process, flavours, description and per-method brew ratings.
@MainActor
final class LiveLotDetailModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded(RemoteLotDetail)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    private let client: CatalogAPIClient
    private let slug: String

    init(slug: String, client: CatalogAPIClient = CatalogAPIClient(transport: URLSessionTransport())) {
        self.slug = slug
        self.client = client
    }

    func load() async {
        phase = .loading
        do {
            phase = .loaded(try await client.fetchLotDetail(slug: slug))
        } catch {
            phase = .failed("تعذّر جلب تفاصيل المحصول. حاول مجددًا.")
        }
    }
}

struct LiveLotDetailView: View {
    let slug: String
    @StateObject private var model: LiveLotDetailModel
    @EnvironmentObject private var auth: AuthModel
    @State private var myReview: RemoteMyReview?
    @State private var showReviewForm = false
    @State private var reporting: ReportRef?
    @State private var flags = RemoteCollectionFlags(owned: false, favorite: false, wantsToTry: false, tried: false)
    @State private var reviews: [RemoteReview] = []
    /// "مفيد" changes made here, by review id.
    @State private var helpful: [String: RemoteLikeState] = [:]
    @State private var showRecipes = false
    @State private var showShareCard = false

    init(slug: String) {
        self.slug = slug
        _model = StateObject(wrappedValue: LiveLotDetailModel(slug: slug))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("جارٍ الجلب…")
            case let .failed(message):
                ContentUnavailableView {
                    Label("تعذّر الجلب", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("إعادة المحاولة") { Task { await model.load() } }.buttonStyle(.borderedProminent)
                }
            case let .loaded(lot):
                detail(lot)
            }
        }
        .brandScreen()
        .navigationTitle("المحصول")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            await loadMyReview()
            await loadCollection()
            await loadReviews()
        }
    }

    private func loadReviews() async {
        let client = CatalogAPIClient(transport: URLSessionTransport())
        reviews = (try? await auth.withOptionalToken { try await client.fetchReviews(slug: slug, accessToken: $0) }) ?? []
        helpful = [:]
    }

    private var collectionControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                collectionToggle("لديّ", "checkmark.circle.fill", flags.owned) { apply(owned: !flags.owned) }
                collectionToggle("مفضّل", "heart.fill", flags.favorite) { apply(favorite: !flags.favorite) }
            }
            HStack(spacing: 8) {
                collectionToggle("ودّي أجرّب", "bookmark.fill", flags.wantsToTry) { apply(wantsToTry: !flags.wantsToTry) }
                collectionToggle("جرّبته", "cup.and.saucer.fill", flags.tried) { apply(tried: !flags.tried) }
            }
        }
    }

    private func collectionToggle(_ label: String, _ icon: String, _ isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isOn ? Brand.olive.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(isOn ? Brand.olive : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("collection-\(label)")
    }

    private func apply(owned: Bool? = nil, favorite: Bool? = nil, wantsToTry: Bool? = nil, tried: Bool? = nil) {
        let updated = RemoteCollectionFlags(
            owned: owned ?? flags.owned,
            favorite: favorite ?? flags.favorite,
            wantsToTry: wantsToTry ?? flags.wantsToTry,
            tried: tried ?? flags.tried
        )
        Haptics.tap()
        let previous = flags
        flags = updated // optimistic
        Task { await persist(updated, previous: previous) }
    }

    private func persist(_ updated: RemoteCollectionFlags, previous: RemoteCollectionFlags) async {
        guard let token = auth.currentAccessToken() else { flags = previous; return }
        let client = CatalogAPIClient(transport: URLSessionTransport())
        func put(_ t: String) async throws -> RemoteCollectionFlags {
            try await client.updateCollectionFlags(slug: slug, accessToken: t, owned: updated.owned,
                                                   favorite: updated.favorite, wantsToTry: updated.wantsToTry, tried: updated.tried)
        }
        do {
            flags = try await put(token)
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken(), let saved = try? await put(fresh) { flags = saved }
            else { flags = previous }
        } catch {
            flags = previous // revert on failure
        }
    }

    private func loadCollection() async {
        guard auth.isSignedIn, let token = auth.currentAccessToken() else { return }
        let client = CatalogAPIClient(transport: URLSessionTransport())
        do {
            flags = try await client.fetchCollectionFlags(slug: slug, accessToken: token)
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken(), let loaded = try? await client.fetchCollectionFlags(slug: slug, accessToken: fresh) {
                flags = loaded
            }
        } catch {
            // keep defaults
        }
    }

    private func detail(_ lot: RemoteLotDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(lot)
                VStack(alignment: .leading, spacing: 6) {
                    Text(lot.nameAr).font(.title2.bold())
                    Text(lot.roasterNameAr).font(.headline).foregroundStyle(.secondary)
                    if let tags = lot.tags, !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Label(LotTagText.nameAr(tag.tag),
                                      systemImage: tag.tag == "luxury" ? "crown.fill" : tag.tag == "infused" ? "drop.fill" : "moon.zzz.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(tag.tag == "luxury" ? Brand.gold.opacity(0.22) : Brand.olive.opacity(0.14), in: Capsule())
                                    .foregroundStyle(tag.tag == "luxury" ? Brand.gold : Brand.olive)
                                    .help(tag.note ?? "")
                            }
                        }
                    }
                    if lot.discoverer == nil, let discoverer = lot.discoveredBy {
                        // Older servers: the name only.
                        Label("اكتشفها: \(discoverer)", systemImage: "star.circle.fill")
                            .font(.subheadline).foregroundStyle(Brand.gold)
                    }
                }

                TasteFingerprintCard(notes: lot.flavorNotes, origin: lot.originNameAr, process: lot.processNameAr)

                if auth.isSignedIn {
                    TasteMatchCard(slug: lot.slug)
                        .id(myReview?.rating) // reloads after rating it
                }

                RatingCard(average: lot.averageRating, count: lot.reviewCount, myRating: myReview?.rating,
                           isSignedIn: auth.isSignedIn) { showReviewForm = true }

                facts(lot)

                if lot.flavorNotes.count > 3 {
                    section("كل النكهات") { chips(lot.flavorNotes) }
                }
                if let discoverer = lot.discoverer {
                    DiscovererCard(discoverer: discoverer, onReport: auth.isSignedIn && discoverer.note?.isEmpty == false
                        ? { reporting = ReportRef(target: .note, targetID: lot.id) } : nil)
                }
                if let description = lot.descriptionAr, !description.isEmpty {
                    section("الوصف") { Text(description).font(.body).foregroundStyle(.secondary) }
                }
                if auth.isSignedIn {
                    section("مجموعتي") { collectionControls }
                    section("تجاربي") {
                        ServerExperiencesSection(slug: slug) { Task { await loadCollection() } }
                    }
                }

                if let community = lot.community, community.collectors + community.brewers > 0 {
                    section("المجتمع") { LotCommunityCard(community: community) }
                }

                if !lot.brewStats.isEmpty {
                    section("التقييم حسب طريقة التحضير") { brewStats(lot.brewStats) }
                }

                section("الوصفات") {
                    Button { showRecipes = true } label: {
                        Label("وصفات هذه القهوة", systemImage: "book.closed")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.olive)
                    .accessibilityIdentifier("lot-recipes")
                }

                if !reviews.isEmpty {
                    section("تقييمات الناس") {
                        VStack(spacing: 14) {
                            ForEach(reviews) { review in
                                PublicReviewRow(
                                    review: review,
                                    helpful: helpful[review.id]
                                        ?? RemoteLikeState(count: review.helpfulCount ?? 0, liked: review.markedHelpful ?? false),
                                    canMark: auth.isSignedIn && review.isMine != true && review.helpfulCount != nil,
                                    onReport: auth.isSignedIn && review.isMine != true
                                        ? { reporting = ReportRef(target: .review, targetID: review.id) } : nil
                                ) { Task { await toggleHelpful(review) } }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if auth.isSignedIn {
                    Button { apply(wantsToTry: !flags.wantsToTry) } label: {
                        Image(systemName: flags.wantsToTry ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(flags.wantsToTry ? "إزالة من ودّي أجرّب" : "ودّي أجرّبها")
                    Button { apply(favorite: !flags.favorite) } label: {
                        Image(systemName: flags.favorite ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel(flags.favorite ? "إزالة من المفضلة" : "أضف للمفضلة")
                }
                Button { showShareCard = true } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("مشاركة")
                    .accessibilityIdentifier("lot-share")
            }
        }
        .tint(Brand.olive)
        .sheet(item: $reporting) { ReportSheet(ref: $0) }
        .sheet(isPresented: $showShareCard) {
            ShareCardSheet(lot: lot, myRating: myReview?.rating).environmentObject(auth)
        }
        .sheet(isPresented: $showRecipes) {
            RecipesHubView(lot: RemoteRecipeLot(slug: lot.slug, nameAr: lot.nameAr, roasterNameAr: lot.roasterNameAr),
                           startOn: .explore)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showReviewForm) {
            ReviewFormView(slug: slug, brewMethods: lot.recommendedBrewMethods, existing: myReview, onSaved: applyResult)
                .environmentObject(auth)
        }
    }

    private func toggleHelpful(_ review: RemoteReview) async {
        let current = helpful[review.id] ?? RemoteLikeState(count: review.helpfulCount ?? 0, liked: review.markedHelpful ?? false)
        let wanted = !current.liked
        helpful[review.id] = RemoteLikeState(count: max(0, current.count + (wanted ? 1 : -1)), liked: wanted)
        Haptics.tap()
        let client = CatalogAPIClient(transport: URLSessionTransport())
        do {
            helpful[review.id] = try await auth.withToken { try await client.setLike(wanted, on: .review, id: review.id, accessToken: $0) }
        } catch {
            helpful[review.id] = current
        }
    }

    private func applyResult(_ result: RemoteReviewResult) {
        myReview = result.review
        Task {
            await model.load() // refresh aggregates + per-method stats
            await loadReviews()
        }
    }

    private func loadMyReview() async {
        guard auth.isSignedIn, let token = auth.currentAccessToken() else { myReview = nil; return }
        let client = CatalogAPIClient(transport: URLSessionTransport())
        do {
            myReview = try await client.fetchMyReview(slug: slug, accessToken: token)
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken() {
                myReview = try? await client.fetchMyReview(slug: slug, accessToken: fresh)
            }
        } catch {
            myReview = nil // no prefill; not fatal
        }
    }

    private func hero(_ lot: RemoteLotDetail) -> some View {
        // The whole bag, never cropped, on its main flavor's wash.
        LotPhotoWell(imageUrl: lot.imageUrl, notes: lot.flavorNotes, roaster: lot.roasterNameAr, name: lot.nameAr,
                     origin: lot.originNameAr, originCode: lot.originCode, padding: 10)
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func facts(_ lot: RemoteLotDetail) -> some View {
        VStack(spacing: 8) {
            if let origin = lot.originNameAr { factRow("المنشأ", origin) }
            if let region = lot.regionAr, !region.isEmpty { factRow("المنطقة", region) }
            if let process = lot.processNameAr { factRow("المعالجة", process) }
            if let variety = lot.variety, !variety.isEmpty { factRow("الصنف", variety) }
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }
            .font(.subheadline)
    }

    private func brewStats(_ stats: [RemoteBrewStat]) -> some View {
        VStack(spacing: 10) {
            ForEach(stats) { stat in
                HStack {
                    Text(Self.brewLabel(stat.method)).font(.subheadline.weight(.medium))
                    Spacer()
                    Label(stat.averageRating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                        .font(.caption).foregroundStyle(Brand.olive)
                    Text("· \(stat.reviewCount)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func chips(_ items: [String]) -> some View {
        FlowChips(items: items)
    }

    static func brewLabel(_ method: String) -> String {
        switch method {
        case "ESPRESSO": return "إسبريسو"
        case "V60": return "V60"
        case "CHEMEX": return "كيمكس"
        case "AEROPRESS": return "إيروبرس"
        case "FRENCH_PRESS": return "فرنش برس"
        case "ARABIC": return "قهوة عربية"
        case "COLD_BREW": return "كولد برو"
        default: return "أخرى"
        }
    }
}

/// One published review in the "تقييمات الناس" list.
private struct PublicReviewRow: View {
    let review: RemoteReview
    let helpful: RemoteLikeState
    let canMark: Bool
    var onReport: (() -> Void)?
    var onHelpful: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let username = review.authorUsername, review.isMine != true {
                    NavigationLink { PublicProfileView(username: username) } label: {
                        Text(review.authorName).font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(review.authorName).font(.subheadline.weight(.semibold))
                }
                Spacer()
                stars
                if let onReport {
                    Menu {
                        Button(role: .destructive, action: onReport) { Label("بلّغ عن التقييم", systemImage: "flag") }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("خيارات التقييم")
                }
            }
            HStack(spacing: 8) {
                Text(LiveLotDetailView.brewLabel(review.brewMethod))
                if review.wouldBuyAgain { Label("يشتريه ثانية", systemImage: "arrow.clockwise") }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let body = review.body, !body.isEmpty {
                Text(body).font(.callout)
            }
            HStack {
                if let date = Self.shortDate(review.createdAt) {
                    Text(date).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if canMark {
                    Button(action: onHelpful) {
                        Label(helpful.count > 0 ? "مفيد · \(helpful.count.formatted())" : "مفيد",
                              systemImage: helpful.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(helpful.liked ? Brand.olive.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
                            .foregroundStyle(helpful.liked ? Brand.olive : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("review-helpful-\(review.id)")
                } else if helpful.count > 0 {
                    Label("\(helpful.count.formatted()) شافوه مفيد", systemImage: "hand.thumbsup")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var stars: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= review.rating ? "star.fill" : "star")
                    .font(.caption2).foregroundStyle(Brand.olive)
            }
        }
    }

    private static func shortDate(_ iso: String) -> String? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        return date?.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Simple wrapping row of pill chips.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(items) { item in
            Text(item)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Brand.olive.opacity(0.12), in: Capsule())
                .foregroundStyle(Brand.olive)
        }
    }
}

/// Minimal wrapping layout for a handful of short chips.
private struct FlexibleWrap<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        HStack { // chips are few; a horizontal scroll keeps it simple and RTL-correct
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(Array(data), id: \.self) { content($0) } }
            }
        }
    }
}
