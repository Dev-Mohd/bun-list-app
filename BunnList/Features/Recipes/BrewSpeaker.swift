import AVFoundation
import BunnListCore

/// Speaks and sounds the brew timer's cues: a tone at each step, the step's line in
/// Arabic, three-two-one before the next, and the finish. Lines with a recording in
/// the bundle (Resources/BrewVoice) play in the recorded voice; the rest are read by
/// the phone's own Arabic voice. Other audio is lowered only while a cue plays.
@MainActor
final class BrewSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var players: [BrewVoice.Mood: AVAudioPlayer] = [:]
    private var queue: AVQueuePlayer?
    private var pendingClips: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var clipsPlaying = false
    private let voice = AVSpeechSynthesisVoice(language: "ar-001")
        ?? AVSpeechSynthesisVoice(language: "ar-SA")
        ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("ar") }

    var hasArabicVoice: Bool { voice != nil }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// `clips` are the recorded files for this cue (see `BrewVoice.clips`); when any
    /// is missing from the bundle the cue's text is spoken instead.
    func play(_ cue: BrewVoice.Cue, clips: [String] = []) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        stopClips()
        let urls = clips.compactMap { Bundle.main.url(forResource: $0, withExtension: "mp3") }
        let recorded = !clips.isEmpty && urls.count == clips.count
        switch cue {
        case let .step(_, line, mood):
            tone(mood)
            if recorded { playClips(urls, after: 0.4) } else { say(line, after: 0.4) }
        case let .count(n):
            if recorded { playClips(urls, after: 0) } else { say(BrewVoice.countWord(n), after: 0, rate: 0.54) }
        case let .finished(line):
            tone(.done)
            if recorded { playClips(urls, after: 0.6) } else { say(line, after: 0.6) }
        }
        // A cue with nothing to say still has to give the audio back.
        if voice == nil && !recorded { settle(after: 1) }
    }

    private func playClips(_ urls: [URL], after delay: TimeInterval) {
        clipsPlaying = true
        pendingClips = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            let items = urls.map { AVPlayerItem(url: $0) }
            let player = AVQueuePlayer(items: items)
            self.queue = player
            if let last = items.last {
                self.endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: last, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.clipsPlaying = false
                        self?.settle(after: 0.3)
                    }
                }
            }
            player.play()
        }
    }

    private func stopClips() {
        pendingClips?.cancel()
        pendingClips = nil
        queue?.pause()
        queue?.removeAllItems()
        queue = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        clipsPlaying = false
    }

    /// Stops mid-sentence (pause, reset, leaving the timer).
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        stopClips()
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
            guard let self, !self.synthesizer.isSpeaking, !self.clipsPlaying,
                  !self.players.values.contains(where: { $0.isPlaying }) else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.settle(after: 0.3) }
    }
}
