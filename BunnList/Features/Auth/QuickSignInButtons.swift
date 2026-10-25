import AuthenticationServices
import GoogleSignIn
import SwiftUI
import UIKit

/// The Apple + Google sign-in buttons, shared by the welcome screen and the email
/// sign-in sheet. Both use the app's own button shape (`AuthButton`); Apple's
/// request runs through ASAuthorizationController, Google's through GoogleSignIn.
struct QuickSignInButtons: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var apple = AppleSignInCoordinator()

    var body: some View {
        VStack(spacing: 12) {
            AuthButton(title: "المتابعة مع Apple", style: .filled) {
                Image(systemName: "apple.logo").font(.system(size: 20, weight: .semibold))
            } action: {
                apple.start { token in Task { await auth.signInWithApple(identityToken: token) } }
            }
            .accessibilityIdentifier("signin-apple")

            AuthButton(title: "المتابعة مع Google") {
                GoogleMark()
            } action: { signInWithGoogle() }
            .accessibilityIdentifier("signin-google")
        }
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

/// Runs Sign in with Apple and hands back the identity token.
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var completion: ((String) -> Void)?

    func start(_ completion: @escaping (String) -> Void) {
        self.completion = completion
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else { return }
        completion?(token)
        completion = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion = nil // canceled or failed — nothing to show
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
