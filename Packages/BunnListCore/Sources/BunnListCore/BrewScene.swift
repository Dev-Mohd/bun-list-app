import Foundation

/// What the brewing animation draws at a moment: which scene (the brewer), the
/// stage of the recipe and how far into it, how much water is in so far and how
/// much has dripped through. Pure, so the timer's numbers and the drawing agree.
public enum BrewSceneKind: Equatable, Sendable {
    case pourOver(iced: Bool)
    case aeropress
    case espresso
    case arabic
    /// Methods without their own scene yet keep the plain timer ring.
    case none

    public static func of(_ plan: BrewPlan) -> BrewSceneKind {
        switch plan.methodCode {
        case "V60": return .pourOver(iced: plan.temperature == .iced || (plan.iceGrams ?? 0) > 0)
        case "AEROPRESS": return .aeropress
        case "ESPRESSO": return .espresso
        case "ARABIC": return .arabic
        default: return .none
        }
    }
}

public struct BrewSceneState: Equatable, Sendable {
    public enum Stage: String, Equatable, Sendable {
        case ready, bloom, pour, swirl, stir, wait, press, serve, done
        // Arabic coffee, by the order of its steps.
        case heat, addCoffee, simmer, addCardamom, settle
    }

    public let stage: Stage
    /// 0…1 through the current stage.
    public let progress: Double
    public let stepIndex: Int
    /// Water poured so far, as a share of the recipe's water (0…1).
    public let poured: Double
    /// Coffee that has come through into the server, as a share (0…1). Never more than `poured`.
    public let drained: Double
    /// Seconds until the next step, nil on the last.
    public let secondsToNext: Double?
    /// A title for the stage when the step kind alone doesn't say it (Arabic coffee).
    public let titleAr: String?

    /// Water standing in the brewer.
    public var standing: Double { max(0, poured - drained) }
    /// In the last three seconds before a step change: the cue to look up.
    public var isCueing: Bool { (secondsToNext ?? .infinity) <= 3 && (secondsToNext ?? 0) > 0 }
}

public enum BrewScene {
    /// The state `elapsed` seconds in. `started` false shows the ready stage.
    public static func state(plan: BrewPlan, elapsed: Double, started: Bool) -> BrewSceneState {
        let steps = plan.steps
        let durations = steps.map { Double(max($0.seconds ?? 0, 0)) }
        let total = durations.reduce(0, +)
        let water = steps.map { $0.kind.addsWater ? ($0.addedWaterGrams ?? 0) : 0 }
        let totalWater = max(water.reduce(0, +), 1)
        let arabic = plan.methodCode == "ARABIC"

        guard started, !steps.isEmpty else {
            return BrewSceneState(stage: .ready, progress: 0, stepIndex: 0, poured: 0, drained: 0,
                                  secondsToNext: nil, titleAr: arabic ? arabicStages(steps).first?.1 : nil)
        }
        if elapsed >= total {
            return BrewSceneState(stage: .done, progress: 1, stepIndex: steps.count - 1, poured: 1, drained: 1,
                                  secondsToNext: nil, titleAr: arabic ? "قهوتك جاهزة" : nil)
        }

        var start = 0.0, index = 0
        for (i, d) in durations.enumerated() {
            if elapsed < start + d { index = i; break }
            start += d
        }
        let duration = max(durations[index], 0.001)
        let progress = min(max((elapsed - start) / duration, 0), 1)

        // Water lands over the first part of a step: blooms are a quick pour, pours a steady one.
        var pouredGrams = water[..<index].reduce(0, +)
        if water[index] > 0 {
            let span = steps[index].kind == .bloom ? 0.4 : 0.85
            pouredGrams += water[index] * min(progress / span, 1)
        }
        let poured = min(pouredGrams / totalWater, 1)

        // Drawdown starts a little into the first step and ends with the recipe.
        let lag = durations.first.map { $0 * 0.5 } ?? 0
        let flow = total > lag ? min(max((elapsed - lag) / (total - lag), 0), 1) : 0
        let drained = min(poured, pow(flow, 0.9))

        let next = index < steps.count - 1 ? start + duration - elapsed : nil
        var stage = BrewSceneState.Stage(rawValue: steps[index].kind.rawValue) ?? .wait
        var title: String?
        if arabic, let mapped = arabicStages(steps)[safe: index] { stage = mapped.0; title = mapped.1 }
        return BrewSceneState(stage: stage, progress: progress, stepIndex: index, poured: poured,
                              drained: drained, secondsToNext: next, titleAr: title)
    }

    /// Arabic coffee's steps are plain pours, waits and stirs; their order says what
    /// each is: heat the water, add the coffee, let it simmer, add the cardamom, let
    /// it settle, serve.
    static func arabicStages(_ steps: [RemoteRecipeStep]) -> [(BrewSceneState.Stage, String)] {
        var stirs = 0
        return steps.enumerated().map { index, step in
            if index == 0 && step.kind != .stir { return (.heat, "سخّن الماء في الدلة") }
            switch step.kind {
            case .serve: return (.serve, "صبّها وقدّمها")
            case .stir, .swirl:
                stirs += 1
                return stirs == 1 ? (.addCoffee, "أضف البن") : (.addCardamom, "أضف الهيل")
            default:
                return stirs >= 2 ? (.settle, "خلّها تركد") : (.simmer, "على نار هادية")
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
