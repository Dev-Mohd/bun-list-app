import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI
import UIKit

/// The Apple + Google quick sign-in buttons, shared by the welcome screen and the
/// email sign-in sheet. Talks to `AuthModel` from the environment.
struct QuickSignInButtons: View {
    @EnvironmentObject private var auth: AuthModel
    var height: CGFloat = 50

    var body: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: height)
            .accessibilityIdentifier("signin-apple")

            GoogleSignInButton(action: signInWithGoogle)
                .frame(height: height)
                .accessibilityIdentifier("signin-google")
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        guard case let .success(authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else { return }
        Task { await auth.signInWithApple(identityToken: token) }
    }

    private func signInWithGoogle() {
        guard let root = Self.rootViewController() else { return }
        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
                guard let idToken = result.user.idToken?.tokenString else { return }
                await auth.signInWithGoogle(idToken: idToken)
            } catch {
                // user canceled or sign-in failed — nothing to show
            }
        }
    }

    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
