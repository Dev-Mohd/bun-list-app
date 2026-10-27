import BunnListCore
import SwiftUI
import UIKit

/// The brewing itself, shaped by the method: the pour timer for pour-overs and
/// immersion, a shot timer for espresso, a checklist for cold brew. `onFinish`
/// gets the seconds brewed, for «كيف طلعت؟».
struct BrewSessionView: View {
    let plan: BrewPlan
    var onFinish: (Int) -> Void

    var body: some View {
        if plan.isEspresso {
            EspressoShotView(plan: plan, onFinish: onFinish)
        } else if !plan.usesTimer || plan.steps.isEmpty {
            ChecklistBrewView(plan: plan, onFinish: onFinish)
        } else {
            BrewTimerView(plan: plan, onFinish: onFinish)
        }
    }
}

/// Espresso: dose in, target out, and a shot timer against the target window.
/// Off target, it suggests one change to try next time, never a sure fix.
@MainActor
struct EspressoShotView: View {
    let plan: BrewPlan
    var onFinish: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date?
    @State private var stoppedAt: TimeInterval?
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// The recipe's own shot time ± 3 s, or the usual espresso window.
    private var target: ClosedRange<Int> {
        if let s = plan.steps.first?.seconds, s > 0 { return max(s - 3, 1)...(s + 3) }
        return 25...32
    }

    private var elapsed: TimeInterval {
        if let stoppedAt { return stoppedAt }
        guard let startedAt else { return 0 }
        return now.timeIntervalSince(startedAt)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                VStack(spacing: 4) {
                    Text(plan.title).font(.title3.bold())
                    Text("\(RecipeText.number(plan.doseGrams))غ بن ← \(RecipeText.number(plan.yieldGrams))غ في الكوب")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 14)
                    Circle()
                        .trim(from: CGFloat(target.lowerBound) / 40, to: CGFloat(target.upperBound) / 40)
                        .stroke(Brand.olive.opacity(0.8), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .trim(from: 0, to: min(elapsed / 40, 1))
                        .stroke(Brand.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", elapsed))
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .contentTransition(.numericText())
                        Text("الهدف \(target.lowerBound)–\(target.upperBound) ث").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .frame(width: 260, height: 260)
                result
                Spacer(minLength: 0)
                controls
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(.white)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.tint(.white).accessibilityLabel("إغلاق")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onReceive(tick) { if startedAt != nil && stoppedAt == nil { now = $0 } }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var result: some View {
        if let stoppedAt {
            let seconds = Int(stoppedAt.rounded())
            VStack(spacing: 6) {
                if target.contains(seconds) {
                    Label("ضمن الهدف", systemImage: "checkmark.seal.fill").font(.title3.bold()).foregroundStyle(Brand.olive)
                } else {
                    Label(seconds < target.lowerBound ? "أسرع من الهدف" : "أبطأ من الهدف", systemImage: "info.circle.fill")
                        .font(.title3.bold()).foregroundStyle(Brand.gold)
                    Text(seconds < target.lowerBound
                         ? "جرّب المرة الجاية طحنة أنعم شوي. غيّر شي واحد بس عشان تعرف أثره."
                         : "جرّب المرة الجاية طحنة أخشن شوي. غيّر شي واحد بس عشان تعرف أثره.")
                        .font(.callout).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                }
            }
        } else if let note = plan.steps.first?.note, !note.isEmpty {
            Text(note).font(.callout).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            if stoppedAt != nil {
                Button { startedAt = nil; stoppedAt = nil } label: {
                    Image(systemName: "arrow.counterclockwise").font(.title2)
                        .frame(width: 60, height: 60).background(Color.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("إعادة")
                Button {
                    let seconds = Int(elapsed.rounded())
                    dismiss()
                    onFinish(seconds)
                } label: {
                    Label("خلصت", systemImage: "checkmark").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 60).background(Brand.gold, in: Capsule()).foregroundStyle(.black)
                }
                .accessibilityIdentifier("brew-finish")
            } else {
                Button {
                    if startedAt == nil {
                        now = Date(); startedAt = now
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else {
                        stoppedAt = elapsed
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } label: {
                    Label(startedAt == nil ? "ابدأ الاستخلاص" : "وقّف", systemImage: startedAt == nil ? "play.fill" : "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 60).background(Brand.gold, in: Capsule()).foregroundStyle(.black)
                }
                .accessibilityIdentifier("brew-start")
            }
        }
        .buttonStyle(.plain)
    }
}

/// Methods measured in hours (cold brew): the steps as a checklist, no countdown.
@MainActor
struct ChecklistBrewView: View {
    let plan: BrewPlan
    var onFinish: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var done = Set<Int>()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(RecipeText.number(plan.doseGrams))غ بن · \(RecipeText.number(plan.hotWaterGrams))غ ماء · طحنة \(plan.grindText)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("الخطوات") {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                        Button {
                            if done.contains(index) { done.remove(index) } else { done.insert(index) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: done.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(done.contains(index) ? Brand.olive : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(RecipeText.stepKind(step.kind)).font(.headline)
                                    if !step.note.isEmpty { Text(step.note).font(.callout).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: done.contains(index))
                    }
                }
            }
            .navigationTitle(plan.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("خلصت") { dismiss(); onFinish(0) }.disabled(done.isEmpty)
                }
            }
        }
    }
}
