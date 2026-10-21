import BunnListCore
import SwiftUI

/// Guest-only account screen. No sign-in, points or challenges are shown because none exist yet.
struct AccountView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let entries = model.book.activeEntries(owner: model.owner)
        NavigationStack {
            List {
                Section { BrandHeading(subtitle: "حسابك على هذا الجهاز") }
                Section("الحالة") {
                    Label("تستخدم التطبيق كزائر", systemImage: "person.crop.circle.badge.questionmark")
                    Text("تسجيل الدخول والمزامنة غير متاحين في هذه النسخة. مجموعتك محفوظة على هذا الجهاز فقط.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("مجموعتك") {
                    LabeledContent("لديّ", value: entries.filter(\.isOwned).count.formatted())
                    LabeledContent("جربته", value: entries.filter(\.isTried).count.formatted())
                    LabeledContent("مفضل", value: entries.filter(\.isFavorite).count.formatted())
                    LabeledContent("ودي أجرب", value: entries.filter(\.wantsToTry).count.formatted())
                }
                Section("عن هذه النسخة") {
                    LabeledContent("الإصدار", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Text("الدليل والمسح تجريبيان. لا نقاط أو تحديات أو وصفات في هذه النسخة.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("حسابي")
        }
    }
}
