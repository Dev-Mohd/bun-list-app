import SwiftUI

/// Sign in: Apple, Google, or email with a 6-digit code. Dismisses itself once
/// signed in. All server talk and state live in `AuthModel`; while it works the
/// sheet shows the drawing mark.
struct SignInView: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        BrandMark(height: 72)
                        BrandWordmark(size: 26)
                    }
                    .padding(.top, 8)

                    switch auth.state {
                    case .signedOut:
                        QuickSignInButtons()
                        divider
                        emailStep
                    case let .awaitingCode(pendingEmail):
                        codeStep(email: pendingEmail)
                    case .signedIn:
                        EmptyView()
                    }

                    if let message = auth.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .brandScreen()
            .navigationTitle("تسجيل الدخول")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
            .overlay { if auth.isBusy { BrandLoadingView(message: "لحظات…") } }
            .animation(.easeInOut(duration: 0.25), value: auth.isBusy)
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Text("أو بالإيميل").font(.footnote).foregroundStyle(.secondary).fixedSize()
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            field {
                TextField("بريدك الإلكتروني", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .accessibilityIdentifier("signin-email-field")
            }
            AuthButton(title: "أرسل الرمز", style: .filled) {
                Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .semibold))
            } action: { send() }
            .disabled(!email.contains("@"))
            .opacity(email.contains("@") ? 1 : 0.5)
            .accessibilityIdentifier("signin-send-code")
            Text("نرسل لك رمز من ٦ أرقام. بدون كلمة مرور.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func codeStep(email: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.open.fill").font(.system(size: 34)).foregroundStyle(Brand.olive)
            Text("أرسلنا الرمز إلى").font(.callout).foregroundStyle(.secondary)
            Text(email).font(.headline).environment(\.layoutDirection, .leftToRight)
            field {
                TextField("٠٠٠٠٠٠", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .focused($focused)
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(6))
                        if code.count == 6 { Task { await auth.verify(code: code) } }
                    }
                    .accessibilityIdentifier("signin-code-field")
            }
            AuthButton(title: "تأكيد", style: .filled) {
                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
            } action: { Task { await auth.verify(code: code) } }
            .disabled(code.count < 6)
            .opacity(code.count < 6 ? 0.5 : 1)
            .accessibilityIdentifier("signin-verify")
            HStack {
                Button("إعادة الإرسال") { Task { await auth.resendCode() } }
                Spacer()
                Button("تغيير البريد") { code = ""; auth.changeEmail() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Brand.olive)
        }
        .onAppear { focused = true }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.ink.opacity(0.12)))
    }

    private func send() {
        guard email.contains("@") else { return }
        Task { await auth.sendCode(email: email) }
    }
}
