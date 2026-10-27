import BunnListCore
import SwiftUI

/// BunnList's coffee card. Everything to decide at a glance, in our own language:
/// the bag lifted off a wash of its main flavor, a passport stamp for its origin
/// (the same stamps as جواز القهوة), the flavor strip — one band per flavor family,
/// in the fingerprint's colors — and, once you've rated a few, how well it fits
/// you. Press to lift the bag; long-press for quick actions.
struct BunnCoffeeCard: View {
    let lot: RemoteLot
    /// Place in a ranked row ("#1"), shown on the photo.
    var rank: Int?

    @EnvironmentObject private var auth: AuthModel
    @ObservedObject private var match = MatchScores.shared

    private var family: FlavorFamily { FlavorFamily.dominant(lot.flavorNotes) }
    private var tint: Color { family == .other ? Brand.gold : family.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
            FlavorStrip(families: FlavorFamily.spectrum(lot.flavorNotes))
                .padding(.horizontal, 10)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(lot.nameAr).font(.headline).foregroundStyle(Brand.ink).lineLimit(1)
                Text(lot.roasterNameAr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(detailLine).lineLimit(1)
                    Spacer(minLength: 4)
                    rating
                }
                .font(.caption2)
                .foregroundStyle(Brand.olive)
                .padding(.top, 2)
                if let by = lot.discoveredBy {
                    Divider().padding(.vertical, 4)
                    HStack(spacing: 6) {
                        Text(String(by.trimmingCharacters(in: CharacterSet(charactersIn: "@")).prefix(1)).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Brand.background)
                            .frame(width: 18, height: 18)
                            .background(Brand.gold, in: Circle())
                        Text("اكتشفها \(by)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                )
        }
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(tint.opacity(0.28), lineWidth: 1))
        .shadow(color: tint.opacity(0.12), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .lotQuickActions(slug: lot.slug, name: lot.nameAr, roaster: lot.roasterNameAr, imageUrl: lot.imageUrl,
                         notes: lot.flavorNotes, origin: lot.originNameAr, originCode: lot.originCode)
        .onAppear { match.want(lot.slug, auth: auth) }
    }

    private var photo: some View {
        LotPhotoWell(imageUrl: lot.imageUrl, notes: lot.flavorNotes, roaster: lot.roasterNameAr, name: lot.nameAr,
                     origin: lot.originNameAr, originCode: lot.originCode, padding: 6)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    if let rank { RankTag(rank: rank) }
                    if let code = lot.originCode, let flag = ReferenceCodes.flag(code) {
                        OriginStamp(flag: flag, color: tint)
                    }
                }
                .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if let score = match.scores[lot.slug] { MatchBadge(score: score).padding(6) }
            }
            .padding(5)
    }

    private var detailLine: String {
        [lot.processNameAr, lot.originNameAr].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var rating: some View {
        if lot.reviewCount > 0 {
            HStack(spacing: 2) {
                Image(systemName: "star.fill").foregroundStyle(Brand.gold)
                Text(lot.averageRating.formatted(.number.precision(.fractionLength(1)))).bold()
                Text("(\(lot.reviewCount.formatted()))").foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .environment(\.layoutDirection, .leftToRight)
        } else {
            Text("جديدة").foregroundStyle(.secondary)
        }
    }

    private var accessibilityText: String {
        var parts = [lot.nameAr, lot.roasterNameAr, detailLine]
        if !lot.flavorNotes.isEmpty { parts.append("نكهات: " + lot.flavorNotes.prefix(3).joined(separator: "، ")) }
        if lot.reviewCount > 0 { parts.append("تقييم \(lot.averageRating.formatted(.number.precision(.fractionLength(1))))") }
        if let score = match.scores[lot.slug] { parts.append("يناسبك \(score) بالمية") }
        return parts.filter { !$0.isEmpty }.joined(separator: "، ")
    }
}

/// One band per flavor family, in the fingerprint's colors; a quiet line when unknown.
struct FlavorStrip: View {
    let families: [FlavorFamily]

    var body: some View {
        HStack(spacing: 3) {
            if families.isEmpty {
                Capsule().fill(Color.secondary.opacity(0.15))
            } else {
                ForEach(families, id: \.self) { Capsule().fill($0.color) }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// The origin as a small passport stamp: dashed ring, flag, slightly askew.
struct OriginStamp: View {
    let flag: String
    let color: Color

    var body: some View {
        Text(flag)
            .font(.system(size: 15))
            .frame(width: 30, height: 30)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2])))
            .rotationEffect(.degrees(-12))
            .accessibilityHidden(true)
    }
}

/// "٨٧٪" with a ring that fills to the score, colored by how well it fits.
struct MatchBadge: View {
    let score: Int

    private var color: Color { score >= 70 ? Brand.olive : score >= 50 ? Brand.gold : Brand.brown }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
                Circle().trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 13, height: 13)
            Text("\(score)٪").font(.caption2.bold().monospacedDigit()).foregroundStyle(Brand.ink)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 0.6))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// "#1" for ranked rows.
struct RankTag: View {
    let rank: Int

    var body: some View {
        Text("#\(rank)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Brand.gold, in: Capsule())
            .environment(\.layoutDirection, .leftToRight)
    }
}
