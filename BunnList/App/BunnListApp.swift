import SwiftUI

@main
struct BunnListApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var composer = Composer()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(composer)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .tint(Brand.olive)
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state = LocalState.demo()
    @Published private(set) var isReady = false
    @Published var error: String?
    private var repository: LocalRepository?

    init() { reload() }

    func reload() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
                .appendingPathComponent("BunnList", isDirectory: true)
            let repository = try LocalRepository(persistence: JSONFilePersistence(fileURL: directory.appendingPathComponent("state-v1.json")))
            self.repository = repository
            state = repository.state
            isReady = true
            error = nil
        } catch {
            isReady = false
            self.error = "تعذّر فتح البيانات المحلية: \(error.localizedDescription)"
        }
    }

    func mutate(_ operation: (LocalRepository) throws -> Void) throws {
        guard let repository else { throw LocalError.damagedFile }
        try operation(repository)
        state = repository.state
    }

    func perform(_ operation: (LocalRepository) throws -> Void) {
        do { try mutate(operation) } catch { self.error = error.localizedDescription }
    }
}

@MainActor
final class Composer: ObservableObject {
    @Published var presented: ExperienceDraft?
    @Published var pending: ExperienceDraft?
    @Published var asksReplacement = false

    func open(_ proposed: ExperienceDraft? = nil, store: AppStore) {
        if let existing = store.state.draft {
            if let proposed {
                if proposed.editingID != nil && proposed.editingID == existing.editingID {
                    presented = existing
                } else {
                    pending = proposed
                    asksReplacement = true
                }
            } else { presented = existing }
        } else { present(proposed ?? ExperienceDraft(), store: store) }
    }

    func present(_ draft: ExperienceDraft, store: AppStore) {
        do {
            try store.mutate { try $0.saveDraft(draft) }
            presented = draft
            pending = nil
        } catch { store.error = error.localizedDescription }
    }
}

private enum Tab: Hashable { case home, discover, add, library, profile }

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var composer: Composer
    @State private var selected: Tab = .home
    @State private var publishedID: UUID?
    var body: some View {
        Group {
            if store.isReady {
                TabView(selection: Binding(get: { selected }, set: { tab in
                    if tab == .add { composer.open(store: store) } else { selected = tab }
                })) {
                    NavigationStack { FeedView(publishedID: $publishedID) }
                        .tabItem { Label("الرئيسية", systemImage: "house") }.tag(Tab.home)
                    NavigationStack { DiscoveryView() }
                        .tabItem { Label("اكتشف", systemImage: "magnifyingglass") }.tag(Tab.discover)
                    Color.clear.tabItem { Label("إضافة تجربة", systemImage: "plus.circle.fill") }.tag(Tab.add)
                    NavigationStack { LibraryView() }
                        .tabItem { Label("مكتبتي", systemImage: "books.vertical") }.tag(Tab.library)
                    NavigationStack { ProfileView(profileID: store.state.localUserID) }
                        .tabItem { Label("حسابي", systemImage: "person.crop.circle") }.tag(Tab.profile)
                }
                .sheet(item: $composer.presented) { draft in
                    ExperienceEditor(initial: draft) { id in
                        publishedID = id
                        selected = .home
                    }
                }
                .confirmationDialog("لديك مسودة محفوظة", isPresented: $composer.asksReplacement, titleVisibility: .visible) {
                    Button("متابعة المسودة المحفوظة") { composer.presented = store.state.draft; composer.pending = nil }
                    Button("استبدال المسودة وبدء التجربة المطلوبة", role: .destructive) {
                        if let draft = composer.pending { composer.present(draft, store: store) }
                    }
                    Button("إلغاء", role: .cancel) { composer.pending = nil }
                } message: { Text("لن تُحذف المسودة السابقة إلا إذا اخترت استبدالها.") }
                .alert("تعذّر الحفظ", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("حسنًا", role: .cancel) { store.error = nil }
                } message: { Text(store.error ?? "") }
            } else {
                ContentUnavailableView {
                    Label("تعذّر فتح بيانات الجهاز", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.error ?? "لم يتم استبدال بياناتك.")
                } actions: {
                    Button("إعادة المحاولة") { store.reload() }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
