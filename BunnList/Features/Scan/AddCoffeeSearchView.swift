import BunnListCore
import SwiftUI

/// «أضف قهوة» (approved mockup): search as you type; each result shows the bag, the roaster with the flag,
/// process and rating, and its flavour notes in their colours, with the typed letters highlighted. Coffees you
/// already have come first under «في مجموعتك» (marked «✓ عندك»), the rest under «من الدليل». Quick filters
/// narrow by country, process or «عندي». Under the results: «ما لقيت قهوتك؟ اقترحها» opens the suggestion form
/// with what you typed.
struct AddCoffeeSearchView: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [RemoteLot] = []
    @State private var searched = false
    @State private var isSearching = false
    @State private var added: Set<String> = []
    @State private var owned: Set<String> = []
    @State private var message: String?
    @State private var showSuggest = false
    @State private var filter: Filter = .all

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    enum Filter: Hashable {
        case all, mine
        case origin(String)
        case process(String)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filtered: [RemoteLot] {
        results.filter { lot in
            switch filter {
            case .all: return true
            case .mine: return owned.contains(lot.slug) || added.contains(lot.slug)
            case let .origin(code): return lot.originCode == code
            case let .process(code): return lot.process == code
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let message {
                        Label(message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    if !results.isEmpty { filters }
                    if isSearching && results.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 78, corner: 18).padding(.horizontal) }
                    } else {
                        let mine = filtered.filter { owned.contains($0.slug) || added.contains($0.slug) }
                        let others = filtered.filter { !(owned.contains($0.slug) || added.contains($0.slug)) }
                        if !mine.isEmpty {
                            group("في مجموعتك")
                            ForEach(mine) { lot in row(lot, have: true) }
                        }
                        if !others.isEmpty {
                            group("من الدليل")
                            ForEach(others) { lot in row(lot, have: false) }
                        }
                        if searched && results.isEmpty {
                            Text("ما لقينا «\(trimmed)» في الدليل.").font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                        }
                    }
                    if searched || !trimmed.isEmpty { suggestCard }
                }
                .padding(.vertical)
            }
            .background(Brand.background.ignoresSafeArea())
            .brandScreen()
            .navigationTitle("أضف قهوة")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "ابحث بالاسم أو المحمصة")
            .onSubmit(of: .search) { Task { await search() } }
            // Search as you type, after a short pause.
            .task(id: trimmed) {
                guard trimmed.count >= 2 else { return }
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled { await search() }
            }
            .task { await loadOwned() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSuggest = true } label: { Label("اقترح", systemImage: "plus") }
                        .accessibilityIdentifier("open-suggest")
                }
            }
            .sheet(isPresented: $showSuggest) {
                SuggestCoffeeView(prefillName: trimmed).environmentObject(auth)
            }
        }
    }

    // MARK: Parts

    private var filters: some View {
        let origins = topCodes(results.compactMap(\.originCode))
        let processes = topCodes(results.map(\.process))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("الكل \(results.count.formatted())", .all)
                ForEach(origins, id: \.self) { code in
                    let name = results.first { $0.originCode == code }?.originNameAr ?? code
                    chip([ReferenceCodes.flag(code), name].compactMap { $0 }.joined(separator: " "), .origin(code))
                }
                ForEach(processes, id: \.self) { code in
                    chip(ReferenceCodes.process(code)?.nameAr ?? code, .process(code))
                }
                if results.contains(where: { owned.contains($0.slug) || added.contains($0.slug) }) { chip("عندي", .mine) }
            }
            .padding(.horizontal)
        }
    }

    private func topCodes(_ codes: [String]) -> [String] {
        Dictionary(grouping: codes, by: { $0 }).filter { $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }.prefix(2).map(\.key)
    }

    private func chip(_ title: String, _ value: Filter) -> some View {
        Button { filter = filter == value ? .all : value; Haptics.tap() } label: {
            Text(title).font(.caption.bold())
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(filter == value ? Brand.ink : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(filter == value ? Brand.background : Brand.ink)
        }
        .buttonStyle(.plain)
    }

    private func group(_ title: String) -> some View {
        Text(title).font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 4)
    }

    private func row(_ lot: RemoteLot, have: Bool) -> some View {
        HStack(spacing: 10) {
            LotPhotoWell(imageUrl: lot.imageUrl, notes: lot.flavorNotes, roaster: lot.roasterNameAr, name: lot.nameAr,
                         origin: lot.originNameAr, originCode: lot.originCode, padding: 3)
                .frame(width: 52, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(highlighted(lot.nameAr)).font(.subheadline.bold()).foregroundStyle(Brand.ink).lineLimit(1)
                Text(meta(lot)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !lot.flavorNotes.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(lot.flavorNotes.prefix(2), id: \.self) { note in
                            let color = FlavorFamily.of(note).color
                            Text(note).font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(color.opacity(0.15), in: Capsule())
                                .foregroundStyle(color)
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            if have {
                Label("عندك", systemImage: "checkmark").font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Brand.background, in: Capsule())
                    .foregroundStyle(Brand.olive)
            } else {
                Button("أضف") { Task { await add(lot) } }
                    .font(.caption.bold())
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Brand.olive, in: Capsule())
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private func meta(_ lot: RemoteLot) -> String {
        var parts = [lot.roasterNameAr]
        let place = [ReferenceCodes.flag(lot.originCode), ReferenceCodes.process(lot.process)?.nameAr].compactMap { $0 }.joined(separator: " ")
        if !place.isEmpty { parts.append(place) }
        if lot.reviewCount > 0 { parts.append("★ \(lot.averageRating.formatted(.number.precision(.fractionLength(1))))") }
        return parts.joined(separator: " · ")
    }

    /// The name with the typed text shaded, so it's clear why it matched.
    private func highlighted(_ name: String) -> AttributedString {
        var text = AttributedString(name)
        guard trimmed.count >= 2, let range = text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) else { return text }
        text[range].backgroundColor = Brand.gold.opacity(0.25)
        return text
    }

    private var suggestCard: some View {
        Button { showSuggest = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(Brand.gold)
                    .frame(width: 42, height: 42)
                    .background(Brand.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ما لقيت قهوتك؟ اقترحها").font(.subheadline.bold()).foregroundStyle(Brand.ink)
                    Text(trimmed.isEmpty ? "صوّر الكيس ونعبّي الباقي" : "بالاسم «\(trimmed)»، أو صوّر الكيس").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 4)
        .accessibilityIdentifier("suggest-from-search")
    }

    // MARK: Data

    private func loadOwned() async {
        guard auth.isSignedIn else { return }
        if let items = try? await auth.withToken({ try await client.fetchCollection(accessToken: $0) }) {
            owned = Set(items.filter(\.owned).map(\.slug))
        }
    }

    private func search() async {
        let q = trimmed
        guard q.count >= 2 else { return }
        isSearching = true
        message = nil
        defer { isSearching = false }
        let found = (try? await client.searchLots(query: q)) ?? []
        guard q == trimmed else { return }
        results = found
        filter = .all
        searched = true
    }

    private func add(_ lot: RemoteLot) async {
        guard auth.isSignedIn else {
            message = "سجّل الدخول من «ملفي» لإضافة القهوة إلى مجموعتك."
            return
        }
        do {
            _ = try await auth.withToken {
                try await client.updateCollectionFlags(slug: lot.slug, accessToken: $0, owned: true, favorite: false, wantsToTry: false, tried: false)
            }
            added.insert(lot.slug)
            Haptics.tap()
        } catch {
            message = "تعذّرت الإضافة. حاول مجددًا."
        }
    }
}
