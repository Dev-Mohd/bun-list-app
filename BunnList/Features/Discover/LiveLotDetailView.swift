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
    @State private var flags = RemoteCollectionFlags(owned: false, favorite: false, wantsToTry: false, tried: false)
    @State private var reviews: [RemoteReview] = []
    @State private var showRecipes = false

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
        reviews = (try? await client.fetchReviews(slug: slug)) ?? []
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
                    if let discoverer = lot.discoveredBy {
                        Label("اكتشفها: \(discoverer)", systemImage: "star.circle.fill")
                            .font(.subheadline).foregroundStyle(Brand.gold)
                            .accessibilityIdentifier("lot-discoverer")
                    }
                    if lot.reviewCount > 0 {
                        Label("\(lot.averageRating.formatted(.number.precision(.fractionLength(1)))) · \(lot.reviewCount) تقييم",
                              systemImage: "star.fill")
                            .font(.subheadline).foregroundStyle(Brand.olive)
                    }
                }

                facts(lot)

                if !lot.flavorNotes.isEmpty {
                    section("النكهات") { chips(lot.flavorNotes) }
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

                reviewSection(lot)

                if !reviews.isEmpty {
                    section("تقييمات الناس") {
                        VStack(spacing: 14) {
                            ForEach(reviews) { PublicReviewRow(review: $0) }
                        }
                    }
                }
            }
            .padding()
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

    @ViewBuilder
    private func reviewSection(_ lot: RemoteLotDetail) -> some View {
        Divider().padding(.vertical, 4)
        if auth.isSignedIn {
            VStack(alignment: .leading, spacing: 8) {
                if let mine = myReview {
                    Label("تقييمك: \(mine.rating) من ٥ · \(LiveLotDetailView.brewLabel(mine.brewMethod))",
                          systemImage: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(Brand.olive)
                }
                Button {
                    showReviewForm = true
                } label: {
                    Label(myReview == nil ? "قيّم هذا المحصول" : "عدّل تقييمك", systemImage: "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("review-cta")
            }
        } else {
            Text("سجّل الدخول من تبويب «حسابي» لتقييم هذا المحصول.")
                .font(.callout).foregroundStyle(.secondary)
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
        Group {
            if let urlString = lot.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }
            } else {
                Brand.olive.opacity(0.12).overlay(
                    Image(systemName: "cup.and.saucer.fill").font(.largeTitle).foregroundStyle(Brand.olive)
                )
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func facts(_ lot: RemoteLotDetail) -> some View {
        VStack(spacing: 8) {
            if let origin = lot.originNameAr { factRow("المنشأ", origin) }
            if let region = lot.regionAr, !region.isEmpty { factRow("المنطقة", region) }
            if let process = lot.processLabel, !process.isEmpty { factRow("المعالجة", process) }
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
        case "COLD_BREW": return "كولد برو"
        default: return "أخرى"
        }
    }
}

/// One published review in the "تقييمات الناس" list.
private struct PublicReviewRow: View {
    let review: RemoteReview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(review.authorName).font(.subheadline.weight(.semibold))
                Spacer()
                stars
            }
            HStack(spacing: 8) {
                Text(LiveLotDetailView.brewLabel(review.brewMethod))
                if review.wouldBuyAgain { Label("يشتريه ثانية", systemImage: "arrow.clockwise") }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let body = review.body, !body.isEmpty {
                Text(body).font(.callout)
            }
            if let date = Self.shortDate(review.createdAt) {
                Text(date).font(.caption2).foregroundStyle(.secondary)
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
