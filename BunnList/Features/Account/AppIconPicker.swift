import BunnListCore
import SwiftUI
import UIKit

/// Keeps the home-screen icon in line with the choice: the picked icon, or, with
/// "تلقائي (موسمي)" on, the season's icon while an occasion lasts.
enum AppIconManager {
    static let choiceKey = "appIcon"
    static let seasonalKey = "seasonalAppIcon"

    @MainActor
    static func apply(now: Date = Date()) {
        let defaults = UserDefaults.standard
        let chosen = AppIconChoice(rawValue: defaults.string(forKey: choiceKey) ?? "") ?? .classic
        let seasonal = defaults.bool(forKey: seasonalKey)
        let wanted = (seasonal ? AppIconChoice.season(on: now) : nil) ?? chosen
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != wanted.assetName else { return }
        UIApplication.shared.setAlternateIconName(wanted.assetName) { _ in }
    }
}

/// "أيقونة التطبيق": pick an icon, and whether it changes by itself on occasions.
struct AppIconPicker: View {
    @AppStorage(AppIconManager.choiceKey) private var choice = AppIconChoice.classic.rawValue
    @AppStorage(AppIconManager.seasonalKey) private var seasonal = false

    private var current: AppIconChoice { AppIconChoice(rawValue: choice) ?? .classic }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(AppIconChoice.allCases, id: \.self) { icon in
                        Button {
                            choice = icon.rawValue
                            Haptics.tap()
                            AppIconManager.apply()
                        } label: {
                            VStack(spacing: 8) {
                                Image(icon.previewName)
                                    .resizable().scaledToFit()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(current == icon ? Brand.gold : Color.secondary.opacity(0.2), lineWidth: current == icon ? 3 : 1))
                                    .overlay(alignment: .bottomLeading) {
                                        if current == icon {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3).foregroundStyle(Brand.gold)
                                                .background(Circle().fill(Color(.systemBackground)))
                                                .offset(x: -6, y: 6)
                                        }
                                    }
                                Text(icon.nameAr).font(.caption).foregroundStyle(Brand.ink)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(current == icon ? Brand.gold.opacity(0.12) : Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.nameAr)
                        .accessibilityAddTraits(current == icon ? .isSelected : [])
                    }
                }

                Toggle(isOn: $seasonal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("تلقائي (موسمي)")
                        Text("تتغيّر الأيقونة في رمضان والعيدين واليوم الوطني ويوم التأسيس، وترجع لاختيارك بعدها.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                .onChange(of: seasonal) { _, _ in AppIconManager.apply() }

                Text("iOS يعرض تنبيه صغير كل ما تغيّرت الأيقونة.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .brandScreen()
        .navigationTitle("أيقونة التطبيق")
    }
}
