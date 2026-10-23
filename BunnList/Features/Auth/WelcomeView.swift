import SwiftUI

/// The landing screen shown on first launch (and after sign-out): explore as a guest,
/// or sign in with Apple / Google / email. Dismisses itself once the user signs in
/// (via `auth.isSignedIn`) or chooses to continue as a guest.
struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthModel
    @Binding var continuedAsGuest: Bool
    @State private var showEmail = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 64))
                .foregroundStyle(Brand.olive)
            Text("بن لست")
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(Brand.ink)
            Text("اكتشف القهوة، بطاقة بطاقة")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    continuedAsGuest = true
                } label: {
                    Label("استكشف كضيف", systemImage: "eye")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Brand.ink)
                .accessibilityIdentifier("welcome-guest")

                HStack(spacing: 10) {
                    line
                    Text("أو").font(.footnote).foregroundStyle(.secondary)
                    line
                }
                .padding(.vertical, 4)

                QuickSignInButtons(height: 50)

                Button {
                    showEmail = true
                } label: {
                    Label("كمّل بالإيميل", systemImage: "envelope")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("welcome-email")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background.ignoresSafeArea())
        .sheet(isPresented: $showEmail) { SignInView() }
    }

    private var line: some View {
        Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
    }
}
