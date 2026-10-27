import BunnListCore
import SwiftUI

/// The grinder guide, loaded once and shared (the brew screen needs «مطحنتي»'s specs).
@MainActor
final class GrinderCatalog: ObservableObject {
    static let shared = GrinderCatalog()
    @Published private(set) var grinders: [RemoteGrinder]?
    @Published private(set) var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    func load(force: Bool = false) async {
        guard force || grinders == nil else { return }
        do {
            grinders = try await client.fetchGrinders()
            failed = false
        } catch {
            failed = grinders == nil
        }
    }

    func grinder(_ id: String?) -> RemoteGrinder? { grinders?.first { $0.id == id } }
}

/// «مطحنتي» lives on the profile; this keeps a copy on the phone for offline use.
enum MyGrinder {
    static let key = "myGuideGrinderID"
}

/// Find your grinder by its picture: search, sections by kind, a card each. Opens
/// the grinder's page, where «هذي مطحنتي» sets it.
@MainActor
struct GrinderGuideView: View {
    @EnvironmentObject private var auth: AuthModel
    @ObservedObject private var catalog = GrinderCatalog.shared
    @AppStorage(MyGrinder.key) private var myID = ""
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var showsDone = false

    private var sections: [(String, [RemoteGrinder])] {
        let list = (catalog.grinders ?? []).filter { $0.matches(query) }
        return RemoteGrinder.categories.compactMap { code in
            let items = list.filter { $0.category == code }
            return items.isEmpty ? nil : (code, items)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                if let mine = catalog.grinder(myID), query.isEmpty {
                    NavigationLink { GrinderDetailView(grinder: mine) } label: { MyGrinderBanner(grinder: mine) }
                        .buttonStyle(CardPressStyle())
                        .padding(.horizontal)
                }
                if catalog.grinders == nil {
                    if catalog.failed {
                        ContentUnavailableView("ما قدرنا نجيب المطاحن", systemImage: "wifi.slash", description: Text("اسحب للتحديث"))
                    } else {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 80)
                    }
                } else if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(sections, id: \.0) { code, items in
                    Section {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                            ForEach(items) { g in
                                NavigationLink { GrinderDetailView(grinder: g) } label: {
                                    GrinderCard(grinder: g, isMine: g.id == myID)
                                }
                                .buttonStyle(CardPressStyle())
                                .cardScrollIn()
                            }
                        }
                        .padding(.horizontal)
                    } header: {
                        HStack(spacing: 8) {
                            Text(RemoteGrinder.categoryAr(code)).font(.title3.bold())
                            Text(items.count.formatted()).font(.caption.bold().monospacedDigit())
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Brand.olive.opacity(0.12), in: Capsule())
                                .foregroundStyle(Brand.olive)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Brand.background.opacity(0.96))
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("دليل المطاحن")
        .searchable(text: $query, prompt: "ماركة أو موديل")
        .toolbar {
            if showsDone { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }
        .task { await catalog.load() }
        .refreshable { await catalog.load(force: true) }
    }
}

/// A grinder as a card: its photo on our light ground, maker, model, range.
private struct GrinderCard: View {
    let grinder: RemoteGrinder
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GrinderPhoto(grinder: grinder)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .overlay(alignment: .topLeading) {
                    if isMine {
                        Label("مطحنتي", systemImage: "checkmark.seal.fill")
                            .font(.caption2.bold()).foregroundStyle(Brand.background)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Brand.olive, in: Capsule())
                            .padding(7)
                    }
                }
                .padding(5)
            VStack(alignment: .leading, spacing: 2) {
                Text(grinder.brand).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                Text(grinder.title).font(.subheadline.bold()).foregroundStyle(Brand.ink).lineLimit(2)
                Text(grinder.rangeAr ?? "المواصفات قريبًا").font(.caption2)
                    .foregroundStyle(grinder.rangeAr == nil ? Color.secondary : Brand.olive).lineLimit(1)
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(isMine ? Brand.olive : Brand.gold.opacity(0.18), lineWidth: isMine ? 2 : 1))
    }
}

/// The photo on a warm light ground (multiplied so its white blends in), or a
/// quiet placeholder until one is added.
struct GrinderPhoto: View {
    let grinder: RemoteGrinder
    @Environment(\.cardPressed) private var pressed

    var body: some View {
        ZStack {
            Color.white
            LinearGradient(colors: [Brand.gold.opacity(0.10), Brand.olive.opacity(0.06)], startPoint: .top, endPoint: .bottom)
            if let url = grinder.imageUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFit().padding(10).blendMode(.multiply)
                            .transition(.opacity)
                    } else {
                        ProgressView().tint(Brand.olive)
                    }
                }
                .scaleEffect(pressed ? 1.05 : 1)
                .offset(y: pressed ? -5 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "dial.medium").font(.system(size: 40, weight: .light))
                    Text("الصورة قريبًا").font(.caption2)
                }
                .foregroundStyle(Brand.olive.opacity(0.5))
            }
        }
        .compositingGroup()
    }
}

private struct MyGrinderBanner: View {
    let grinder: RemoteGrinder

    var body: some View {
        HStack(spacing: 14) {
            GrinderPhoto(grinder: grinder).frame(width: 70, height: 70).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("مطحنتي").font(.caption.bold()).foregroundStyle(Brand.olive)
                Text("\(grinder.brand) \(grinder.title)").font(.headline).foregroundStyle(Brand.ink)
                    .environment(\.layoutDirection, .leftToRight)
                Text(grinder.rangeAr ?? "المواصفات قريبًا").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.backward").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Brand.olive.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.olive.opacity(0.3)))
    }
}

/// One grinder: the photo, how it adjusts, where zero is, its sources, and «هذي مطحنتي».
@MainActor
struct GrinderDetailView: View {
    let grinder: RemoteGrinder
    @EnvironmentObject private var auth: AuthModel
    @AppStorage(MyGrinder.key) private var myID = ""
    @State private var isSaving = false
    @State private var showSignIn = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    private var isMine: Bool { myID == grinder.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GrinderPhoto(grinder: grinder)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                if let credit = grinder.imageCredit {
                    Text(credit).font(.caption2).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(grinder.brand).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(grinder.title).font(.largeTitle.bold()).foregroundStyle(Brand.ink)
                    Text(grinder.categoryAr).font(.callout).foregroundStyle(Brand.olive)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                specs

                if let zero = grinder.zeroGuideAr, !zero.isEmpty {
                    infoBlock("وين الصفر؟", icon: "scope", text: zero)
                }
                if let notes = grinder.notesAr, !notes.isEmpty {
                    infoBlock("ملاحظات", icon: "lightbulb", text: notes)
                }
                if !grinder.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("المصادر").font(.headline)
                        ForEach(grinder.sources, id: \.self) { source in
                            if let url = URL(string: source.url) {
                                Link(destination: url) { Label(source.label, systemImage: "link").font(.callout) }
                                    .tint(Brand.olive)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { mineButton }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSignIn) { SignInView() }
    }

    @ViewBuilder
    private var specs: some View {
        if grinder.hasSpecs {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let a = grinder.adjustment { spec("طريقة الضبط", RemoteGrinder.adjustmentAr(a)) }
                if let r = grinder.rangeAr { spec("المدى", r) }
                if let c = grinder.clicksPerRotation { spec("في اللفة الكاملة", "\(c) كليك") }
                if let m = grinder.micronsPerStep {
                    spec("كل كليك", "≈ \(m == m.rounded() ? String(Int(m)) : String(format: "%.1f", m)) ميكرون")
                }
            }
        } else {
            Label("نجمع مواصفاتها من مصادر الشركة. تقدر تختارها كمطحنتك الحين، والمواصفات تنضاف قريبًا.",
                  systemImage: "clock.badge.checkmark")
                .font(.callout).foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func spec(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(Brand.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func infoBlock(_ title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var mineButton: some View {
        Button {
            Task { await toggleMine() }
        } label: {
            Label(isMine ? "مطحنتي ✓" : "هذي مطحنتي", systemImage: isMine ? "checkmark.seal.fill" : "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(isMine ? Brand.olive.opacity(0.15) : Brand.olive, in: Capsule())
                .foregroundStyle(isMine ? Brand.olive : Brand.background)
        }
        .buttonStyle(CardPressStyle())
        .disabled(isSaving)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .sensoryFeedback(.success, trigger: isMine)
    }

    private func toggleMine() async {
        let next: String? = isMine ? nil : grinder.id
        myID = next ?? ""
        guard auth.isSignedIn else { return }
        isSaving = true
        defer { isSaving = false }
        try? await auth.withToken { try await client.setMyGrinder(next, accessToken: $0) }
    }
}
