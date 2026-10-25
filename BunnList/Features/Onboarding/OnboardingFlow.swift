import BunnListCore
import SwiftUI

/// First run after signing in: set up the profile, then pick the coffees at home.
/// Finishing or skipping records it on the server so it shows once per account.
@MainActor
struct OnboardingFlow: View {
    @EnvironmentObject private var auth: AuthModel
    @EnvironmentObject private var profile: ProfileStore
    @State private var step = 0
    var onFinished: () -> Void

    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    ProfileSetupView(mode: .firstRun) { withAnimation { step = 1 } }
                } else {
                    FirstCoffeesView { Task { await finish() } }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        ForEach(0..<2) { i in
                            Capsule().fill(i <= step ? Brand.olive : Color.secondary.opacity(0.25))
                                .frame(width: i == step ? 24 : 8, height: 8)
                        }
                    }
                    .accessibilityLabel("الخطوة \((step + 1).formatted()) من ٢")
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish() async {
        try? await auth.withToken { try await client.markOnboarded(accessToken: $0) }
        await profile.refresh(auth)
        onFinished()
    }
}
