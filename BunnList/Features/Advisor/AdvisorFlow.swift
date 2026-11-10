import BunnListCore
import SwiftUI

/// The home's «ساعدني أختار ✨» card.
struct AdvisorCard: View {
    var open: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ساعدني أختار").font(.title2.bold())
                    Text("جاوب كم سؤال ونطلع لك قهوتك").font(.subheadline).opacity(0.85)
                    Text("يلا نبدأ")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Brand.background, in: Capsule())
                        .foregroundStyle(Brand.brown)
                        .padding(.top, 6)
                }
                Spacer()
                ZStack {
                    Text("✨").font(.system(size: 22)).offset(x: -26, y: -24).opacity(pulse ? 1 : 0.3)
                    Text("☕").font(.system(size: 50)).rotationEffect(.degrees(pulse ? -6 : 6))
                    Text("✨").font(.system(size: 16)).offset(x: 24, y: 22).opacity(pulse ? 0.3 : 1)
                }
                .frame(width: 90)
            }
            .foregroundStyle(Brand.background)
            .padding(20)
            .background(LinearGradient(colors: [Brand.brown, Brand.olive], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 26))
            .scaleEffect(pulse ? 1.015 : 1)
            .shadow(color: Brand.olive.opacity(pulse ? 0.3 : 0.1), radius: pulse ? 16 : 8, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true } }
        .accessibilityLabel("ساعدني أختار: جاوب كم سؤال ونطلع لك قهوتك")
        .accessibilityIdentifier("open-advisor")
    }
}

/// «ساعدني أختار»: a few tapped questions (milk only after espresso), an optional
/// sentence, then three coffees with why they fit.
@MainActor
struct AdvisorFlow: View {
    @EnvironmentObject private var auth: AuthModel
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case asking, loading, result(RemoteAdvisorResult), failed }

    @State private var answers = AdvisorAnswers()
    @State private var index = 0
    @State private var phase = Phase.asking
    @State private var forward = true
    @State private var addTo: RemoteLot?

    private let client = CatalogAPIClient(transport: URLSessionTransport())
    private var steps: [AdvisorStep] { answers.steps }
    private var step: AdvisorStep { steps[min(index, steps.count - 1)] }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                switch phase {
                case .asking: asking
                case .loading: AdvisorLoading()
                case let .result(result): AdvisorResults(result: result, milkDrink: answers.milkPreset?.milkDrink, addTo: { addTo = $0 }, restart: restart)
                case .failed:
                    ContentUnavailableView {
                        Label("ما قدرنا نختار الحين", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("حاول مرة ثانية") { Task { await submit() } }.buttonStyle(.borderedProminent).tint(Brand.olive)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("إغلاق")
                }
                if phase == .asking && index > 0 {
                    ToolbarItem(placement: .primaryAction) {
                        Button { back() } label: { Image(systemName: "chevron.forward") }.accessibilityLabel("رجوع")
                    }
                }
            }
            .sheet(item: $addTo) { lot in AddToListSheet(slug: lot.slug, lotName: lot.nameAr) }
        }
    }

    // MARK: Questions

    private var asking: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.gold.opacity(0.18))
                        Capsule().fill(Brand.olive).frame(width: geo.size.width * CGFloat(index + 1) / CGFloat(steps.count))
                    }
                }
                .frame(height: 8)
                .environment(\.layoutDirection, .rightToLeft)
                Text(step == .text ? "✨ اختياري" : "\((index + 1).formatted()) من \((steps.count - 1).formatted())")
                    .font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.top, 8)
            .animation(.spring(response: 0.4), value: index)

            ZStack {
                stepView(step)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .leading : .trailing).combined(with: .opacity),
                                            removal: .move(edge: forward ? .trailing : .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func stepView(_ step: AdvisorStep) -> some View {
        switch step {
        case .mood:
            question("وش جوّك اليوم؟", "على حسب جوّك نختار") {
                optionGrid([
                    (emoji("☀️"), "أبي أصحصح", "قوية ومنعشة", AdvisorAnswers.Mood.wake),
                    (emoji("🛋️"), "روقان", "أبي أهدأ", .calm),
                    (emoji("👥"), "عندي ضيوف", "ترضي الكل", .guests),
                    (emoji("🧭"), "شي جديد", "فاجئني", .new),
                ], selected: answers.mood) { answers.mood = $0; advance() }
            }
        case .method:
            question("وش بتستخدم؟", "نختار اللي تطلع حلوة فيه") {
                optionGrid([
                    (icon(.v60), "V60", nil, AdvisorAnswers.Method.v60),
                    (icon(.espresso), "إسبريسو", nil, .espresso),
                    (icon(.chemex), "كيمكس", nil, .chemex),
                    (icon(.frenchPress), "فرنش برس", nil, .frenchPress),
                ], selected: answers.method) { method in
                    answers.method = method
                    if method != .espresso { answers.milk = nil; answers.milkDrink = nil }
                    advance()
                }
            }
        case .milk:
            question("تشربها مع حليب؟", "لاتيه، كورتادو، فلات وايت…") {
                optionGrid([
                    (icon(.milk), "إيه، مع حليب", "نختار اللي تحلى معه", true),
                    (icon(.black), "لا، سادة", "إسبريسو صافي", false),
                ], selected: answers.milk) { milk in
                    answers.milk = milk
                    if !milk { answers.milkDrink = nil }
                    advance()
                }
            }
        case .milkDrink:
            question("أي مشروب؟", "نعطيك وصفته وكمية الحليب مع النتيجة") {
                optionGrid(AdvisorAnswers.milkDrinks.map { drink in
                    (AnyView(MilkDrinkGlass(drink: drink, size: 60)), drink.nameAr,
                     Optional("\(Int(drink.typicalMilkGrams))غ حليب · كوب \(drink.cupMl) مل"), drink)
                }, selected: answers.milkDrink) { answers.milkDrink = $0; advance() }
            }
        case .flavors:
            question("وش يشدّك في الطعم؟", "اختر اللي تبي، أو تخطّ") {
                AdvisorFlavorChips(selected: $answers.families)
                Spacer()
                nextButton(answers.families.isEmpty ? "أي شي، تخطّي" : "التالي") { advance() }
            }
        case .serve:
            question("حار ولا بارد؟", nil) {
                HStack(spacing: 12) {
                    serveHalf(.hot, "حار", .hot, [Color(red: 0.96, green: 0.84, blue: 0.72), Color(red: 0.91, green: 0.66, blue: 0.43)], Color(red: 0.35, green: 0.18, blue: 0.07))
                    serveHalf(.iced, "بارد", .iced, [Color(red: 0.86, green: 0.93, blue: 0.95), Color(red: 0.61, green: 0.78, blue: 0.85)], Color(red: 0.09, green: 0.23, blue: 0.29))
                }
                .frame(height: 300)
            }
        case .adventure:
            question("مغامر ولا تبي المضمون؟", "اسحب") {
                AdvisorAdventureSlider(value: $answers.adventure)
                Spacer()
                nextButton("التالي") { advance() }
            }
        case .text:
            question("تبي تقول شي زيادة؟", "اكتب بكلامك، ونفهمك") {
                AdvisorTextStep(text: $answers.text, signedIn: auth.isSignedIn)
                Spacer()
                nextButton("طلّع لي قهوتي ✨") { Task { await submit() } }
                Button("تخطّي") { answers.text = ""; Task { await submit() } }
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private func question<Content: View>(_ title: String, _ subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.largeTitle.bold()).foregroundStyle(Brand.ink)
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            content()
        }
        .padding()
        .padding(.top, 8)
    }

    private func emoji(_ text: String) -> AnyView { AnyView(Text(text).font(.system(size: 40))) }
    private func icon(_ kind: BrewIcon.Kind) -> AnyView { AnyView(BrewIcon(kind: kind, size: 60)) }

    private func optionGrid<T: Equatable>(_ items: [(AnyView, String, String?, T)], selected: T?, pick: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let on = selected == item.3
                Button {
                    Haptics.tap()
                    pick(item.3)
                } label: {
                    VStack(spacing: 6) {
                        item.0.scaleEffect(on ? 1.18 : 1).rotationEffect(.degrees(on ? -6 : 0))
                        Text(item.1).font(.headline).foregroundStyle(Brand.ink)
                        if let sub = item.2 { Text(sub).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 130)
                    .background(on ? Brand.olive.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(on ? Brand.olive : .clear, lineWidth: 2.5))
                    .scaleEffect(on ? 1.03 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.55), value: on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func serveHalf(_ kind: BrewIcon.Kind, _ label: String, _ serve: AdvisorAnswers.Serve, _ colors: [Color], _ ink: Color) -> some View {
        let on = answers.serve == serve
        let dim = answers.serve != nil && !on
        return Button {
            Haptics.tap()
            answers.serve = serve
            advance()
        } label: {
            VStack(spacing: 8) {
                BrewIcon(kind: kind, size: 96)
                Text(label).font(.title2.bold()).foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 28))
            .scaleEffect(on ? 1.04 : dim ? 0.94 : 1)
            .opacity(dim ? 0.4 : 1)
            .shadow(color: .black.opacity(on ? 0.15 : 0), radius: 14, y: 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: answers.serve)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white)
                .background(Brand.olive, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Flow

    private func advance() {
        Task {
            // A beat to see the choice land.
            try? await Task.sleep(nanoseconds: 320_000_000)
            forward = true
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index = min(index + 1, steps.count - 1) }
        }
    }

    private func back() {
        forward = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index = max(0, index - 1) }
    }

    private func restart() {
        answers = AdvisorAnswers()
        index = 0
        forward = false
        withAnimation { phase = .asking }
    }

    private func submit() async {
        withAnimation { phase = .loading }
        let started = Date()
        do {
            let result = try await client.advise(answers, accessToken: auth.currentAccessToken())
            // Let the loading moment breathe.
            let wait = max(0, 1.8 - Date().timeIntervalSince(started))
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            Haptics.tap()
            withAnimation(.spring(response: 0.5)) { phase = .result(result) }
        } catch {
            withAnimation { phase = .failed }
        }
    }
}

private struct AdvisorFlavorChips: View {
    @Binding var selected: Set<FlavorFamily>
    private let families: [FlavorFamily] = [.berry, .chocolate, .floral, .citrus, .caramel, .nutty, .honey, .tea, .tropical, .stoneFruit, .spice, .driedFruit]

    var body: some View {
        RoasterWrapLayout(spacing: 10) {
            ForEach(families, id: \.self) { family in
                let on = selected.contains(family)
                Button {
                    Haptics.tap()
                    if on { selected.remove(family) } else { selected.insert(family) }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(on ? Color.white : family.color).frame(width: 14, height: 14)
                        Text(family.shortNameAr).font(.headline)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .foregroundStyle(on ? Color.white : Brand.ink)
                    .background(on ? family.color : Color(.secondarySystemGroupedBackground), in: Capsule())
                    .scaleEffect(on ? 1.07 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: on)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(family.nameAr)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

private struct AdvisorAdventureSlider: View {
    @Binding var value: Double

    private var face: String { value < 0.34 ? "🛡️" : value < 0.67 ? "🙂" : "🚀" }
    private var line: String { value < 0.34 ? "أبي المضمون 👌" : value < 0.67 ? "وسط، فاجئني شوي" : "مغامر 😎" }

    var body: some View {
        VStack(spacing: 26) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [Brand.gold, Brand.gold.opacity(0.2), Brand.olive], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 12)
                    Text(face).font(.title2)
                        .frame(width: 50, height: 50)
                        .background(Color.white, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .offset(x: CGFloat(value) * (w - 50))
                        .gesture(DragGesture().onChanged { g in
                            let new = min(1, max(0, Double((g.location.x - 25) / (w - 50))))
                            if (new < 0.34) != (value < 0.34) || (new < 0.67) != (value < 0.67) { Haptics.tap() }
                            value = new
                        })
                }
                .frame(height: 50)
            }
            .frame(height: 50)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel("المغامرة")
            .accessibilityValue(line)
            .accessibilityAdjustableAction { dir in
                value = min(1, max(0, value + (dir == .increment ? 0.25 : -0.25)))
            }
            HStack {
                VStack(spacing: 3) { Text("🚀 مغامر").font(.headline); Text("معالجة غريبة أو دولة جديدة").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                VStack(spacing: 3) { Text("🛡️ مضمون").font(.headline); Text("الأعلى تقييمًا").font(.caption).foregroundStyle(.secondary) }
            }
            Text(line).font(.title3.bold()).foregroundStyle(Brand.olive).animation(.default, value: line)
        }
        .padding(.top, 30)
    }
}

private struct AdvisorTextStep: View {
    @Binding var text: String
    let signedIn: Bool
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("مثل: أبي شي يشبه قهوة جربتها في مقهى، طعمها توت وما فيها مرارة")
                        .foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 8)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .onChange(of: text) { _, v in if v.count > 300 { text = String(v.prefix(300)) } }
            }
            .font(.body)
            .frame(minHeight: 140)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(focused ? Brand.olive : Brand.gold.opacity(0.25), lineWidth: 2))
            .disabled(!signedIn)
            .opacity(signedIn ? 1 : 0.5)
            if !signedIn {
                Label("سجّل دخول عشان نقرأ كلامك. تقدر تكمل بدونه.", systemImage: "person.crop.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AdvisorLoading: View {
    @State private var spin = false
    @State private var line = 0
    private let lines = ["نقرأ ذوقك…", "نقلّب في القهاوي عشانك…", "نختار الأنسب…"]

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                ForEach(0..<5) { i in
                    Capsule().fill(Brand.brown).frame(width: 22, height: 30)
                        .offset(y: -80)
                        .rotationEffect(.degrees(Double(i) * 72))
                }
                .rotationEffect(.degrees(spin ? 360 : 0))
                Text("☕").font(.system(size: 60))
            }
            .frame(width: 200, height: 200)
            Text(lines[line]).font(.title3.bold()).foregroundStyle(Brand.ink)
                .id(line).transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .onAppear { withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { spin = true } }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation { line = (line + 1) % lines.count }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AdvisorResults: View {
    let result: RemoteAdvisorResult
    /// The milk drink picked on the way, to show its recipe with the coffees.
    var milkDrink: MilkDrink? = nil
    var addTo: (RemoteLot) -> Void
    var restart: () -> Void

    @EnvironmentObject private var auth: AuthModel
    @State private var shown = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("✨ قهوتك اليوم").font(.subheadline.bold()).foregroundStyle(Brand.gold)
                    Text(result.picks.isEmpty ? "ما لقينا شي يناسب" : "لقينا لك \(result.picks.count.formatted()) تناسبك")
                        .font(.title.bold())
                }
                if let chips = result.understood?.chips, !chips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("✨ فهمنا منك:").font(.subheadline.bold()).foregroundStyle(Brand.gold)
                        RoasterChips(items: chips, colors: chips.indices.map { [Brand.olive, Brand.brown, Brand.gold][$0 % 3] })
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(result.picks.enumerated()), id: \.element.id) { i, pick in
                    NavigationLink { LiveLotDetailView(slug: pick.lot.slug) } label: {
                        AdvisorPickCard(pick: pick, first: i == 0, play: shown > i,
                                        addTo: auth.isSignedIn ? { addTo(pick.lot) } : nil)
                    }
                    .buttonStyle(.plain)
                    .opacity(shown > i ? 1 : 0)
                    .offset(y: shown > i ? 0 : 40)
                }
                if let milkDrink {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("وصفة مشروبك").font(.headline).foregroundStyle(Brand.ink)
                        MilkGuideCard(drink: milkDrink)
                        Text("تلقاها في «حضّر» ← إسبريسو ← وصفات BunnList، مع مؤقّت الشوت.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                Button(action: restart) {
                    Label("جرّب أسئلة ثانية", systemImage: "arrow.counterclockwise")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding()
        }
        .task {
            for i in 1...max(1, result.picks.count) {
                try? await Task.sleep(nanoseconds: 260_000_000)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { shown = i }
            }
        }
    }
}

private struct AdvisorPickCard: View {
    let pick: RemoteAdvisorPick
    let first: Bool
    let play: Bool
    var addTo: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: pick.lot.imageUrl.flatMap(URL.init(string:))) { $0.resizable().scaledToFit() } placeholder: {
                Brand.gold.opacity(0.12)
            }
            .frame(width: 70, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                if let tag = pick.tag {
                    Text(tag).font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(first ? Brand.gold : Brand.olive, in: Capsule())
                }
                Text(pick.lot.nameAr).font(.headline).foregroundStyle(Brand.ink).lineLimit(2)
                Text(pick.lot.roasterNameAr).font(.caption).foregroundStyle(.secondary)
                Text(pick.reason).font(.caption.weight(.semibold)).foregroundStyle(Brand.olive).lineLimit(2)
                if let addTo {
                    Button(action: addTo) {
                        Label("أضفها لقائمة", systemImage: "text.badge.plus").font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.brown)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            MatchRing(score: pick.score, play: play, size: 66, tint: Brand.olive)
                .foregroundStyle(Brand.olive)
                .animation(.easeOut(duration: 1.1), value: play)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(first ? Brand.gold : .clear, lineWidth: 2.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pick.lot.nameAr) من \(pick.lot.roasterNameAr)، توافق \(pick.score)٪. \(pick.reason)")
    }
}
