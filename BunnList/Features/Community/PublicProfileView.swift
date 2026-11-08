import BunnListCore
import SwiftUI

/// A profile, addressed by @username, laid out the same for you and for others:
/// picture, name, @username, points and bio; followers, following and points; the
/// follow button (or, on your own, edit and «اكتشف ناس»); then tabs for their
/// coffees by shelf, published recipes and discoveries. A private account shows
/// only the header to people who don't follow it. `extra` goes under the header
/// (the owner's own taste card).
@MainActor
struct PublicProfileView<Extra: View>: View {
    let username: String
    @ViewBuilder var extra: () -> Extra

    @EnvironmentObject private var auth: AuthModel
    @State private var profile: RemotePublicProfile?
    @State private var failed = false
    @State private var isBusy = false
    @State private var list: FollowList?
    @State private var showSignIn = false
    @State private var showEditor = false
    @State private var reporting: ReportRef?
    @State private var tab = ProfileTab.coffees
    @State private var shelf = CoffeeShelf.owned
    @State private var coffees: RemotePersonCoffees?
    @State private var coffeesHidden = false
    @State private var requests = 0
    @State private var confirmBlock = false
    /// Your own recipes, private ones too, on your own profile.
    @State private var myRecipes: [RemoteRecipe]?
    @State private var editorDraft: DraftRef?

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
        .navigationTitle(profile?.isMe == true ? "ملفي" : "@\(username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.isSignedIn, let p = profile, !p.isMe {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: "تابع @\(p.username) في BunnList ☕") { Label("شارك الحساب", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { reporting = ReportRef(target: .profile, targetID: p.username) } label: {
                            Label("بلّغ عن الحساب", systemImage: "flag")
                        }
                        if p.isBlocked == true {
                            Button { Task { await setBlocked(false) } } label: { Label("إلغاء الحظر", systemImage: "hand.raised.slash") }
                        } else {
                            Button(role: .destructive) { confirmBlock = true } label: { Label("حظر الحساب", systemImage: "hand.raised.fill") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("خيارات الحساب")
                }
            }
        }
        .sheet(item: $reporting) { ReportSheet(ref: $0) }
        .confirmationDialog("تحظر @\(username)؟", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("حظر", role: .destructive) { Task { await setBlocked(true) } }
        } message: {
            Text("ما بتشوفون نشاط وتعليقات بعض، وتنلغي المتابعة بينكم. تقدر تلغي الحظر من الإعدادات.")
        }
        .task { if profile == nil { await load() } }
        .task(id: "\(shelf.rawValue)|\(profile?.isFollowing ?? false)") { await loadCoffees() }
        .refreshable { await load(); await loadCoffees() }
        .sheet(item: $list) { which in
            NavigationStack { FollowListView(username: username, list: which, showsDone: true, canRemove: profile?.isMe == true) }
                .environmentObject(auth)
        }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await load() } }) {
            NavigationStack { ProfileSetupView(mode: .edit) { } }
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .sheet(item: $editorDraft) { ref in
            ServerRecipeEditor(draft: ref.draft) { _ in Task { await loadMyRecipes() } }
                .environmentObject(auth)
        }
        .task(id: "\(tab)|\(profile?.isMe ?? false)") { if tab == .recipes, profile?.isMe == true { await loadMyRecipes() } }
    }

    private func loadMyRecipes() async {
        guard auth.isSignedIn else { return }
        if let all = try? await auth.withToken({ try await client.fetchMyRecipes(accessToken: $0) }) {
            myRecipes = all.filter { $0.state != .deleted }
        }
    }

    /// «الوصفات» on your own profile: all your recipes (published or 🔒 خاصة) and «＋ سوّ وصفة جديدة».
    @ViewBuilder
    private var myRecipesTab: some View {
        VStack(spacing: 8) {
            if let myRecipes {
                ForEach(myRecipes) { recipe in
                    Button { editorDraft = DraftRef(draft: RecipeDraft(editing: recipe)) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.title.isEmpty ? RecipeText.method(recipe.methodCode) : recipe.title).font(.subheadline.bold()).foregroundStyle(Brand.ink)
                                Text([RecipeText.method(recipe.methodCode), recipe.lot?.nameAr ?? "عامة"].joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let published = recipe.state == .published
                            Text(published ? "منشورة" : "🔒 خاصة").font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(published ? Brand.olive.opacity(0.15) : Brand.background, in: Capsule())
                                .foregroundStyle(published ? Brand.olive : .secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 58, corner: 18) }
            }
            CreateRecipeCard {
                var draft = RecipeDraft()
                if let classic = BrewPreset.all.first { draft.apply(classic) }
                editorDraft = DraftRef(draft: draft)
            }
        }
        .padding(.horizontal)
    }

    private func content(_ p: RemotePublicProfile) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header(p)
                extra()
                if p.isBlocked == true {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.raised.fill").font(.largeTitle).foregroundStyle(.secondary)
                        Text("حظرت هذا الحساب").font(.headline)
                        Text("ما تشوف نشاطه وتعليقاته، وهو ما يشوف حقك.").font(.subheadline).foregroundStyle(.secondary)
                        Button("إلغاء الحظر") { Task { await setBlocked(false) } }.buttonStyle(.bordered).tint(Brand.olive)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal)
                } else if locked(p) {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Brand.gold)
                        Text("هذا الحساب خاص").font(.headline)
                        Text(p.requested == true ? "طلبت تتابعه. أول ما يقبل بتشوف قهاويه ووصفاته."
                                                  : "تابعه عشان تشوف قهاويه ووصفاته.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal)
                } else {
                    Picker("القسم", selection: $tab) {
                        ForEach(ProfileTab.allCases, id: \.self) { Text($0.nameAr).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    switch tab {
                    case .coffees: coffeesTab
                    case .recipes: if p.isMe { myRecipesTab } else { recipesTab(p) }
                    case .lists: UserListsGrid(username: username)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func locked(_ p: RemotePublicProfile) -> Bool {
        p.isPrivate == true && !p.isMe && !p.isFollowing
    }

    // MARK: Header

    private func header(_ p: RemotePublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AvatarView(url: p.avatarUrl, name: p.displayName ?? p.username, size: 76)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(p.displayName ?? p.username).font(.title2.bold()).foregroundStyle(Brand.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if p.isPrivate == true {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("حساب خاص")
                        }
                    }
                    Text("@\(p.username)").font(.subheadline).foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
            }
            if let bio = p.bio, !bio.isEmpty {
                Text(bio).font(.callout).foregroundStyle(.primary.opacity(0.85))
            }
            HStack(spacing: 8) {
                Button { list = .followers } label: { count(p.followers, "متابِع") }
                    .buttonStyle(.plain).disabled(p.followers == nil || locked(p))
                Button { list = .following } label: { count(p.following, "يتابع") }
                    .buttonStyle(.plain).disabled(p.following == nil || locked(p))
                count(p.points, "نقطة")
            }
            if p.isMe {
                HStack(spacing: 8) {
                    Button { showEditor = true } label: { pill("عدّل ملفك", filled: true) }
                        .accessibilityIdentifier("edit-profile")
                    NavigationLink { FindPeopleView() } label: { pill("اكتشف ناس", filled: false) }
                        .accessibilityIdentifier("find-people")
                }
                .buttonStyle(.plain)
                if requests > 0 {
                    NavigationLink { FollowRequestsView() } label: {
                        HStack {
                            Label("طلبات المتابعة", systemImage: "person.badge.clock")
                            Spacer()
                            Text(requests.formatted()).font(.caption.bold().monospacedDigit())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Brand.gold, in: Capsule()).foregroundStyle(.white)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            } else if p.isBlocked != true {
                let state = FollowState(following: p.isFollowing, requested: p.requested ?? false)
                Button { Task { await toggleFollow(p) } } label: {
                    pill(state.buttonAr, filled: state == .none)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("follow-button")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
    }

    private func pill(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(filled ? Brand.ink : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(filled ? Brand.background : Brand.ink)
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
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Tabs

    @ViewBuilder
    private var coffeesTab: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoffeeShelf.allCases) { s in
                    ChoiceChip(title: coffees.map { "\(s.nameAr) \($0.counts[s].formatted())" } ?? s.nameAr,
                               isSelected: shelf == s) { shelf = s }
                }
            }
            .padding(.horizontal)
        }
        if coffeesHidden {
            Label("قهاويه خاصة", systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary).padding(.top, 20)
        } else if let coffees {
            if coffees.coffees.isEmpty {
                Text("ما فيه قهاوي هنا بعد.").font(.callout).foregroundStyle(.secondary).padding(.top, 20)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(coffees.coffees) { item in
                        NavigationLink { LiveLotDetailView(slug: item.slug) } label: {
                            VStack(spacing: 6) {
                                LotPhotoWell(imageUrl: item.imageUrl, notes: [], roaster: item.roasterNameAr, name: item.nameAr,
                                             origin: item.originNameAr, originCode: item.originCode, padding: 6)
                                    .aspectRatio(3 / 4, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(item.nameAr).font(.caption.weight(.semibold)).foregroundStyle(Brand.ink).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        } else {
            // Bag-shaped shimmering tiles while the shelf loads.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(spacing: 6) {
                        SkeletonBlock(height: 140, corner: 14)
                        SkeletonBlock(height: 10, corner: 5).padding(.horizontal, 12)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func recipesTab(_ p: RemotePublicProfile) -> some View {
        if p.recipes.isEmpty {
            Text(p.activityHidden == true ? "وصفاته خاصة." : "ما نشر وصفات بعد.").font(.callout).foregroundStyle(.secondary).padding(.top, 20)
        } else {
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
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func activityTab(_ p: RemotePublicProfile) -> some View {
        if p.discoveries.isEmpty {
            Text(p.activityHidden == true ? "نشاطه خاص." : "ما اكتشف قهوة بعد.").font(.callout).foregroundStyle(.secondary).padding(.top, 20)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("اكتشافاته", systemImage: "sparkles").font(.headline).padding(.horizontal)
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
                .padding(.horizontal)
            }
        }
    }

    // MARK: Loading

    private func setBlocked(_ blocked: Bool) async {
        do {
            _ = try await auth.withToken { try await client.setBlocked(blocked, username: username, accessToken: $0) }
            Haptics.tap()
            await load()
        } catch {}
    }

    private func load() async {
        failed = false
        do {
            profile = try await client.fetchUser(username, accessToken: auth.isSignedIn ? auth.currentAccessToken() : nil)
            if profile?.isMe == true, auth.isSignedIn {
                requests = (try? await auth.withToken { try await client.followRequests(accessToken: $0) })?.count ?? 0
            }
        } catch {
            if profile == nil { failed = true }
        }
    }

    private func loadCoffees() async {
        guard let p = profile, !locked(p) else { return }
        do {
            coffees = try await auth.withOptionalToken { try await client.personCoffees(username, shelf: shelf, accessToken: $0) }
            coffeesHidden = false
        } catch APIError.forbidden {
            coffeesHidden = true
        } catch {
            // Keeps what was shown.
        }
    }

    private func toggleFollow(_ p: RemotePublicProfile) async {
        guard auth.isSignedIn else { showSignIn = true; return }
        isBusy = true
        defer { isBusy = false }
        let isOn = p.isFollowing || p.requested == true
        do {
            try await auth.withToken { try await client.setFollowing(!isOn, username: p.username, accessToken: $0) }
            Haptics.tap()
            await load()
        } catch {
            // The button keeps its old state.
        }
    }
}

extension PublicProfileView where Extra == EmptyView {
    init(username: String) {
        self.init(username: username) { EmptyView() }
    }
}

enum ProfileTab: CaseIterable {
    case coffees, recipes, lists

    var nameAr: String {
        switch self {
        case .coffees: return "القهوات"
        case .recipes: return "الوصفات"
        case .lists: return "القوائم"
        }
    }
}

/// Followers or following of one account; each row opens that person's profile.
struct FollowListView: View {
    let username: String
    let list: FollowList
    /// Shown when presented as a sheet.
    var showsDone = false
    /// Your own followers can be removed (they aren't told).
    var canRemove = false

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
                        .swipeActions {
                            if canRemove && list == .followers {
                                Button("إزالة", role: .destructive) { Task { await remove(person) } }
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

    private func remove(_ person: RemotePerson) async {
        do {
            try await auth.withToken { try await client.removeFollower(username: person.username, accessToken: $0) }
            people?.removeAll { $0.username == person.username }
        } catch {
            // Stays in the list.
        }
    }
}
