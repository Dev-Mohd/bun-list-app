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

// MARK: - Coffee page: floating bag, fact tiles, taste lean, buy button, roaster recipe

/// The bag floats gently on its flavour wash while its notes drift around it.
struct FloatingBagHero: View {
    let lot: RemoteLotDetail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var bob = false

    /// Bubble spots as fractions of the hero, away from the bag in the middle.
    private static let spots: [CGPoint] = [CGPoint(x: 0.80, y: 0.15), CGPoint(x: 0.19, y: 0.30),
                                           CGPoint(x: 0.83, y: 0.68), CGPoint(x: 0.21, y: 0.82)]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LotPhotoWell(imageUrl: lot.imageUrl, notes: lot.flavorNotes, roaster: lot.roasterNameAr, name: lot.nameAr,
                             origin: lot.originNameAr, originCode: lot.originCode, padding: 36)
                    .offset(y: bob ? -7 : 2)
                    .rotationEffect(.degrees(bob ? -1.2 : 0.4))
                    .scaleEffect(shown ? 1 : 0.88)
                    .opacity(shown ? 1 : 0)
                ForEach(Array(lot.flavorNotes.prefix(4).enumerated()), id: \.offset) { index, note in
                    NoteBubble(note: note)
                        .offset(y: bob ? (index.isMultiple(of: 2) ? -6 : 5) : 0)
                        .position(x: geo.size.width * Self.spots[index].x, y: geo.size.height * Self.spots[index].y)
                        .scaleEffect(shown ? 1 : 0.2)
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.25 + Double(index) * 0.12), value: shown)
                }
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { shown = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true).delay(0.8)) { bob = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([lot.nameAr] + lot.flavorNotes.prefix(4)).joined(separator: "، "))
    }
}

private struct NoteBubble: View {
    let note: String

    var body: some View {
        let family = FlavorFamily.of(note)
        let tint = family == .other ? Brand.brown : family.color
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(note).lineLimit(1)
        }
        .font(.footnote.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(.white.opacity(0.94), in: Capsule())
        .shadow(color: Brand.brown.opacity(0.16), radius: 8, y: 4)
        .fixedSize()
    }
}

/// Only the facts the coffee has, as tiles that rise in one after another; a
/// missing fact leaves no empty box (see CoffeeFactTiles). Then the taste lean
/// and how people brew it, which come from notes and logs, not from the roaster.
struct CoffeeFactsGrid: View {
    let lot: RemoteLotDetail
    @State private var appeared = false

    private var tileRows: [[CoffeeFactTiles.Tile]] {
        var out: [[CoffeeFactTiles.Tile]] = []
        var pending: [CoffeeFactTiles.Tile] = []
        for tile in lot.factTiles {
            if tile.wide { out.append([tile]) } else {
                pending.append(tile)
                if pending.count == 2 { out.append(pending); pending = [] }
            }
        }
        if !pending.isEmpty { out.append(pending) }
        return out
    }

    var body: some View {
        let rows = tileRows
        let lean = TasteLean.position(lot.flavorNotes)
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.kind) { tile in self.tile(tile.kind) }
                }
                .rise(appeared, order: index)
            }
            if let lean {
                FactTile { TasteLeanTile(position: lean, play: appeared) }.rise(appeared, order: rows.count)
            }
            if let top = lot.topCommunityMethod {
                FactTile {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill").font(.title3).foregroundStyle(Brand.olive)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("أكثر طريقة يحضّرونها فيها الناس").font(.subheadline.weight(.bold))
                            Text("\(LiveLotDetailView.brewLabel(top.method)) · \(top.count) تجربة")
                                .font(.footnote).foregroundStyle(Brand.brown)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .rise(appeared, order: rows.count + 1)
            }
        }
        .onAppear { appeared = true }
    }

    @ViewBuilder private func tile(_ kind: CoffeeFactTiles.Kind) -> some View {
        switch kind {
        case .origin:
            FactTile(minHeight: 104) {
                if lot.originCode?.uppercased() == "XB" || (lot.originNameAr ?? "").contains("مزيج") {
                    BlendTile(region: lot.regionAr, play: appeared)
                } else {
                    OriginTile(country: lot.originNameAr ?? "", code: lot.originCode, region: lot.regionAr, play: appeared)
                }
            }
        case .altitude:
            FactTile(minHeight: 104) { AltitudeTile(meters: lot.altitudeMeters ?? 0, play: appeared) }
        case .process:
            FactTile(minHeight: 104) { ProcessTile(code: lot.process, name: lot.processNameAr ?? "") }
        case .variety:
            FactTile(minHeight: 104) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("السلالة").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(lot.variety ?? "").font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "leaf.fill").font(.title2).foregroundStyle(Brand.olive.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct FactTile<Content: View>: View {
    var minHeight: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.brown.opacity(0.12)))
    }
}

private extension View {
    /// Rises into place, each row a beat after the one above.
    func rise(_ shown: Bool, order: Int) -> some View {
        offset(y: shown ? 0 : 22)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.15 + Double(order) * 0.1), value: shown)
    }
}

/// The flag and country, with a dotted line that draws from the farm to a cup.
private struct OriginTile: View {
    let country: String
    let code: String?
    let region: String?
    let play: Bool
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                if let flag = ReferenceCodes.flag(code) { Text(flag).font(.system(size: 34)) }
                Text(country).font(.title3.bold())
                Text(region?.isEmpty == false ? region! : "من \(country) لفنجانك")
                    .font(.footnote).foregroundStyle(Brand.brown)
            }
            Spacer(minLength: 8)
            ZStack {
                RouteArc()
                    .trim(from: 0, to: play ? 1 : 0)
                    .stroke(Brand.gold.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))
                    .animation(.easeOut(duration: 1.4).delay(0.6), value: play)
                GeometryReader { geo in
                    Circle().fill(Brand.gold).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Brand.gold, lineWidth: 2).scaleEffect(pulse ? 2.4 : 1).opacity(pulse ? 0 : 0.8))
                        .position(x: geo.size.width * 0.06, y: geo.size.height * 0.86)
                    Image(systemName: "cup.and.saucer.fill").font(.footnote).foregroundStyle(Brand.brown)
                        .position(x: geo.size.width * 0.94, y: geo.size.height * 0.78)
                        .opacity(play ? 1 : 0)
                        .animation(.easeIn(duration: 0.3).delay(1.8), value: play)
                }
            }
            .frame(width: 140, height: 64)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(0.8)) { pulse = true }
        }
    }
}

/// A blend has no single farm: three origins drift together into one cup.
private struct BlendTile: View {
    let region: String?
    let play: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var merged = false

    private static let colors: [Color] = [Brand.gold, Brand.olive, Brand.brown]

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("مزيج").font(.title3.bold())
                Text(region?.isEmpty == false ? region! : "خلطة من أكثر من منشأ في فنجان واحد")
                    .font(.footnote).foregroundStyle(Brand.brown)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let angle = Double(i) * 2 * .pi / 3 - .pi / 2
                    Circle().fill(Self.colors[i].opacity(0.75))
                        .frame(width: 30, height: 30)
                        .offset(x: merged ? cos(angle) * 9 : cos(angle) * 30, y: merged ? sin(angle) * 9 : sin(angle) * 30)
                        .blendMode(.multiply)
                }
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .opacity(merged ? 1 : 0)
                    .scaleEffect(merged ? 1 : 0.4)
            }
            .frame(width: 96, height: 76)
            .accessibilityHidden(true)
        }
        .onChange(of: play) { if play { animate() } }
        .onAppear { if play { animate() } }
        .accessibilityElement(children: .combine)
    }

    private func animate() {
        guard !merged else { return }
        if reduceMotion { merged = true; return }
        withAnimation(.spring(response: 1.1, dampingFraction: 0.7).delay(0.5)) { merged = true }
    }
}

private struct RouteArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.86))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.70),
                          control: CGPoint(x: rect.width * 0.5, y: -rect.height * 0.35))
        return path
    }
}

/// The height counts up while a mountain draws itself.
private struct AltitudeTile: View {
    let meters: Int
    let play: Bool
    @State private var shown = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("الارتفاع").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(shown.formatted(.number.locale(Locale(identifier: "en")))) م")
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText(value: Double(shown)))
            Spacer(minLength: 4)
            ZStack(alignment: .bottomLeading) {
                Mountain().fill(Brand.olive.opacity(0.14)).opacity(play ? 1 : 0)
                    .animation(.easeIn(duration: 0.6).delay(1.6), value: play)
                Mountain().trim(from: 0, to: play ? 1 : 0)
                    .stroke(Brand.olive, style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                    .animation(.easeOut(duration: 1.3).delay(0.5), value: play)
            }
            .frame(width: 84, height: 44)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeOut(duration: 1.3).delay(0.5)) { shown = meters }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الارتفاع \(meters) متر")
    }
}

private struct Mountain: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [CGPoint(x: 0, y: 1), CGPoint(x: 0.32, y: 0.3), CGPoint(x: 0.46, y: 0.5),
                                 CGPoint(x: 0.66, y: 0.05), CGPoint(x: 1, y: 1)]
        path.move(to: CGPoint(x: points[0].x * rect.width, y: points[0].y * rect.height))
        for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x * rect.width, y: p.y * rect.height)) }
        return path
    }
}

/// The process with a small moving sign: a turning sun for dried, drops for washed, and so on.
private struct ProcessTile: View {
    let code: String
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    private var symbol: (name: String, color: Color, spins: Bool) {
        switch code {
        case "NATURAL": return ("sun.max.fill", Brand.gold, true)
        case "WASHED": return ("drop.fill", .blue.opacity(0.7), false)
        case "HONEY": return ("drop.halffull", Brand.gold, false)
        case "ANAEROBIC": return ("aqi.medium", Brand.brown, false)
        case "EXPERIMENTAL": return ("sparkles", Brand.olive, false)
        case "MIXED": return ("circle.hexagongrid.fill", Brand.brown, false)
        default: return ("leaf.fill", Brand.olive, false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("المعالجة").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(name).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Image(systemName: symbol.name)
                .font(.system(size: 30))
                .foregroundStyle(symbol.color)
                .rotationEffect(.degrees(symbol.spins && spin ? 360 : 0))
                .symbolEffect(.pulse, options: .repeating, isActive: !symbol.spins && !reduceMotion)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard symbol.spins, !reduceMotion else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// A bar from chocolate and nuts to fruit, with a bean that slides to where the notes lean.
private struct TasteLeanTile: View {
    let position: Double
    let play: Bool

    private static let stops: [Color] = [FlavorFamily.chocolate.color, FlavorFamily.caramel.color, FlavorFamily.berry.color]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("نكهتها تميل لـ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: Self.stops, startPoint: .leading, endPoint: .trailing))
                            .frame(height: 10)
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.ink)
                            .frame(width: 26, height: 26)
                            .background(Color(.systemBackground), in: Circle())
                            .overlay(Circle().stroke(Brand.ink, lineWidth: 2))
                            .offset(x: (geo.size.width - 26) * (play ? position : 0.5))
                            .animation(.spring(response: 0.9, dampingFraction: 0.55).delay(0.9), value: play)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 26)
                HStack {
                    Text("شوكولاتة ومكسرات")
                    Spacer()
                    Text("حلاوة وكراميل")
                    Spacer()
                    Text("فواكه وزهور")
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position > 0.66 ? "نكهتها تميل للفواكه" : position < 0.33 ? "نكهتها تميل للشوكولاتة والمكسرات" : "نكهتها تميل للحلاوة والكراميل")
    }
}

/// "اشترِ من المحمصة": opens the product page; a light sweeps across it now and then.
struct BuyButton: View {
    let link: RemoteBuyLink
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false
    @State private var nudge = false

    var body: some View {
        Button {
            guard let url = URL(string: link.url) else { return }
            Haptics.tap()
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: link.isRoasterStore ? "bag.fill" : "storefront.fill")
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title).font(.headline)
                    Text(link.subtitle).font(.caption).opacity(0.75).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.backward").font(.headline)
                    .offset(x: nudge ? -5 : 0)
            }
            .foregroundStyle(Brand.background)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Brand.ink, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 70)
                        .rotationEffect(.degrees(20))
                        .offset(x: sweep ? geo.size.width + 70 : -140)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("يفتح صفحة المنتج")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).delay(1.6).repeatForever(autoreverses: false)) { sweep = true }
            withAnimation(.easeInOut(duration: 0.8).delay(2).repeatForever(autoreverses: true)) { nudge = true }
        }
    }
}

/// The roaster's own recipe: the numbers, a timer ring that runs while you brew,
/// and the pours to tick off as you go.
struct RoasterRecipeCard: View {
    let recipes: [RemoteRoasterRecipe]
    let roasterNameAr: String
    let fromStore: Bool
    @State private var picked = 0
    @State private var elapsed = 0
    @State private var running = false
    @State private var done: Set<Int> = []
    @State private var ticker: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    private var recipe: RemoteRoasterRecipe { recipes[min(picked, recipes.count - 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("وصفة المحمصة").font(.headline)
                Text("من \(roasterNameAr)").font(.caption.weight(.bold)).foregroundStyle(Brand.gold)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Brand.gold.opacity(0.15), in: Capsule())
                Spacer(minLength: 0)
                if recipes.count == 1 {
                    Text(recipe.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            if recipes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(recipes.enumerated()), id: \.offset) { index, r in
                            Button {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.35)) { picked = index }
                            } label: {
                                Label(r.tool ?? r.methodNameAr, systemImage: r.isIced ? "snowflake" : "flame.fill")
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(picked == index ? Brand.olive : Brand.brown.opacity(0.08), in: Capsule())
                                    .foregroundStyle(picked == index ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(r.label)
                        }
                    }
                }
                .onChange(of: picked) { reset() }
            }
            if recipe.isMachineLink {
                machineRecipe
            } else {
                handRecipe
            }
            Text(fromStore ? "المصدر: صفحة المنتج في المتجر" : "المصدر: صفحة المنتج في موقع المحمصة")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Brand.brown.opacity(0.12)))
        .onDisappear { ticker?.cancel(); running = false }
    }

    /// An xBloom recipe: the machine runs it, so only a way to open it there.
    private var machineRecipe: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: recipe.isIced ? "snowflake" : "flame.fill")
                    .font(.title2)
                    .foregroundStyle(recipe.isIced ? Color.cyan : Brand.gold)
                    .symbolEffect(.pulse, options: .repeating)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.isIced ? "وصفة باردة لجهاز xBloom" : "وصفة حارة لجهاز xBloom").font(.subheadline.weight(.bold))
                    Text("المحمصة جهّزتها، والجهاز يحضّرها لك بالضبط").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let link = recipe.link, let url = URL(string: link) {
                Button {
                    Haptics.tap()
                    openURL(url)
                } label: {
                    Label("افتح الوصفة في xBloom", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Brand.olive, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var handRecipe: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if let total = recipe.timeSec { ring(total: total) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    if let dose = recipe.doseG { stat(RemoteRoasterRecipe.grams(dose), "جرام قهوة") }
                    if let water = recipe.waterMl { stat("\(water)", recipe.method == "ESPRESSO" ? "مل في الفنجان" : "مل ماء") }
                    if let temp = recipe.tempC { stat("\(temp)°", "الحرارة") }
                    if let grind = recipe.grind { stat(grind, "الطحنة") }
                    else if let ratio = recipe.ratio, recipe.method != "ESPRESSO" {
                        stat("1:\(RemoteRoasterRecipe.grams(ratio))", "النسبة")
                    }
                }
            }
            if !recipe.steps.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.3)) {
                                if done.contains(index) { done.remove(index) } else { done.insert(index) }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().stroke(done.contains(index) ? Brand.olive : Brand.brown.opacity(0.3), lineWidth: 2)
                                    if done.contains(index) {
                                        Circle().fill(Brand.olive)
                                        Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
                                    } else {
                                        Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 24, height: 24)
                                Text(step).font(.subheadline)
                                    .foregroundStyle(done.contains(index) ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(done.contains(index) ? Brand.olive.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if recipe.timeSec != nil {
                Button(action: toggle) {
                    Label(running ? "إيقاف المؤقت" : elapsed > 0 ? "كمّل المؤقت" : "حضّرها معي بالمؤقت",
                          systemImage: running ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Brand.olive, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ring(total: Int) -> some View {
        ZStack {
            Circle().stroke(Brand.brown.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, Double(elapsed) / Double(max(total, 1))))
                .stroke(Brand.olive, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: elapsed)
            VStack(spacing: 0) {
                Text(RemoteRoasterRecipe.clock(elapsed > 0 ? elapsed : total))
                    .font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText(value: Double(elapsed)))
                Text(elapsed > 0 ? "من \(RemoteRoasterRecipe.clock(total))" : "الوقت")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الوقت \(RemoteRoasterRecipe.clock(total))")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Brand.brown.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggle() {
        Haptics.tap()
        if running {
            ticker?.cancel()
            running = false
            return
        }
        let total = recipe.timeSec ?? 0
        if elapsed >= total { elapsed = 0 }
        running = true
        ticker = Task { @MainActor in
            while !Task.isCancelled && elapsed < total + 30 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation { elapsed += 1 }
                if elapsed == total { Haptics.tap() }
            }
            running = false
        }
    }

    private func reset() {
        ticker?.cancel()
        running = false
        elapsed = 0
        done = []
    }
}
