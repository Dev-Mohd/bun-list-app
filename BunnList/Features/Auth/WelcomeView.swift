import SwiftUI

/// The landing screen shown on first launch (and after sign-out): the mark draws
/// itself, then three swipeable cards show what the app does, with sign in with
/// Apple, Google or email (or look around as a guest) always below them.
/// While a sign-in is under way the whole screen becomes the drawing mark.
struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthModel
    @Binding var continuedAsGuest: Bool
    @State private var showEmail = false
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                brandPage.tag(0)
                ForEach(Array(IntroCard.all.enumerated()), id: \.offset) { index, card in
                    IntroCardView(card: card).tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)

            PageDots(count: IntroCard.all.count + 1, current: page)
                .padding(.vertical, 10)

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

    private var brandPage: some View {
        VStack(spacing: 18) {
            Spacer()
            BrandMark(height: 130)
            BrandWordmark(size: 32)
            VStack(spacing: 4) {
                Text("اكتشف، قيّم، واختر أفضل محاصيل القهوة")
                    .font(.title3.weight(.semibold)).foregroundStyle(Brand.olive)
                    .multilineTextAlignment(.center)
                Text("Rate Coffee. Brew Smarter.")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer()
            Label("اسحب وتعرّف على التطبيق", systemImage: "hand.draw")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }
}

/// One card of the welcome tour: a real screen from the app, a title and a line.
struct IntroCard {
    let image: String
    let title: String
    let detail: String

    static let all = [
        IntroCard(image: "IntroDiscover", title: "اكتشف بذوقك",
                  detail: "أكثر من ٧٠٠ قهوة مختصة من محامص سعودية، و«ساعدني أختار» يرشّح لك على ذوقك."),
        IntroCard(image: "IntroBrew", title: "حضّرها صح",
                  detail: "وصفات دقيقة لكل طريقة، ومؤقت يمشي معك صبّة صبّة."),
        IntroCard(image: "IntroCollection", title: "مجموعتك ورحلتك",
                  detail: "سجّل قهاويك، وجمّع جوازك، وتابع الذوّاقة في المجتمع."),
    ]
}

private struct IntroCardView: View {
    let card: IntroCard

    var body: some View {
        VStack(spacing: 18) {
            Image(card.image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Brand.ink.opacity(0.08)))
                // The shot is the top of a screen; fade its cut edge into the page.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: Brand.ink.opacity(0.15), radius: 18, y: 10)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(card.title).font(.title2.bold()).foregroundStyle(Brand.ink)
                Text(card.detail).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? Brand.olive : Brand.olive.opacity(0.25))
                    .frame(width: i == current ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3), value: current)
        .accessibilityLabel("البطاقة \((current + 1).formatted()) من \(count.formatted())")
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
