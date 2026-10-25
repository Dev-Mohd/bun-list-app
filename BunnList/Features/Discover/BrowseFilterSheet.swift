import BunnListCore
import SwiftUI

/// "فلترة": sort, origin, roaster, flavor, process, brew method and favorites,
/// with the live number of matching coffees on the apply button. Edits a copy and
/// hands it back on apply.
@MainActor
struct BrowseFilterSheet: View {
    @Binding var filters: BrowseFilters
    let facets: RemoteFacets?
    let isSignedIn: Bool

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BrowseFilters()
    @State private var count: Int?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("الترتيب").font(.headline)
                        ChipWrap(BrowseFilters.Sort.allCases, id: \.self) { sort in
                            chip(sort.nameAr, on: draft.sort == sort) { draft.sort = sort }
                        }
                    }

                    VStack(spacing: 10) {
                        facetRow("الأصل", selection: $draft.origins, facets: facets?.origins ?? []) { $0.labelAr }
                        facetRow("المحمصة", selection: $draft.roasters, facets: facets?.roasters ?? []) { $0.labelAr }
                        flavorRow
                        facetRow("المعالجة", selection: $draft.processes, facets: facets?.processes ?? []) {
                            ReferenceCodes.process($0.value)?.nameAr ?? $0.value
                        }
                        facetRow("التحضير", selection: $draft.methods, facets: facets?.methods ?? []) {
                            LotCommunityCard.methodName($0.value)
                        }
                    }

                    if isSignedIn {
                        Toggle(isOn: $draft.favoritesOnly) {
                            Label("اللي في مفضلتي بس", systemImage: "heart.fill")
                        }
                        .tint(Brand.olive)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .background(Brand.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    filters = draft
                    dismiss()
                } label: {
                    Text(count.map { "اعرض \($0.formatted()) قهوة" } ?? "اعرض النتائج")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.ink)
                .clipShape(Capsule())
                .padding()
                .background(.bar)
                .accessibilityIdentifier("filters-apply")
            }
            .brandScreen()
            .navigationTitle("فلترة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("مسح الكل") {
                        let text = draft.text, shelf = draft.shelf
                        draft = BrowseFilters()
                        draft.text = text
                        draft.shelf = shelf
                    }
                    .disabled(draft.activeCount == 0 && draft.sort == .ratingDesc)
                }
            }
            .onAppear { draft = filters }
            .task(id: draft) {
                count = nil
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let current = draft
                count = try? await auth.withOptionalToken { try await client.browse(current, limit: 1, accessToken: $0) }.total
            }
        }
    }

    private var flavorRow: some View {
        let flavorFacets = facets?.flavors.filter { FlavorFamily(rawValue: $0.value) != nil } ?? []
        return NavigationLink {
            List(flavorFacets) { facet in
                let family = FlavorFamily(rawValue: facet.value) ?? .other
                Button {
                    if draft.flavors.contains(family) { draft.flavors.remove(family) } else { draft.flavors.insert(family) }
                } label: {
                    HStack {
                        Circle().fill(family.color).frame(width: 14, height: 14)
                        Text(family.nameAr).foregroundStyle(.primary)
                        Text("(\(facet.count.formatted()))").foregroundStyle(.secondary)
                        Spacer()
                        if draft.flavors.contains(family) { Image(systemName: "checkmark").foregroundStyle(Brand.olive) }
                    }
                }
            }
            .brandScreen()
            .navigationTitle("النكهات")
        } label: {
            rowLabel("النكهات", summary: draft.flavors.isEmpty ? "الكل" : draft.flavors.map(\.nameAr).sorted().joined(separator: "، "))
        }
        .buttonStyle(.plain)
    }

    private func facetRow(_ title: String, selection: Binding<Set<String>>, facets: [RemoteFacets.Facet],
                          label: @escaping (RemoteFacets.Facet) -> String) -> some View {
        NavigationLink {
            FacetPicker(title: title, facets: facets, selection: selection, label: label)
        } label: {
            let names = facets.filter { selection.wrappedValue.contains($0.value) }.map(label)
            rowLabel(title, summary: names.isEmpty ? "الكل (\(facets.count.formatted()))" : names.joined(separator: "، "))
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, summary: String) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(Brand.ink)
            Spacer()
            Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(on ? .white : Brand.ink)
                .background(on ? Brand.ink : Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(on ? 0 : 0.3)))
        }
        .buttonStyle(.plain)
    }
}

/// Multi-select list of one facet, searchable when long (roasters).
private struct FacetPicker: View {
    let title: String
    let facets: [RemoteFacets.Facet]
    @Binding var selection: Set<String>
    let label: (RemoteFacets.Facet) -> String
    @State private var query = ""

    private var shown: [RemoteFacets.Facet] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? facets : facets.filter { label($0).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            if !selection.isEmpty {
                Button("إلغاء التحديد") { selection.removeAll() }
            }
            ForEach(shown) { facet in
                Button {
                    if selection.contains(facet.value) { selection.remove(facet.value) } else { selection.insert(facet.value) }
                } label: {
                    HStack {
                        Text(label(facet)).foregroundStyle(.primary)
                        Text("(\(facet.count.formatted()))").foregroundStyle(.secondary)
                        Spacer()
                        if selection.contains(facet.value) { Image(systemName: "checkmark").foregroundStyle(Brand.olive) }
                    }
                }
            }
        }
        .brandScreen()
        .navigationTitle(title)
        .searchable(text: $query, prompt: "ابحث")
    }
}

/// Wrapping row of chips.
private struct ChipWrap<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let content: (Data.Element) -> Content

    init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.id = id
        self.content = content
    }

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(data, id: id) { content($0) }
        }
    }
}

/// Lays children out left-to-right (right-to-left in Arabic), wrapping lines.
private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += line + spacing; x = 0; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
