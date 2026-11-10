import BunnListCore
import SwiftUI
import UIKit

/// Guided brew: a full-screen timer that walks through the recipe's steps, showing
/// what to do now, the scale reading to pour up to, and what comes next. Methods
/// with a scene (V60 hot and iced, AeroPress, Arabic coffee) draw the brewer live
/// instead of the ring. A light tap three seconds before each step, a stronger one
/// at the change, and the screen stays awake while brewing. With `onFinish`,
/// ending the brew hands back the elapsed seconds (for «كيف طلعت؟»).
///
/// Hands-free: each step is announced by a tone and a spoken line, with a
/// three-two-one before the next (the speaker button mutes it). The glance layout
/// (the eye button) swaps the scene for one giant number and a whole-screen colour:
/// gold while pouring, dark while waiting.
@MainActor
struct BrewTimerView: View {
    let plan: BrewPlan
    var onFinish: ((Int) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt: Date?
    @State private var pausedElapsed: TimeInterval = 0
    @State private var now = Date()
    @State private var lastStep = -1
    @State private var cuedStep = -1
    @State private var spokenSecond = -1
    /// «استعد»: seconds left before the clock starts, so the phone can be put down first.
    @State private var prepLeft: Int?
    @State private var prepTask: Task<Void, Never>?
    @State private var speaker = BrewSpeaker()
    @AppStorage("brew.voice") private var voiceOn = true
    @AppStorage("brew.glance") private var glance = true

    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var timeline: BrewTimeline { BrewTimeline(steps: plan.steps) }

    private var elapsed: TimeInterval {
        guard let startedAt else { return pausedElapsed }
        return pausedElapsed + now.timeIntervalSince(startedAt)
    }

    private var isRunning: Bool { startedAt != nil }
    private var titles: [String?] { BrewVoice.titles(plan: plan) }

    /// What the hands are doing now, for the glance colour. Nil before the start.
    private func mood(_ position: BrewTimeline.Position) -> BrewVoice.Mood? {
        if position.isFinished { return elapsed > 0 ? .done : nil }
        guard isRunning || elapsed > 0, let step = plan.steps[safe: position.stepIndex] else { return nil }
        return BrewVoice.mood(step: step, titleAr: titles[safe: position.stepIndex] ?? nil)
    }

    /// Gold is the only light backdrop: everything on it turns dark.
    private func onGold(_ position: BrewTimeline.Position) -> Bool { glance && mood(position) == .pour }
    private func ink(_ position: BrewTimeline.Position) -> Color { onGold(position) ? .black : .white }
    private func accent(_ position: BrewTimeline.Position) -> Color { onGold(position) ? .black : Brand.gold }
    private var sceneKind: BrewSceneKind { BrewSceneKind.of(plan) }
    private var totalWater: Double {
        plan.steps.reduce(0) { $0 + ($1.kind.addsWater ? ($1.addedWaterGrams ?? 0) : 0) }
    }

    /// Elapsed at a given moment, for the smooth animation (the tick drives the rest).
    private func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return pausedElapsed }
        return pausedElapsed + date.timeIntervalSince(startedAt)
    }

    private var sceneState: BrewSceneState {
        BrewScene.state(plan: plan, elapsed: elapsed, started: isRunning || elapsed > 0)
    }

    var body: some View {
        let position = timeline.position(at: Int(elapsed))
        NavigationStack {
            VStack(spacing: 24) {
                if glance {
                    glanceBoard(position)
                } else {
                    header
                    if sceneKind == .ring { dial(position) } else { scene }
                    currentStep(position)
                    Spacer(minLength: 0)
                }
                nextStep(position)
                controls(position)
            }
            .padding()
            .background {
                if glance {
                    glanceColor(position).ignoresSafeArea().animation(.easeInOut(duration: 0.35), value: mood(position))
                } else {
                    backdrop.ignoresSafeArea()
                }
            }
            .foregroundStyle(ink(position))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(ink(position))
                        .accessibilityLabel("إغلاق")
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 18) {
                        Button {
                            voiceOn.toggle()
                            if !voiceOn { speaker.stop() }
                        } label: { Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill") }
                            .accessibilityLabel(voiceOn ? "إيقاف الصوت" : "تشغيل الصوت")
                            .accessibilityIdentifier("brew-voice")
                        Button { withAnimation { glance.toggle() } } label: {
                            Image(systemName: glance ? "eye.fill" : "eye")
                        }
                        .accessibilityLabel(glance ? "عرض التفاصيل" : "عرض النظرة السريعة")
                        .accessibilityIdentifier("brew-glance")
                    }
                    .tint(ink(position))
                }
                if let onFinish, elapsed > 0 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("خلصت") {
                            let seconds = Int(elapsed)
                            dismiss()
                            onFinish(seconds)
                        }
                        .font(.headline).tint(accent(position))
                        .accessibilityIdentifier("brew-finish")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onReceive(tick) { date in
            guard isRunning else { return }
            now = date
            let current = timeline.position(at: Int(elapsed))
            // One cue a second at most; a late tick past the end still says the finish.
            let second = min(Int(elapsed), timeline.totalSeconds)
            if second != spokenSecond {
                spokenSecond = second
                if voiceOn, let cue = BrewVoice.cue(timeline: timeline, second: second, titles: titles) { speaker.play(cue) }
            }
            if sceneState.isCueing, cuedStep != current.stepIndex {
                cuedStep = current.stepIndex
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if current.stepIndex != lastStep || current.isFinished {
                if lastStep >= 0 { UINotificationFeedbackGenerator().notificationOccurred(current.isFinished ? .success : .warning) }
                lastStep = current.isFinished ? plan.steps.count : current.stepIndex
            }
            if current.isFinished { pause() }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            prepTask?.cancel()
            speaker.stop()
        }
        .overlay {
            // The detailed layout has no board to show the get-ready count on.
            if let prepLeft, !glance {
                VStack(spacing: 6) {
                    Text(BrewVoice.readyLine).font(.title.bold())
                    Text("\(prepLeft)").font(.system(size: 120, weight: .heavy, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.75))
                .allowsHitTesting(false)
            }
        }
    }

    private func glanceColor(_ position: BrewTimeline.Position) -> Color {
        switch mood(position) {
        case .pour: return Color(red: 0.78, green: 0.6, blue: 0.24)
        case .act: return Color(red: 0.29, green: 0.2, blue: 0.16)
        case .done: return Color(red: 0.33, green: 0.39, blue: 0.27)
        case .wait, nil: return Color(red: 0.09, green: 0.08, blue: 0.07)
        }
    }

    /// The glance layout: what to do in two words, and one number big enough to
    /// read from the counter. Pouring shows the scale reading; anything else the
    /// seconds left.
    @ViewBuilder
    private func glanceBoard(_ position: BrewTimeline.Position) -> some View {
        let fg = ink(position)
        let step = plan.steps[safe: position.stepIndex]
        VStack(spacing: 6) {
            Text(plan.title).font(.headline)
            if mood(position) != nil, !position.isFinished {
                Text("خطوة \(position.stepIndex + 1) من \(plan.steps.count) · \(RecipeText.duration(Int(elapsed)))")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(fg.opacity(0.7))
            }
            Spacer(minLength: 0)
            if let prepLeft {
                Text(BrewVoice.readyLine).font(.system(size: 34, weight: .bold))
                Text("\(prepLeft)")
                    .font(.system(size: 170, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("حط الجوال وامسك الغلاية").font(.title3.bold()).foregroundStyle(fg.opacity(0.75))
            } else if position.isFinished && elapsed > 0 {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 64))
                Text("خلصت، بالعافية").font(.system(size: 40, weight: .heavy))
                Text("تذوّقها وهي دافئة ثم وهي تبرد؛ النكهات تتغير.").font(.callout).foregroundStyle(fg.opacity(0.75))
            } else if mood(position) == nil {
                Text("جاهز؟").font(.system(size: 64, weight: .heavy))
                if let t = plan.waterTempC {
                    Text("جهّز الماء على \(RecipeText.number(t))°م").font(.title2.bold()).foregroundStyle(Brand.gold)
                }
                Text(voiceOn ? "حط الجوال قدامك واضغط «ابدأ». بنقول لك كل خطوة بالصوت، وما تحتاج تلمسه."
                     : "الصوت مقفّل. شغّله من زر السماعة فوق عشان نقول لك كل خطوة.")
                    .font(.callout).foregroundStyle(fg.opacity(0.75)).padding(.top, 6)
                if voiceOn && !speaker.hasArabicVoice {
                    Text("جوالك ما فيه صوت عربي، فبتسمع النغمات بس. تقدر تنزّل صوت عربي من إعدادات الجوال.")
                        .font(.footnote).foregroundStyle(fg.opacity(0.6))
                }
            } else if let step {
                let title = (titles[safe: position.stepIndex] ?? nil) ?? sceneState.titleAr
                if let pourTo = position.pourTo, mood(position) == .pour {
                    Text(step.kind == .bloom ? "تفتيح · صبّ لين" : "صبّ لين").font(.system(size: 34, weight: .bold))
                    Text(RecipeText.number(pourTo))
                        .font(.system(size: 170, weight: .heavy, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.4).lineLimit(1)
                        .contentTransition(.numericText())
                        .environment(\.layoutDirection, .leftToRight)
                    Text("غرام على الميزان").font(.title3.bold()).foregroundStyle(fg.opacity(0.75))
                    Text("باقي \(RecipeText.duration(position.secondsLeftInStep))")
                        .font(.system(size: 34, weight: .bold, design: .monospaced)).padding(.top, 8)
                } else {
                    Text(title ?? glanceVerb(step)).font(.system(size: 34, weight: .bold))
                    Text(position.secondsLeftInStep >= 60 ? RecipeText.duration(position.secondsLeftInStep) : "\(position.secondsLeftInStep)")
                        .font(.system(size: 170, weight: .heavy, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.4).lineLimit(1)
                        .contentTransition(.numericText())
                        .environment(\.layoutDirection, .leftToRight)
                    Text(position.secondsLeftInStep >= 60 ? "باقي" : "ثانية باقية").font(.title3.bold()).foregroundStyle(fg.opacity(0.75))
                    if step.isAddition {
                        Text(BrewVoice.line(step: step, pourTo: nil)).font(.title2.bold()).padding(.top, 8)
                    }
                }
                if !step.note.isEmpty {
                    Text(step.note).font(.callout).foregroundStyle(fg.opacity(0.8)).lineLimit(3).padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
            if isRunning, !position.isFinished {
                Text("ضغطتين على الشاشة تنقلك للخطوة التالية").font(.caption).foregroundStyle(fg.opacity(0.55))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // Wet hands miss small buttons: the whole board takes a double tap for «next».
        .onTapGesture(count: 2) {
            guard isRunning, !position.isFinished else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            skip(position)
        }
        .accessibilityElement(children: .combine)
    }

    private func glanceVerb(_ step: RemoteRecipeStep) -> String {
        switch step.kind {
        case .wait: return "انتظر"
        case .swirl: return "حرّك القمع"
        case .stir: return "قلّب"
        case .press: return "اضغط بهدوء"
        case .serve: return "قدّم القهوة"
        case .bloom, .pour: return "صبّ"
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(plan.title).font(.title3.bold())
            Text("\(RecipeText.method(plan.methodCode)) · \(RecipeText.number(plan.doseGrams))غ بن · \(RecipeText.number(plan.waterTempC))°م")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }
    }

    /// Black, warming (or cooling, iced) as the brew goes on.
    private var backdrop: some View {
        let total = Double(max(timeline.totalSeconds, 1))
        let warmth = 0.12 + min(elapsed / total, 1) * 0.3
        let iced = sceneKind == .pourOver(iced: true)
        let tint = iced ? Color(red: 0.35, green: 0.55, blue: 0.7) : Color(red: 0.62, green: 0.4, blue: 0.16)
        return ZStack {
            Color.black
            RadialGradient(colors: [tint.opacity(warmth), .clear], center: .center, startRadius: 10, endRadius: 420)
                .animation(.easeInOut(duration: 1), value: warmth)
        }
    }

    /// The live brewer, the clock and the scale reading.
    private var scene: some View {
        TimelineView(.animation) { context in
            let now = elapsed(at: context.date)
            let state = BrewScene.state(plan: plan, elapsed: now, started: isRunning || now > 0)
            VStack(spacing: 6) {
                BrewSceneView(kind: sceneKind, state: state, clock: context.date.timeIntervalSinceReferenceDate)
                    .frame(maxWidth: .infinity)
                    .frame(height: 290)
                HStack(alignment: .lastTextBaseline, spacing: 18) {
                    Text(RecipeText.duration(Int(now)))
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                    if totalWater > 0 {
                        Text("\(RecipeText.number(state.poured * totalWater)) / \(RecipeText.number(totalWater))غ")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(Brand.gold)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الوقت \(RecipeText.duration(Int(elapsed))) من \(RecipeText.duration(timeline.totalSeconds))")
    }

    private func dial(_ position: BrewTimeline.Position) -> some View {
        let total = max(timeline.totalSeconds, 1)
        let progress = min(elapsed / Double(total), 1)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Brand.gold, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            VStack(spacing: 6) {
                Text(RecipeText.duration(Int(elapsed)))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                Text("من \(RecipeText.duration(timeline.totalSeconds))")
                    .font(.subheadline.monospaced()).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 240, height: 240)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الوقت \(RecipeText.duration(Int(elapsed))) من \(RecipeText.duration(timeline.totalSeconds))")
    }

    @ViewBuilder
    private func currentStep(_ position: BrewTimeline.Position) -> some View {
        if position.isFinished && elapsed > 0 {
            VStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill").font(.largeTitle).foregroundStyle(Brand.gold)
                Text("قهوتك جاهزة، بالعافية").font(.title2.bold())
                Text("تذوّقها وهي دافئة ثم وهي تبرد؛ النكهات تتغير.").font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)
        } else if let step = plan.steps[safe: position.stepIndex] {
            VStack(spacing: 10) {
                Label(sceneState.titleAr ?? RecipeText.stepKind(step.kind), systemImage: RecipeText.stepIcon(step.kind))
                    .font(.title.bold())
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: position.stepIndex)
                if let pourTo = position.pourTo {
                    Text("صب حتى \(RecipeText.number(pourTo))غ")
                        .font(.system(.title2, design: .monospaced).bold())
                        .foregroundStyle(Brand.gold)
                }
                // Before starting: the water to prepare. While pouring: a pour's own temperature.
                if !isRunning && elapsed == 0, let t = plan.waterTempC, plan.usesTimer {
                    Text("جهّز الماء على \(RecipeText.number(t))°م").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.85))
                } else if step.kind.addsWater, let t = step.tempC {
                    Text("الماء على \(RecipeText.number(t))°").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.85))
                }
                if step.isAddition {
                    Text(step.addition == "ice" ? "أضف \(RecipeText.number(step.addedWaterGrams))غ ثلج"
                         : "أضف \(RecipeText.number(step.addedWaterGrams))غ ماء \(AdditionTemp.nameAr(step.additionTemp))")
                        .font(.system(.title3, design: .monospaced).bold()).foregroundStyle(Brand.gold)
                }
                if !step.note.isEmpty {
                    Text(step.note).font(.callout).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                }
                if isRunning || elapsed > 0 {
                    Text("باقي \(RecipeText.duration(position.secondsLeftInStep))")
                        .font(.subheadline.monospaced()).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    @ViewBuilder
    private func nextStep(_ position: BrewTimeline.Position) -> some View {
        if !position.isFinished, let next = plan.steps[safe: position.stepIndex + 1] {
            HStack {
                Text("التالي").font(.caption).foregroundStyle(ink(position).opacity(0.6))
                Label(RecipeText.stepKind(next.kind), systemImage: RecipeText.stepIcon(next.kind)).font(.subheadline)
                Spacer()
            }
            .padding(12)
            .background(sceneState.isCueing ? accent(position).opacity(0.35) : ink(position).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(sceneState.isCueing ? 1.03 : 1)
            .animation(.spring(response: 0.35), value: sceneState.isCueing)
        }
    }

    private func controls(_ position: BrewTimeline.Position) -> some View {
        HStack(spacing: 16) {
            Button { reset() } label: {
                Image(systemName: "arrow.counterclockwise").font(.title2)
                    .frame(width: 60, height: 60)
                    .background(ink(position).opacity(0.12), in: Circle())
            }
            .accessibilityLabel("إعادة")
            .disabled(elapsed == 0)

            Button {
                if prepLeft != nil { cancelPrep() } else if isRunning { pause() } else { start(position) }
            } label: {
                Label(prepLeft != nil ? "إلغاء" : (isRunning ? "إيقاف مؤقت" : (elapsed > 0 && !position.isFinished ? "متابعة" : "ابدأ")),
                      systemImage: prepLeft != nil ? "xmark" : (isRunning ? "pause.fill" : "play.fill"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(accent(position), in: Capsule())
                    .foregroundStyle(onGold(position) ? Color(red: 0.78, green: 0.6, blue: 0.24) : .black)
            }
            .accessibilityIdentifier("brew-start")

            Button { skip(position) } label: {
                Image(systemName: "forward.end.fill").font(.title2)
                    .frame(width: 60, height: 60)
                    .background(ink(position).opacity(0.12), in: Circle())
            }
            .accessibilityLabel("الخطوة التالية")
            .disabled(position.isFinished)
        }
        .buttonStyle(.plain)
    }

    /// A fresh brew gets «استعد» and a short count first; resuming starts at once.
    private func start(_ position: BrewTimeline.Position) {
        if position.isFinished { reset() }
        if elapsed == 0 { beginPrep() } else { begin() }
    }

    private func begin() {
        now = Date()
        startedAt = now
        if lastStep < 0 { lastStep = 0 }
    }

    private func beginPrep() {
        prepTask?.cancel()
        prepLeft = BrewVoice.prepSeconds
        if voiceOn { speaker.play(.step(index: 0, line: BrewVoice.readyLine, mood: .act)) }
        prepTask = Task { @MainActor in
            for n in stride(from: BrewVoice.prepSeconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                withAnimation { prepLeft = n }
                if (1...3).contains(n), voiceOn { speaker.play(.count(n)) }
            }
            prepLeft = nil
            prepTask = nil
            begin()
        }
    }

    private func cancelPrep() {
        prepTask?.cancel()
        prepTask = nil
        prepLeft = nil
        speaker.stop()
    }

    private func pause() {
        pausedElapsed = elapsed
        startedAt = nil
        // The finishing line plays on; a pause mid-brew cuts the sentence.
        if !timeline.position(at: Int(pausedElapsed)).isFinished { speaker.stop() }
    }

    private func reset() {
        prepTask?.cancel()
        prepTask = nil
        prepLeft = nil
        startedAt = nil
        pausedElapsed = 0
        lastStep = -1
        cuedStep = -1
        spokenSecond = -1
        speaker.stop()
    }

    /// Jumps to the start of the next step (for when you finish a pour early).
    private func skip(_ position: BrewTimeline.Position) {
        let target = TimeInterval(timeline.start(of: position.stepIndex + 1))
        if isRunning {
            now = Date()
            startedAt = now
        }
        pausedElapsed = target
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
