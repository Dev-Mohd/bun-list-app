import SwiftUI

/// The landing screen shown on first launch (and after sign-out): the mark draws
/// itself, then sign in with Apple, Google or email, or look around as a guest.
/// While a sign-in is under way the whole screen becomes the drawing mark.
struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthModel
    @Binding var continuedAsGuest: Bool
    @State private var showEmail = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                BrandMark(height: 130)
                BrandWordmark(size: 32)
                Text("كل كيس قهوة.. له حكاية")
                    .font(.title3.weight(.medium)).foregroundStyle(Brand.olive)
            }

            Spacer()

            VStack(spacing: 12) {
                QuickSignInButtons()

                AuthButton(title: "المتابعة بالإيميل", style: .outline) {
                    Image(systemName: "envelope.fill").font(.system(size: 17, weight: .semibold))
                } action: { showEmail = true }
                .accessibilityIdentifier("welcome-email")

                Button {
                    continuedAsGuest = true
                } label: {
                    Text("تصفّح كضيف")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.gold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("welcome-guest")
                .padding(.top, 4)

                if let message = auth.errorMessage, !showEmail {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.red)
                }

                Text("بالمتابعة توافق على الشروط وسياسة الخصوصية.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandBackdrop())
        .overlay {
            if auth.isBusy && !showEmail { BrandLoadingView(message: "نجهّز حسابك…") }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isBusy)
        .sheet(isPresented: $showEmail) { SignInView() }
    }
}

/// One full-width sign-in button: same height, corners and type for every provider.
struct AuthButton<Icon: View>: View {
    enum Style { case filled, outline }

    let title: String
    var style: Style = .outline
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon().frame(width: 22, height: 22)
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(style == .filled ? Brand.background : Brand.olive)
            .background(style == .filled ? Brand.ink : Brand.background,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style == .filled ? .clear : Brand.olive.opacity(0.55), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// Google's four-color "G", drawn (no bundled artwork needed).
struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let line = s * 0.2
            let rect = CGRect(x: line / 2, y: line / 2, width: s - line, height: s - line)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            func arc(_ from: Double, _ to: Double, _ color: Color) {
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                context.stroke(path, with: .color(color), lineWidth: line)
            }
            arc(-40, 45, Color(red: 0.26, green: 0.52, blue: 0.96))   // blue, right
            arc(45, 135, Color(red: 0.20, green: 0.66, blue: 0.33))   // green, bottom
            arc(135, 200, Color(red: 0.98, green: 0.74, blue: 0.02))  // yellow, left
            arc(200, 320, Color(red: 0.92, green: 0.26, blue: 0.21))  // red, top
            var bar = Path()
            bar.move(to: CGPoint(x: center.x, y: center.y))
            bar.addLine(to: CGPoint(x: center.x + radius + line / 2, y: center.y))
            context.stroke(bar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)), lineWidth: line)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
