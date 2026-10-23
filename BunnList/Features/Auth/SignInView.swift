import SwiftUI

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
