import Foundation

/// Hands-free brewing: what the timer says and sounds at each second, so the brew
/// can be followed without looking at the phone. Pure text and samples; the app
/// does the speaking and the playing.
public enum BrewVoice {
    /// What the hands are doing in a step. Drives the tone and the glance colour.
    public enum Mood: String, Equatable, Sendable {
        /// Water is going in: watch the scale.
        case pour
        /// A short action: swirl, stir, press, serve.
        case act
        /// Hands off.
        case wait
        case done
    }

    public enum Cue: Equatable, Sendable {
        /// A step begins: play the mood's tone, then say the line.
        case step(index: Int, line: String, mood: Mood)
        /// Three, two, one before the step ends.
        case count(Int)
        case finished(line: String)
    }

    public static let finishedLine = "خلصت، بالعافية"

    /// Said when «ابدأ» is pressed: a few seconds to put the phone down and pick up the kettle.
    public static let readyLine = "استعد"
    public static let prepSeconds = 5

    /// The espresso shot has two moments worth saying: the window opening, and its end.
    public static func espressoLine(second: Int, target: ClosedRange<Int>) -> String? {
        if second == target.lowerBound { return "وصلت \(spokenDuration(second))، تقدر توقّف" }
        if second == target.upperBound { return "وقّف الحين" }
        return nil
    }

    /// A step shorter than this has no countdown: its own line would still be playing.
    static let countdownMinSeconds = 8

    public static func countWord(_ n: Int) -> String {
        switch n {
        case 3: return "ثلاثة"
        case 2: return "اثنين"
        default: return "واحد"
        }
    }

    /// Titles that replace the step kind (Arabic coffee), one per step; nil elsewhere.
    public static func titles(plan: BrewPlan) -> [String?] {
        guard plan.methodCode == "ARABIC" else { return plan.steps.map { _ in nil } }
        return BrewScene.arabicStages(plan.steps).map { $0.1 }
    }

    public static func mood(step: RemoteRecipeStep, titleAr: String? = nil) -> Mood {
        if titleAr != nil { return step.kind == .wait || step.kind.addsWater ? .wait : .act }
        if step.kind.addsWater { return .pour }
        return step.kind == .wait ? .wait : .act
    }

    /// "30 ثانية", "دقيقة و 15 ثانية", "دقيقتين".
    public static func spokenDuration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        var parts: [String] = []
        switch m {
        case 0: break
        case 1: parts.append("دقيقة")
        case 2: parts.append("دقيقتين")
        case 3...10: parts.append("\(m) دقايق")
        default: parts.append("\(m) دقيقة")
        }
        switch s {
        case 0: break
        case 1: parts.append("ثانية")
        case 2: parts.append("ثانيتين")
        case 3...10: parts.append("\(s) ثواني")
        default: parts.append("\(s) ثانية")
        }
        return parts.isEmpty ? "لحظة" : parts.joined(separator: " و ")
    }

    private static func grams(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// The line for the start of a step. `pourTo` is the scale reading to reach.
    public static func line(step: RemoteRecipeStep, pourTo: Double?, titleAr: String? = nil) -> String {
        let seconds = step.seconds ?? 0
        if let titleAr {
            // Arabic coffee: the stage says it; the waiting ones get their time.
            return mood(step: step, titleAr: titleAr) == .wait && seconds > 0 ? "\(titleAr)، \(spokenDuration(seconds))" : titleAr
        }
        switch step.kind {
        case .bloom:
            guard let pourTo else { return "تفتيح" }
            return "تفتيح. صبّ لين \(grams(pourTo)) غرام"
        case .pour:
            guard let pourTo else { return "صبّ" }
            return "صبّ لين \(grams(pourTo)) غرام"
        case .wait: return seconds > 0 ? "انتظر \(spokenDuration(seconds))" : "انتظر"
        case .swirl: return "حرّك القمع"
        case .stir: return "قلّب"
        case .press: return "اضغط بهدوء"
        case .serve:
            if step.isAddition, let g = step.addedWaterGrams {
                return step.addition == "ice" ? "أضف \(grams(g)) غرام ثلج" : "أضف \(grams(g)) غرام ماء"
            }
            return "قدّم القهوة"
        }
    }

    /// What happens as the clock reaches `second`, if anything. At most one cue a
    /// second: the end, else a step's start, else the countdown.
    public static func cue(timeline: BrewTimeline, second: Int, titles: [String?] = []) -> Cue? {
        guard !timeline.steps.isEmpty, second >= 0 else { return nil }
        let position = timeline.position(at: second)
        if position.isFinished { return second == timeline.totalSeconds ? .finished(line: finishedLine) : nil }
        let index = position.stepIndex
        let step = timeline.steps[index]
        let title = titles.indices.contains(index) ? titles[index] : nil
        if second == timeline.start(of: index) {
            return .step(index: index, line: line(step: step, pourTo: position.pourTo, titleAr: title),
                         mood: mood(step: step, titleAr: title))
        }
        if (1...3).contains(position.secondsLeftInStep), (step.seconds ?? 0) >= countdownMinSeconds {
            return .count(position.secondsLeftInStep)
        }
        return nil
    }
}

/// The timer's tones, drawn as samples so they need no sound files: two rising
/// notes to start pouring, two falling to stop, one for an action, three for done.
public enum BrewTone {
    public static let sampleRate = 44_100

    static func notes(_ mood: BrewVoice.Mood) -> [(hz: Double, seconds: Double)] {
        switch mood {
        case .pour: return [(660, 0.12), (990, 0.16)]
        case .wait: return [(880, 0.12), (587, 0.18)]
        case .act: return [(784, 0.16)]
        case .done: return [(660, 0.12), (880, 0.12), (1175, 0.26)]
        }
    }

    /// Mono 16-bit samples, each note faded in and out so it doesn't click.
    public static func samples(_ mood: BrewVoice.Mood) -> [Int16] {
        var out: [Int16] = []
        for note in notes(mood) {
            let count = Int(note.seconds * Double(sampleRate))
            let fade = Double(sampleRate) * 0.012
            for i in 0..<count {
                let envelope = min(1, Double(i) / fade, Double(count - 1 - i) / fade)
                let value = sin(2 * .pi * note.hz * Double(i) / Double(sampleRate)) * envelope * 0.55
                out.append(Int16(value * Double(Int16.max)))
            }
        }
        return out
    }

    /// The same tone as a WAV file in memory.
    public static func wav(_ mood: BrewVoice.Mood) -> Data {
        let pcm = samples(mood)
        var data = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + pcm.count * 2)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(pcm.count * 2)
        for sample in pcm { withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }
}
