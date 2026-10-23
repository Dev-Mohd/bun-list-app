import BunnListCore
import SwiftUI

@main
struct BunnListApp: App {
    @StateObject private var model = AppModel.live()
    @StateObject private var auth = AuthModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(auth)
                .environment(\.layoutDirection, .rightToLeft)
                .tint(Brand.olive)
        }
    }
}

enum AppTab: Hashable {
    case discover, collection, scan, community, account
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: AppTab = .discover

    var body: some View {
        if let loadError = model.loadError {
            ContentUnavailableView {
                Label("تعذّر فتح البيانات", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("إعادة المحاولة") { model.reload() }.buttonStyle(.borderedProminent)
            }
        } else {
            TabView(selection: $tab) {
                DiscoverView()
                    .tabItem { Label("اكتشف", systemImage: "magnifyingglass") }
                    .tag(AppTab.discover)
                CollectionView()
                    .tabItem { Label("مجموعتي", systemImage: "square.stack.3d.up") }
                    .tag(AppTab.collection)
                ScanView()
                    .tabItem { Label("مسح", systemImage: "camera.viewfinder") }
                    .tag(AppTab.scan)
                CommunityView()
                    .tabItem { Label("المجتمع", systemImage: "person.3") }
                    .tag(AppTab.community)
                AccountView()
                    .tabItem { Label("حسابي", systemImage: "person.crop.circle") }
                    .tag(AppTab.account)
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
