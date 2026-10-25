import SwiftUI

/// The BunnList logo drawn in piece by piece (the real logo split into its five
/// shapes): each shape wipes in from its leading edge, then the gold dot pops in.
/// With `looping` it draws again every couple of seconds, for waiting screens.
struct BrandMark: View {
    var height: CGFloat = 96
    var animated = true
    var looping = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: [CGFloat] = Array(repeating: 0, count: 5)

    private static let aspect: CGFloat = 420.0 / 535.0

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                piece(index)
            }
        }
        .frame(width: height * Self.aspect, height: height)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
        .task {
            guard animated && !reduceMotion else { progress = Array(repeating: 1, count: 5); return }
            repeat {
                await draw()
                guard looping else { return }
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.easeIn(duration: 0.25)) { progress = Array(repeating: 0, count: 5) }
                try? await Task.sleep(for: .milliseconds(300))
            } while !Task.isCancelled
        }
    }

    @ViewBuilder
    private func piece(_ index: Int) -> some View {
        let image = Image("LogoPart\(index + 1)")
        Group {
            // The two dark shapes follow the ink color so they show in dark mode.
            if index == 0 || index == 2 {
                image.renderingMode(.template).resizable().scaledToFit().foregroundStyle(Brand.ink)
            } else {
                image.resizable().scaledToFit()
            }
        }
        .mask(alignment: .leading) {
            if index == 4 {
                Rectangle()
            } else {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * progress[index])
                }
            }
        }
        .scaleEffect(index == 4 ? max(progress[index], 0.01) : 1, anchor: UnitPoint(x: 0.88, y: 0.48))
        .opacity(index == 4 ? Double(progress[index]) : 1)
    }

    private func draw() async {
        for index in 0..<4 {
            withAnimation(.easeOut(duration: 0.22)) { progress[index] = 1 }
            try? await Task.sleep(for: .milliseconds(150))
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { progress[4] = 1 }
        try? await Task.sleep(for: .milliseconds(350))
    }
}

/// The name under the mark: Arabic, then "BunnList".
struct BrandWordmark: View {
    var size: CGFloat = 34

    var body: some View {
        VStack(spacing: 2) {
            Text("بن لست").font(.system(size: size, weight: .black)).foregroundStyle(Brand.ink)
            Text("BunnList")
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .tracking(size * 0.08)
                .foregroundStyle(Brand.ink.opacity(0.6))
                .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("بن لست")
    }
}

/// Full-screen wait: the mark drawing itself on the cream ground.
struct BrandLoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: 18) {
            BrandMark(height: 110, looping: true)
            BrandWordmark(size: 28)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background.ignoresSafeArea())
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message ?? "جارٍ التحميل")
    }
}
