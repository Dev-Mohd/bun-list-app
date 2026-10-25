import BunnListCore
import SwiftUI

/// First run, step two: "what's at home?" Pick up to three coffees and they join
/// the collection as owned, so a new account never starts empty.
@MainActor
struct FirstCoffeesView: View {
    static let limit = 3
    var onDone: () -> Void

    @EnvironmentObject private var auth: AuthModel
    @State private var lots: [RemoteLot]?
    @State private var query = ""
    @State private var results: [RemoteLot]?
    @State private var selected: [String: RemoteLot] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var shown: [RemoteLot] { results ?? lots ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("وش عندك في البيت؟").font(.title.bold())
                    Text("اختر لين ٣ قهوات عندك الحين وتنضاف لمجموعتك. تقدر تمسح أكياسك بعدين وتضيف أكثر.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("ابحث باسم القهوة أو المحمصة", text: $query)
                        .onSubmit { Task { await search() } }
                        .submitLabel(.search)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .onChange(of: query) { _, v in if v.trimmingCharacters(in: .whitespaces).isEmpty { results = nil } }

                if lots == nil && results == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(shown) { lot in
                            Button { toggle(lot) } label: {
                                CoffeeCard(lot: lot, isSelected: selected[lot.id] != nil)
                            }
                            .buttonStyle(.plain)
                            .disabled(selected[lot.id] == nil && selected.count >= Self.limit)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Brand.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                Text("اخترت \(selected.count.formatted()) من \(Self.limit.formatted())").font(.caption).foregroundStyle(.secondary)
                Button { Task { await save() } } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text("أضفها لمجموعتي")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(selected.isEmpty ? Color.secondary.opacity(0.4) : Brand.olive, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty || isSaving)
                .accessibilityIdentifier("first-coffees-add")
                Button("تخطّي") { onDone() }.font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .task { lots = (try? await client.fetchLots()) ?? [] }
    }

    private func toggle(_ lot: RemoteLot) {
        if selected[lot.id] != nil {
            selected[lot.id] = nil
        } else if selected.count < Self.limit {
            selected[lot.id] = lot
        }
        Haptics.tap()
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        results = (try? await client.searchLots(query: q)) ?? []
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            for lot in selected.values {
                _ = try await auth.withToken {
                    try await client.updateCollectionFlags(slug: lot.slug, accessToken: $0,
                                                           owned: true, favorite: false, wantsToTry: false, tried: false)
                }
            }
            Haptics.tap()
            onDone()
        } catch {
            errorMessage = "تعذّرت الإضافة. حاول مجددًا."
        }
    }
}

/// A catalog card in BunnList's palette: the bag on a cream panel, then name,
/// roaster and origin; a gold ring and check when selected.
struct CoffeeCard: View {
    let lot: RemoteLot
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Brand.gold.opacity(0.12)
                if let url = lot.imageUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit().padding(10) } placeholder: { ProgressView() }
                } else {
                    CoffeeArtCard(roaster: lot.roasterNameAr, name: lot.nameAr, origin: lot.originNameAr, originCode: lot.originCode)
                }
            }
            .frame(height: 140)
            .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(lot.nameAr).font(.subheadline.bold()).lineLimit(1)
                Text(lot.roasterNameAr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let origin = lot.originNameAr {
                    Label(origin, systemImage: "globe").font(.caption2).foregroundStyle(Brand.olive).lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Brand.gold : Color.secondary.opacity(0.15), lineWidth: isSelected ? 3 : 1))
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(Brand.gold)
                    .background(Circle().fill(.white))
                    .padding(8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
