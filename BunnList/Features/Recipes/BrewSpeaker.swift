import AVFoundation
import BunnListCore

/// Speaks and sounds the brew timer's cues: a tone at each step, the step's line in
/// Arabic, three-two-one before the next, and the finish. Other audio is lowered
/// only while a cue plays. Without an Arabic voice on the phone, the tones still play.
@MainActor
final class BrewSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var players: [BrewVoice.Mood: AVAudioPlayer] = [:]
    private let voice = AVSpeechSynthesisVoice(language: "ar-001")
        ?? AVSpeechSynthesisVoice(language: "ar-SA")
        ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("ar") }

    var hasArabicVoice: Bool { voice != nil }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ cue: BrewVoice.Cue) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        switch cue {
        case let .step(_, line, mood):
            tone(mood)
            say(line, after: 0.4)
        case let .count(n):
            say(BrewVoice.countWord(n), after: 0, rate: 0.54)
        case let .finished(line):
            tone(.done)
            say(line, after: 0.6)
        }
        // A cue with nothing to say still has to give the audio back.
        if voice == nil { settle(after: 1) }
    }

    /// Stops mid-sentence (pause, reset, leaving the timer).
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        players.values.forEach { $0.stop() }
        settle(after: 0.1)
    }

    private func tone(_ mood: BrewVoice.Mood) {
        if players[mood] == nil { players[mood] = try? AVAudioPlayer(data: BrewTone.wav(mood)) }
        guard let player = players[mood] else { return }
        player.currentTime = 0
        player.play()
    }

    private func say(_ text: String, after delay: TimeInterval, rate: Float = 0.5) {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.preUtteranceDelay = delay
        synthesizer.speak(utterance)
    }

    /// Lets other audio come back up once nothing of ours is playing.
    private func settle(after delay: TimeInterval) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.synthesizer.isSpeaking, !self.players.values.contains(where: { $0.isPlaying }) else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.settle(after: 0.3) }
    }
}
