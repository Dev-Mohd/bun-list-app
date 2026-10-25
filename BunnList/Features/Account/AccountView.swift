import BunnListCore
import SwiftUI

/// Profile ("ملفي"). Signed in: the header (picture, name, @username, bio) with
/// counts, shortcuts, the collection card, the taste card, the wishlist and
/// contributions — all from /api/v1/me/summary. As a guest: the on-device
/// collection counts and the ways to sign in. Account controls live in Settings.
struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @State private var summary: RemoteProfileSummary?
    @State private var points: RemotePoints?
    @State private var editingRecipe: ClientID?
    @State private var showSignIn = false
    @State private var showSettings = false
    @State private var showRecipes = false
    @State private var showProfileEditor = false

    private var me: RemoteMe? { profile.me }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ProfileHeader(isSignedIn: auth.isSignedIn, me: me, summary: summary, points: points) { showProfileEditor = true }
                    if auth.isSignedIn {
                        shortcuts
                        collectionCard
                        tasteCard
                        wishlistCard
                    } else {
                        guestCollection
                        signInCard
                    }
                    deviceRecipes
                }
                .padding(.vertical)
            }
            .background(Brand.background.ignoresSafeArea())
            .navigationTitle("ملفي")
            .navigationDestination(for: String.self) { LiveLotDetailView(slug: $0) }
            .navigationDestination(for: CollectionSlice.self) { FilteredCollectionView(filter: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("الإعدادات")
                        .accessibilityIdentifier("open-settings")
                }
                if let username = me?.username {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: "تابع ذائقتي في بُن لست: @\(username) ☕") {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("شارك ملفك")
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: auth.isSignedIn) { _, _ in Task { await load() } }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showProfileEditor) {
                NavigationStack { ProfileSetupView(mode: .edit) { } }
                    .environmentObject(auth)
                    .environmentObject(profile)
            }
            .sheet(isPresented: $showRecipes) { RecipesHubView(startOn: auth.isSignedIn ? .mine : .explore) }
            .sheet(item: Binding(get: { editingRecipe.map(RecipeRef.init) }, set: { editingRecipe = $0?.id })) { ref in
                RecipeEditor(lotID: model.recipe(ref.id)?.lotID, existing: ref.id)
            }
            .sheet(isPresented: $showSignIn) { SignInView() }
        }
    }

    // MARK: Signed in

    private var shortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                NavigationLink(value: CollectionSlice.favorite) {
                    ShortcutTile(icon: "heart.fill", color: .red, title: "مفضّلتي", count: summary?.collection.favorite)
                }
                NavigationLink(value: CollectionSlice.tried) {
                    ShortcutTile(icon: "cup.and.saucer.fill", color: Brand.brown, title: "جرّبته", count: summary?.collection.tried)
                }
                Button { showRecipes = true } label: {
                    ShortcutTile(icon: "book.closed.fill", color: Brand.olive, title: "وصفاتي", count: summary?.recipes)
                }
                .accessibilityIdentifier("open-recipes")
                NavigationLink { MySubmissionsView() } label: {
                    ShortcutTile(icon: "sparkles", color: Brand.gold, title: "اقتراحاتي", count: summary?.submissions)
                }
                .accessibilityIdentifier("open-my-submissions")
                if me?.isAdmin == true {
                    NavigationLink { AdminReviewView() } label: {
                        ShortcutTile(icon: "checkmark.shield.fill", color: Brand.ink, title: "المراجعة", count: nil)
                    }
                    .accessibilityIdentifier("open-admin-review")
                }
            }
            .padding(.horizontal)
            .buttonStyle(.plain)
        }
    }

    private var collectionCard: some View {
        NavigationLink(value: CollectionSlice.owned) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((summary?.collection.owned ?? 0).formatted())
                        .font(.system(size: 44, weight: .heavy)).foregroundStyle(.white)
                    Label("مجموعتي", systemImage: "chevron.left")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.headline).foregroundStyle(.white.opacity(0.9))
                    Text("القهوات اللي عندك الحين").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                BagFan(urls: summary?.recentBags ?? [])
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Brand.olive, Brand.olive.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityIdentifier("open-collection")
    }

    @ViewBuilder
    private var tasteCard: some View {
        if let taste = summary?.taste {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("ذائقتك").font(.title3.bold())
                    Spacer()
                    if let avg = taste.averageRating {
                        Label(avg.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                            .font(.subheadline.bold()).foregroundStyle(Brand.gold)
                    }
                }
                if taste.unlocked {
                    TasteDetails(taste: taste)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "lock.fill").font(.title2).foregroundStyle(Brand.gold)
                            .frame(width: 52, height: 52)
                            .background(Brand.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("بطاقة ذائقتك تنتظرك").font(.headline)
                            Text("قيّم \(taste.required.formatted()) قهوات ونقولك وش يعجبك: المنشأ والمعالجة والنكهات وطريقتك المفضلة.")
                                .font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: Double(taste.progress), total: Double(taste.required)).tint(Brand.gold)
                            Text("\(taste.progress.formatted())/\(taste.required.formatted())").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal)
        }
    }

    private var wishlistCard: some View {
        NavigationLink(value: CollectionSlice.wantsToTry) {
            HStack(spacing: 14) {
                Image(systemName: "bookmark.fill").font(.title2).foregroundStyle(Brand.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("قائمة الأمنيات").font(.headline).foregroundStyle(.white)
                    Text((summary?.collection.wantsToTry ?? 0) > 0
                         ? "\((summary?.collection.wantsToTry ?? 0).formatted()) قهوة ودّك تجربها"
                         : "أضف القهوة اللي ودّك تجربها بعدين")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.left").foregroundStyle(.white.opacity(0.6))
            }
            .padding(18)
            .background(Brand.ink, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: Guest

    private var guestCollection: some View {
        let entries = model.book.activeEntries(owner: model.owner)
        return VStack(alignment: .leading, spacing: 10) {
            Text("مجموعتك على هذا الجهاز").font(.headline).padding(.horizontal)
            HStack(spacing: 10) {
                StatTile(count: entries.filter(\.isOwned).count, label: "لديّ", icon: "checkmark.circle.fill")
                StatTile(count: entries.filter(\.isFavorite).count, label: "مفضّل", icon: "heart.fill")
                StatTile(count: entries.filter(\.wantsToTry).count, label: "ودّي أجرّب", icon: "bookmark.fill")
                StatTile(count: entries.filter(\.isTried).count, label: "جرّبته", icon: "cup.and.saucer.fill")
            }
            .padding(.horizontal)
        }
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("سجّل دخولك").font(.title3.bold())
            Text("احفظ مجموعتك على كل أجهزتك، وسوّ وصفاتك، واقترح قهوة ويطلع اسمك كمكتشف لها.")
                .font(.callout).foregroundStyle(.secondary)
            QuickSignInButtons(height: 48)
            Button("كمّل بالإيميل") { showSignIn = true }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("account-signin")
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal)
    }

    // MARK: Both

    @ViewBuilder
    private var deviceRecipes: some View {
        let recipes = model.myRecipes()
        if !recipes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("وصفات على هذا الجهاز").font(.headline)
                ForEach(recipes) { recipe in
                    Button { editingRecipe = recipe.clientID } label: { RecipeRow(recipe: recipe) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("نسخ") { _ = model.copyRecipe(recipe.clientID) }
                            Button("حذف", role: .destructive) { model.setRecipeLifecycle(recipe.clientID, to: .deleted) }
                        }
                }
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal)
        }
    }

    private func load() async {
        guard auth.isSignedIn else { summary = nil; points = nil; profile.clear(); return }
        await profile.refresh(auth)
        let client = CatalogAPIClient(transport: URLSessionTransport())
        if let fresh = try? await auth.withToken({ try await client.fetchProfileSummary(accessToken: $0) }) {
            summary = fresh
        }
        points = try? await auth.withToken { try await client.fetchPoints(accessToken: $0) }
    }
}

/// Which slice of the collection a list shows.
enum CollectionSlice: String, Hashable, CaseIterable {
    case owned, favorite, wantsToTry, tried

    var title: String {
        switch self {
        case .owned: return "مجموعتي"
        case .favorite: return "مفضّلتي"
        case .wantsToTry: return "قائمة الأمنيات"
        case .tried: return "جرّبته"
        }
    }

    func includes(_ item: RemoteCollectionItem) -> Bool {
        switch self {
        case .owned: return item.owned
        case .favorite: return item.favorite
        case .wantsToTry: return item.wantsToTry
        case .tried: return item.tried
        }
    }
}

/// The profile header: picture, name, @username, bio, edit button and the counts row.
private struct ProfileHeader: View {
    let isSignedIn: Bool
    let me: RemoteMe?
    let summary: RemoteProfileSummary?
    let points: RemotePoints?
    var onEdit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            AvatarView(url: me?.avatarUrl, name: me?.displayName, size: 96)
            if isSignedIn {
                Text(me?.displayName ?? "حسابك").font(.title2.bold()).foregroundStyle(Brand.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let username = me?.username {
                    Text("@\(username)").font(.subheadline).foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
                if let bio = me?.bio, !bio.isEmpty {
                    Text(bio).font(.callout).multilineTextAlignment(.center).foregroundStyle(.primary.opacity(0.8))
                }
                Button(action: onEdit) {
                    Label("عدّل ملفك", systemImage: "pencil")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Brand.olive.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.olive)
                .accessibilityIdentifier("edit-profile")

                if let points {
                    HStack(spacing: 14) {
                        Label(points.total.formatted(), systemImage: "star.fill").foregroundStyle(Brand.gold)
                        Label(points.streak.formatted(), systemImage: "flame.fill").foregroundStyle(.orange)
                    }
                    .font(.subheadline.bold().monospacedDigit())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(points.total) نقطة، سلسلة \(points.streak) أيام")
                }

                HStack(spacing: 0) {
                    count(summary?.collection.owned, "مجموعتي")
                    divider
                    count(summary?.discoveries, "اكتشافات")
                    divider
                    count(summary?.ratings, "تقييمات")
                    divider
                    count(summary?.experiences, "تجارب")
                }
                .padding(.top, 6)

                if let username = me?.username, let summary, summary.followers != nil {
                    HStack(spacing: 18) {
                        followLink(summary.followers ?? 0, "متابِع", username: username, list: .followers)
                        followLink(summary.following ?? 0, "يتابع", username: username, list: .following)
                        NavigationLink { PublicProfileView(username: username) } label: {
                            Label("ملفي العام", systemImage: "person.crop.circle")
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Brand.olive)
                    .buttonStyle(.plain)
                }
            } else {
                Text("زائر").font(.title2.bold()).foregroundStyle(Brand.ink)
                Label("استكشاف بدون حساب", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
    }

    private var divider: some View {
        Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 28)
    }

    private func followLink(_ value: Int, _ label: String, username: String, list: FollowList) -> some View {
        NavigationLink { FollowListView(username: username, list: list) } label: {
            Text("\(value.formatted()) \(label)").monospacedDigit()
        }
    }

    private func count(_ value: Int?, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text((value ?? 0).formatted()).font(.headline.monospacedDigit()).foregroundStyle(Brand.ink)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ShortcutTile: View {
    let icon: String
    let color: Color
    let title: String
    let count: Int?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.primary)
            if let count {
                Text(count.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(width: 82)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// Up to three owned bags fanned out like cards; empty frames when there are none.
private struct BagFan: View {
    let urls: [String]

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                card(urls.indices.contains(index) ? urls[index] : nil)
                    .rotationEffect(.degrees(Double(index - 1) * 12))
                    .offset(x: CGFloat(index - 1) * 22)
                    .zIndex(index == 1 ? 1 : 0)
            }
        }
        .frame(width: 130, height: 96)
        .accessibilityHidden(true)
    }

    private func card(_ url: String?) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(url == nil ? 0.18 : 0.95))
            .frame(width: 58, height: 80)
            .overlay {
                if let url, let parsed = URL(string: url) {
                    AsyncImage(url: parsed) { $0.resizable().scaledToFit().padding(4) } placeholder: { Color.clear }
                } else {
                    Image(systemName: "cup.and.saucer").foregroundStyle(.white.opacity(0.6))
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// The unlocked taste card's contents.
private struct TasteDetails: View {
    let taste: RemoteProfileSummary.Taste

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !taste.topOrigins.isEmpty {
                row("المناشئ اللي تحبها") {
                    ForEach(taste.topOrigins, id: \.self) { chip("\($0.name) · \($0.average.formatted(.number.precision(.fractionLength(1))))★") }
                }
            }
            if !taste.topProcesses.isEmpty {
                row("المعالجة") {
                    ForEach(taste.topProcesses, id: \.self) { chip(ReferenceCodes.process($0.name)?.nameAr ?? $0.name) }
                }
            }
            if !taste.topFlavors.isEmpty {
                row("النكهات") {
                    ForEach(taste.topFlavors, id: \.self) { chip($0) }
                }
            }
            if let method = taste.favoriteMethod {
                Label("طريقتك المفضلة: \(ReferenceCodes.brewMethod(method)?.nameAr ?? method)", systemImage: "drop.fill")
                    .font(.subheadline).foregroundStyle(Brand.olive)
            }
        }
    }

    private func row(_ title: String, @ViewBuilder chips: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { chips() } }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Brand.olive.opacity(0.12), in: Capsule())
            .foregroundStyle(Brand.olive)
    }
}

/// One collection stat tile (count + label), used for the guest's on-device collection.
private struct StatTile: View {
    let count: Int
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(Brand.olive)
            Text(count.formatted()).font(.title3.bold()).foregroundStyle(Brand.ink)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Puts the icon after the title (e.g. "مجموعتي ‹").
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.font(.caption) }
    }
}

private struct RecipeRef: Identifiable { let id: ClientID }
