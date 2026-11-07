import SwiftUI
import TipKit

/// One-time tips («فقاعات الشرح»): each shows once, on the screen it explains, and goes away when
/// dismissed or when the person does what it suggests. Two tips on the same screen come one after the other.
enum AppTips {
    private static let resetKey = "tips.reset"

    /// Call once at launch. A reset asked for in Settings happens here, before TipKit starts
    /// (TipKit only allows clearing its store before it's configured).
    static func configure() {
        if UserDefaults.standard.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: resetKey)
        }
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
    }

    /// «اعرض التلميحات من جديد»: takes effect the next time the app opens.
    static func showAgainNextLaunch() { UserDefaults.standard.set(true, forKey: resetKey) }
}

// MARK: The tips

struct AdvisorTip: Tip {
    @Parameter static var done: Bool = false
    var title: Text { Text("محتار وش تشتري؟") }
    var message: Text? { Text("جاوب كم سؤال ونطلع لك قهوة على ذوقك.") }
    var image: Image? { Image(systemName: "sparkles") }
}

struct ScanTip: Tip {
    var title: Text { Text("صوّر الكيس") }
    var message: Text? { Text("صوّر كيس قهوتك ونطلّعها لك من الدليل، وتضيفها لمجموعتك بضغطة.") }
    var image: Image? { Image(systemName: "camera.viewfinder") }
    var rules: [Rule] { #Rule(AdvisorTip.$done) { $0 == true } }
}

struct SaveTip: Tip {
    @Parameter static var done: Bool = false
    var title: Text { Text("ودّي أجرّب") }
    var message: Text? { Text("احفظ القهوة وترجع لها من مجموعتي، ومعها المفضلة والقوائم.") }
    var image: Image? { Image(systemName: "bookmark") }
}

struct RateTip: Tip {
    var title: Text { Text("قيّمها") }
    var message: Text? { Text("كل تقييم يعلّمنا ذوقك، ويخلّي «كم تناسبك» أدق.") }
    var image: Image? { Image(systemName: "star.bubble") }
    var rules: [Rule] { #Rule(SaveTip.$done) { $0 == true } }
}

struct PassportTip: Tip {
    var title: Text { Text("جواز قهوتك") }
    var message: Text? { Text("كل قهوة تضيفها تختم دولتها في جوازك. كم دولة تقدر تجمع؟") }
    var image: Image? { Image(systemName: "globe.europe.africa") }
}

struct BrewTip: Tip {
    var title: Text { Text("حضّر معنا") }
    var message: Text? { Text("اختر قهوتك والطريقة، والمؤقت يمشي معك صبّة صبّة.") }
    var image: Image? { Image(systemName: "timer") }
}

struct UpdatesTip: Tip {
    var title: Text { Text("صوتك يوصلنا") }
    var message: Text? { Text("هنا تحديثات BunnList، ومنها ترسل اقتراحاتك وأي مشكلة تواجهك.") }
    var image: Image? { Image(systemName: "megaphone") }
}

// MARK: Showing them

extension View {
    /// A brand-styled popover tip. `onDone` runs once the tip has shown and gone (dismissed or invalidated),
    /// so the next tip on the same screen can follow.
    func appTip<T: Tip>(_ tip: T, arrowEdge: Edge = .top, onDone: (() -> Void)? = nil) -> some View {
        self
            .popoverTip(tip, arrowEdge: arrowEdge)
            .tipBackground(Brand.background)
            .tint(Brand.olive)
            .task {
                guard let onDone else { return }
                var shown = false
                for await should in tip.shouldDisplayUpdates {
                    if should { shown = true } else if shown { onDone(); return }
                }
            }
    }
}
