import SwiftUI
import UIKit

/// Semantic colors from the asset catalog (light and dark variants defined there).
enum Brand {
    static let ink = Color("Ink")
    static let olive = Color("Olive")
    static let background = Color("Background")
    static let gold = Color("Gold")
    static let brown = Color("Brown")
}

/// App heading with the original symbol. The PNG is not in the repository yet; until it is added to
/// `BunnListSymbol`, a clearly separate system placeholder and a note are shown instead of a redrawn logo.
struct BrandHeading: View {
    var subtitle = "اكتشف قهوتك واجمعها"

    var body: some View {
        HStack(spacing: 12) {
            if let image = UIImage(named: "BunnListSymbol") {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 40, height: 46)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("بن لست").font(.title2.bold()).foregroundStyle(Brand.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                if UIImage(named: "BunnListSymbol") == nil {
                    Text("ملف الشعار الأصلي غير مضمّن بعد").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown wherever demo data or demo results are visible.
struct SampleBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "flask")
            .font(.caption)
            .foregroundStyle(Brand.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Brand.gold.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.olive.opacity(0.18)))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

// MARK: App-wide look

/// Light, dark, or following the phone ("تلقائي"). Stored under "appearance".
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }

    var nameAr: String {
        switch self {
        case .system: return "تلقائي"
        case .light: return "فاتح"
        case .dark: return "داكن"
        }
    }
}

/// The brand applied to UIKit-backed chrome every screen shares: navigation bars
/// (cream, ink titles), the tab bar (olive selection), segmented controls,
/// switches, and the default tint for alerts and system buttons.
enum BrandAppearance {
    static func apply(_ appearance: AppAppearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }

    static func configure() {
        let background = UIColor(named: "Background") ?? .systemBackground
        let ink = UIColor(named: "Ink") ?? .label
        let olive = UIColor(named: "Olive") ?? .systemGreen

        func rounded(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
        }

        UINavigationBar.appearance().tintColor = olive
        // iOS 26 draws its own (glass) bars; a custom bar appearance there leaves
        // the large titles («مجموعتي», «المجتمع»…) blank, so keep the system's.
        if #available(iOS 26, *) {
            configureControls(olive: olive, ink: ink)
            return
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = background
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: ink, .font: rounded(.headline, .bold)]
        nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: rounded(.largeTitle, .heavy)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = olive

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = background
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.selected.iconColor = olive
            item.selected.titleTextAttributes = [.foregroundColor: olive]
            item.normal.iconColor = .secondaryLabel
            item.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        configureControls(olive: olive, ink: ink)
    }

    private static func configureControls(olive: UIColor, ink: UIColor) {
        UISegmentedControl.appearance().selectedSegmentTintColor = olive
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: ink], for: .normal)
        UISwitch.appearance().onTintColor = olive
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = olive
    }
}

/// A screen on the brand's cream ground. Lists and forms drop their gray system
/// background so their white rows sit on cream like the rest of the app.
struct BrandScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Brand.background.ignoresSafeArea())
    }
}

extension View {
    func brandScreen() -> some View { modifier(BrandScreen()) }
}
