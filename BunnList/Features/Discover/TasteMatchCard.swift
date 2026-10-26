import BunnListCore
import SwiftUI

/// "تناسبك ٨٧٪": a ring with the score, a verdict and the reasons; before enough
/// ratings, how many more it needs. Loads itself for a lot when signed in.
@MainActor
struct TasteMatchCard: View {
    let slug: String
    var compact = false

    @EnvironmentObject private var auth: AuthModel
    @State private var match: RemoteTasteMatch?
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        Group {
            if let match {
                if let score = match.score { scored(score, match) } else { learning(match) }
            }
        }
        .task(id: slug) {
            guard auth.isSignedIn else { return }
            match = try? await auth.withToken { try await client.fetchTasteMatch(slug: slug, accessToken: $0) }
        }
    }

    private func color(_ score: Int) -> Color {
        score >= 70 ? Brand.olive : score >= 50 ? Brand.gold : Brand.brown
    }

    private func scored(_ score: Int, _ m: RemoteTasteMatch) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().stroke(color(score).opacity(0.18), lineWidth: compact ? 6 : 9)
                Circle().trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color(score), style: StrokeStyle(lineWidth: compact ? 6 : 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)٪").font((compact ? Font.headline : .title2).bold().monospacedDigit()).foregroundStyle(Brand.ink)
            }
            .frame(width: compact ? 58 : 82, height: compact ? 58 : 82)
            .environment(\.layoutDirection, .leftToRight)

            VStack(alignment: .leading, spacing: 5) {
                Text(m.verdictAr ?? "").font(compact ? .subheadline.bold() : .headline).foregroundStyle(color(score))
                ForEach(m.reasons.prefix(compact ? 1 : 3), id: \.self) { reason in
                    Label(reason.text, systemImage: reason.positive ? "plus.circle.fill" : "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(reason.positive ? Brand.olive : Brand.brown)
                }
                if let mine = m.myRating, !compact {
                    Text("وقيّمتها أنت \(mine) من ٥").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 12 : 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("تناسبك بنسبة \(score) بالمية. \(m.verdictAr ?? "")")
    }

    private func learning(_ m: RemoteTasteMatch) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(Brand.gold)
            VStack(alignment: .leading, spacing: 4) {
                Text("قيّم \(m.needed.formatted()) \(m.needed == 1 ? "قهوة" : "قهوات") زيادة ونقول لك تناسبك أو لا")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    ForEach(0..<(m.ratedCount + m.needed), id: \.self) { i in
                        Capsule().fill(i < m.ratedCount ? Brand.gold : Brand.gold.opacity(0.2)).frame(width: 18, height: 5)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 12 : 16)
        .background(Brand.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
    }
}
