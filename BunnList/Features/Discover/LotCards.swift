import BunnListCore
import Charts
import SwiftUI

/// "بصمة الطعم": the coffee's top flavor notes over a blend of their colors, with
/// origin and process below. Drawn from the coffee's own data.
struct TasteFingerprintCard: View {
    let notes: [String]
    let origin: String?
    let process: String?

    private var top: [String] { Array(notes.prefix(3)) }

    private func color(_ note: String) -> Color {
        let c = FlavorFamily.of(note).rgb
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    private var background: some View {
        let colors = top.isEmpty ? [Brand.olive, Brand.brown] : top.map(color)
        return ZStack {
            LinearGradient(colors: colors.count > 1 ? colors : colors + [Brand.brown], startPoint: .topTrailing, endPoint: .bottomLeading)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("بصمة الطعم").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            if top.isEmpty {
                Text("ما انضافت نكهات بعد").font(.title3.bold()).foregroundStyle(.white)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(top.enumerated()), id: \.offset) { index, note in
                        HStack(spacing: 10) {
                            Circle().fill(color(note)).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            Text(note)
                                .font(index == 0 ? .largeTitle.bold() : .title.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }
            if origin != nil || process != nil {
                HStack(spacing: 0) {
                    if let origin { fact("المنشأ", origin) }
                    if origin != nil && process != nil {
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 34)
                    }
                    if let process { fact("المعالجة", process) }
                }
                .padding(.vertical, 10)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
            Text(value).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }
}

/// The lot's rating in large type with the call to rate it.
struct RatingCard: View {
    let average: Double
    let count: Int
    let myRating: Int?
    let isSignedIn: Bool
    var onRate: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if count > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "laurel.leading").font(.largeTitle).foregroundStyle(Brand.gold)
                    Text(average.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 56, weight: .heavy, design: .rounded)).foregroundStyle(Brand.ink)
                    Image(systemName: "laurel.trailing").font(.largeTitle).foregroundStyle(Brand.gold)
                }
                .environment(\.layoutDirection, .leftToRight)
                Text("\(count.formatted()) تقييم").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Image(systemName: "star.bubble").font(.largeTitle).foregroundStyle(Brand.gold)
                Text("ما أحد قيّمها بعد. كن الأول!").font(.subheadline).foregroundStyle(.secondary)
            }
            if let myRating {
                Label("تقييمك: \(myRating) من ٥", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(Brand.olive)
            }
            if isSignedIn {
                Button(action: onRate) {
                    Label(myRating == nil ? "جرّبتها؟ قيّمها الآن" : "عدّل تقييمك", systemImage: "cup.and.saucer.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.ink)
                .foregroundStyle(Brand.background)
                .clipShape(Capsule())
                .accessibilityIdentifier("review-cta")
            } else {
                Text("سجّل الدخول من «ملفي» عشان تقيّمها.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

/// Who discovered the coffee, linking to their profile, with their public note.
struct DiscovererCard: View {
    let discoverer: RemoteDiscoverer
    var onReport: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("اكتشفها", systemImage: "star.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Brand.gold)
            if let username = discoverer.username {
                NavigationLink { PublicProfileView(username: username) } label: { person }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lot-discoverer")
            } else {
                person.accessibilityIdentifier("lot-discoverer")
            }
            if let note = discoverer.note, !note.isEmpty {
                Text("“\(note)”")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .contextMenu {
                        if let onReport {
                            Button(role: .destructive, action: onReport) { Label("بلّغ عن الملاحظة", systemImage: "flag") }
                        }
                    }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var person: some View {
        HStack(spacing: 12) {
            AvatarView(url: discoverer.avatarUrl, name: discoverer.name, size: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(discoverer.name).font(.headline)
                if let username = discoverer.username {
                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            Spacer()
            if discoverer.username != nil {
                Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// "المجتمع": how many collected and brewed the coffee, and which methods they use.
struct LotCommunityCard: View {
    let community: RemoteLotCommunity

    private static let palette: [Color] = [Brand.gold, Brand.olive, Brand.brown, .orange, .teal, .pink, .gray]

    private var slices: [(name: String, count: Int, percent: Int, color: Color)] {
        let percents = LotCommunityStats.percentages(community.methods.map(\.count))
        return community.methods.enumerated().map { index, m in
            (Self.methodName(m.method), m.count, percents[index], Self.palette[index % Self.palette.count])
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                stat(community.collectors, "المجمّعين")
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 40)
                stat(community.brewers, "حضّروها")
            }
            if !slices.isEmpty {
                Divider()
                Text("كيف يحضّرونها").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Chart(Array(slices.enumerated()), id: \.offset) { _, slice in
                        SectorMark(angle: .value("العدد", slice.count), innerRadius: .ratio(0.72), angularInset: 2)
                            .foregroundStyle(slice.color)
                            .cornerRadius(4)
                    }
                    .frame(height: 200)
                    if let first = slices.first {
                        VStack(spacing: 2) {
                            Text("\(first.percent)%").font(.title.bold().monospacedDigit())
                            Text(first.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(spacing: 8) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                        HStack {
                            Circle().fill(slice.color).frame(width: 10, height: 10)
                            Text(slice.name).font(.subheadline)
                            Spacer()
                            Text(slice.count.formatted()).font(.subheadline.monospacedDigit())
                            Text("\(slice.percent)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted()).font(.title2.bold().monospacedDigit()).foregroundStyle(Brand.ink)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    static func methodName(_ code: String) -> String {
        ReferenceCodes.brewMethod(code)?.nameAr ?? (code == "V60" ? "V60" : LiveLotDetailView.brewLabel(code))
    }
}
