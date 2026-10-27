import BunnListCore
import SwiftUI
import UIKit

/// Guided brew: a full-screen timer that walks through the recipe's steps, showing
/// what to do now, the scale reading to pour up to, and what comes next. Methods
/// with a scene (V60 hot and iced, AeroPress, Arabic coffee) draw the brewer live
/// instead of the ring. A light tap three seconds before each step, a stronger one
/// at the change, and the screen stays awake while brewing. With `onFinish`,
/// ending the brew hands back the elapsed seconds (for «كيف طلعت؟»).
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

    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var timeline: BrewTimeline { BrewTimeline(steps: plan.steps) }

    private var elapsed: TimeInterval {
        guard let startedAt else { return pausedElapsed }
        return pausedElapsed + now.timeIntervalSince(startedAt)
    }

    private var isRunning: Bool { startedAt != nil }
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
                header
                if sceneKind == .none { dial(position) } else { scene }
                currentStep(position)
                Spacer(minLength: 0)
                nextStep(position)
                controls(position)
            }
            .padding()
            .background(backdrop.ignoresSafeArea())
            .foregroundStyle(.white)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(.white)
                        .accessibilityLabel("إغلاق")
                }
                if let onFinish, elapsed > 0 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("خلصت") {
                            let seconds = Int(elapsed)
                            dismiss()
                            onFinish(seconds)
                        }
                        .font(.headline).tint(Brand.gold)
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
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
                Text("التالي").font(.caption).foregroundStyle(.white.opacity(0.6))
                Label(RecipeText.stepKind(next.kind), systemImage: RecipeText.stepIcon(next.kind)).font(.subheadline)
                Spacer()
            }
            .padding(12)
            .background(sceneState.isCueing ? Brand.gold.opacity(0.35) : Color.white.opacity(0.08),
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
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("إعادة")
            .disabled(elapsed == 0)

            Button { isRunning ? pause() : start(position) } label: {
                Label(isRunning ? "إيقاف مؤقت" : (elapsed > 0 && !position.isFinished ? "متابعة" : "ابدأ"),
                      systemImage: isRunning ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Brand.gold, in: Capsule())
                    .foregroundStyle(.black)
            }
            .accessibilityIdentifier("brew-start")

            Button { skip(position) } label: {
                Image(systemName: "forward.end.fill").font(.title2)
                    .frame(width: 60, height: 60)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("الخطوة التالية")
            .disabled(position.isFinished)
        }
        .buttonStyle(.plain)
    }

    private func start(_ position: BrewTimeline.Position) {
        if position.isFinished { reset() }
        now = Date()
        startedAt = now
        if lastStep < 0 { lastStep = 0 }
    }

    private func pause() {
        pausedElapsed = elapsed
        startedAt = nil
    }

    private func reset() {
        startedAt = nil
        pausedElapsed = 0
        lastStep = -1
        cuedStep = -1
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
