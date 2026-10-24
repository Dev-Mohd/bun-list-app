import BunnListCore
import SwiftUI

/// Profile screen ("ملفي"): a header, the collection summary tiles (from the server
/// when signed in, else the on-device guest collection), sign-in / account controls,
/// recipes, and the about section.
struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthModel
    @State private var editingRecipe: ClientID?
    @State private var showSignIn = false
    @State private var confirmDelete = false
    @State private var showSettings = false
    @State private var showRecipes = false
    @State private var serverItems: [RemoteCollectionItem] = []

    private var counts: (owned: Int, tried: Int, favorite: Int, wants: Int) {
        if auth.isSignedIn {
            return (serverItems.filter(\.owned).count, serverItems.filter(\.tried).count,
                    serverItems.filter(\.favorite).count, serverItems.filter(\.wantsToTry).count)
        }
        let entries = model.book.activeEntries(owner: model.owner)
        return (entries.filter(\.isOwned).count, entries.filter(\.isTried).count,
                entries.filter(\.isFavorite).count, entries.filter(\.wantsToTry).count)
    }

    var body: some View {
        let recipes = model.myRecipes()
        NavigationStack {
            List {
                Section {
                    ProfileHeader(isSignedIn: auth.isSignedIn)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("مجموعتي") {
                    let c = counts
                    HStack(spacing: 10) {
                        StatTile(count: c.owned, label: "لديّ", icon: "checkmark.circle.fill")
                        StatTile(count: c.favorite, label: "مفضّل", icon: "heart.fill")
                        StatTile(count: c.wants, label: "ودّي أجرّب", icon: "bookmark.fill")
                        StatTile(count: c.tried, label: "جرّبته", icon: "cup.and.saucer.fill")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                accountStatusSection

                Section("الوصفات") {
                    Button { showRecipes = true } label: {
                        Label("بار التحضير", systemImage: "book.closed.fill")
                    }
                    .accessibilityIdentifier("open-recipes")
                }

                if !recipes.isEmpty {
                Section("وصفات على هذا الجهاز") {
                    if recipes.isEmpty {
                        Text("لا وصفات بعد. أنشئ وصفة من صفحة المحصول.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(recipes) { recipe in
                            Button { editingRecipe = recipe.clientID } label: { RecipeRow(recipe: recipe) }
                                .swipeActions {
                                    Button("حذف", role: .destructive) { model.setRecipeLifecycle(recipe.clientID, to: .deleted) }
                                    Button("نسخ") { _ = model.copyRecipe(recipe.clientID) }.tint(Brand.olive)
                                }
                        }
                    }
                }
                }

                Section("عن هذه النسخة") {
                    LabeledContent("الإصدار", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Text("الدليل والمسح تجريبيان. لا نقاط أو تحديات في هذه النسخة.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("ملفي")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityIdentifier("open-settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showRecipes) { RecipesHubView(startOn: auth.isSignedIn ? .mine : .explore) }
            .task { await loadServerCollection() }
            .onChange(of: auth.isSignedIn) { _, _ in Task { await loadServerCollection() } }
            .sheet(item: Binding(get: { editingRecipe.map(RecipeRef.init) }, set: { editingRecipe = $0?.id })) { ref in
                RecipeEditor(lotID: model.recipe(ref.id)?.lotID, existing: ref.id)
            }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .confirmationDialog("حذف الحساب نهائيًا؟", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("حذف الحساب", role: .destructive) { Task { await auth.deleteAccount() } }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيُحذف حسابك وبياناته على الخادم نهائيًا. لا يمكن التراجع. مجموعتك على هذا الجهاز تبقى.")
            }
        }
    }

    @ViewBuilder
    private var accountStatusSection: some View {
        switch auth.state {
        case .signedIn(let accountID):
            Section("الحساب") {
                Label("مسجّل الدخول", systemImage: "checkmark.seal.fill").foregroundStyle(Brand.olive)
                LabeledContent("المعرّف", value: String(accountID.prefix(12)) + "…")
                Button("تسجيل الخروج") { auth.signOut() }
                Button("حذف الحساب", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("account-delete")
            }
        default:
            Section("تسجيل الدخول") {
                Label("تستخدم التطبيق كزائر", systemImage: "person.crop.circle.badge.questionmark")
                Text("سجّل الدخول لحفظ حسابك ومزامنة مجموعتك بين أجهزتك. مجموعتك الحالية محفوظة على هذا الجهاز.")
                    .font(.callout).foregroundStyle(.secondary)
                QuickSignInButtons(height: 48)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                Button("كمّل بالإيميل") { showSignIn = true }
                    .accessibilityIdentifier("account-signin")
            }
        }
    }

    private func loadServerCollection() async {
        guard auth.isSignedIn, let token = auth.currentAccessToken() else { serverItems = []; return }
        let client = CatalogAPIClient(transport: URLSessionTransport())
        do {
            serverItems = try await client.fetchCollection(accessToken: token)
        } catch APIError.unauthorized {
            if let fresh = await auth.refreshAccessToken() {
                serverItems = (try? await client.fetchCollection(accessToken: fresh)) ?? serverItems
            }
        } catch {
            // keep what we have
        }
    }
}

/// The profile header card: avatar + a status line.
private struct ProfileHeader: View {
    let isSignedIn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Brand.olive.opacity(0.15))
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "person.fill").font(.title).foregroundStyle(Brand.olive))
            VStack(alignment: .leading, spacing: 4) {
                Text(isSignedIn ? "حسابك" : "زائر").font(.title2.bold()).foregroundStyle(Brand.ink)
                Label(isSignedIn ? "مسجّل الدخول" : "استكشاف بدون حساب",
                      systemImage: isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                    .font(.subheadline)
                    .foregroundStyle(isSignedIn ? Brand.olive : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

/// One collection stat tile (count + label).
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
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct RecipeRef: Identifiable { let id: ClientID }
