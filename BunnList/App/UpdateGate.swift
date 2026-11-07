import BunnListCore
import SwiftUI

/// Checks /app/config on launch and when the app comes back: a build below the minimum gets a
/// full-screen stop with a link to the App Store (no way past it); below the latest, a one-time nudge.
struct UpdateGate: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var config: RemoteAppConfig?
    @State private var showNudge = false
    @AppStorage("update.nudgedBuild") private var nudgedBuild = 0

    private static let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    private var verdict: RemoteAppConfig.Verdict {
        config.map { RemoteAppConfig.verdict(build: Self.build, platform: $0.ios) } ?? .ok
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if verdict == .required, let config {
                    ForcedUpdateView(message: config.updateMessageAr) { open(config.ios.storeUrl) }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: verdict)
            .alert("فيه تحديث جديد ✨", isPresented: $showNudge) {
                Button("حدّث الحين") { if let config { open(config.ios.storeUrl) } }
                Button("بعدين", role: .cancel) {}
            } message: {
                Text("نزّلنا نسخة جديدة من BunnList فيها تحسينات. حدّثها من App Store.")
            }
            .task { await check() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await check() } } }
    }

    private func check() async {
        guard let fresh = try? await CatalogAPIClient(transport: URLSessionTransport()).appConfig() else { return }
        config = fresh
        if RemoteAppConfig.verdict(build: Self.build, platform: fresh.ios) == .suggested, nudgedBuild < fresh.ios.latestBuild {
            nudgedBuild = fresh.ios.latestBuild
            showNudge = true
        }
    }

    private func open(_ link: String) {
        if let url = URL(string: link) { openURL(url) }
    }
}

/// The stop screen: the logo, why, and «حدّث التطبيق».
private struct ForcedUpdateView: View {
    let message: String
    var update: () -> Void

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                BrandMark(height: 120, animated: false)
                Text("حدّث BunnList").font(.largeTitle.bold()).foregroundStyle(Brand.ink)
                Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                Spacer()
                Button(action: update) {
                    Text("حدّث التطبيق").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(Brand.background).background(Brand.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

extension View {
    func updateGate() -> some View { modifier(UpdateGate()) }
}
