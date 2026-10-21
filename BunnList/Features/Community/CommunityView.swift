import SwiftUI

/// Placeholder tab: community needs real accounts (C03/C04) and moderation (C07). No inactive buttons.
struct CommunityView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("المجتمع غير متاح في هذه النسخة", systemImage: "person.3")
            } description: {
                Text("هذه نسخة محلية بلا حسابات. التجارب العامة والمتابعة والتعليقات تصل مع الحسابات الحقيقية.")
            }
            .navigationTitle("المجتمع")
            .accessibilityIdentifier("community-unavailable")
        }
    }
}
