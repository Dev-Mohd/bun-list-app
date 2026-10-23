import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI
import UIKit

/// Email sign-in: enter an email, receive a 6-digit code, enter it. Dismisses itself
/// once signed in. All server talk and state live in `AuthModel`.
struct SignInView: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                switch auth.state {
                case .signedOut:
                    quickSignInSection
                    emailStep
                case let .awaitingCode(pendingEmail):
                    codeStep(email: pendingEmail)
                case .signedIn:
                    EmptyView()
                }

                if let message = auth.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .navigationTitle("تسجيل الدخول")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
            .disabled(auth.isBusy)
            .overlay { if auth.isBusy { ProgressView() } }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
    }

    private var quickSignInSection: some View {
        Section {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("signin-apple")

            GoogleSignInButton(action: signInWithGoogle)
                .frame(height: 48)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("signin-google")
        } header: {
            Text("الدخول السريع")
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

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    private var emailStep: some View {
        Section {
            TextField("بريدك الإلكتروني", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("signin-email-field")
            Button("أرسل الرمز") { Task { await auth.sendCode(email: email) } }
                .disabled(email.isEmpty)
                .accessibilityIdentifier("signin-send-code")
        } header: {
            Text("ندخلك برمز لمرة واحدة")
        } footer: {
            Text("سنرسل رمزًا من ٦ أرقام إلى بريدك. لا كلمة مرور.")
        }
    }

    private func codeStep(email: String) -> some View {
        Section {
            Text("أرسلنا رمزًا إلى \(email)").font(.callout).foregroundStyle(.secondary)
            TextField("الرمز (٦ أرقام)", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .accessibilityIdentifier("signin-code-field")
            Button("تأكيد") { Task { await auth.verify(code: code) } }
                .disabled(code.count < 6)
                .accessibilityIdentifier("signin-verify")
            Button("إعادة إرسال الرمز") { Task { await auth.resendCode() } }
            Button("تغيير البريد", role: .cancel) { code = ""; auth.changeEmail() }
        }
    }
}
