import BunnListCore
import SwiftUI

/// "جواز قهوتك": a ختم for every origin tasted, stamped like a passport page, and
/// badges with progress. Coffees count once owned, tried, rated or brewed.
@MainActor
struct PassportView: View {
    @EnvironmentObject private var auth: AuthModel
    @State private var passport: RemotePassport?
    @State private var failed = false
    private let client = CatalogAPIClient(transport: URLSessionTransport())

    var body: some View {
        ScrollView {
            if let passport {
                VStack(alignment: .leading, spacing: 22) {
                    cover(passport)
                    stamps(passport)
                    badges(passport)
                }
                .padding()
            } else if failed {
                ContentUnavailableView("ما قدرنا نفتح الجواز", systemImage: "wifi.slash", description: Text("اسحب للتحديث"))
                    .padding(.top, 80)
            } else {
                ProgressView().tint(Brand.olive).padding(.top, 120)
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .brandScreen()
        .navigationTitle("جواز قهوتك")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            passport = try await auth.withToken { try await client.fetchPassport(accessToken: $0) }
            failed = false
        } catch {
            failed = passport == nil
        }
    }

    // MARK: Cover

    private func cover(_ p: RemotePassport) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("جواز القهوة").font(.title3.bold())
                    Text("COFFEE PASSPORT").font(.caption2.weight(.semibold)).tracking(3).opacity(0.7)
                }
                Spacer()
                Image(systemName: "globe.europe.africa.fill").font(.system(size: 34)).foregroundStyle(Brand.gold)
            }
            HStack(spacing: 0) {
                coverStat(p.countries, "بلد")
                coverStat(p.regions, "منطقة من ٤")
                coverStat(p.processes, "معالجة")
                coverStat(p.earnedCount, "وسام")
            }
        }
        .padding(18)
        .foregroundStyle(Brand.background)
        .background(Brand.olive, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.6), lineWidth: 1).padding(5))
    }

    private func coverStat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted()).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption2).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stamps

    @ViewBuilder
    private func stamps(_ p: RemotePassport) -> some View {
        Text("الأختام").font(.headline)
        if p.stamps.isEmpty {
            Label("جرّب أي قهوة أو قيّمها أو أضفها لمجموعتك وتنختم أول صفحة", systemImage: "seal")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                ForEach(Array(p.stamps.enumerated()), id: \.element.id) { index, stamp in
                    PassportStamp(stamp: stamp, tilt: [-8, 5, -3, 9, -6, 3][index % 6])
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: Badges

    @ViewBuilder
    private func badges(_ p: RemotePassport) -> some View {
        Text("الأوسمة").font(.headline)
        VStack(spacing: 10) {
            ForEach(p.badges.sorted { $0.earned && !$1.earned }) { BadgeRow(badge: $0) }
        }
    }
}

private struct PassportStamp: View {
    let stamp: RemotePassport.Stamp
    let tilt: Double

    private var color: Color {
        switch stamp.region {
        case "africa": return Brand.brown
        case "americas": return Brand.olive
        case "arabia": return Brand.gold
        default: return Brand.ink
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(flag(stamp.code)).font(.title2)
            Text(stamp.nameAr).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
            if let date = stamp.firstDate {
                Text(date.formatted(.dateTime.month(.abbreviated).year())).font(.system(size: 9).monospacedDigit())
            }
            if stamp.count > 1 {
                Text("×\(stamp.count)").font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(color)
        .frame(width: 92, height: 92)
        .overlay(Circle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
        .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 1).padding(5))
        .rotationEffect(.degrees(tilt))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ختم \(stamp.nameAr)، \(stamp.count) قهوة")
    }

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
    }
}

private struct BadgeRow: View {
    let badge: RemotePassport.Badge

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: badge.icon)
                .font(.title3)
                .foregroundStyle(badge.earned ? Brand.background : Brand.olive.opacity(0.5))
                .frame(width: 46, height: 46)
                .background(badge.earned ? AnyShapeStyle(Brand.gold) : AnyShapeStyle(Brand.olive.opacity(0.1)), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(badge.titleAr).font(.subheadline.bold())
                    Spacer()
                    if badge.earned {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.olive)
                    } else {
                        Text("\(badge.current)/\(badge.goal)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                Text(badge.detailAr).font(.caption).foregroundStyle(.secondary)
                if !badge.earned {
                    ProgressView(value: badge.progress).tint(Brand.olive)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .opacity(badge.earned ? 1 : 0.9)
        .accessibilityElement(children: .combine)
    }
}
