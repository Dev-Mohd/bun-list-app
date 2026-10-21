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
