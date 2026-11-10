import BunnListCore
import SwiftUI

// «مبدع مؤسس»: the seal, the chip next to a name, the gold ring on a picture, the sheet that
// explains it (number, places left, perks), the founder's linked accounts, editing them,
// and a story-sized card to share the badge.

/// The gold seal with the BunnList mark.
struct FounderSeal: View {
    var size: CGFloat = 28
    var dashed = true

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.965, green: 0.867, blue: 0.62), Color(red: 0.85, green: 0.663, blue: 0.29),
                                                  Color(red: 0.596, green: 0.439, blue: 0.165)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            Circle().strokeBorder(.white.opacity(0.45), lineWidth: max(1, size * 0.03))
            if dashed && size >= 40 {
                Circle().inset(by: size * 0.1)
                    .stroke(Brand.brown.opacity(0.35), style: StrokeStyle(lineWidth: max(1, size * 0.015), dash: [size * 0.03, size * 0.03]))
            }
            if let mark = UIImage(named: "BunnListSymbol") {
                Image(uiImage: mark).resizable().scaledToFit().frame(width: size * 0.48, height: size * 0.48)
                    .shadow(color: .white.opacity(0.5), radius: 0, y: 1)
            } else {
                Text("B").font(.system(size: size * 0.45, weight: .black)).foregroundStyle(Brand.ink)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.596, green: 0.439, blue: 0.165).opacity(0.35), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
    }
}

/// «مبدع مؤسس · #07», or just «مؤسس» where space is tight. Tapping opens the explainer.
struct FounderChip: View {
    let number: Int
    var compact = false
    var name: String? = nil
    var isMine = false
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: compact ? 4 : 6) {
                FounderSeal(size: compact ? 16 : 22, dashed: false)
                if compact {
                    Text("مؤسس")
                } else {
                    Text("مبدع مؤسس · ") + Text(FounderBadge.label(number)).monospacedDigit()
                }
            }
            .font(compact ? .caption2.bold() : .caption.bold())
            .padding(.leading, compact ? 5 : 7).padding(.trailing, compact ? 8 : 11).padding(.vertical, compact ? 2 : 4)
            .background(Color(red: 0.96, green: 0.906, blue: 0.776), in: Capsule())
            .foregroundStyle(Color(red: 0.43, green: 0.31, blue: 0.07))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("مبدع مؤسس رقم \(number)")
        .sheet(isPresented: $showSheet) {
            FounderSheet(number: number, name: name, isMine: isMine).presentationDetents([.large])
        }
    }
}

extension View {
    /// A gold ring around a founder's picture, with a small seal at its corner.
    @ViewBuilder
    func founderRing(_ isFounder: Bool, size: CGFloat) -> some View {
        if isFounder {
            self
                .overlay(Circle().inset(by: -size * 0.05).stroke(Color(red: 0.85, green: 0.663, blue: 0.29), lineWidth: max(2, size * 0.035)))
                .overlay(alignment: .bottomLeading) {
                    if size >= 44 {
                        FounderSeal(size: size * 0.36, dashed: false)
                            .overlay(Circle().stroke(Brand.background, lineWidth: max(2, size * 0.03)))
                            .offset(x: -size * 0.04, y: size * 0.02)
                    }
                }
        } else {
            self
        }
    }
}

/// A founder's accounts elsewhere, as small pills that open the account.
struct SocialLinksRow: View {
    let socials: Socials
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !socials.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(socials.linked) { item in
                        Button { if let url = item.url { openURL(url) } } label: {
                            HStack(spacing: 6) {
                                SocialTile(network: item.network, size: 20)
                                Text(item.handle).font(.footnote.bold())
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.network.nameAr): \(item.handle)")
                    }
                }
            }
        }
    }
}

/// Two letters on a coloured tile for a network (we don't draw their logos).
struct SocialTile: View {
    let network: SocialNetwork
    var size: CGFloat = 20

    var body: some View {
        Text(network.mark)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.3))
    }

    private var fill: AnyShapeStyle {
        switch network {
        case .tiktok, .x: return AnyShapeStyle(Color.black)
        case .instagram: return AnyShapeStyle(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .bottomLeading, endPoint: .topTrailing))
        case .youtube: return AnyShapeStyle(Color.red)
        }
    }
}

/// What the badge is: the seal, «رقم ٧ من ١٠٠», how many places are left, what founders get,
/// and for the founder themself, a card to share.
struct FounderSheet: View {
    let number: Int
    var name: String?
    var isMine = false

    @Environment(\.dismiss) private var dismiss
    @State private var stats: FounderStats?
    @State private var shareImage: UIImage?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FounderSeal(size: 140).padding(.top, 12)
                    Text("مبدع مؤسس").font(.title.bold())
                    (Text("رقم ") + Text("\(number)").monospacedDigit() + Text(" من ") + Text("\(stats?.limit ?? 100)").monospacedDigit())
                        .font(.headline).foregroundStyle(Brand.gold)
                    Text("من أوائل المبدعين اللي بنوا BunnList معنا. الشارة دائمة، وما تنعطى بعد أول \((stats?.limit ?? 100).formatted()).")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let stats {
                        VStack(spacing: 6) {
                            ProgressView(value: stats.progress).tint(Brand.gold)
                            HStack {
                                Text("\(stats.taken.formatted()) مؤسس انضموا")
                                Spacer()
                                Text(stats.isFull ? "اكتمل المؤسسون" : "باقي \(stats.remaining.formatted()) مكان")
                            }
                            .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                    VStack(spacing: 10) {
                        perk(1, "وصفاتك تطلع باسمك، ومعها كم شخص حضّرها")
                        perk(2, "روابط حساباتك (تيك توك، إنستقرام…) في ملفك")
                        perk(3, "نبرزك في حسابات BunnList")
                    }
                    .padding(.top, 6)
                    if isMine {
                        if let shareImage {
                            ShareLink(item: Image(uiImage: shareImage), preview: SharePreview("مبدع مؤسس في BunnList", image: Image(uiImage: shareImage))) {
                                Label("شارك شارتك", systemImage: "square.and.arrow.up")
                                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Brand.olive, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
                            }
                            .padding(.top, 8)
                        } else {
                            ProgressView().padding(.top, 8)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .background(Brand.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .task {
                stats = try? await client.fetchFounderStats()
                if isMine { shareImage = FounderShareCard.render(number: number, name: name, limit: stats?.limit ?? 100) }
            }
        }
    }

    private func perk(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(n.formatted()).font(.footnote.bold()).foregroundStyle(Brand.gold)
                .frame(width: 28, height: 28).background(Color(red: 0.96, green: 0.906, blue: 0.776), in: RoundedRectangle(cornerRadius: 8))
            Text(text).font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A 1080×1920 card (story / TikTok size) a founder shares: the seal, their number and name, BunnList.
enum FounderShareCard {
    @MainActor
    static func render(number: Int, name: String?, limit: Int) -> UIImage? {
        let renderer = ImageRenderer(content: Card(number: number, name: name, limit: limit))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1920)
        return renderer.uiImage
    }

    private struct Card: View {
        let number: Int
        let name: String?
        let limit: Int

        var body: some View {
            ZStack {
                Color(red: 0.969, green: 0.945, blue: 0.91)
                RadialGradient(colors: [Color(red: 0.6, green: 0.44, blue: 0.14).opacity(0.22), .clear], center: .init(x: 0.5, y: 0.32),
                               startRadius: 0, endRadius: 620)
                VStack(spacing: 34) {
                    Spacer().frame(height: 260)
                    FounderSeal(size: 420)
                    Text("مبدع مؤسس").font(.system(size: 96, weight: .bold)).foregroundStyle(Brand.ink)
                    (Text("رقم ") + Text("\(number)") + Text(" من ") + Text("\(limit)"))
                        .font(.system(size: 54, weight: .semibold)).foregroundStyle(Brand.gold)
                    if let name, !name.isEmpty {
                        Text(name).font(.system(size: 48, weight: .semibold)).foregroundStyle(Brand.brown)
                    }
                    Spacer()
                    HStack(spacing: 18) {
                        if let mark = UIImage(named: "BunnListSymbol") {
                            Image(uiImage: mark).resizable().scaledToFit().frame(height: 72)
                        }
                        Text("BunnList").font(.system(size: 64, weight: .black)).foregroundStyle(Brand.ink)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    Text("دليل القهوة المختصة").font(.system(size: 38, weight: .semibold)).foregroundStyle(Brand.gold)
                    Spacer().frame(height: 300)
                }
            }
            .frame(width: 1080, height: 1920)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

/// Founders link their accounts elsewhere; each field takes a handle or a profile link.
struct FounderSocialsEditor: View {
    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var values: [SocialNetwork: String] = [:]
    @State private var saving = false
    @State private var message: String?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Form {
            if let founder = profile.me?.founder {
                Section {
                    HStack(spacing: 12) {
                        FounderSeal(size: 48, dashed: false)
                        VStack(alignment: .leading, spacing: 2) {
                            (Text("أنت مبدع مؤسس ") + Text(founder.label).monospacedDigit()).font(.headline)
                            Text("حساباتك تطلع في ملفك وعلى وصفاتك.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("حساباتك") {
                ForEach(SocialNetwork.allCases) { network in
                    HStack(spacing: 12) {
                        SocialTile(network: network, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(network.nameAr).font(.caption).foregroundStyle(.secondary)
                            TextField("@اسم الحساب أو الرابط", text: binding(network))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(.URL)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        if invalid(network) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                                .accessibilityLabel("الاسم غير صحيح")
                        }
                    }
                }
            }
            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("حساباتك")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") { Task { await save() } }.disabled(saving || SocialNetwork.allCases.contains(where: invalid))
            }
        }
        .onAppear {
            guard values.isEmpty, let socials = profile.me?.socials else { return }
            for network in SocialNetwork.allCases { values[network] = socials[network] ?? "" }
        }
    }

    private func binding(_ network: SocialNetwork) -> Binding<String> {
        Binding(get: { values[network] ?? "" }, set: { values[network] = $0 })
    }

    private func invalid(_ network: SocialNetwork) -> Bool {
        let text = (values[network] ?? "").trimmingCharacters(in: .whitespaces)
        return !text.isEmpty && network.handle(from: text) == nil
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var cleaned: [SocialNetwork: String] = [:]
        for network in SocialNetwork.allCases {
            let text = (values[network] ?? "").trimmingCharacters(in: .whitespaces)
            cleaned[network] = text.isEmpty ? "" : (network.handle(from: text) ?? text)
        }
        do {
            _ = try await auth.withToken { try await client.updateSocials(cleaned, accessToken: $0) }
            await profile.refresh(auth)
            Haptics.tap()
            dismiss()
        } catch {
            message = "تعذّر الحفظ. تأكد من أسماء الحسابات وحاول مرة ثانية."
        }
    }
}
