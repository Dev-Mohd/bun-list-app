import BunnListCore
import SwiftUI

/// Someone's public profile, addressed by @username: picture, name, bio, points,
/// followers / following, a follow button, their discoveries and published recipes.
/// Pushed with a plain NavigationLink so it works from any stack.
@MainActor
struct PublicProfileView: View {
    let username: String

    @EnvironmentObject private var auth: AuthModel
    @State private var profile: RemotePublicProfile?
    @State private var failed = false
    @State private var isBusy = false
    @State private var list: FollowList?
    @State private var showSignIn = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Group {
            if let profile {
                content(profile)
            } else if failed {
                ContentUnavailableView {
                    Label("تعذّر فتح الملف", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("قد يكون الحساب غير موجود، أو تحقّق من اتصالك.")
                } actions: {
                    Button("إعادة المحاولة") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("@\(username)")
        .navigationBarTitleDisplayMode(.inline)
        .task { if profile == nil { await load() } }
        .refreshable { await load() }
        .sheet(item: $list) { which in
            NavigationStack { FollowListView(username: username, list: which, showsDone: true) }
                .environmentObject(auth)
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
    }

    private func content(_ p: RemotePublicProfile) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                header(p)

                if !p.discoveries.isEmpty {
                    section("اكتشافاته", icon: "sparkles") {
                        VStack(spacing: 0) {
                            ForEach(p.discoveries) { lot in
                                NavigationLink { LiveLotDetailView(slug: lot.slug) } label: {
                                    HStack {
                                        LiveLotRow(lot: lot)
                                        Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal).padding(.vertical, 6)
                                if lot.id != p.discoveries.last?.id { Divider().padding(.leading) }
                            }
                        }
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                }

                if !p.recipes.isEmpty {
                    section("وصفاته المنشورة", icon: "book.closed.fill") {
                        VStack(spacing: 0) {
                            ForEach(p.recipes) { recipe in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.title).font(.subheadline.weight(.semibold))
                                        Text([ReferenceCodes.brewMethod(recipe.methodCode)?.nameAr ?? recipe.methodCode, recipe.lotNameAr]
                                            .compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal).padding(.vertical, 10)
                                if recipe.id != p.recipes.last?.id { Divider().padding(.leading) }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                }

                if p.activityHidden == true {
                    Label("اكتشافاته ووصفاته خاصة", systemImage: "lock.fill")
                        .font(.callout).foregroundStyle(.secondary).padding(.top, 20)
                } else if p.discoveries.isEmpty && p.recipes.isEmpty {
                    Text("ما نشر شي بعد.").font(.callout).foregroundStyle(.secondary).padding(.top, 20)
                }
            }
            .padding(.vertical)
        }
    }

    private func header(_ p: RemotePublicProfile) -> some View {
        VStack(spacing: 10) {
            AvatarView(url: p.avatarUrl, name: p.displayName ?? p.username, size: 96)
            Text(p.displayName ?? p.username).font(.title2.bold()).foregroundStyle(Brand.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("@\(p.username)").font(.subheadline).foregroundStyle(.secondary)
                .environment(\.layoutDirection, .leftToRight)
            if let bio = p.bio, !bio.isEmpty {
                Text(bio).font(.callout).multilineTextAlignment(.center).foregroundStyle(.primary.opacity(0.8))
            }

            if !p.isMe {
                Button { Task { await toggleFollow(p) } } label: {
                    Label(p.isFollowing ? "تتابعه" : "تابِع", systemImage: p.isFollowing ? "checkmark" : "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 120, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(p.isFollowing ? Brand.olive.opacity(0.35) : Brand.olive)
                .disabled(isBusy)
                .accessibilityIdentifier("follow-button")
            }

            HStack(spacing: 0) {
                Button { list = .followers } label: { count(p.followers, "متابِعون") }
                    .buttonStyle(.plain).disabled(p.followers == nil)
                divider
                Button { list = .following } label: { count(p.following, "يتابع") }
                    .buttonStyle(.plain).disabled(p.following == nil)
                divider
                count(p.points, "نقطة")
                divider
                count(p.activityHidden == true ? nil : p.discoveries.count, "اكتشافات")
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.title3.bold())
            content()
        }
        .padding(.horizontal)
    }

    private var divider: some View {
        Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 28)
    }

    /// nil shows a lock: the owner keeps the number private.
    private func count(_ value: Int?, _ label: String) -> some View {
        VStack(spacing: 2) {
            Group {
                if let value { Text(value.formatted()) } else { Image(systemName: "lock.fill").accessibilityLabel("خاص") }
            }
            .font(.headline.monospacedDigit()).foregroundStyle(Brand.ink)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        failed = false
        do {
            profile = try await client.fetchUser(username, accessToken: auth.isSignedIn ? auth.currentAccessToken() : nil)
        } catch {
            if profile == nil { failed = true }
        }
    }

    private func toggleFollow(_ p: RemotePublicProfile) async {
        guard auth.isSignedIn else { showSignIn = true; return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.withToken { try await client.setFollowing(!p.isFollowing, username: p.username, accessToken: $0) }
            Haptics.tap()
            await load()
        } catch {
            // The button keeps its old state.
        }
    }
}

extension FollowList: Identifiable {
    public var id: String { rawValue }
}

/// Followers or following of one account; each row opens that person's profile.
struct FollowListView: View {
    let username: String
    let list: FollowList
    /// Shown when presented as a sheet.
    var showsDone = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthModel
    @State private var people: [RemotePerson]?
    @State private var failed = false
    @State private var isPrivate = false

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Group {
            if let people {
                if people.isEmpty {
                    ContentUnavailableView(list == .followers ? "ما عنده متابِعون بعد" : "ما يتابع أحد بعد",
                                           systemImage: "person.2")
                } else {
                    List(people) { person in
                        NavigationLink { PublicProfileView(username: person.username) } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: person.avatarUrl, name: person.displayName ?? person.username, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.displayName ?? person.username).font(.subheadline.weight(.semibold))
                                    Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                                        .environment(\.layoutDirection, .leftToRight)
                                }
                            }
                        }
                    }
                }
            } else if isPrivate {
                ContentUnavailableView("القائمة خاصة", systemImage: "lock.fill",
                                       description: Text("صاحب الحساب مخفيها."))
            } else if failed {
                ContentUnavailableView("تعذّر التحميل", systemImage: "wifi.exclamationmark")
            } else {
                ProgressView()
            }
        }
        .brandScreen()
        .navigationTitle(list == .followers ? "المتابِعون" : "يتابع")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }
        .task {
            do {
                people = try await auth.withOptionalToken { try await client.fetchFollowList(list, username: username, accessToken: $0) }
            } catch APIError.forbidden {
                isPrivate = true
            } catch {
                failed = true
            }
        }
    }
}
