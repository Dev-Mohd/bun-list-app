import BunnListCore
import GoogleSignIn
import SwiftUI

@main
struct BunnListApp: App {
    @StateObject private var model = AppModel.live()
    @StateObject private var auth = AuthModel.live()
    @StateObject private var profile = ProfileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(auth)
                .environmentObject(profile)
                .environment(\.layoutDirection, .rightToLeft)
                .tint(Brand.olive)
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }
}

enum AppTab: Hashable {
    case discover, collection, scan, community, account
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("continuedAsGuest") private var continuedAsGuest = false
    @State private var tab: AppTab = .discover

    /// UI tests launch straight into the tabs, past the welcome gate.
    private var uiTesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    var body: some View {
        if !uiTesting && !auth.isSignedIn && !continuedAsGuest {
            WelcomeView(continuedAsGuest: $continuedAsGuest)
        } else if let loadError = model.loadError {
            ContentUnavailableView {
                Label("تعذّر فتح البيانات", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("إعادة المحاولة") { model.reload() }.buttonStyle(.borderedProminent)
            }
        } else {
            TabView(selection: $tab) {
                DiscoverView(tab: $tab)
                    .tabItem { Label("اكتشف", systemImage: "magnifyingglass") }
                    .tag(AppTab.discover)
                CollectionView()
                    .tabItem { Label("مجموعتي", systemImage: "square.stack.3d.up") }
                    .tag(AppTab.collection)
                ScanView()
                    .tabItem { Label("مسح", systemImage: "camera.viewfinder") }
                    .tag(AppTab.scan)
                CommunityView()
                    .tabItem { Label("المجتمع", systemImage: "person.3.fill") }
                    .tag(AppTab.community)
                AccountView()
                    .tabItem { Label("حسابي", systemImage: "person.crop.circle") }
                    .tag(AppTab.account)
            }
            .task(id: auth.isSignedIn) { await profile.refresh(auth) }
            .fullScreenCover(isPresented: Binding(
                get: { !uiTesting && auth.isSignedIn && profile.me.map { !$0.isOnboarded } == true },
                set: { _ in }
            )) {
                OnboardingFlow { }
                    .environmentObject(auth)
                    .environmentObject(profile)
            }
            .alert("تنبيه", isPresented: Binding(get: { model.errorMessage != nil },
                                                 set: { if !$0 { model.errorMessage = nil } })) {
                Button("حسنًا", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}
