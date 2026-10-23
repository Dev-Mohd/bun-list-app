import UIKit

/// Light haptic feedback, gated by the user's "الاهتزاز" setting (stored under the
/// same key the Settings toggle binds to).
enum Haptics {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
