import BunnListCore
import SwiftUI

/// "بار التحضير": the user's recipes and published recipes from everyone, synced
/// with the server. Presented as a sheet; `lot` narrows "استكشف" to one coffee and
/// pre-selects it for a new recipe.
@MainActor
struct RecipesHubView: View {
    enum Tab: Hashable { case mine, explore }

    var lot: RemoteRecipeLot?

    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var mine: [RemoteRecipe]?
    @State private var explore: [RemoteRecipe]?
    @State private var failed = false
    @State private var editorDraft: DraftRef?

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    init(lot: RemoteRecipeLot? = nil, startOn tab: Tab = .mine) {
        self.lot = lot
        _tab = State(initialValue: tab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("القسم", selection: $tab) {
                    Text("وصفاتي").tag(Tab.mine)
                    Text(lot == nil ? "استكشف" : "وصفات هذه القهوة").tag(Tab.explore)
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch tab {
                    case .mine: mineContent
                    case .explore: exploreContent
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Brand.background.ignoresSafeArea())
            .navigationTitle("بار التحضير")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("إغلاق")
                }
                if auth.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button { startNew() } label: { Image(systemName: "plus") }
                            .accessibilityLabel("وصفة جديدة")
                            .accessibilityIdentifier("recipe-new")
                    }
                }
            }
            .navigationDestination(for: RemoteRecipe.self) { recipe in
                RecipeDetailView(recipe: recipe) { change in apply(change) }
            }
            .sheet(item: $editorDraft) { ref in
                ServerRecipeEditor(draft: ref.draft) { saved in apply(.saved(saved)) }
                    .environmentObject(auth)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private var mineContent: some View {
        if !auth.isSignedIn {
            ContentUnavailableView {
                Label("سجّل الدخول لوصفاتك", systemImage: "person.crop.circle")
            } description: {
                Text("وصفاتك تُحفظ في حسابك وتظهر على كل أجهزتك. سجّل الدخول من «ملفي».")
            }
        } else if let mine {
            if mine.isEmpty {
                ContentUnavailableView {
                    Label("بار التحضير فاضي", systemImage: "book.closed")
                } description: {
                    Text("كل باريستا له توقيعه — اكتب أول وصفة لك.")
                } actions: {
                    Button("أنشئ وصفتك الأولى") { startNew() }
                        .buttonStyle(.borderedProminent).tint(Brand.ink)
                }
            } else {
                List(mine) { recipe in
                    NavigationLink(value: recipe) { RecipeListRow(recipe: recipe) }
                }
                .scrollContentBackground(.hidden)
            }
        } else {
            loadingOrFailed
        }
    }

    @ViewBuilder
    private var exploreContent: some View {
        if let explore {
            if explore.isEmpty {
                ContentUnavailableView {
                    Label("لا وصفات منشورة بعد", systemImage: "sparkles")
                } description: {
                    Text(lot == nil ? "انشر وصفتك لتكون أول وصفة هنا." : "كن أول من ينشر وصفة لهذه القهوة.")
                }
            } else {
                List(explore) { recipe in
                    NavigationLink(value: recipe) { RecipeListRow(recipe: recipe, showsAuthor: true) }
                }
                .scrollContentBackground(.hidden)
            }
        } else {
            loadingOrFailed
        }
    }

    @ViewBuilder
    private var loadingOrFailed: some View {
        if failed {
            ContentUnavailableView {
                Label("تعذّر تحميل الوصفات", systemImage: "wifi.exclamationmark")
            } description: {
                Text("تحقّق من اتصالك ثم أعد المحاولة.")
            } actions: {
                Button("إعادة المحاولة") { Task { await load() } }.buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView()
        }
    }

    private func startNew() {
        var draft = RecipeDraft(lot: lot)
        if let classic = BrewPreset.all.first { draft.apply(classic) }
        editorDraft = DraftRef(draft: draft)
    }

    private func load() async {
        failed = false
        do {
            if auth.isSignedIn {
                mine = try await auth.withToken { try await client.fetchMyRecipes(accessToken: $0) }
            }
            explore = try await client.exploreRecipes(lotSlug: lot?.slug, accessToken: auth.currentAccessToken())
        } catch {
            failed = true
        }
    }

    private func apply(_ change: RecipeChange) {
        switch change {
        case let .saved(recipe):
            upsert(recipe, into: &mine)
            if recipe.state == .published { upsert(recipe, into: &explore) } else { explore?.removeAll { $0.id == recipe.id } }
            if recipe.isMine { tab = .mine }
        case let .deleted(id):
            mine?.removeAll { $0.id == id }
            explore?.removeAll { $0.id == id }
        case let .copy(recipe):
            editorDraft = DraftRef(draft: RecipeDraft(copying: recipe))
        }
    }

    private func upsert(_ recipe: RemoteRecipe, into list: inout [RemoteRecipe]?) {
        guard list != nil else { return }
        if let index = list?.firstIndex(where: { $0.id == recipe.id }) {
            list?[index] = recipe
        } else {
            list?.insert(recipe, at: 0)
        }
    }
}

/// What a detail screen reports back to the hub.
enum RecipeChange {
    case saved(RemoteRecipe)
    case deleted(String)
    case copy(RemoteRecipe)
}

struct DraftRef: Identifiable {
    let id = UUID()
    let draft: RecipeDraft
}
