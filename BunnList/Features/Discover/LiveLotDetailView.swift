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
        }
    }

    private func detail(_ lot: RemoteLotDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(lot)
                VStack(alignment: .leading, spacing: 6) {
                    Text(lot.nameAr).font(.title2.bold())
                    Text(lot.roasterNameAr).font(.headline).foregroundStyle(.secondary)
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
                if !lot.brewStats.isEmpty {
                    section("التقييم حسب طريقة التحضير") { brewStats(lot.brewStats) }
                }

                reviewSection(lot)
            }
            .padding()
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
        Task { await model.load() } // refresh aggregates + per-method stats
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
