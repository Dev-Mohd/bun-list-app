import BunnListCore
import SwiftUI

/// Account screen: email sign-in (one-time code) plus the on-device collection summary.
struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthModel
    @State private var editingRecipe: ClientID?
    @State private var showSignIn = false
    @State private var confirmDelete = false

    var body: some View {
        let entries = model.book.activeEntries(owner: model.owner)
        let recipes = model.myRecipes()
        NavigationStack {
            List {
                Section { BrandHeading(subtitle: "حسابك على هذا الجهاز") }
                accountStatusSection
                Section("مجموعتك") {
                    LabeledContent("لديّ", value: entries.filter(\.isOwned).count.formatted())
                    LabeledContent("جربته", value: entries.filter(\.isTried).count.formatted())
                    LabeledContent("مفضل", value: entries.filter(\.isFavorite).count.formatted())
                    LabeledContent("ودي أجرب", value: entries.filter(\.wantsToTry).count.formatted())
                }
                Section("وصفاتي") {
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
                Section("عن هذه النسخة") {
                    LabeledContent("الإصدار", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Text("الدليل والمسح تجريبيان. لا نقاط أو تحديات في هذه النسخة.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("حسابي")
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
}

private struct RecipeRef: Identifiable { let id: ClientID }
