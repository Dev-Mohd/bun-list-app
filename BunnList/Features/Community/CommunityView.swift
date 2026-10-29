import BunnListCore
import SwiftUI

/// "المجتمع": your points, streak and week, what's trending this week (coffees,
/// roasters, recipes), the community pulse, the leaderboard (this week or all
/// time), how points are earned, and the challenges. The leaderboard is public;
/// your own card needs an account.
@MainActor
struct CommunityView: View {
    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @State private var points: RemotePoints?
    @State private var board: RemoteLeaderboard?
    @State private var allTime = false
    @State private var kind = LeaderboardKind.points
    @State private var failed = false
    @State private var showRules = false
    @State private var showChallenges = false
    @State private var showSignIn = false
    @State private var feed: RemoteHome?
    @State private var feedFailed = false
    @State private var trendTab = TrendTab.coffee
    @State private var searchPreset: SearchPreset?
    @State private var pulseScope = PulseScope.everyone
    @State private var followingFeed: [RemotePulseItem]?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if auth.isSignedIn { myCard } else { guestCard }

                    HStack(spacing: 10) {
                        Button { showRules = true } label: {
                            Label("كيف أجمع النقاط؟", systemImage: "questionmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        Button { showChallenges = true } label: {
                            Label("التحديات", systemImage: "flag.checkered")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.olive)
                    .padding(.horizontal)

                    TrendingSection(trending: feed?.trending, failed: feedFailed, tab: $trendTab) { roaster in
                        var filters = BrowseFilters()
                        filters.roasters = [roaster.slug]
                        searchPreset = SearchPreset(filters: filters)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if auth.isSignedIn {
                        Picker("النبض", selection: $pulseScope) {
                            Text("الكل").tag(PulseScope.everyone)
                            Text("أتابعهم").tag(PulseScope.following)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }
                    if pulseScope == .following && auth.isSignedIn {
                        followingSection
                    } else {
                        PulseSection(items: feed?.pulse ?? [])
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    leaderboardSection
                }
                .padding(.vertical)
            }
            .background(Brand.background.ignoresSafeArea())
            .brandScreen()
            .navigationTitle("المجتمع")
            .task(id: "\(kind.rawValue)-\(allTime)") { await load() }
            .task(id: auth.isSignedIn) { await loadFeed() }
            .task(id: pulseScope) { if pulseScope == .following { await loadFollowing() } }
            .refreshable { await load(); await loadFeed(); if pulseScope == .following { await loadFollowing() } }
            .onChange(of: auth.isSignedIn) { _, _ in Task { await load() } }
            .navigationDestination(for: String.self) { LiveLotDetailView(slug: $0) }
            .navigationDestination(item: $searchPreset) { SearchView(tab: .constant(.community), initial: $0.filters) }
            .sheet(isPresented: $showRules) { PointRulesView() }
            .sheet(isPresented: $showChallenges) { JourneysView() }
            .sheet(isPresented: $showSignIn) { SignInView() }
        }
    }

    // MARK: Cards

    private var myCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(url: profile.me?.avatarUrl, name: profile.me?.displayName, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.me?.displayName ?? "نقاطك").font(.headline).foregroundStyle(.white)
                    if let rank = board?.me?.rank {
                        Text("ترتيبك \(rank.formatted()) \(allTime ? "على الإطلاق" : "هذا الأسبوع")")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                    } else {
                        Text("ابدأ تجمع نقاط وتطلع في القائمة").font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
            }
            HStack(spacing: 0) {
                stat("\((points?.total ?? 0).formatted())", "نقطة", "star.fill")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 36)
                stat("\((points?.streak ?? 0).formatted())", (points?.streak ?? 0) == 1 ? "يوم متواصل" : "أيام متواصلة", "flame.fill")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 36)
                stat("+\((points?.week ?? 0).formatted())", "هذا الأسبوع", "chart.line.uptrend.xyaxis")
            }
            if let streak = points?.streak, streak > 0 {
                let toBonus = 7 - streak % 7
                Text(toBonus == 7 ? "أكملت أسبوع! كمّل عشان المكافأة الجاية 🔥"
                     : "باقي \(toBonus.formatted()) \(toBonus == 1 ? "يوم" : "أيام") على مكافأة السلسلة (+٢٥)")
                    .font(.caption).foregroundStyle(Brand.gold)
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [Brand.olive, Brand.olive.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Label(value, systemImage: icon).font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("انضم للمجتمع").font(.title3.bold())
            Text("سجّل دخولك وابدأ تجمع نقاط من تقييماتك ووصفاتك واكتشافاتك، وتطلع في قائمة المتصدرين.")
                .font(.callout).foregroundStyle(.secondary)
            Button("سجّل دخولك") { showSignIn = true }.buttonStyle(.borderedProminent).tint(Brand.olive)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var followingSection: some View {
        if let followingFeed {
            if followingFeed.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2").font(.largeTitle).foregroundStyle(Brand.gold)
                    Text("ما فيه جديد ممن تتابعهم").font(.headline)
                    Text("تابع ناس ذوقهم قريب منك وتشوف وش جربوا ووش حضّروا هنا أول بأول.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    NavigationLink { FindPeopleView() } label: {
                        Label("اكتشف ناس", systemImage: "person.badge.plus").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.olive)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)
            } else {
                PulseSection(items: followingFeed, title: "أتابعهم", icon: "person.2.fill", limit: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding()
        }
    }

    private func loadFollowing() async {
        guard auth.isSignedIn else { return }
        if let items = try? await auth.withToken({ try await client.followingFeed(accessToken: $0) }) {
            followingFeed = items
        } else if followingFeed == nil {
            followingFeed = []
        }
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("المتصدرين", systemImage: "trophy.fill").font(.title3.bold()).foregroundStyle(Brand.ink)
                Spacer()
            }
            Picker("الترتيب حسب", selection: $kind) {
                ForEach(LeaderboardKind.allCases, id: \.self) { Text($0.titleAr).tag($0) }
            }
            .pickerStyle(.segmented)
            if kind == .points {
                Picker("الفترة", selection: $allTime) {
                    Text("هذا الأسبوع").tag(false)
                    Text("كل الأوقات").tag(true)
                }
                .pickerStyle(.segmented)
            }

            if let board {
                if board.entries.isEmpty {
                    ContentUnavailableView(kind == .points ? "ما أحد جمع نقاط \(allTime ? "بعد" : "هالأسبوع")" : "القائمة فاضية للحين", systemImage: "trophy",
                                           description: Text("قيّم قهوة أو انشر وصفة وكن أول اسم في القائمة."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(board.entries, id: \.self) { entry in
                            if let username = entry.username, !entry.isMe {
                                NavigationLink { PublicProfileView(username: username) } label: { LeaderboardRow(entry: entry, kind: kind) }
                                    .buttonStyle(.plain)
                            } else {
                                LeaderboardRow(entry: entry, kind: kind)
                            }
                            if entry != board.entries.last { Divider().padding(.leading, 64) }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
            } else if failed {
                ContentUnavailableView("تعذّر التحميل", systemImage: "wifi.exclamationmark")
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 30)
            }
        }
        .padding(.horizontal)
    }

    /// Trending and the pulse (from the home feed).
    private func loadFeed() async {
        do {
            feed = try await auth.withOptionalToken { try await client.fetchHome(accessToken: $0) }
            feedFailed = false
        } catch {
            feedFailed = feed == nil
        }
    }

    private func load() async {
        failed = false
        let token = auth.isSignedIn ? auth.currentAccessToken() : nil
        if auth.isSignedIn {
            points = try? await auth.withToken { try await client.fetchPoints(accessToken: $0) }
        } else {
            points = nil
        }
        do {
            board = try await client.fetchLeaderboard(allTime: kind != .points || allTime, kind: kind, accessToken: token)
        } catch {
            failed = true
        }
    }
}

private struct LeaderboardRow: View {
    let entry: RemoteLeaderboard.Entry
    var kind = LeaderboardKind.points

    var body: some View {
        HStack(spacing: 12) {
            rankBadge
            AvatarView(url: entry.avatarUrl, name: entry.name, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.isMe ? "\(entry.name) (أنت)" : entry.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let username = entry.username {
                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            Spacer()
            Label(kind == .points ? entry.points.formatted() : "\(entry.points.formatted()) \(kind.unitAr)",
                  systemImage: kind == .discoverers ? "sparkles" : kind == .raters ? "star.bubble.fill" : "star.fill")
                .font(.subheadline.bold().monospacedDigit()).foregroundStyle(Brand.gold)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(entry.isMe ? Brand.gold.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rankBadge: some View {
        switch entry.rank {
        case 1: Text("🥇").font(.title3).frame(width: 28)
        case 2: Text("🥈").font(.title3).frame(width: 28)
        case 3: Text("🥉").font(.title3).frame(width: 28)
        default:
            Text(entry.rank.formatted()).font(.subheadline.bold().monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
        }
    }
}

/// "كيف أجمع النقاط؟": the rewards table.
struct PointRulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PointRules.table.indices, id: \.self) { i in
                        let rule = PointRules.table[i]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.titleAr)
                                if !rule.noteAr.isEmpty { Text(rule.noteAr).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text("+\(rule.points.formatted())").font(.headline.monospacedDigit()).foregroundStyle(Brand.gold)
                        }
                    }
                } footer: {
                    Text("السلسلة تزيد يوم كل ما سويت نشاط واحد على الأقل (بتوقيت السعودية). لو حذفت شي، تنسحب نقاطه. ما تبي تطلع في المتصدرين؟ من الإعدادات.")
                }
            }
            .brandScreen()
            .navigationTitle("كيف أجمع النقاط؟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The community pulse: everyone, or only people you follow.
enum PulseScope: Hashable { case everyone, following }
